--!strict
--[[
	R6Math
	Pure math for procedural R6 motion. No services: unit-tested under Lune against the
	real R6 joint constants.

	THE key rule (read r6_motor6d_math.md):
	  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
	  Every procedural offset in this library is written in PART0 SPACE (e.g. "move the
	  torso down in HumanoidRootPart space", "rotate the head about the neck point in
	  Torso space") and converted once with jointOffset(). Offsets written directly in
	  C0's frame are what broke the legacy script: RootJoint.C0's local Y axis points
	  BACKWARDS and its local Z axis points UP.
]]

local R6Math = {}

-- Default R6 joints (Part0-space C0 / Part1-space C1), for reference and tests.
R6Math.DEFAULT_C0 = {
	RootJoint = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	Neck = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	RightHip = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftHip = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	RightShoulder = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftShoulder = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}
R6Math.DEFAULT_C1 = {
	RootJoint = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	Neck = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	RightHip = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftHip = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	RightShoulder = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftShoulder = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}

--[[
	Converts an offset expressed in Part0 space into the pre-multiplier for Transform:
	  Part0 * offset * C0 * T * C1^-1  ==  Part0 * C0 * (jointOffset(C0, offset) * T) * C1^-1
	so `joint.Transform = jointOffset(c0, offset) * animatedTransform` layers the offset
	on top of whatever the Animator produced this frame.
]]
function R6Math.jointOffset(c0: CFrame, part0Offset: CFrame): CFrame
	return c0:Inverse() * part0Offset * c0
end

-- Rotation `rotation` (in Part0 axes) about the Part0-space point `pivot`.
function R6Math.rotationAbout(pivot: Vector3, rotation: CFrame): CFrame
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot)
end

--[[
	Yaw/pitch of a direction expressed in the character root's space.
	yaw  > 0 : target is to the LEFT  (rotation about +Y)
	pitch > 0: target is ABOVE        (rotation about +X)
	Use them as CFrame.fromEulerAnglesYXZ(pitch, yaw, 0) to aim a -Z facing part.
]]
function R6Math.lookAngles(localDirection: Vector3): (number, number)
	if localDirection.Magnitude < 1e-6 then
		return 0, 0
	end
	local d = localDirection.Unit
	return math.atan2(-d.X, -d.Z), math.asin(math.clamp(d.Y, -1, 1))
end

--[[
	Foot planting solver for rigid (knee-less) R6 legs.

	leftError / rightError: ground height under each foot minus the resting foot height
	(both in root space). > 0: ground above the foot (would clip). < 0: foot floats.
	nil: no ground found under that foot (ledge) -> treated as "no adjustment".

	Returns:
	  drop  >= 0 : lower the whole body (RootJoint) so the lowest foot touches down;
	  raiseL/R >= 0 : then lift each foot by this much (tuck + hip bend).
]]
function R6Math.solveFeet(
	leftError: number?,
	rightError: number?,
	maxDrop: number,
	maxRaise: number
): (number, number, number)
	local eL = leftError or 0
	local eR = rightError or 0
	local drop = math.clamp(-math.min(eL, eR, 0), 0, maxDrop)
	local raiseL = math.clamp(eL + drop, 0, maxRaise)
	local raiseR = math.clamp(eR + drop, 0, maxRaise)
	return drop, raiseL, raiseR
end

--[[
	How to lift a rigid leg by `raise` studs:
	  1. tuck: slide the leg up into the torso (invisible on R6: same depth, hidden inside
	     the torso volume) up to `maxTuck`;
	  2. bend: swing the leg forward about the hip by `angle`, which lifts the foot by
	     legLength * (1 - cos(angle)).
	Returns (tuck, angle). Apply as CFrame.new(0, tuck, 0) * rotationAbout(hip, Angles(angle, 0, 0)).
]]
function R6Math.legRaise(raise: number, legLength: number, maxTuck: number): (number, number)
	local tuck = math.clamp(raise, 0, maxTuck)
	local rest = math.max(raise - tuck, 0)
	local angle = math.acos(math.clamp(1 - rest / legLength, -1, 1))
	return tuck, angle
end

export type LeanSettings = {
	referenceSpeed: number, -- speed (studs/s) that produces `speedLean`
	speedLean: number, -- radians of forward lean at referenceSpeed
	accelLean: number, -- multiplier on atan(acceleration / gravity)
	bankScale: number, -- multiplier on atan(centripetal acceleration / gravity)
	maxForward: number,
	maxBackward: number,
	maxBank: number,
}

--[[
	Physically-inspired lean targets.
	  forward lean = speed posture + atan(a_forward / g)   (accelerate -> lean in, brake -> lean back)
	  bank         = atan(yawRate * speed / g)             (a motorcycle's lean angle in a turn)
	localVelocity / localAcceleration are in root space (-Z = forward).
	yawRate > 0 when turning left. Returns (forwardLean > 0 = forward, bank > 0 = left).
]]
function R6Math.leanAngles(
	localVelocity: Vector3,
	localAcceleration: Vector3,
	yawRate: number,
	gravity: number,
	s: LeanSettings
): (number, number)
	local forwardSpeed = -localVelocity.Z
	local horizontalSpeed = Vector3.new(localVelocity.X, 0, localVelocity.Z).Magnitude
	local forwardAccel = -localAcceleration.Z
	local g = math.max(gravity, 1)

	local lean = s.speedLean * math.clamp(forwardSpeed / math.max(s.referenceSpeed, 1e-3), -1, 1.5)
		+ s.accelLean * math.atan(forwardAccel / g)
	local bank = s.bankScale * math.atan(yawRate * horizontalSpeed / g)

	return math.clamp(lean, -s.maxBackward, s.maxForward), math.clamp(bank, -s.maxBank, s.maxBank)
end

-- Forward lean that matches the slope ahead (uphill -> lean in). normal in root space.
function R6Math.slopeLean(localNormal: Vector3): number
	return math.asin(math.clamp(localNormal.Z, -1, 1))
end

-- Signed yaw change (radians) between two horizontal look vectors (+ = turned left).
function R6Math.yawDelta(previousLook: Vector3, currentLook: Vector3): number
	local a = Vector3.new(previousLook.X, 0, previousLook.Z)
	local b = Vector3.new(currentLook.X, 0, currentLook.Z)
	if a.Magnitude < 1e-6 or b.Magnitude < 1e-6 then
		return 0
	end
	a, b = a.Unit, b.Unit
	return math.atan2(a:Cross(b).Y, a:Dot(b))
end

function R6Math.smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Frame-rate independent exponential smoothing factor.
function R6Math.expAlpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

return R6Math
