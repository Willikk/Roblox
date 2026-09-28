--!strict
--[[
	Controller (client)
	Runs the procedural layers on EVERY R6 character this client can see: the local
	player, other players and tagged NPCs. Each client animates everyone locally from
	replicated positions, so nothing but head-look angles ever goes over the network.

	Frame loop (RunService.PreSimulation, i.e. after the Animator wrote this frame's pose):
	  sensing + layers : at a LOD rate (distance / on-screen)
	  rig:apply()      : every frame (the Animator resets Transform every frame)

	Usage (LocalScript in StarterPlayerScripts):
		local Controller = require(ReplicatedStorage.R6Procedural.Controller)
		Controller.start()                                  -- defaults
		Controller.start({ head = { armPitchShare = 0.5 } }) -- overrides (see Config)

	NPCs: CollectionService:AddTag(npcModel, "R6Procedural"); optional attribute
	"R6_LookAt" (Vector3 world point) for their head target.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local R6Procedural = script.Parent
local Config = require(R6Procedural.Config)
local LookNet = require(R6Procedural.LookNet)
local R6Math = require(R6Procedural.R6Math)
local Rig = require(R6Procedural.Rig)
local Sensor = require(R6Procedural.Sensor)
local Types = require(R6Procedural.Types)

local Controller = {}

Controller.TAG = "R6Procedural"

-- Order matters: BodyLean publishes rig.pose, HeadLook consumes it.
Controller.layers = {
	require(R6Procedural.Layers.BodyLean),
	require(R6Procedural.Layers.TerrainAdaptation),
	require(R6Procedural.Layers.LandingImpact),
	require(R6Procedural.Layers.HeadLook),
	require(R6Procedural.Layers.Breathing),
} :: { Types.Layer }

type Entry = {
	model: Model,
	player: Player?,
	isLocal: boolean,
	rig: Rig.Rig,
	sensor: Sensor.Sensor,
	accumulator: number,
	enabled: boolean,
	remoteLook: Types.LookTarget?,
	weight: (attribute: string) -> number,
}

local cfg: Config.Config = Config.resolve(nil)
local entries: { [Model]: Entry } = {}
local pending: { [Model]: boolean } = {}
local rayParams = RaycastParams.new()
local started = false
local layerFailed: { [string]: boolean } = {}

local localLook: Types.LookTarget? = nil
local lastSent: Types.LookTarget? = nil
local sendClock = 0
local lastSendTime = 0
local lookRemote: UnreliableRemoteEvent? = nil

local function rebuildRayFilter()
	local ignore: { Instance } = {}
	for model in entries do
		table.insert(ignore, model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local vfx = workspace:FindFirstChild("VFX")
	if vfx then
		table.insert(ignore, vfx)
	end
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true
	rayParams.RespectCanCollide = true
end

local function untrack(model: Model)
	local entry = entries[model]
	if entry then
		entries[model] = nil
		if entry.enabled and entry.rig.torso.Parent then
			entry.rig:restore()
		end
		rebuildRayFilter()
	end
	pending[model] = nil
end

local function track(model: Model, player: Player?)
	if entries[model] or pending[model] then
		return
	end
	pending[model] = true
	task.spawn(function()
		-- Parts/joints stream in over a few frames: retry for up to ~10 s.
		local rig: Rig.Rig? = nil
		for _ = 1, 40 do
			if not pending[model] or model.Parent == nil then
				pending[model] = nil
				return
			end
			rig = Rig.new(model)
			if rig then
				break
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 then
				pending[model] = nil
				return -- R15: not handled by this system
			end
			task.wait(0.25)
		end
		pending[model] = nil
		if rig == nil then
			return
		end
		local entry: Entry = {
			model = model,
			player = player,
			isLocal = player ~= nil and player == Players.LocalPlayer,
			rig = rig,
			sensor = Sensor.new(),
			accumulator = 0,
			enabled = false,
			remoteLook = nil,
			weight = function(attribute: string): number
				local value = model:GetAttribute(attribute)
				return if type(value) == "number" then math.clamp(value, 0, 1) else 1
			end,
		}
		entries[model] = entry
		rebuildRayFilter()
		model.Destroying:Connect(function()
			untrack(model)
		end)
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				untrack(model)
			end
		end)
	end)
end

local function trackPlayer(player: Player)
	if player.Character then
		track(player.Character, player)
	end
	player.CharacterAdded:Connect(function(character)
		track(character, player)
	end)
	player.CharacterRemoving:Connect(function(character)
		untrack(character)
	end)
end

-- LOD sensing interval in seconds, or nil when the character is too far to bother.
local function lodInterval(entry: Entry, camera: Camera?): number?
	if entry.isLocal or camera == nil then
		return 0
	end
	local lod = cfg.lod
	local position = entry.rig.root.Position
	local distance = (camera.CFrame.Position - position).Magnitude
	local interval: number
	if distance <= lod.fullRateDistance then
		interval = 0
	elseif distance <= lod.halfRateDistance then
		interval = 1 / 30
	elseif distance <= lod.lowRateDistance then
		interval = 1 / 15
	else
		return nil
	end
	local _, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen then
		interval = math.max(interval, lod.offscreenInterval)
	end
	return interval
end

local function lookTargetFor(entry: Entry, camera: Camera?): Types.LookTarget?
	local rootCF = entry.rig.root.CFrame
	if entry.isLocal then
		if camera == nil then
			return nil
		end
		local yaw, pitch = R6Math.lookAngles(rootCF:VectorToObjectSpace(camera.CFrame.LookVector))
		localLook = { yaw = yaw, pitch = pitch }
		return localLook
	elseif entry.player then
		return entry.remoteLook
	end
	local lookAt = entry.model:GetAttribute("R6_LookAt")
	if typeof(lookAt) == "Vector3" then
		local from = if entry.rig.head then entry.rig.head.Position else rootCF.Position
		local yaw, pitch = R6Math.lookAngles(rootCF:VectorToObjectSpace(lookAt - from))
		return { yaw = yaw, pitch = pitch }
	end
	return nil
end

local function runLayers(entry: Entry, dt: number, camera: Camera?)
	local ctx: Types.FrameContext = {
		isLocal = entry.isLocal,
		lookTarget = lookTargetFor(entry, camera),
		weight = entry.weight,
	}
	local rig, sensor = entry.rig, entry.sensor
	rig:begin()
	for _, layer in Controller.layers do
		local ok, err = (pcall :: any)(layer.update, rig, sensor, dt, cfg, ctx)
		if not ok and not layerFailed[layer.name] then
			layerFailed[layer.name] = true
			warn(`[R6Procedural] layer {layer.name} failed (reported once):`, err)
		end
	end
end

local function sendLocalLook(dt: number)
	local remote = lookRemote
	local look = localLook
	if remote == nil or look == nil then
		return
	end
	sendClock += dt
	if sendClock < 1 / cfg.head.sendRate then
		return
	end
	sendClock = 0
	local now = os.clock()
	local previous = lastSent
	local changed = previous == nil
		or math.abs(previous.yaw - look.yaw) > cfg.head.sendThreshold
		or math.abs(previous.pitch - look.pitch) > cfg.head.sendThreshold
	if changed or now - lastSendTime > 1 then
		remote:FireServer(LookNet.encodeLocal(look.yaw, look.pitch))
		lastSent = { yaw = look.yaw, pitch = look.pitch }
		lastSendTime = now
	end
end

local function onPreSimulation(dt: number)
	local camera = workspace.CurrentCamera
	for model, entry in entries do
		local rig = entry.rig
		if not rig:isAlive() then
			untrack(model)
			continue
		end
		local interval = if model:GetAttribute("R6_Disabled") == true then nil else lodInterval(entry, camera)
		if interval == nil then
			if entry.enabled then
				rig:restore()
				entry.enabled = false
			end
			entry.sensor.lastPosition = nil
			entry.accumulator = 0
			continue
		end
		entry.enabled = true
		entry.accumulator += dt
		local sense = entry.accumulator >= interval
		if sense then
			local stepDt = entry.accumulator
			entry.accumulator = 0
			Sensor.update(entry.sensor, rig, stepDt, rayParams, cfg, entry.isLocal, true)
			runLayers(entry, stepDt, camera)
		end
		rig:apply()
	end
	sendLocalLook(dt)
end

local function onLookBatch(payload: any)
	local batch = LookNet.decodeBatch(payload)
	if batch == nil then
		return
	end
	local me = Players.LocalPlayer
	for _, item in batch do
		if me and item.userId == me.UserId then
			continue
		end
		local player = Players:GetPlayerByUserId(item.userId)
		local character = player and player.Character
		local entry = character and entries[character]
		if entry then
			entry.remoteLook = { yaw = item.yaw, pitch = item.pitch }
		end
	end
end

function Controller.start(overrides: { [string]: any }?)
	if started then
		return
	end
	started = true
	cfg = Config.resolve(overrides)
	rebuildRayFilter()

	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerAdded:Connect(trackPlayer)

	for _, model in CollectionService:GetTagged(Controller.TAG) do
		if model:IsA("Model") then
			track(model, nil)
		end
	end
	CollectionService:GetInstanceAddedSignal(Controller.TAG):Connect(function(model)
		if model:IsA("Model") then
			track(model, nil)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(Controller.TAG):Connect(function(model)
		if model:IsA("Model") and Players:GetPlayerFromCharacter(model) == nil then
			untrack(model)
		end
	end)

	RunService.PreSimulation:Connect(onPreSimulation)

	-- Head-look replication is optional: without the server relay everything else works.
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("R6ProceduralRemotes", 15)
		local remote = remotes and remotes:FindFirstChild("Look")
		if remote and remote:IsA("UnreliableRemoteEvent") then
			lookRemote = remote
			remote.OnClientEvent:Connect(onLookBatch)
		end
	end)
end

-- Debug / tooling: current entry count and whether a model is being animated.
function Controller.stats(): (number, number)
	local total, active = 0, 0
	for _, entry in entries do
		total += 1
		if entry.enabled then
			active += 1
		end
	end
	return total, active
end

return Controller
