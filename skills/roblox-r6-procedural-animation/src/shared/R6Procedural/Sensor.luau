--!strict
--[[
	Sensor
	Per-character kinematics and ground sensing shared by all layers.

	Velocity is derived from the root's POSITION history (smoothed), not from
	AssemblyLinearVelocity: it is identical for the local player, other players
	(interpolated replication), NPCs and anchored/animated rigs.
]]

local Config = require(script.Parent.Config)
local R6Math = require(script.Parent.R6Math)
local Rig = require(script.Parent.Rig)

export type Sensor = {
	lastPosition: Vector3?,
	lastLook: Vector3?,
	velocity: Vector3, -- world, smoothed
	rawVelocity: Vector3,
	acceleration: Vector3, -- world, smoothed
	yawRate: number, -- rad/s, + = turning left
	grounded: boolean,
	airTime: number,
	fallSpeed: number, -- downward speed while airborne (>= 0)
	landingImpact: number, -- > 0 only on the frame the character lands
	leftError: number?, -- ground height - rest foot height (root space)
	rightError: number?,
	groundNormal: Vector3, -- root space
	stateWeight: number, -- 0..1, fades procedural motion in unsuitable states
}

local Sensor = {}

local BLOCKING_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

function Sensor.new(): Sensor
	return {
		lastPosition = nil,
		lastLook = nil,
		velocity = Vector3.zero,
		rawVelocity = Vector3.zero,
		acceleration = Vector3.zero,
		yawRate = 0,
		grounded = true,
		airTime = 0,
		fallSpeed = 0,
		landingImpact = 0,
		leftError = nil,
		rightError = nil,
		groundNormal = Vector3.yAxis,
		stateWeight = 1,
	}
end

local function footRay(
	rig: Rig.Rig,
	side: number,
	shift: Vector3,
	params: RaycastParams,
	cfg: Config.Config
): RaycastResult?
	local rootCF = rig.root.CFrame
	local origin = rootCF.Position + rootCF.RightVector * (side * rig.hipHalfWidth) + shift
	return workspace:Raycast(origin, Vector3.new(0, -cfg.sensing.rayLength, 0), params)
end

-- `sense` = false on LOD frames: kinematics still update, rays are skipped.
function Sensor.update(
	sensor: Sensor,
	rig: Rig.Rig,
	dt: number,
	params: RaycastParams,
	cfg: Config.Config,
	isLocal: boolean,
	sense: boolean
)
	local s = cfg.sensing
	local rootCF = rig.root.CFrame
	local position = rootCF.Position
	dt = math.max(dt, 1e-3)

	-- Kinematics.
	local previousVelocity = sensor.velocity
	if sensor.lastPosition then
		local raw = (position - sensor.lastPosition :: Vector3) / dt
		if raw.Magnitude > 400 then
			raw = sensor.rawVelocity -- teleport: ignore the jump
		end
		sensor.rawVelocity = raw
		sensor.velocity = sensor.velocity:Lerp(raw, R6Math.expAlpha(s.velocitySharpness, dt))
	end
	local accel = (sensor.velocity - previousVelocity) / dt
	sensor.acceleration = sensor.acceleration:Lerp(accel, R6Math.expAlpha(s.accelerationSharpness, dt))
	local look = rootCF.LookVector
	if sensor.lastLook then
		local rate = R6Math.yawDelta(sensor.lastLook :: Vector3, look) / dt
		sensor.yawRate += (rate - sensor.yawRate) * R6Math.expAlpha(s.yawRateSharpness, dt)
	end
	sensor.lastPosition = position
	sensor.lastLook = look

	-- State weight.
	local humanoid = rig.humanoid
	local blocked = humanoid.Sit or humanoid.PlatformStand or humanoid.Health <= 0
	if isLocal and not blocked then
		blocked = BLOCKING_STATES[humanoid:GetState()] == true
	end
	local targetWeight = if blocked then 0 else 1
	sensor.stateWeight += (targetWeight - sensor.stateWeight) * R6Math.expAlpha(10, dt)

	-- Ground.
	sensor.landingImpact = 0
	if sense then
		local horizontal = Vector3.new(sensor.velocity.X, 0, sensor.velocity.Z)
		local shift = horizontal * s.lookAhead
		local left = footRay(rig, -1, shift, params, cfg)
		local right = footRay(rig, 1, shift, params, cfg)
		sensor.leftError = if left then (left.Position.Y - position.Y) - rig.restFootY else nil
		sensor.rightError = if right then (right.Position.Y - position.Y) - rig.restFootY else nil

		local normal = Vector3.zero
		if left then
			normal += left.Normal
		end
		if right then
			normal += right.Normal
		end
		sensor.groundNormal = if normal.Magnitude > 1e-3 then rootCF:VectorToObjectSpace(normal.Unit) else Vector3.yAxis

		local lowestError = math.min(sensor.leftError or -math.huge, sensor.rightError or -math.huge)
		local grounded = lowestError > -s.groundTolerance - 0.5 and math.abs(sensor.rawVelocity.Y) < 30
		if not grounded then
			sensor.airTime += dt
			sensor.fallSpeed = math.max(0, -sensor.rawVelocity.Y)
		elseif not sensor.grounded then
			sensor.landingImpact = sensor.fallSpeed
			sensor.airTime = 0
			sensor.fallSpeed = 0
		end
		sensor.grounded = grounded
	end
end

return Sensor
