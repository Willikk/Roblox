--!strict
--[[
	Client
	Client-side VFX dispatcher: receives compact packets from the server, culls by
	distance, scales by adaptive quality, and plays effects locally.

	Usage (LocalScript):
		local VFXClient = require(ReplicatedStorage.VFX.Client)
		VFXClient.start()

		-- Client-side prediction (instant feedback for the attacker; the server then
		-- broadcasts to everybody else with `exclude = attacker`):
		VFXClient.play("Slash", { cframe = slashFrame, power = 1.5, seed = seed })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(script.Parent.Assets)
local Net = require(script.Parent.Net)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Types)

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

local Client = {}

Client.settings = {
	quality = 1, -- user setting ceiling (0.25 .. 1)
	adaptiveQuality = true, -- lower quality automatically when FPS drops
	distanceScale = 1, -- multiplies every effect's maxDistance
	defaultMaxDistance = 400,
}

local effects: { [string]: Types.Effect } = {}
local started = false
local adaptiveQuality = 1

-- Registers an effect implemented outside VFX/Effects (themes, game-specific effects).
-- The name must also be listed in Registry.luau to travel over the network.
function Client.registerEffect(name: string, effect: Types.Effect)
	effects[name] = effect
	if started and effect.preload then
		task.spawn(effect.preload)
	end
end

local function loadEffect(name: string): Types.Effect?
	local cached = effects[name]
	if cached then
		return cached
	end
	local moduleScript = script.Parent.Effects:FindFirstChild(name)
	if moduleScript == nil or not moduleScript:IsA("ModuleScript") then
		warn(`[VFX.Client] no effect module named {name}`)
		return nil
	end
	local effect = (require :: any)(moduleScript) :: Types.Effect
	effects[name] = effect
	return effect
end

function Client.quality(): number
	return math.clamp(math.min(Client.settings.quality, adaptiveQuality), 0.25, 1)
end

local function dispatch(params: Types.EffectParams)
	local effect = loadEffect(params.name)
	if effect == nil then
		return
	end
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - params.cframe.Position).Magnitude else 0
	local maxDistance = (effect.maxDistance or Client.settings.defaultMaxDistance) * Client.settings.distanceScale
	if distance > maxDistance then
		return
	end
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local ctx: Types.EffectContext = {
		quality = Client.quality(),
		distance = distance,
		isLocalSource = character ~= nil and params.source == character,
		isLocalTarget = character ~= nil and params.target == character,
		rng = Random.new(params.seed),
	}
	local ok, err = (pcall :: any)(effect.play, params, ctx)
	if not ok then
		warn(`[VFX.Client] {params.name} failed:`, err)
	end
end

-- Plays an effect locally (prediction, cosmetics, UI-driven effects).
function Client.play(name: string, p: PlayParams)
	dispatch({
		name = name,
		cframe = p.cframe,
		scale = p.scale or 1,
		color = p.color,
		power = p.power or 1,
		variant = p.variant or 0,
		seed = p.seed or math.random(0, 65535),
		source = p.source,
		target = p.target,
	})
end

local function onPacket(payload: any, instances: any)
	local records = Net.decode(payload)
	if records == nil then
		return
	end
	local list: { any } = if type(instances) == "table" then instances else {}
	for _, record in records do
		local name = Registry.nameOf(record.id)
		if name == nil then
			continue
		end
		local source = list[record.sourceIndex]
		local target = list[record.targetIndex]
		dispatch({
			name = name,
			cframe = record.cframe,
			scale = record.scale,
			color = record.color,
			power = record.power,
			variant = record.variant,
			seed = record.seed,
			source = if typeof(source) == "Instance" then source else nil,
			target = if typeof(target) == "Instance" then target else nil,
		})
	end
end

local function startAdaptiveQuality()
	local samples = 0
	local total = 0
	RunService.PostSimulation:Connect(function(dt)
		if not Client.settings.adaptiveQuality then
			adaptiveQuality = 1
			return
		end
		samples += 1
		total += dt
		if samples >= 90 then
			local fps = samples / total
			if fps < 40 then
				adaptiveQuality = math.max(0.35, adaptiveQuality - 0.15)
			elseif fps > 55 then
				adaptiveQuality = math.min(1, adaptiveQuality + 0.05)
			end
			samples, total = 0, 0
		end
	end)
end

function Client.start()
	if started then
		return
	end
	started = true

	for _, name in Registry.names() do
		if effects[name] == nil and script.Parent.Effects:FindFirstChild(name) == nil then
			continue -- provided at runtime by Client.registerEffect
		end
		local effect = loadEffect(name)
		if effect and effect.preload then
			local ok, err = (pcall :: any)(effect.preload)
			if not ok then
				warn(`[VFX.Client] preload {name} failed:`, err)
			end
		end
	end
	task.spawn(Assets.preloadAsync)
	startAdaptiveQuality()

	local remotes = ReplicatedStorage:WaitForChild("VFXRemotes")
	local unreliable = remotes:WaitForChild("Unreliable") :: UnreliableRemoteEvent
	local reliable = remotes:WaitForChild("Reliable") :: RemoteEvent
	unreliable.OnClientEvent:Connect(onPacket)
	reliable.OnClientEvent:Connect(onPacket)
end

return Client
