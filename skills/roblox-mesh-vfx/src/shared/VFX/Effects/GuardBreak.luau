--!strict
--[[
	GuardBreak
	Posture shattered: glassy guard shards fly out, a violent ring, big flash, long
	hitstop, and a desaturated impact punch for the two fighters.
	params.target = the defender whose guard broke.
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

local GuardBreak = {} :: Types.Effect
GuardBreak.maxDistance = 320

local SHARD = Color3.fromRGB(170, 215, 255)
local HOT = Color3.fromRGB(255, 120, 80)

function GuardBreak.preload()
	Shapes.preload()
end

function GuardBreak.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	local direction = params.cframe.LookVector
	Shapes.flash(position, Color3.new(1, 1, 1), 4.5, 0.16, 16)
	Shapes.shards(position, SHARD, math.floor(10 * ctx.quality + 0.5), 28, ctx.rng)
	Shapes.ring(VFXMath.alignToNormal(position, direction), 0.5, 6, 1, HOT, 0.28)
	Shapes.ring(VFXMath.alignToNormal(position, Vector3.yAxis), 0.5, 7, 0.6, SHARD, 0.34, 0.04)
	Particles.burst(
		"Sparks",
		VFXMath.alignToNormal(position, Vector3.yAxis),
		26 * ctx.quality,
		{ color = HOT, spread = 90 }
	)
	if params.target then
		Shapes.highlight(params.target, HOT, 0.45, "VFX_GuardBreak", 0.2)
	end
	if ctx.distance < 100 then
		Hitstop.apply({ params.source, params.target }, 0.16, { freezeVFX = true })
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and (params.source == me or params.target == me) then
		CameraShaker.addTrauma(if params.target == me then 0.5 else 0.25)
		CameraShaker.kick(direction, 1.2)
		ScreenFlash.impactFrame(0.05)
		ScreenFlash.impact({ duration = 0.3, saturation = -0.35, contrast = 0.25, blur = 5 })
	end
end

return GuardBreak
