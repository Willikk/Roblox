--!strict
--[[
	DarkHit: flesh hit. Pixel blood burst, steel spark, stepped droplets arcing to the
	ground, a blood pool under the victim, dark-red body flash, heavy hitstop and choppy
	camera. Heavy hits (variant bit 0) add an ink burst and, for the two fighters, a manga
	impact frame. params.cframe LookVector = blow direction.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = script.Parent.Parent
local ImpactFrame = require(DarkStyle.ImpactFrame)
local Settings = require(DarkStyle.Settings)
local Sprite3D = require(DarkStyle.Sprite3D)
local VFX = ReplicatedStorage:WaitForChild("VFX")
local Assets = require(VFX:WaitForChild("Assets"))
local CameraShaker = require(VFX:WaitForChild("CameraShaker"))
local Hitstop = require(VFX:WaitForChild("Hitstop"))
local Shapes = require(VFX:WaitForChild("Shapes"))
local Types = require(VFX:WaitForChild("Types"))
local VFXMath = require(VFX:WaitForChild("VFXMath"))

local DarkHit = {} :: Types.Effect
DarkHit.maxDistance = 260

local DARK_RED = Color3.fromRGB(120, 12, 14)

function DarkHit.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local heavy = bit32.band(params.variant, 1) == 1
	local position = params.cframe.Position
	local direction = params.cframe.LookVector
	local power = math.clamp(params.power, 0.4, 4)
	local rng = ctx.rng

	local burst = Settings.burstSprite()
	if burst then
		Sprite3D.play(burst, position, { scale = 0.9 + 0.25 * power, lightInfluence = 0.5, group = "world" })
		local drops = math.floor((5 + 3 * power) * ctx.quality + 0.5)
		for _ = 1, drops do
			local v = (direction * VFXMath.randomRange(rng, 6, 16))
				+ VFXMath.randomInCone(rng, Vector3.yAxis, math.rad(60)) * VFXMath.randomRange(rng, 6, 14)
			Sprite3D.play("Droplet", position, {
				velocity = v,
				gravity = 70,
				lifetime = VFXMath.randomRange(rng, 0.45, 0.8),
				scale = VFXMath.randomRange(rng, 0.9, 1.6),
				lightInfluence = 0.4,
				tint = if Settings.blood == "ichor" then Color3.fromRGB(40, 36, 50) else nil,
			})
		end
		local ground = workspace:Raycast(position, Vector3.new(0, -8, 0), Assets.groundParams())
		if ground and Settings.blood == "blood" then
			Sprite3D.ground(
				"BloodPool",
				ground.Position + direction * 1.5,
				ground.Normal,
				2.5 + power,
				Settings.poolLifetime
			)
		end
	end
	Sprite3D.play("Spark", position - direction * 0.4, { scale = 1 + 0.2 * power, rotation = rng:NextNumber(0, 90) })
	if heavy then
		Sprite3D.play("InkBurst", position, { scale = 0.6 + 0.15 * power, rotation = rng:NextNumber(0, 360) })
	end
	if params.target then
		Shapes.highlight(params.target, DARK_RED, 0.2, "VFX_DarkHit", 0.25)
	end

	if ctx.distance < 90 then
		Hitstop.apply(
			{ params.source, params.target },
			0.06 + 0.025 * power + (if heavy then 0.06 else 0),
			{ freezeVFX = heavy }
		)
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and params.target == me then
		CameraShaker.addTrauma(0.25 + 0.1 * power)
		CameraShaker.kick(direction, 0.8 + 0.3 * power)
	elseif me and params.source == me then
		CameraShaker.addTrauma(0.1 + 0.05 * power)
		CameraShaker.fovPunch(-(2 + power))
	end
	if heavy and Settings.impactFrames and me and (params.source == me or params.target == me) then
		ImpactFrame.play({ burst = true })
	end
end

return DarkHit
