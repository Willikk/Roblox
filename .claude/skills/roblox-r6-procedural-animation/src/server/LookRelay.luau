--!strict
--[[
	LookRelay (server)
	Relays head-look angles between clients. Joint Transform/C0 edits made on a client
	never replicate, so each client sends its own look (4 bytes, <= 15 Hz) and the server
	broadcasts one batched packet to everyone at 15 Hz.

	* Validates type, size, NaN and range; rate-limits each player (30 packets/s).
	* Only changed entries are broadcast, plus a full refresh every 2 s for late joiners.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookNet = require(ReplicatedStorage:WaitForChild("R6Procedural"):WaitForChild("LookNet"))

type State = { yaw: number, pitch: number, dirty: boolean }
type Budget = { windowStart: number, count: number }

local LookRelay = {}

local BROADCAST_INTERVAL = 1 / 15
local FULL_REFRESH_INTERVAL = 2
local MAX_PACKETS_PER_SECOND = 30

local states: { [Player]: State } = {}
local budgets: { [Player]: Budget } = {}
local started = false

local function allowed(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if budget == nil or now - budget.windowStart >= 1 then
		budgets[player] = { windowStart = now, count = 1 }
		return true
	end
	budget.count += 1
	return budget.count <= MAX_PACKETS_PER_SECOND
end

function LookRelay.start()
	if started then
		return
	end
	started = true

	local folder = Instance.new("Folder")
	folder.Name = "R6ProceduralRemotes"
	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = "Look"
	remote.Parent = folder
	folder.Parent = ReplicatedStorage

	remote.OnServerEvent:Connect(function(player: Player, payload: unknown)
		if not allowed(player) then
			return
		end
		local yaw, pitch = LookNet.decodeLocal(payload)
		if yaw == nil or pitch == nil then
			return
		end
		local state = states[player]
		local clampedYaw = math.clamp(yaw, -math.pi, math.pi)
		local clampedPitch = math.clamp(pitch, -math.pi / 2, math.pi / 2)
		if state then
			state.yaw, state.pitch, state.dirty = clampedYaw, clampedPitch, true
		else
			states[player] = { yaw = clampedYaw, pitch = clampedPitch, dirty = true }
		end
	end)

	local broadcastClock, refreshClock = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		broadcastClock += dt
		refreshClock += dt
		if broadcastClock < BROADCAST_INTERVAL then
			return
		end
		broadcastClock = 0
		local full = refreshClock >= FULL_REFRESH_INTERVAL
		if full then
			refreshClock = 0
		end

		local batch: { LookNet.Entry } = {}
		for player, state in states do
			if state.dirty or full then
				state.dirty = false
				table.insert(batch, { userId = player.UserId, yaw = state.yaw, pitch = state.pitch })
				if #batch == LookNet.MAX_ENTRIES then
					remote:FireAllClients(LookNet.encodeBatch(batch))
					batch = {}
				end
			end
		end
		if #batch > 0 then
			remote:FireAllClients(LookNet.encodeBatch(batch))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		budgets[player] = nil
	end)
end

return LookRelay
