--!strict
--[[
	PoseLibrary
	Keyframed procedural poses for R6 (combat moves, reactions) with ZERO animation assets.

	A pose = per-joint rotation (degrees, Part0 space, applied about the joint's natural
	pivot) + optional translation (studs, Part0 space). Conventions (tested):
	  * Shoulders / hips:  X+ swings the limb FORWARD (90 = pointing forward, 170 = overhead),
	                       Z+ moves the hand towards +X (right arm: outwards, left arm: inwards).
	  * RootJoint (torso): X+ leans BACK, Y+ twists LEFT, Z+ tilts LEFT. Pivot: hip line.
	  * Neck:              X+ looks up, Y+ looks left.
	Clips are sampled with world/server time so every client shows the same frame.

	Attack clips are generated from the move timings (windup / active / recovery), so the
	visible strike ALWAYS matches the server hitbox window.
]]

local R6Math = require(script.Parent.R6Math)

export type JointName = "RootJoint" | "Neck" | "LeftHip" | "RightHip" | "LeftShoulder" | "RightShoulder"
export type JointPose = { rot: Vector3, pos: Vector3? }
export type Pose = { [string]: JointPose }
export type Keyframe = { t: number, pose: Pose, ease: ((number) -> number)? }
export type Clip = {
	duration: number,
	keys: { Keyframe },
	blendIn: number,
	blendOut: number,
	loop: boolean?,
}

local PoseLibrary = {}

local function outQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function outExpo(t: number): number
	return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
end
local function inOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end
local function inQuad(t: number): number
	return t * t
end
PoseLibrary.ease = { outQuad = outQuad, outExpo = outExpo, inOutSine = inOutSine, inQuad = inQuad }

local NEUTRAL: Pose = {}
PoseLibrary.NEUTRAL = NEUTRAL

local JOINTS: { JointName } = { "RootJoint", "Neck", "LeftHip", "RightHip", "LeftShoulder", "RightShoulder" }
PoseLibrary.JOINTS = JOINTS

local function jp(x: number, y: number, z: number, pos: Vector3?): JointPose
	return { rot = Vector3.new(x, y, z), pos = pos }
end
PoseLibrary.jp = jp

-- Linear blend of two poses (missing joints = neutral).
function PoseLibrary.blend(a: Pose, b: Pose, t: number): Pose
	local out: Pose = {}
	for _, name in JOINTS do
		local joint = name
		local ja, jb = a[joint], b[joint]
		if ja or jb then
			local ra = if ja then ja.rot else Vector3.zero
			local rb = if jb then jb.rot else Vector3.zero
			local pa = if ja and ja.pos then ja.pos else Vector3.zero
			local pb = if jb and jb.pos then jb.pos else Vector3.zero
			out[joint] = { rot = ra:Lerp(rb, t), pos = pa:Lerp(pb, t) }
		end
	end
	return out
end

-- Samples a clip at `time` seconds. Returns the pose and the blend weight (0..1).
function PoseLibrary.sample(clip: Clip, time: number): (Pose, number)
	local duration = clip.duration
	if clip.loop then
		time %= duration
	elseif time < 0 or time > duration then
		return NEUTRAL, 0
	end
	local keys = clip.keys
	local pose: Pose = keys[1].pose
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if time >= a.t and time <= b.t then
			local span = b.t - a.t
			local k = if span > 0 then (time - a.t) / span else 1
			local ease = b.ease or inOutSine
			pose = PoseLibrary.blend(a.pose, b.pose, ease(k))
			break
		elseif i == #keys - 1 then
			pose = b.pose
		end
	end
	local weight = 1
	if not clip.loop then
		if clip.blendIn > 0 then
			weight = math.min(weight, time / clip.blendIn)
		end
		if clip.blendOut > 0 then
			weight = math.min(weight, (duration - time) / clip.blendOut)
		end
	end
	return pose, math.clamp(weight, 0, 1)
end

--[[
	Part0-space offset CFrame of one joint for a pose entry, rotating about the joint's
	natural pivot. `pivot` comes from the rig (hip line for torso/hips, C0 position for
	neck/shoulders).
]]
function PoseLibrary.jointCFrame(entry: JointPose, pivot: Vector3, weight: number): CFrame
	local r = entry.rot * (math.pi / 180 * weight)
	local rotation = CFrame.fromEulerAnglesYXZ(r.X, r.Y, r.Z)
	local offset = R6Math.rotationAbout(pivot, rotation)
	if entry.pos then
		offset = CFrame.new(entry.pos * weight) * offset
	end
	return offset
end

export type AttackPoses = { windup: Pose, strike: Pose, follow: Pose? }
export type Timing = { windup: number, active: number, recovery: number }

--[[
	Builds an attack clip whose keys line up with gameplay timings:
	  0 -> windup      : neutral -> windup pose (anticipation, easeOut)
	  windup -> +active : windup -> strike pose (explosive, outExpo) = hitbox window
	  -> +recovery      : strike -> follow-through -> neutral
]]
function PoseLibrary.attack(poses: AttackPoses, timing: Timing): Clip
	local t1 = timing.windup
	local t2 = t1 + timing.active
	local t3 = t2 + timing.recovery
	local follow = poses.follow or poses.strike
	return {
		duration = t3,
		blendIn = math.min(0.06, t1),
		blendOut = math.min(0.12, timing.recovery),
		keys = {
			{ t = 0, pose = NEUTRAL },
			{ t = t1, pose = poses.windup, ease = outQuad },
			{ t = t2, pose = poses.strike, ease = outExpo },
			{ t = t2 + timing.recovery * 0.45, pose = follow, ease = outQuad },
			{ t = t3, pose = NEUTRAL, ease = inOutSine },
		},
	}
end

-- Held pose (block stance, idle guard): short blend in, loops until the action changes.
function PoseLibrary.hold(pose: Pose, blendIn: number): Clip
	return {
		duration = 1,
		blendIn = blendIn,
		blendOut = 0,
		loop = true,
		keys = { { t = 0, pose = pose }, { t = 1, pose = pose } },
	}
end

-- One-shot reaction: snap to `pose` then recover over `duration`.
function PoseLibrary.reaction(pose: Pose, snap: number, duration: number): Clip
	return {
		duration = duration,
		blendIn = 0,
		blendOut = duration * 0.4,
		keys = {
			{ t = 0, pose = NEUTRAL },
			{ t = snap, pose = pose, ease = outExpo },
			{ t = duration, pose = NEUTRAL, ease = inOutSine },
		},
	}
end

------------------------------------------------------------------------------------
-- Clip registry (combat code registers its own clips; defaults below are ready to use)
------------------------------------------------------------------------------------

local clips: { [string]: Clip } = {}

function PoseLibrary.register(name: string, clip: Clip)
	clips[name] = clip
end

function PoseLibrary.get(name: string): Clip?
	return clips[name]
end

-- Generic reactions / stances (weapon-agnostic).
PoseLibrary.register(
	"Stagger",
	PoseLibrary.reaction({
		RootJoint = jp(14, 0, -6),
		Neck = jp(18, 8, 0),
		RightShoulder = jp(-15, 0, 20),
		LeftShoulder = jp(-15, 0, -20),
	}, 0.06, 0.45)
)
PoseLibrary.register(
	"GuardBroken",
	PoseLibrary.reaction({
		RootJoint = jp(24, 0, 0, Vector3.new(0, -0.3, 0)),
		Neck = jp(25, 0, 0),
		RightShoulder = jp(40, 0, 70),
		LeftShoulder = jp(40, 0, -70),
		LeftHip = jp(-18, 0, 0),
		RightHip = jp(10, 0, 0),
	}, 0.08, 1.1)
)
PoseLibrary.register(
	"Parried", -- attacker recoil after being parried
	PoseLibrary.reaction({
		RootJoint = jp(16, -12, 0),
		RightShoulder = jp(150, 0, 35),
		Neck = jp(12, 0, 0),
	}, 0.07, 0.6)
)
PoseLibrary.register(
	"DodgeLeft",
	PoseLibrary.reaction({
		RootJoint = jp(-10, 0, 22, Vector3.new(0, -0.6, 0)),
		LeftHip = jp(20, 0, -15),
		RightHip = jp(-10, 0, 25),
		LeftShoulder = jp(30, 0, -40),
		RightShoulder = jp(-20, 0, 30),
	}, 0.08, 0.4)
)
PoseLibrary.register(
	"DodgeRight",
	PoseLibrary.reaction({
		RootJoint = jp(-10, 0, -22, Vector3.new(0, -0.6, 0)),
		RightHip = jp(20, 0, 15),
		LeftHip = jp(-10, 0, -25),
		RightShoulder = jp(30, 0, 40),
		LeftShoulder = jp(-20, 0, -30),
	}, 0.08, 0.4)
)
PoseLibrary.register(
	"DodgeBack",
	PoseLibrary.reaction({
		RootJoint = jp(-16, 0, 0, Vector3.new(0, -0.7, 0)),
		LeftHip = jp(35, 0, 0),
		RightHip = jp(-25, 0, 0),
		LeftShoulder = jp(40, 0, -15),
		RightShoulder = jp(40, 0, 15),
	}, 0.08, 0.4)
)

return PoseLibrary
