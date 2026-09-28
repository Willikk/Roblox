--!strict
--[[
	Particles
	Pooled one-shot particle bursts (sparks, dust, embers) using ParticleEmitter:Emit().

	* Designers can override any kind with a ParticleEmitter named like the kind in
	  ReplicatedStorage.Assets.VFX.Particles (e.g. "Sparks"). Otherwise a procedural
	  emitter using built-in engine textures is used, so it works with zero assets.
	* Emitters are pooled per kind. A holder is NOT shared between simultaneous bursts:
	  Color/Size sequences are evaluated live for every particle, so recoloring a shared
	  emitter would recolor particles that are already flying.

	Usage:
		Particles.burst("Sparks", VFXMath.alignToNormal(hitPos, hitNormal), 18, { color = Color3.new(1, .8, .4) })
]]

local Assets = require(script.Parent.Assets)
local Pool = require(script.Parent.Pool)

export type Kind = "Sparks" | "Dust" | "Embers"

export type BurstOptions = {
	color: Color3?,
	sizeScale: number?,
	speedScale: number?,
	spread: number?, -- degrees, overrides SpreadAngle (both axes)
}

type Holder = {
	part: BasePart,
	attachment: Attachment,
	emitter: ParticleEmitter,
	baseSize: { NumberSequenceKeypoint },
	baseSpeed: NumberRange,
	baseColor: ColorSequence,
	baseSpread: Vector2,
	maxLifetime: number,
}

local Particles = {}

local BUILTIN_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local BUILTIN_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function proceduralEmitter(kind: Kind): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LockedToPart = false
	e.EmissionDirection = Enum.NormalId.Top
	if kind == "Sparks" then
		e.Texture = BUILTIN_SPARK
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Brightness = 3
		e.Lifetime = NumberRange.new(0.15, 0.35)
		e.Speed = NumberRange.new(28, 48)
		e.SpreadAngle = Vector2.new(55, 55)
		e.Drag = 6
		e.Acceleration = Vector3.new(0, -45, 0)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Squash = NumberSequence.new(1.2)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 160))
	elseif kind == "Dust" then
		e.Texture = BUILTIN_SMOKE
		e.LightEmission = 0
		e.LightInfluence = 1
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(8, 16)
		e.SpreadAngle = Vector2.new(80, 80)
		e.Drag = 4
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 5.5),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Color = ColorSequence.new(Color3.fromRGB(150, 140, 125))
	else -- Embers
		e.Texture = BUILTIN_SPARK
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Brightness = 2
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(8, 18)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Drag = 2
		e.Acceleration = Vector3.new(0, 8, 0)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Color = ColorSequence.new(Color3.fromRGB(255, 170, 90))
	end
	return e
end

local pools: { [Kind]: Pool.Pool<Holder> } = {}

local function makeHolder(kind: Kind): Holder
	local part = Instance.new("Part")
	part.Name = `Particles_{kind}`
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	Pool.makeVisual(part)
	part.CFrame = Pool.PARK_CFRAME

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local template = Assets.find(`Particles/{kind}`)
	local emitter: ParticleEmitter = if template and template:IsA("ParticleEmitter")
		then template:Clone()
		else proceduralEmitter(kind)
	emitter.Enabled = false
	emitter.Parent = attachment
	part.Parent = Assets.workspaceFolder()

	return {
		part = part,
		attachment = attachment,
		emitter = emitter,
		baseSize = emitter.Size.Keypoints,
		baseSpeed = emitter.Speed,
		baseColor = emitter.Color,
		baseSpread = emitter.SpreadAngle,
		maxLifetime = emitter.Lifetime.Max,
	}
end

local function poolFor(kind: Kind): Pool.Pool<Holder>
	local pool = pools[kind]
	if pool == nil then
		pool = Pool.new(function(): Holder
			return makeHolder(kind)
		end, {
			onRelease = function(holder: Holder)
				holder.part.CFrame = Pool.PARK_CFRAME
			end,
		})
		pools[kind] = pool
	end
	return pool :: Pool.Pool<Holder>
end

-- Emits `count` particles from `cframe` (particles leave along cframe.UpVector).
function Particles.burst(kind: Kind, cframe: CFrame, count: number, options: BurstOptions?)
	local n = math.floor(count + 0.5)
	if n <= 0 then
		return
	end
	local pool = poolFor(kind)
	local holder = pool:acquire()
	local emitter = holder.emitter

	local sizeScale = if options and options.sizeScale then options.sizeScale else 1
	local speedScale = if options and options.speedScale then options.speedScale else 1

	local keypoints = table.create(#holder.baseSize)
	for i, kp in holder.baseSize do
		keypoints[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * sizeScale, kp.Envelope * sizeScale)
	end
	emitter.Size = NumberSequence.new(keypoints)
	emitter.Speed = NumberRange.new(holder.baseSpeed.Min * speedScale, holder.baseSpeed.Max * speedScale)
	emitter.Color = if options and options.color then ColorSequence.new(options.color) else holder.baseColor
	emitter.SpreadAngle = if options and options.spread
		then Vector2.new(options.spread, options.spread)
		else holder.baseSpread

	-- Must be a direct write (not Animator.move): Emit() samples the position right now.
	holder.part.CFrame = cframe
	emitter:Emit(n)

	-- Real time on purpose (not time-scaled): particles themselves ignore hitstop.
	task.delay(holder.maxLifetime + 0.1, function()
		pool:release(holder)
	end)
end

-- Builds the pools ahead of time so the first burst does not allocate.
function Particles.prewarm(kinds: { Kind }, perKind: number)
	for _, kind in kinds do
		local pool = poolFor(kind :: Kind)
		local held = {}
		for i = 1, perKind do
			held[i] = pool:acquire()
		end
		for _, holder in held do
			pool:release(holder)
		end
	end
end

return Particles
