--!strict
--[[
	TextureAnimator
	UV scrolling and flipbooks, all driven by the shared Animator loop (one connection,
	time-scaled by hitstop, errors isolated).

	What scrolls on what (engine facts, check before promising an effect):
	  * Texture (on a Part or MeshPart face)  -> OffsetStudsU/V. Face-projected, NOT the
	    mesh UV map. Wraps cleanly at StudsPerTileU/V.            -> TextureAnimator.scroll
	  * Decal                                 -> UVOffset / UVScale (newer API; test on
	    target devices, it has had perf/distance issues).         -> TextureAnimator.scrollDecal
	  * Beam / Trail                          -> native: Beam.TextureSpeed, Trail.TextureMode.
	    No script needed and the cheapest option for energy flow.
	  * MeshPart.TextureID (true mesh UVs)    -> cannot be offset; animate by swapping frames
	    (TextureAnimator.flipbook) or use a spritesheet on a Decal (spritesheet).

	Usage:
		local stop = TextureAnimator.scroll(texture, Vector2.new(0, 12)) -- studs / second
		TextureAnimator.flipbook(meshPart, frames, 24, true)
		stop()
]]

local Animator = require(script.Parent.Animator)

export type Stop = () -> ()

local TextureAnimator = {}

local function wrap(value: number, period: number): number
	if period <= 0 then
		return value
	end
	return value % period -- Luau % is floored: always in [0, period)
end

-- Scrolls a Texture by `speed` studs/second. Offsets are wrapped by StudsPerTile so
-- long-lived auras never lose float precision and never visibly jump.
function TextureAnimator.scroll(texture: Texture, speed: Vector2, group: string?): Stop
	local handle = Animator.bind(function(dt)
		if texture.Parent == nil then
			return
		end
		texture.OffsetStudsU = wrap(texture.OffsetStudsU + speed.X * dt, texture.StudsPerTileU)
		texture.OffsetStudsV = wrap(texture.OffsetStudsV + speed.Y * dt, texture.StudsPerTileV)
	end, { group = group })
	return function()
		handle:cancel()
	end
end

-- Scrolls a Decal through UVOffset (units: UV per second, 1 = one full tile).
function TextureAnimator.scrollDecal(decal: Decal, speed: Vector2, group: string?): Stop
	local handle = Animator.bind(function(dt)
		if decal.Parent == nil then
			return
		end
		local o = decal.UVOffset
		decal.UVOffset = Vector2.new(wrap(o.X + speed.X * dt, 1), wrap(o.Y + speed.Y * dt, 1))
	end, { group = group })
	return function()
		handle:cancel()
	end
end

type FlipbookTarget = Decal | MeshPart

local function setFrame(target: FlipbookTarget, id: string)
	if target:IsA("MeshPart") then
		target.TextureID = id
	elseif target:IsA("Decal") then -- Decal or Texture
		target.Texture = id
	end
end

--[[
	Cycles through separate image ids (preload them first with ContentProvider or the
	first loop will flicker). Works on MeshPart.TextureID (true mesh UVs), Decal, Texture.
]]
function TextureAnimator.flipbook(
	target: FlipbookTarget,
	frames: { string },
	fps: number,
	loop: boolean,
	group: string?
): Stop
	local count = #frames
	if count == 0 then
		return function() end
	end
	local current = 0
	local handle
	handle = Animator.bind(function(_dt, elapsed)
		local index = math.floor(elapsed * fps)
		if not loop and index >= count then
			setFrame(target, frames[count])
			handle:cancel()
			return
		end
		index = index % count + 1
		if index ~= current then
			current = index
			setFrame(target, frames[index])
		end
	end, { group = group })
	return function()
		handle:cancel()
	end
end

--[[
	Plays a spritesheet (cols x rows grid, row-major, top-left first) on a Decal through
	UVScale/UVOffset: one texture upload, no per-frame asset swap.
]]
function TextureAnimator.spritesheet(
	decal: Decal,
	cols: number,
	rows: number,
	frameCount: number,
	fps: number,
	loop: boolean,
	group: string?
): Stop
	decal.UVScale = Vector2.new(1 / cols, 1 / rows)
	local handle
	handle = Animator.bind(function(_dt, elapsed)
		local index = math.floor(elapsed * fps)
		if not loop and index >= frameCount then
			index = frameCount - 1
			handle:cancel()
		end
		index %= frameCount
		local col = index % cols
		local row = math.floor(index / cols)
		decal.UVOffset = Vector2.new(col / cols, row / rows)
	end, { group = group })
	return function()
		handle:cancel()
	end
end

TextureAnimator._wrap = wrap

return TextureAnimator
