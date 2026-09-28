--!strict
--[[
	TerrainAdaptation
	Foot planting for rigid R6 legs on stairs, rocks and slopes.

	1. Pelvis drop: the Humanoid stands on the HIGHEST point under its hitbox, so on a
	   stair edge one foot floats. The whole body is lowered until the lowest foot
	   touches its ground.
	2. Foot raise: the other foot, now clipping, is lifted by tucking the leg into the
	   torso (hidden on R6) and then bending it forward at the hip.
	Planting fades out with speed (the walk cycle owns the legs while running); the
	pelvis drop is partially kept so running down stairs still hugs the steps.
]]

local R6Procedural = script.Parent.Parent
local R6Math = require(R6Procedural.R6Math)
local Spring = require(R6Procedural.Spring)
local Types = require(R6Procedural.Types)

local TerrainAdaptation = { name = "TerrainAdaptation" } :: Types.Layer

function TerrainAdaptation.update(rig, sensor, dt, cfg, ctx)
	local c = cfg.terrain
	local state = rig.layerState.TerrainAdaptation
	if state == nil then
		state = Spring.new(Vector3.zero, c.frequency, c.damping)
		rig.layerState.TerrainAdaptation = state
	end
	local spring = state :: Spring.Spring

	local speed = Vector3.new(sensor.velocity.X, 0, sensor.velocity.Z).Magnitude
	local moving = R6Math.smoothstep(c.plantFadeStart, c.plantFadeEnd, speed)
	local base = sensor.stateWeight * ctx.weight("R6_Terrain") * (if sensor.grounded then 1 else 0)
	local plantWeight = base * (1 - moving)
	local dropWeight = base * (1 - moving * (1 - c.runningDropWeight))

	local drop, raiseL, raiseR = R6Math.solveFeet(sensor.leftError, sensor.rightError, c.maxPelvisDrop, c.maxFootRaise)
	spring.target = Vector3.new(drop * dropWeight, raiseL * plantWeight, raiseR * plantWeight)
	local p = spring:update(dt)
	local d = math.max(p.X, 0)

	if d > 1e-3 then
		rig:add("RootJoint", CFrame.new(0, -d, 0))
	end
	local hipPivot = Vector3.new(0, rig.hipLineY, 0)
	local function raiseLeg(joint: "LeftHip" | "RightHip", raise: number)
		if raise <= 1e-3 then
			return
		end
		local tuck, angle = R6Math.legRaise(raise, rig.legLength, c.maxTuck)
		rig:add(joint, CFrame.new(0, tuck, 0) * R6Math.rotationAbout(hipPivot, CFrame.Angles(angle, 0, 0)))
	end
	raiseLeg("LeftHip", p.Y)
	raiseLeg("RightHip", p.Z)
end

return TerrainAdaptation
