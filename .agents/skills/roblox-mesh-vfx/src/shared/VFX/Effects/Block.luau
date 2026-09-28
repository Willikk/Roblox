--!strict
--[[
	Block
	Guarded hit: short white-steel sparks, a small flash, a tiny hitstop and a light
	camera tap for the defender. params.target = defender.
]]

local Players = game:GetService("Players")

local VFX = script.Parent.Parent
local CameraShaker = require(VFX.CameraShaker)
local Hitstop = require(VFX.Hitstop)
local Particles = require(VFX.Particles)
local Shapes = require(VFX.Shapes)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local Block = {} :: Types.Effect
Block.maxDistance = 220

local STEEL = Color3.fromRGB(225, 232, 245)

function Block.preload()
	Shapes.preload()
end

function Block.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	local direction = params.cframe.LookVector
	Shapes.flash(position, STEEL, 1.6, 0.08, 4)
	Particles.burst(
		"Sparks",
		VFXMath.lookAlong(position, -direction) * CFrame.Angles(-math.pi / 2, 0, 0),
		12 * ctx.quality,
		{
			color = STEEL,
			spread = 60,
			sizeScale = 0.7,
		}
	)
	if ctx.distance < 90 then
		Hitstop.apply({ params.source, params.target }, 0.035)
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and params.target == me then
		CameraShaker.addTrauma(0.08)
		CameraShaker.kick(direction, 0.3)
	end
end

return Block
