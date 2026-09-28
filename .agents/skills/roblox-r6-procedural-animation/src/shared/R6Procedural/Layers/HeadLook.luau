--!strict
--[[
	HeadLook
	Head (and a share of the torso) turns towards the look target: the camera for the
	local player, replicated angles for other players, the "R6_LookAt" attribute
	(Vector3 world point) for NPCs.

	* Targets behind the character relax to neutral instead of snapping to a clamp.
	* Torso takes `torsoShare` of the yaw; the legs counter-twist so feet stay planted.
	* The neck compensates the body lean/bank, keeping the gaze level (stabilization).
]]

local R6Procedural = script.Parent.Parent
local R6Math = require(R6Procedural.R6Math)
local Spring = require(R6Procedural.Spring)
local Types = require(R6Procedural.Types)

local HeadLook = { name = "HeadLook" } :: Types.Layer

function HeadLook.update(rig, sensor, dt, cfg, ctx)
	local c = cfg.head
	local state = rig.layerState.HeadLook
	if state == nil then
		state = Spring.new(Vector3.zero, c.frequency, c.damping)
		rig.layerState.HeadLook = state
	end
	local spring = state :: Spring.Spring

	local yaw, pitch = 0, 0
	local target = ctx.lookTarget
	if target then
		yaw, pitch = target.yaw, target.pitch
		if math.abs(yaw) > c.backCutoff then
			yaw, pitch = 0, 0
		end
		yaw = math.clamp(yaw, -c.maxYaw, c.maxYaw)
		pitch = math.clamp(pitch, -c.maxDown, c.maxUp)
	end
	local weight = sensor.stateWeight * ctx.weight("R6_HeadLook")
	spring.target = Vector3.new(yaw, pitch, 0) * weight
	local p = spring:update(dt)
	local smoothYaw, smoothPitch = p.X, p.Y

	local torsoYaw = smoothYaw * c.torsoShare
	if math.abs(torsoYaw) > 1e-4 then
		rig:add("RootJoint", CFrame.Angles(0, torsoYaw, 0))
		local counter = R6Math.rotationAbout(Vector3.new(0, rig.hipLineY, 0), CFrame.Angles(0, -torsoYaw, 0))
		rig:add("LeftHip", counter)
		rig:add("RightHip", counter)
	end

	local neckPitch = smoothPitch + rig.pose.lean * c.leanCompensation
	local neckRoll = -rig.pose.bank * c.bankCompensation
	local neckPivot = rig:c0("Neck").Position
	rig:add(
		"Neck",
		R6Math.rotationAbout(neckPivot, CFrame.fromEulerAnglesYXZ(neckPitch, smoothYaw - torsoYaw, neckRoll))
	)

	if c.armPitchShare > 0 then
		local armPitch = smoothPitch * c.armPitchShare
		rig:add("LeftShoulder", R6Math.rotationAbout(rig:c0("LeftShoulder").Position, CFrame.Angles(armPitch, 0, 0)))
		rig:add("RightShoulder", R6Math.rotationAbout(rig:c0("RightShoulder").Position, CFrame.Angles(armPitch, 0, 0)))
	end
end

return HeadLook
