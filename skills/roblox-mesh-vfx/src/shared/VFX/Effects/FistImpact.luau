--!strict
--[[
	FistImpact
	Punch connect: ImpactBurst (sparks, flash, victim highlight, hitstop, camera) plus an
	air-pressure shock ring facing the punch and, for heavy hits (variant bit 0), a second
	wide ring and a dust puff. params.cframe LookVector = punch direction.
]]

local VFX = script.Parent.Parent
local ImpactBurst = require(script.Parent.ImpactBurst)
local Particles = require(VFX.Particles)
local Shapes = require(VFX.Shapes)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local FistImpact = {} :: Types.Effect
FistImpact.maxDistance = 250

local AIR = Color3.fromRGB(245, 245, 255)

function FistImpact.preload()
	Shapes.preload()
	if ImpactBurst.preload then
		ImpactBurst.preload()
	end
end

function FistImpact.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local heavy = bit32.band(params.variant, 1) == 1
	ImpactBurst.play({
		name = "ImpactBurst",
		cframe = params.cframe,
		scale = params.scale,
		color = params.color or Color3.fromRGB(255, 240, 215),
		power = params.power * 0.8,
		variant = params.variant,
		seed = params.seed,
		source = params.source,
		target = params.target,
	}, ctx)
	local position = params.cframe.Position
	local facing = VFXMath.alignToNormal(position, params.cframe.LookVector)
	Shapes.ring(facing, 0.3, if heavy then 4.2 else 2.6, if heavy then 0.8 else 0.5, AIR, 0.18)
	if heavy then
		Shapes.ring(facing * CFrame.new(0, 0.8, 0), 0.5, 6, 0.5, AIR, 0.26, 0.05)
		Particles.burst("Dust", facing, 6 * ctx.quality, { sizeScale = 0.6, speedScale = 1.2, spread = 40 })
	end
end

return FistImpact
