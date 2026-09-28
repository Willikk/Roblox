--!strict
--[[
	VFXService (server)
	The server never renders effects. It validates gameplay, then sends compact effect
	records to the clients that can actually see them.

	* Batching: every record queued during a frame is packed into as few packets as
	  possible (28 records per packet, 31 bytes each) and flushed once on Heartbeat.
	* Interest management: only players within `radius` of the effect receive it.
	* Unreliable by default (cosmetic, latest-wins); `reliable = true` for effects that
	  must not be lost (ultimates, cutscene beats).
	* Prediction friendly: `exclude = attackerPlayer` when the attacker already played
	  the effect locally.

	Usage:
		local VFXService = require(ServerScriptService.VFXServer.VFXService)
		VFXService.start()
		VFXService.play("GroundSlam", { cframe = CFrame.new(pos), power = 2, seed = seed })
		VFXService.play("ImpactBurst", {
			cframe = CFrame.lookAt(hitPos, hitPos + swingDir),
			source = attacker.Character, target = victim.Character, power = 1.5,
		}, { radius = 250 })
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VFX = ReplicatedStorage:WaitForChild("VFX")
local Net = require(VFX:WaitForChild("Net"))
local Registry = require(VFX:WaitForChild("Registry"))

export type PlayParams = {
	cframe: CFrame,
	scale: number?,
	color: Color3?,
	power: number?,
	variant: number?,
	seed: number?,
	source: Instance?,
	target: Instance?,
}

export type PlayOptions = {
	radius: number?, -- default 500 studs
	exclude: Player?, -- typically the attacker who predicted the effect
	only: { Player }?, -- explicit recipients
	reliable: boolean?,
}

type Queued = {
	record: Net.Record,
	source: Instance?,
	target: Instance?,
}

type Outbox = { unreliable: { Queued }, reliable: { Queued } }

local VFXService = {}

-- UnreliableRemoteEvent drops payloads above ~900 bytes; keep a safety margin.
local UNRELIABLE_BUDGET = 820
local INSTANCE_REF_BYTES = 12

local remotes: Folder? = nil
local unreliableRemote: UnreliableRemoteEvent? = nil
local reliableRemote: RemoteEvent? = nil
local outboxes: { [Player]: Outbox } = {}

local function outboxFor(player: Player): Outbox
	local box = outboxes[player]
	if box == nil then
		box = { unreliable = {}, reliable = {} }
		outboxes[player] = box
	end
	return box :: Outbox
end

local function recipients(position: Vector3, options: PlayOptions?): { Player }
	if options and options.only then
		return options.only
	end
	local radius = if options and options.radius then options.radius else 500
	local exclude = options and options.exclude
	local list = {}
	for _, player in Players:GetPlayers() do
		if player == exclude then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- Players without a character (spectating / loading) still receive nearby-only
		-- effects conservatively: include them, the client culls by camera distance.
		if root == nil or not root:IsA("BasePart") or (root.Position - position).Magnitude <= radius then
			table.insert(list, player)
		end
	end
	return list
end

function VFXService.play(name: string, params: PlayParams, options: PlayOptions?)
	local record: Net.Record = {
		id = Registry.idOf(name),
		seed = params.seed or math.random(0, 65535),
		cframe = params.cframe,
		scale = params.scale or 1,
		color = params.color,
		power = params.power or 1,
		variant = params.variant or 0,
		sourceIndex = 0,
		targetIndex = 0,
	}
	local queued: Queued = { record = record, source = params.source, target = params.target }
	local reliable = options ~= nil and options.reliable == true
	for _, player in recipients(params.cframe.Position, options) do
		local box = outboxFor(player)
		table.insert(if reliable then box.reliable else box.unreliable, queued)
	end
end

local function send(player: Player, list: { Queued }, reliable: boolean)
	local packetRecords: { Net.Record } = {}
	local instances: { Instance } = {}
	local indexOf: { [Instance]: number } = {}

	local function indexFor(inst: Instance?): number
		if inst == nil then
			return 0
		end
		local index = indexOf[inst]
		if index == nil then
			if #instances >= 255 then
				return 0
			end
			table.insert(instances, inst)
			index = #instances
			indexOf[inst] = index
		end
		return index :: number
	end

	local function flush()
		if #packetRecords == 0 then
			return
		end
		local payload = Net.encode(packetRecords)
		if reliable then
			(reliableRemote :: RemoteEvent):FireClient(player, payload, instances)
		else
			(unreliableRemote :: UnreliableRemoteEvent):FireClient(player, payload, instances)
		end
		packetRecords, instances, indexOf = {}, {}, {}
	end

	-- Conservative byte estimate: header + records + instance references.
	local function estimate(extraRecords: number, extraInstances: number): number
		return 1
			+ Net.RECORD_SIZE * (#packetRecords + extraRecords)
			+ INSTANCE_REF_BYTES * (#instances + extraInstances)
	end

	for _, item in list do
		local newRefs = 0
		if item.source and indexOf[item.source] == nil then
			newRefs += 1
		end
		if item.target and item.target ~= item.source and indexOf[item.target] == nil then
			newRefs += 1
		end
		if #packetRecords >= Net.MAX_RECORDS or (not reliable and estimate(1, newRefs) > UNRELIABLE_BUDGET) then
			flush()
		end
		-- Records are shared between recipients: copy before stamping indices.
		local record = table.clone(item.record)
		record.sourceIndex = indexFor(item.source)
		record.targetIndex = indexFor(item.target)
		table.insert(packetRecords, record)
	end
	flush()
end

local function onHeartbeat()
	for player, box in outboxes do
		if player.Parent == nil then
			outboxes[player] = nil
			continue
		end
		if #box.unreliable > 0 then
			send(player, box.unreliable, false)
			table.clear(box.unreliable)
		end
		if #box.reliable > 0 then
			send(player, box.reliable, true)
			table.clear(box.reliable)
		end
	end
end

local function setupCollisionGroup()
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered("VFXDebris") then
			PhysicsService:RegisterCollisionGroup("VFXDebris")
		end
		PhysicsService:CollisionGroupSetCollidable("VFXDebris", "VFXDebris", false)
		-- If the game puts characters in a "Characters" group, debris never push them.
		if PhysicsService:IsCollisionGroupRegistered("Characters") then
			PhysicsService:CollisionGroupSetCollidable("VFXDebris", "Characters", false)
		end
	end)
	if not ok then
		warn("[VFXService] collision group setup failed:", err)
	end
end

function VFXService.start()
	if remotes then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "VFXRemotes"

	local unreliable = Instance.new("UnreliableRemoteEvent")
	unreliable.Name = "Unreliable"
	unreliable.Parent = folder

	local reliable = Instance.new("RemoteEvent")
	reliable.Name = "Reliable"
	reliable.Parent = folder

	folder.Parent = ReplicatedStorage
	remotes, unreliableRemote, reliableRemote = folder, unreliable, reliable

	setupCollisionGroup()
	RunService.Heartbeat:Connect(onHeartbeat)
	Players.PlayerRemoving:Connect(function(player)
		outboxes[player] = nil
	end)
end

function VFXService.remotes(): Folder
	assert(remotes, "VFXService.start() must be called first")
	return remotes
end

return VFXService
