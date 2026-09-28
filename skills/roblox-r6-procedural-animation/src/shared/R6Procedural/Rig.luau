--!strict
--[[
	Rig
	Finds the six R6 joints and layers procedural offsets on top of the animation.

	How offsets are written (the officially recommended layering, see Motor6D/
	AnimationConstraint docs): every frame, in RunService.PreSimulation, AFTER the
	Animator wrote its pose,
	    joint.Transform = jointOffset(C0, part0Offset) * animatedTransform
	Advantages over writing C0:
	  * stacks with any animation instead of fighting it;
	  * works for Motor6D AND AnimationConstraint (Avatar Joint Upgrade) joints;
	  * nothing to "restore": the Animator rewrites Transform next frame.

	Robustness: when the Animator did NOT rewrite Transform this frame (no track on that
	joint, Animator.EvaluationThrottled, far LOD) we detect our own last write and
	re-apply on the stored base, so offsets never accumulate.
]]

local R6Math = require(script.Parent.R6Math)

export type JointName = "RootJoint" | "Neck" | "LeftHip" | "RightHip" | "LeftShoulder" | "RightShoulder"

type JointInstance = Motor6D | AnimationConstraint

type JointState = {
	instance: JointInstance,
	offset: CFrame, -- accumulated Part0-space offset for this frame
	lastWritten: CFrame?,
	lastBase: CFrame?,
}

export type Pose = {
	lean: number, -- current forward lean (rad), shared between layers
	bank: number,
}

export type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	head: BasePart?,
	joints: { [JointName]: JointState },
	pose: Pose,
	layerState: { [string]: any },
	-- Geometry (read from the actual parts: scaled rigs work).
	legLength: number,
	restFootY: number, -- resting foot height relative to the root center (negative)
	hipLineY: number, -- torso-space Y of the hip line (bottom of the torso)
	hipHalfWidth: number, -- torso-space X of each leg's center line

	begin: (self: Rig) -> (),
	add: (self: Rig, joint: JointName, part0Offset: CFrame) -> (),
	apply: (self: Rig) -> (),
	restore: (self: Rig) -> (),
	isAlive: (self: Rig) -> boolean,
	c0: (self: Rig, joint: JointName) -> CFrame,
}

local Rig = {}
Rig.__index = Rig

local JOINT_LOOKUP: { [JointName]: { part: string, name: string } } = {
	RootJoint = { part = "HumanoidRootPart", name = "RootJoint" },
	Neck = { part = "Torso", name = "Neck" },
	LeftHip = { part = "Torso", name = "Left Hip" },
	RightHip = { part = "Torso", name = "Right Hip" },
	LeftShoulder = { part = "Torso", name = "Left Shoulder" },
	RightShoulder = { part = "Torso", name = "Right Shoulder" },
}

local IDENTITY = CFrame.new()

local function asJoint(inst: Instance?): JointInstance?
	if inst == nil then
		return nil
	elseif inst:IsA("Motor6D") then
		return inst
	elseif inst:IsA("AnimationConstraint") then
		return inst
	end
	return nil
end

local function findJoint(character: Model, partName: string, jointName: string): JointInstance?
	local part = character:FindFirstChild(partName)
	local direct = asJoint(part and part:FindFirstChild(jointName))
	if direct then
		return direct
	end
	-- AnimationConstraints may live elsewhere in the model.
	for _, descendant in character:GetDescendants() do
		if descendant.Name == jointName then
			local joint = asJoint(descendant)
			if joint then
				return joint
			end
		end
	end
	return nil
end

local function getC0(joint: JointInstance): CFrame
	if joint:IsA("Motor6D") then
		return joint.C0
	end
	local constraint = joint :: AnimationConstraint
	local attachment = constraint.Attachment0
	return if attachment then attachment.CFrame else IDENTITY
end

local function getTransform(joint: JointInstance): CFrame
	if joint:IsA("Motor6D") then
		return joint.Transform
	end
	return (joint :: AnimationConstraint).Transform
end

local function setTransform(joint: JointInstance, value: CFrame)
	if joint:IsA("Motor6D") then
		joint.Transform = value
	else
		(joint :: AnimationConstraint).Transform = value
	end
end

local function same(a: CFrame, b: CFrame): boolean
	return a.Position:FuzzyEq(b.Position, 1e-5)
		and a.XVector:FuzzyEq(b.XVector, 1e-5)
		and a.YVector:FuzzyEq(b.YVector, 1e-5)
end

local function isIdentity(cf: CFrame): boolean
	return same(cf, IDENTITY)
end

-- Returns nil when the model is not a complete R6 rig (yet).
function Rig.new(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end
	if root == nil or not root:IsA("BasePart") or torso == nil or not torso:IsA("BasePart") then
		return nil
	end
	local joints = {} :: { [JointName]: JointState }
	for name, where in JOINT_LOOKUP do
		local joint = findJoint(character, where.part, where.name)
		if joint == nil then
			return nil
		end
		joints[name :: JointName] = { instance = joint, offset = IDENTITY, lastWritten = nil, lastBase = nil }
	end

	local leg = character:FindFirstChild("Left Leg")
	local legLength = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	local head = character:FindFirstChild("Head")

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		torso = torso,
		head = if head and head:IsA("BasePart") then head else nil,
		joints = joints,
		pose = { lean = 0, bank = 0 },
		layerState = {},
		legLength = legLength,
		-- Humanoid docs (R6): Height = LeftLeg.Size.Y + 0.5 * RootPart.Size.Y + HipHeight
		restFootY = -(legLength + 0.5 * root.Size.Y + humanoid.HipHeight),
		hipLineY = -0.5 * torso.Size.Y,
		hipHalfWidth = 0.25 * torso.Size.X,
	}, Rig)
	return (self :: any) :: Rig
end

function Rig.c0(self: Rig, joint: JointName): CFrame
	return getC0(self.joints[joint].instance)
end

-- Clears this frame's offsets (called before the layers run).
function Rig.begin(self: Rig)
	for _, joint in self.joints do
		joint.offset = IDENTITY
	end
end

-- Adds a Part0-space offset (later layers are applied on the outside).
function Rig.add(self: Rig, joint: JointName, part0Offset: CFrame)
	local state = self.joints[joint]
	state.offset = part0Offset * state.offset
end

-- Writes Transform for every joint. Must run every frame (PreSimulation), even on
-- frames where the layers did not re-sense, because the Animator resets Transform.
function Rig.apply(self: Rig)
	for _, joint in self.joints do
		local instance = joint.instance
		local current = getTransform(instance)
		local lastWritten = joint.lastWritten
		local base = if lastWritten and joint.lastBase and same(current, lastWritten) then joint.lastBase else current

		if isIdentity(joint.offset) then
			if lastWritten then
				if base ~= current then
					setTransform(instance, base)
				end
				joint.lastWritten, joint.lastBase = nil, nil
			end
			continue
		end

		local out = R6Math.jointOffset(getC0(instance), joint.offset) * base
		setTransform(instance, out)
		joint.lastWritten, joint.lastBase = out, base
	end
end

-- Removes every procedural offset (LOD off, disabled, rig removed).
function Rig.restore(self: Rig)
	self:begin()
	self:apply()
end

function Rig.isAlive(self: Rig): boolean
	return self.character.Parent ~= nil
		and self.root.Parent ~= nil
		and self.torso.Parent ~= nil
		and self.humanoid.Health > 0
end

return Rig
