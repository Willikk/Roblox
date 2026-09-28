--!strict
--[[
	LandingImpact
	Crouch-and-recover on landing, proportional to the fall speed: the pelvis dips on a
	bouncy spring while the legs tuck by the same amount, so the feet stay on the floor
	(reads as bent knees on a knee-less rig). Works for every character (derived from
	position history, no Humanoid state needed).
]]

local R6Procedural = script.Parent.Parent
local R6Math = require(R6Procedural.R6Math)
local Spring = require(R6Procedural.Spring)
local Types = require(R6Procedural.Types)

local LandingImpact = { name = "LandingImpact" } :: Types.Layer

function LandingImpact.update(rig, sensor, dt, cfg, ctx)
	local c = cfg.landing
	local state = rig.layerState.LandingImpact
	if state == nil then
		state = Spring.new(Vector3.zero, c.frequency, c.damping)
		rig.layerState.LandingImpact = state
	end
	local spring = state :: Spring.Spring

	if sensor.landingImpact > c.minImpactSpeed then
		local strength = (sensor.landingImpact - c.minImpactSpeed) * c.impulseScale
		spring:impulse(Vector3.new(strength * 12 * ctx.weight("R6_Landing") * sensor.stateWeight, 0, 0))
	end
	local dip = math.clamp(spring:update(dt).X, 0, c.maxDip)
	if dip <= 1e-3 then
		return
	end
	local hipLine = Vector3.new(0, rig.hipLineY, 0)
	rig:add("RootJoint", CFrame.new(0, -dip, 0) * R6Math.rotationAbout(hipLine, CFrame.Angles(-dip * 0.25, 0, 0)))
	local tuck = CFrame.new(0, dip, 0) * R6Math.rotationAbout(hipLine, CFrame.Angles(dip * 0.25, 0, 0))
	rig:add("LeftHip", tuck)
	rig:add("RightHip", tuck)
end

return LandingImpact
