--!strict
--[[
	Shockwave
	Expanding ground rings aligned to the real surface under the impact.

	params.cframe : impact point (only the position and the LookVector are used: the
	                client re-raycasts locally and aligns to the ground normal, so slopes,
	                stairs and terrain all look right).
	params.scale  : final radius multiplier (1 = 9 studs).
	params.power  : number of rings (1 + floor(power), max 4) and thickness.

	Mesh mode: MeshPart "Meshes/Shockwaves/Shockwave" (ring in the XZ plane, Y up).
	Fallback : expanding BeamArc ring + ForceField disc (zero assets).
]]

local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Assets = require(VFX.Assets)
local BeamArc = require(VFX.BeamArc)
local Ease = require(VFX.Ease)
local Fade = require(VFX.Fade)
local Pool = require(VFX.Pool)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local Shockwave = {} :: Types.Effect
Shockwave.maxDistance = 450

local BASE_RADIUS = 9
local DEFAULT_COLOR = Color3.fromRGB(235, 240, 255)
local RING_DELAY = 0.07

local meshPool: Pool.PartPool? = nil
local ringPool: Pool.Pool<BeamArc.BeamArc>? = nil
local discPool: Pool.PartPool? = nil

local function getMeshPool(): Pool.PartPool?
	if meshPool then
		return meshPool
	end
	local template = Assets.findPart("Meshes/Shockwaves/Shockwave")
	if template then
		meshPool = Pool.fromTemplate(template, Assets.workspaceFolder(), 4)
	end
	return meshPool
end

local function getRingPool(): Pool.Pool<BeamArc.BeamArc>
	local pool = ringPool
	if pool == nil then
		pool = Pool.new(function(): BeamArc.BeamArc
			return BeamArc.new(Assets.workspaceFolder(), 4, { segmentsPerPiece = 10 })
		end, {
			prewarm = 3,
			onRelease = function(arc: BeamArc.BeamArc)
				arc:setEnabled(false)
			end,
		})
		ringPool = pool
	end
	return pool :: Pool.Pool<BeamArc.BeamArc>
end

local function getDiscPool(): Pool.PartPool
	local pool = discPool
	if pool == nil then
		local template = Instance.new("Part")
		template.Name = "ShockwaveDisc"
		template.Shape = Enum.PartType.Cylinder
		template.Material = Enum.Material.ForceField
		template.Size = Vector3.new(0.2, 1, 1)
		template.Transparency = 0
		pool = Pool.fromTemplate(template, Assets.workspaceFolder(), 3)
		discPool = pool
	end
	return pool :: Pool.PartPool
end

-- Re-aligns the effect to the local ground (falls back to the sent orientation).
local function groundFrame(params: Types.EffectParams): CFrame
	local origin = params.cframe.Position
	local result = workspace:Raycast(origin + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), Assets.groundParams())
	if result then
		return VFXMath.alignToNormal(result.Position + result.Normal * 0.06, result.Normal, params.cframe.LookVector)
	end
	return params.cframe
end

local function playMeshRing(
	pool: Pool.PartPool,
	frame: CFrame,
	radius: number,
	thickness: number,
	color: Color3?,
	delay: number,
	spin: number
)
	local part = pool:acquire()
	local snapshot = pool.snapshotOf[part]
	if color then
		part.Color = color
	end
	Fade.apply(snapshot, 0)
	local lifetime = 0.55
	Animator.play(lifetime, function(t)
		local d = 2 * radius * Ease.lerp(0.15, 1, Ease.outExpo(t))
		local h = thickness * Ease.lerp(1.6, 0.12, Ease.outQuad(t))
		part.Size = Vector3.new(d, h, d)
		Animator.move(part, frame * CFrame.Angles(0, spin * t, 0))
		Fade.apply(snapshot, Ease.outQuad(Ease.phase(t, 0, 0.05)) * (1 - Ease.inQuad(Ease.phase(t, 0.25, 1))))
	end, {
		delay = delay,
		onComplete = function()
			pool:release(part)
		end,
	})
end

local function playBeamRing(frame: CFrame, radius: number, width: number, color: Color3, delay: number)
	local pool = getRingPool()
	local ring = pool:acquire()
	ring:setColor(color)
	ring:setFrame(frame)
	ring:set(0.01, 0, 2 * math.pi, function()
		return 0
	end, 1)
	ring:setEnabled(true)
	local lifetime = 0.5
	Animator.play(lifetime, function(t)
		local r = radius * Ease.lerp(0.1, 1, Ease.outExpo(t))
		local w = width * Ease.lerp(1, 0.15, Ease.outQuad(t))
		local transparency = Ease.lerp(0.05, 1, Ease.inQuad(Ease.phase(t, 0.2, 1)))
		ring:set(r, 0, 2 * math.pi, function()
			return w
		end, transparency)
	end, {
		delay = delay,
		onComplete = function()
			pool:release(ring)
		end,
	})
end

local function playDisc(frame: CFrame, radius: number, color: Color3)
	local pool = getDiscPool()
	local disc = pool:acquire()
	local snapshot = pool.snapshotOf[disc]
	disc.Color = color
	-- Cylinder axis is the part's X axis: rotate it onto the frame's Y (up).
	local flat = frame * CFrame.Angles(0, 0, math.pi / 2)
	Animator.play(0.4, function(t)
		local d = 2 * radius * Ease.lerp(0.1, 0.9, Ease.outExpo(t))
		disc.Size = Vector3.new(0.15, d, d)
		Animator.move(disc, flat)
		Fade.apply(snapshot, 0.55 * (1 - Ease.outQuad(t)))
	end, {
		onComplete = function()
			pool:release(disc)
		end,
	})
end

function Shockwave.preload()
	getMeshPool()
	getRingPool()
	getDiscPool()
end

function Shockwave.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local frame = groundFrame(params)
	local radius = BASE_RADIUS * params.scale
	local rings = math.clamp(1 + math.floor(params.power), 1, 4)
	if ctx.quality < 0.5 then
		rings = math.min(rings, 2)
	end
	local color = params.color or DEFAULT_COLOR

	local mesh = getMeshPool()
	for i = 1, rings do
		local k = i - 1
		local ringRadius = radius * (1 - 0.18 * k)
		local delay = k * RING_DELAY
		if mesh then
			local spin = (ctx.rng:NextNumber() - 0.5) * 1.2 -- seeded: identical on every client
			playMeshRing(mesh, frame, ringRadius, params.scale * (0.6 + 0.2 * params.power), params.color, delay, spin)
		else
			playBeamRing(frame, ringRadius, params.scale * (1.1 - 0.2 * k), color, delay)
		end
	end
	if mesh == nil then
		playDisc(frame, radius, color)
	end
end

return Shockwave
