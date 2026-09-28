--!strict
--[[
	GroundSlam
	Composite effect: shockwave rings + crater rocks + dust + distance-based camera shake.
	One network record triggers the whole combo (cheaper and perfectly synchronized).

	params.cframe : impact point, params.scale : size, params.power : 1 (stomp) .. 4 (ultimate)
]]

local VFX = script.Parent.Parent
local Assets = require(VFX.Assets)
local CameraShaker = require(VFX.CameraShaker)
local CraterRocks = require(script.Parent.CraterRocks)
local Particles = require(VFX.Particles)
local ScreenFlash = require(VFX.ScreenFlash)
local Shockwave = require(script.Parent.Shockwave)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local GroundSlam = {} :: Types.Effect
GroundSlam.maxDistance = 500

function GroundSlam.preload()
	if Shockwave.preload then
		Shockwave.preload()
	end
	if CraterRocks.preload then
		CraterRocks.preload()
	end
	Particles.prewarm({ "Dust" }, 2)
end

function GroundSlam.play(params: Types.EffectParams, ctx: Types.EffectContext)
	Shockwave.play(params, ctx)
	CraterRocks.play(params, ctx)

	local origin = params.cframe.Position
	local hit = workspace:Raycast(origin + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), Assets.groundParams())
	if hit then
		local color = Assets.surfaceLook(hit)
		local frame = VFXMath.alignToNormal(hit.Position, hit.Normal)
		Particles.burst("Dust", frame, (8 + 6 * params.power) * ctx.quality, {
			color = color:Lerp(Color3.new(0.85, 0.82, 0.78), 0.35),
			sizeScale = params.scale,
			speedScale = 0.8 + 0.25 * params.power,
			spread = 85,
		})
	end

	-- Everybody nearby feels it; the closer, the harder.
	CameraShaker.addTraumaAt(0.25 + 0.15 * params.power, origin, 40 + 20 * params.power * params.scale)
	if params.power >= 3 and ctx.distance < 60 then
		ScreenFlash.impact({ duration = 0.25, brightness = 0.06, contrast = 0.15, blur = 4 })
	end
end

return GroundSlam
