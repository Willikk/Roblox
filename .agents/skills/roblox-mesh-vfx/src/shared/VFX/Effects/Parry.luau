--!strict
--[[
	Parry
	The signature Deepwoken read: a big yellow star spark, a golden ring, a light pop,
	sparks, and a heavy hitstop on both fighters (world VFX frozen too).
	params.cframe = contact point (LookVector = blow direction), source = parrier,
	target = parried attacker.
]]

local Players = game:GetService("Players")

local VFX = script.Parent.Parent
local CameraShaker = require(VFX.CameraShaker)
local Hitstop = require(VFX.Hitstop)
local Particles = require(VFX.Particles)
local ScreenFlash = require(VFX.ScreenFlash)
local Shapes = require(VFX.Shapes)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local Parry = {} :: Types.Effect
Parry.maxDistance = 300

local GOLD = Color3.fromRGB(255, 214, 90)
local WHITE_HOT = Color3.fromRGB(255, 250, 225)

function Parry.preload()
	Shapes.preload()
	Particles.prewarm({ "Sparks" }, 3)
end

function Parry.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	local direction = params.cframe.LookVector
	local power = math.clamp(params.power, 0.5, 3)

	Shapes.flash(position, WHITE_HOT, 3.2 * power, 0.12, 14)
	Shapes.star(position, GOLD, 5.5 * power, 0.16, ctx.rng)
	Shapes.ring(VFXMath.alignToNormal(position, direction), 0.3, 4.5 * power, 0.7, GOLD, 0.22)
	Particles.burst(
		"Sparks",
		VFXMath.lookAlong(position, -direction) * CFrame.Angles(-math.pi / 2, 0, 0),
		30 * ctx.quality,
		{
			color = GOLD,
			speedScale = 1.3,
			spread = 80,
		}
	)

	if ctx.distance < 90 then
		Hitstop.apply({ params.source, params.target }, 0.12, { freezeVFX = true })
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and (params.source == me or params.target == me) then
		CameraShaker.addTrauma(0.22)
		CameraShaker.fovPunch(-4)
		ScreenFlash.impact({ duration = 0.14, brightness = 0.08, bloom = 1.4, contrast = 0.15 })
	end
end

return Parry
