--!strict
--[[
	Pool
	Object pooling for effect instances. Creating/destroying Instances every hit causes
	GC spikes and replication-free but still costly parenting work; reusing them does not.

	Parked objects stay parented (re-parenting is the expensive part) and are moved far
	away + fully transparent, which is the approach used by PartCache-style libraries.

	Usage (generic):
		local pool = Pool.new(function() return makeHolder() end, {
			onRelease = function(holder) holder.Beam.Enabled = false end,
			prewarm = 8,
		})
		local holder = pool:acquire()
		pool:release(holder)

	Usage (template BasePart / MeshPart):
		local pool = Pool.fromTemplate(template, folder, 6)
		local part, snapshot = pool:acquire(), pool.snapshotOf[part]
]]

local Fade = require(script.Parent.Fade)

export type Hooks<T> = {
	onAcquire: ((T) -> ())?,
	onRelease: ((T) -> ())?,
	onDestroy: ((T) -> ())?, -- called when an item beyond `max` is discarded
	prewarm: number?,
	max: number?, -- objects beyond this count are destroyed on release instead of kept
}

export type Pool<T> = {
	acquire: (self: Pool<T>) -> T,
	release: (self: Pool<T>, item: T) -> (),
	size: (self: Pool<T>) -> (number, number),
}

export type PartPool = Pool<BasePart> & {
	snapshotOf: { [BasePart]: Fade.Snapshot },
	template: BasePart,
}

local Pool = {}

-- Far below the map, where anchored parts are never rendered nor queried.
Pool.PARK_CFRAME = CFrame.new(0, -5e4, 0)

function Pool.new<T>(factory: () -> T, hooks: Hooks<T>?): Pool<T>
	local free: { T } = {}
	local inUse: { [T]: boolean } = {}
	local total = 0
	local max = if hooks and hooks.max then hooks.max else math.huge
	local onAcquire = hooks and hooks.onAcquire
	local onRelease = hooks and hooks.onRelease
	local onDestroy = hooks and hooks.onDestroy

	local pool = {} :: Pool<T>

	function pool.acquire(_self: Pool<T>): T
		local item = table.remove(free)
		if item == nil then
			item = factory()
			total += 1
		end
		assert(item ~= nil, "pool factory returned nil")
		inUse[item] = true
		if onAcquire then
			onAcquire(item)
		end
		return item
	end

	function pool.release(_self: Pool<T>, item: T)
		if not inUse[item] then
			return -- double release guard
		end
		inUse[item] = nil
		if onRelease then
			onRelease(item)
		end
		if #free + 1 > max then
			total -= 1
			if onDestroy then
				onDestroy(item)
			end
			if typeof(item) == "Instance" then
				(item :: any):Destroy()
			end
			return
		end
		table.insert(free, item)
	end

	function pool.size(_self: Pool<T>): (number, number)
		return total, #free
	end

	local prewarm = if hooks and hooks.prewarm then hooks.prewarm else 0
	for _ = 1, prewarm do
		local item = factory()
		total += 1
		if onRelease then
			onRelease(item)
		end
		table.insert(free, item)
	end

	return pool
end

-- Makes a clone safe to use as a pure visual (no physics, no queries, no shadows).
function Pool.makeVisual(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Locked = true
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
end

-- Pool of clones of a BasePart/MeshPart template (its Decals, Textures, Beams... included).
function Pool.fromTemplate(template: BasePart, parent: Instance, prewarm: number?, max: number?): PartPool
	local snapshotOf: { [BasePart]: Fade.Snapshot } = {}
	local templateSize = template.Size
	local templateColor = template.Color

	local base = Pool.new(function(): BasePart
		local part = template:Clone()
		Pool.makeVisual(part)
		part.CFrame = Pool.PARK_CFRAME
		part.Parent = parent
		snapshotOf[part] = Fade.capture(part)
		return part
	end, {
		prewarm = prewarm,
		max = max,
		onRelease = function(part: BasePart)
			local snapshot = snapshotOf[part]
			if snapshot then
				Fade.restore(snapshot)
			end
			part.Size = templateSize
			part.Color = templateColor
			for _, d in part:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d:Clear()
				end
			end
			part.CFrame = Pool.PARK_CFRAME
		end,
		onDestroy = function(part: BasePart)
			snapshotOf[part] = nil
		end,
	})

	local pool = base :: PartPool
	pool.snapshotOf = snapshotOf
	pool.template = template
	return pool
end

return Pool
