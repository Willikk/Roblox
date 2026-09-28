--!strict
--[[
	Shapes
	Pooled building blocks for combat feedback, shared by the combat effects:
	  flash(position, color, size, duration, light)   neon sphere + point light pop
	  ring(frame, r0, r1, width, color, duration)      expanding BeamArc ring (plane = frame XZ)
	  star(position, color, length, duration, rng)     crossed neon spikes: the "parry spark"
	  shards(position, color, count, speed, rng)       glassy chips flung out (guard break)
	  highlight(model, color, duration, name)          body flash (restarts on re-trigger)
]]

local Animator = require(script.Parent.Animator)
local Assets = require(script.Parent.Assets)
local BeamArc = require(script.Parent.BeamArc)
local Ease = require(script.Parent.Ease)
local Fade = require(script.Parent.Fade)
local Pool = require(script.Parent.Pool)
local VFXMath = require(script.Parent.VFXMath)

local Shapes = {}

local flashPool: Pool.PartPool? = nil
local spikePool: Pool.PartPool? = nil
local shardPool: Pool.PartPool? = nil
local ringPool: Pool.Pool<BeamArc.BeamArc>? = nil
local highlights: { [Instance]: { highlight: Highlight, handle: Animator.Handle? } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

local function getFlashPool(): Pool.PartPool
	if flashPool == nil then
		local template = Instance.new("Part")
		template.Shape = Enum.PartType.Ball
		template.Material = Enum.Material.Neon
		template.Size = Vector3.one
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 8
		light.Shadows = false
		light.Parent = template
		flashPool = Pool.fromTemplate(template, Assets.workspaceFolder(), 8)
	end
	return flashPool :: Pool.PartPool
end

local function getSpikePool(): Pool.PartPool
	if spikePool == nil then
		local template = Instance.new("Part")
		template.Material = Enum.Material.Neon
		template.Size = Vector3.new(0.12, 0.12, 1)
		spikePool = Pool.fromTemplate(template, Assets.workspaceFolder(), 12)
	end
	return spikePool :: Pool.PartPool
end

local function getShardPool(): Pool.PartPool
	if shardPool == nil then
		local template = Instance.new("WedgePart")
		template.Material = Enum.Material.Glass
		template.Transparency = 0.15
		template.Size = Vector3.new(0.15, 0.6, 0.5)
		shardPool = Pool.fromTemplate(template, Assets.workspaceFolder(), 12)
	end
	return shardPool :: Pool.PartPool
end

local function getRingPool(): Pool.Pool<BeamArc.BeamArc>
	if ringPool == nil then
		ringPool = Pool.new(function(): BeamArc.BeamArc
			return BeamArc.new(Assets.workspaceFolder(), 4, { segmentsPerPiece = 8 })
		end, {
			prewarm = 4,
			onRelease = function(arc: BeamArc.BeamArc)
				arc:setEnabled(false)
			end,
		})
	end
	return ringPool :: Pool.Pool<BeamArc.BeamArc>
end

function Shapes.flash(position: Vector3, color: Color3, size: number, duration: number, lightBrightness: number?)
	local pool = getFlashPool()
	local part = pool:acquire()
	local snapshot = pool.snapshotOf[part]
	part.Color = color
	local light = part:FindFirstChildWhichIsA("PointLight")
	if light then
		light.Color = color
	end
	part.CFrame = CFrame.new(position)
	local brightness = lightBrightness or 8
	Animator.play(duration, function(t)
		part.Size = Vector3.one * size * Ease.lerp(0.3, 1, Ease.outExpo(t))
		Fade.apply(snapshot, 1 - Ease.inQuad(t))
		if light then
			light.Brightness = brightness * (1 - t)
		end
	end, {
		group = "ui", -- a flash must pop even during hitstop
		onComplete = function()
			pool:release(part)
		end,
	})
end

function Shapes.ring(
	frame: CFrame,
	r0: number,
	r1: number,
	width: number,
	color: Color3,
	duration: number,
	delay: number?
)
	local pool = getRingPool()
	local ring = pool:acquire()
	ring:setColor(color)
	ring:setFrame(frame)
	ring:set(math.max(r0, 0.01), 0, 2 * math.pi, function()
		return 0
	end, 1)
	ring:setEnabled(true)
	Animator.play(duration, function(t)
		local r = Ease.lerp(r0, r1, Ease.outExpo(t))
		local w = width * (1 - Ease.outQuad(t))
		ring:set(math.max(r, 0.01), 0, 2 * math.pi, function()
			return w
		end, Ease.lerp(0, 1, Ease.inQuad(t)))
	end, {
		group = "ui",
		delay = delay,
		onComplete = function()
			pool:release(ring)
		end,
	})
end

-- The classic "parry spark": 3-4 crossed neon spikes that stretch out and vanish.
function Shapes.star(position: Vector3, color: Color3, length: number, duration: number, rng: Random)
	local pool = getSpikePool()
	local count = 4
	for i = 1, count do
		local part = pool:acquire()
		local snapshot = pool.snapshotOf[part]
		part.Color = color
		local orientation = CFrame.new(position)
			* CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
			* CFrame.Angles((i / count) * math.pi + rng:NextNumber() * 0.3, 0, 0)
		local thickness = VFXMath.randomRange(rng, 0.1, 0.22)
		local len = length * VFXMath.randomRange(rng, 0.7, 1.2)
		Animator.play(duration, function(t)
			local grow = Ease.outExpo(Ease.phase(t, 0, 0.35))
			local thin = 1 - Ease.inQuad(Ease.phase(t, 0.25, 1))
			part.Size = Vector3.new(thickness * thin + 0.01, thickness * thin + 0.01, len * grow + 0.05)
			Animator.move(part, orientation)
			Fade.apply(snapshot, thin)
		end, {
			group = "ui",
			onComplete = function()
				pool:release(part)
			end,
		})
	end
end

-- Chips flung outward with fake gravity (anchored, no physics cost).
function Shapes.shards(position: Vector3, color: Color3, count: number, speed: number, rng: Random)
	local pool = getShardPool()
	for _ = 1, count do
		local part = pool:acquire()
		local snapshot = pool.snapshotOf[part]
		part.Color = color
		local velocity = VFXMath.randomInCone(rng, Vector3.yAxis, math.rad(75))
			* speed
			* VFXMath.randomRange(rng, 0.6, 1.2)
		local spin = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		local scale = VFXMath.randomRange(rng, 0.7, 1.6)
		part.Size = Vector3.new(0.15, 0.6, 0.5) * scale
		local lifetime = VFXMath.randomRange(rng, 0.5, 0.8)
		Animator.play(lifetime, function(_t, _dt, elapsed)
			local p = position + velocity * elapsed + Vector3.new(0, -60, 0) * (elapsed * elapsed * 0.5)
			local r = spin * elapsed
			Animator.move(part, CFrame.new(p) * CFrame.fromEulerAnglesXYZ(r.X, r.Y, r.Z))
			Fade.apply(snapshot, 1 - Ease.inQuad(math.clamp(elapsed / lifetime, 0, 1)))
		end, {
			onComplete = function()
				pool:release(part)
			end,
		})
	end
end

function Shapes.highlight(model: Instance, color: Color3, duration: number, name: string, peak: number?)
	if not model:IsA("Model") then
		return
	end
	local key = model
	local entry = highlights[key]
	if entry == nil or entry.highlight.Parent == nil or entry.highlight.Name ~= name then
		local h = Instance.new("Highlight")
		h.Name = name
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = model
		h.Parent = model
		entry = { highlight = h, handle = nil }
		highlights[key] = entry
	end
	local e = entry :: { highlight: Highlight, handle: Animator.Handle? }
	if e.handle then
		e.handle:cancel()
	end
	local h = e.highlight
	h.FillColor = color
	h.Enabled = true
	local start = peak or 0.1
	h.FillTransparency = start
	e.handle = Animator.play(duration, function(t)
		h.FillTransparency = Ease.lerp(start, 1, Ease.outQuad(t))
	end, {
		group = "ui",
		onComplete = function(cancelled)
			if not cancelled then
				h.Enabled = false
				e.handle = nil
			end
		end,
	})
end

function Shapes.preload()
	getFlashPool()
	getSpikePool()
	getShardPool()
	getRingPool()
end

return Shapes
