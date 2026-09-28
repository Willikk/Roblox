--!strict
--[[
	Slash
	Weapon swing crescent.

	params.cframe  : slash frame. UpVector = normal of the swing plane (tilt it for
	                 diagonal slashes), LookVector = direction the blade travels towards.
	params.scale   : radius multiplier (1 = 5 studs).
	params.variant : bit 0 = mirrored sweep (right-to-left), bit 1 = no white core.
	params.power   : 0.5 (jab) .. 3 (heavy) -> width, lifetime.

	Mesh mode (preferred): MeshPart templates "Meshes/Slashes/Slash" and optional
	"Meshes/Slashes/SlashCore". Authoring convention: arc in the XZ plane, centered on the
	origin, bulging towards -Z, template Size = look at scale 1 (see blender_pipeline.md).
	Beam mode (fallback, zero assets): two BeamArcs (color + white core) that "draw" the
	crescent (head leads, tail wipes), with a sin-shaped width profile.
]]

local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Assets = require(VFX.Assets)
local BeamArc = require(VFX.BeamArc)
local Ease = require(VFX.Ease)
local Fade = require(VFX.Fade)
local Pool = require(VFX.Pool)
local Types = require(VFX.Types)

local Slash = {} :: Types.Effect
Slash.maxDistance = 350

local DEFAULT_COLOR = Color3.fromRGB(150, 205, 255)
local CORE_COLOR = Color3.fromRGB(255, 255, 255)
local BASE_RADIUS = 5
local SWEEP = math.rad(165)

local meshPools: { [string]: Pool.PartPool } = {}
local arcPool: Pool.Pool<BeamArc.BeamArc>? = nil

local function meshPool(name: string): Pool.PartPool?
	local existing = meshPools[name]
	if existing then
		return existing
	end
	local template = Assets.findPart(`Meshes/Slashes/{name}`)
	if template == nil then
		return nil
	end
	local pool = Pool.fromTemplate(template, Assets.workspaceFolder(), 4)
	meshPools[name] = pool
	return pool
end

local function getArcPool(): Pool.Pool<BeamArc.BeamArc>
	local pool = arcPool
	if pool == nil then
		pool = Pool.new(function(): BeamArc.BeamArc
			return BeamArc.new(Assets.workspaceFolder(), 2, { segmentsPerPiece = 16 })
		end, {
			prewarm = 4,
			onRelease = function(arc: BeamArc.BeamArc)
				arc:setEnabled(false)
			end,
		})
		arcPool = pool
	end
	return pool :: Pool.Pool<BeamArc.BeamArc>
end

-- Mesh layer: squash & stretch + spin + fade on one pooled MeshPart.
local function playMeshLayer(
	pool: Pool.PartPool,
	frame: CFrame,
	scale: number,
	color: Color3?,
	direction: number,
	lifetime: number,
	delay: number
)
	local part = pool:acquire()
	local snapshot = pool.snapshotOf[part]
	local baseSize = pool.template.Size * scale
	if color then
		part.Color = color
	end
	Fade.apply(snapshot, 0)

	Animator.play(lifetime, function(t)
		-- Spin: fast launch, soft settle (the arc "travels" through its sweep).
		local yaw = direction * math.rad(Ease.lerp(-38, 22, Ease.outQuart(t)))
		-- Width grows with an exponential snap; thickness pops then thins while dissolving.
		local grow = Ease.lerp(0.72, 1.12, Ease.outExpo(t))
		local thickness = Ease.lerp(0.12, 1, Ease.outExpo(Ease.phase(t, 0, 0.14)))
			* Ease.lerp(1, 0.3, Ease.inQuad(Ease.phase(t, 0.35, 1)))
		part.Size = Vector3.new(baseSize.X * grow, baseSize.Y * thickness, baseSize.Z * grow)
		Animator.move(part, frame * CFrame.Angles(0, yaw, 0))

		local fadeIn = Ease.outQuad(Ease.phase(t, 0, 0.06))
		local fadeOut = 1 - Ease.inQuad(Ease.phase(t, 0.4, 1))
		Fade.apply(snapshot, fadeIn * fadeOut)
	end, {
		delay = delay,
		onComplete = function()
			pool:release(part)
		end,
	})
end

-- Beam layer: the crescent is drawn head-first, then wiped from the tail.
local function playArcLayer(
	frame: CFrame,
	radius: number,
	width: number,
	color: Color3,
	direction: number,
	lifetime: number,
	zOffset: number
)
	local pool = getArcPool()
	local arc = pool:acquire()
	arc:setColor(color)
	for _, beam in arc.beams do
		beam.ZOffset = zOffset
	end
	arc:setFrame(frame)
	arc:setEnabled(true)

	local half = SWEEP / 2
	Animator.play(lifetime, function(t)
		local head = -half + SWEEP * Ease.outExpo(Ease.phase(t, 0, 0.32))
		local tail = -half + SWEEP * Ease.inQuad(Ease.phase(t, 0.12, 1))
		local r = radius * Ease.lerp(0.92, 1.06, Ease.outQuad(t))
		local w = width * Ease.lerp(1, 0.45, Ease.inQuad(Ease.phase(t, 0.3, 1)))
		local transparency = Ease.lerp(0.02, 1, Ease.inQuad(Ease.phase(t, 0.45, 1)))
		if head - tail < 1e-3 then
			arc:set(r, tail, tail + 1e-3, function()
				return 0
			end, 1)
			return
		end
		arc:set(r, tail * direction, head * direction, function(u)
			return w * math.sin(math.pi * u) ^ 0.75
		end, transparency)
	end, {
		onComplete = function()
			pool:release(arc)
		end,
	})
end

function Slash.preload()
	meshPool("Slash")
	meshPool("SlashCore")
	getArcPool()
end

function Slash.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local direction = if bit32.band(params.variant, 1) == 1 then -1 else 1
	local withCore = bit32.band(params.variant, 2) == 0
	local power = math.clamp(params.power, 0.25, 5)
	local lifetime = 0.26 + 0.05 * power
	local color = params.color or DEFAULT_COLOR

	local main = meshPool("Slash")
	if main then
		playMeshLayer(main, params.cframe, params.scale, params.color, direction, lifetime, 0)
		local core = if withCore then meshPool("SlashCore") else nil
		if core then
			playMeshLayer(core, params.cframe, params.scale * 0.94, CORE_COLOR, direction, lifetime * 0.85, 0.015)
		end
		return
	end

	-- Zero-asset fallback.
	local radius = BASE_RADIUS * params.scale
	local width = (0.9 + 0.35 * power) * params.scale
	playArcLayer(params.cframe, radius, width, color, direction, lifetime, 0)
	if withCore and ctx.quality > 0.3 then
		playArcLayer(params.cframe, radius * 0.985, width * 0.42, CORE_COLOR, direction, lifetime * 0.85, 0.15)
	end
end

return Slash
