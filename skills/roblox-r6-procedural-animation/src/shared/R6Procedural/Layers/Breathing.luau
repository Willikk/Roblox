--!strict
--[[
	Breathing
	Subtle idle life: chest rises/falls, arms sway outwards. Fades out when moving.
	Also the simplest example of a custom layer: copy it to write your own.
]]

local R6Procedural = script.Parent.Parent
local R6Math = require(R6Procedural.R6Math)
local Types = require(R6Procedural.Types)

local Breathing = { name = "Breathing" } :: Types.Layer

function Breathing.update(rig, sensor, dt, cfg, ctx)
	local c = cfg.breathing
	local speed = Vector3.new(sensor.velocity.X, 0, sensor.velocity.Z).Magnitude
	local weight = (1 - R6Math.smoothstep(c.idleSpeed * 0.5, c.idleSpeed, speed))
		* sensor.stateWeight
		* ctx.weight("R6_Breathing")
	local phase = (rig.layerState.BreathingPhase or 0) + dt * c.rate * 2 * math.pi
	rig.layerState.BreathingPhase = phase % (2 * math.pi)
	if weight <= 1e-3 then
		return
	end
	local b = math.sin(phase) * weight

	local hipLine = Vector3.new(0, rig.hipLineY, 0)
	rig:add("RootJoint", R6Math.rotationAbout(hipLine, CFrame.Angles(b * c.torsoAngle, 0, 0)))
	local counter = R6Math.rotationAbout(hipLine, CFrame.Angles(-b * c.torsoAngle, 0, 0))
	rig:add("LeftHip", counter)
	rig:add("RightHip", counter)
	-- Arms swing slightly outwards on the inhale (+Z rotation moves a hanging hand to +X).
	local sway = (b * 0.5 + 0.5 * weight) * c.armAngle
	rig:add("LeftShoulder", R6Math.rotationAbout(rig:c0("LeftShoulder").Position, CFrame.Angles(0, 0, -sway)))
	rig:add("RightShoulder", R6Math.rotationAbout(rig:c0("RightShoulder").Position, CFrame.Angles(0, 0, sway)))
end

return Breathing
