--!strict
--[[
	BodyLean
	Forward/back lean from speed + acceleration, banking into turns, leaning into slopes.

	* Forward lean pivots on the hip line and the hips counter-rotate, so the character
	  bends at the waist while the legs stay planted (R6 has no spine joint).
	* Bank pivots on the feet: the whole body tilts into the turn like a runner/bike.
	* A spring (slightly under-damped) gives the natural overshoot when stopping.
	Writes rig.pose.lean / rig.pose.bank for the head stabilization in HeadLook.
]]

local R6Procedural = script.Parent.Parent
local R6Math = require(R6Procedural.R6Math)
local Spring = require(R6Procedural.Spring)
local Types = require(R6Procedural.Types)

local BodyLean = { name = "BodyLean" } :: Types.Layer

function BodyLean.update(rig, sensor, dt, cfg, ctx)
	local c = cfg.lean
	local state = rig.layerState.BodyLean
	if state == nil then
		state = Spring.new(Vector3.zero, c.frequency, c.damping)
		rig.layerState.BodyLean = state
	end
	local spring = state :: Spring.Spring

	local rootCF = rig.root.CFrame
	local localVelocity = rootCF:VectorToObjectSpace(Vector3.new(sensor.velocity.X, 0, sensor.velocity.Z))
	local localAccel = rootCF:VectorToObjectSpace(Vector3.new(sensor.acceleration.X, 0, sensor.acceleration.Z))

	local lean, bank = R6Math.leanAngles(localVelocity, localAccel, sensor.yawRate, workspace.Gravity, c)
	if sensor.grounded then
		lean += c.slopeLean * R6Math.slopeLean(sensor.groundNormal)
	end
	local weight = sensor.stateWeight * ctx.weight("R6_Lean") * (if sensor.grounded then 1 else 0.4)
	spring.target = Vector3.new(math.clamp(lean, -c.maxBackward, c.maxForward), bank, 0) * weight
	local p = spring:update(dt)

	rig.pose.lean = p.X
	rig.pose.bank = p.Y

	local hipLine = Vector3.new(0, rig.hipLineY, 0)
	local feet = Vector3.new(0, rig.restFootY, 0)
	rig:add(
		"RootJoint",
		R6Math.rotationAbout(feet, CFrame.Angles(0, 0, p.Y)) * R6Math.rotationAbout(hipLine, CFrame.Angles(-p.X, 0, 0))
	)
	local compensation = R6Math.rotationAbout(hipLine, CFrame.Angles(p.X * c.legCompensation, 0, 0))
	rig:add("LeftHip", compensation)
	rig:add("RightHip", compensation)
end

return BodyLean
