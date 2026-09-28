--!strict
--!native
--[[
	Canvas
	Tiny RGBA8 pixel canvas (pure Luau, `buffer`-backed) for generating pixel art at
	runtime or offline. Colors are packed 0xRRGGBB integers; alpha is binary (0 / 255):
	real pixel art never has soft edges. Tested under Lune.
]]

export type Canvas = { w: number, h: number, px: buffer }

local Canvas = {}

function Canvas.new(w: number, h: number): Canvas
	return { w = w, h = h, px = buffer.create(w * h * 4) }
end

local function index(c: Canvas, x: number, y: number): number
	return (y * c.w + x) * 4
end

function Canvas.inside(c: Canvas, x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < c.w and y < c.h
end

function Canvas.set(c: Canvas, x: number, y: number, color: number)
	x, y = math.floor(x), math.floor(y)
	if x < 0 or y < 0 or x >= c.w or y >= c.h then
		return
	end
	local i = index(c, x, y)
	buffer.writeu8(c.px, i, bit32.band(bit32.rshift(color, 16), 0xFF))
	buffer.writeu8(c.px, i + 1, bit32.band(bit32.rshift(color, 8), 0xFF))
	buffer.writeu8(c.px, i + 2, bit32.band(color, 0xFF))
	buffer.writeu8(c.px, i + 3, 255)
end

function Canvas.erase(c: Canvas, x: number, y: number)
	if Canvas.inside(c, x, y) then
		buffer.writeu32(c.px, index(c, x, y), 0)
	end
end

function Canvas.alpha(c: Canvas, x: number, y: number): number
	if not Canvas.inside(c, x, y) then
		return 0
	end
	return buffer.readu8(c.px, index(c, x, y) + 3)
end

function Canvas.get(c: Canvas, x: number, y: number): number?
	if Canvas.alpha(c, x, y) == 0 then
		return nil
	end
	local i = index(c, x, y)
	return bit32.bor(
		bit32.lshift(buffer.readu8(c.px, i), 16),
		bit32.lshift(buffer.readu8(c.px, i + 1), 8),
		buffer.readu8(c.px, i + 2)
	)
end

-- 4x4 Bayer ordered-dither threshold in [0, 1).
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
function Canvas.bayer(x: number, y: number): number
	return BAYER[(y % 4) * 4 + (x % 4) + 1] / 16
end

function Canvas.fillCircle(c: Canvas, cx: number, cy: number, r: number, color: number)
	for y = math.floor(cy - r), math.ceil(cy + r) do
		for x = math.floor(cx - r), math.ceil(cx + r) do
			local dx, dy = x + 0.5 - cx, y + 0.5 - cy
			if dx * dx + dy * dy <= r * r then
				Canvas.set(c, x, y, color)
			end
		end
	end
end

-- Bresenham line with a square brush.
function Canvas.line(c: Canvas, x0: number, y0: number, x1: number, y1: number, color: number, brush: number?)
	local b = brush or 1
	local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
	for i = 0, steps do
		local k = i / steps
		local x = math.floor(x0 + (x1 - x0) * k + 0.5)
		local y = math.floor(y0 + (y1 - y0) * k + 0.5)
		for oy = 0, b - 1 do
			for ox = 0, b - 1 do
				Canvas.set(c, x + ox - math.floor(b / 2), y + oy - math.floor(b / 2), color)
			end
		end
	end
end

--[[
	1-px outline: every transparent pixel touching an opaque one (4-neighbourhood)
	becomes `color`. The single most important step for readable pixel art.
]]
function Canvas.outline(c: Canvas, color: number)
	local marks = {}
	for y = 0, c.h - 1 do
		for x = 0, c.w - 1 do
			if Canvas.alpha(c, x, y) == 0 then
				if
					Canvas.alpha(c, x + 1, y) > 0
					or Canvas.alpha(c, x - 1, y) > 0
					or Canvas.alpha(c, x, y + 1) > 0
					or Canvas.alpha(c, x, y - 1) > 0
				then
					table.insert(marks, y * c.w + x)
				end
			end
		end
	end
	for _, m in marks do
		Canvas.set(c, m % c.w, math.floor(m / c.w), color)
	end
end

-- Copies `src` into `dst` at (dx, dy) (opaque pixels only).
function Canvas.blit(dst: Canvas, src: Canvas, dx: number, dy: number)
	for y = 0, src.h - 1 do
		for x = 0, src.w - 1 do
			local color = Canvas.get(src, x, y)
			if color then
				Canvas.set(dst, dx + x, dy + y, color)
			end
		end
	end
end

function Canvas.opaqueCount(c: Canvas): number
	local n = 0
	for y = 0, c.h - 1 do
		for x = 0, c.w - 1 do
			if Canvas.alpha(c, x, y) > 0 then
				n += 1
			end
		end
	end
	return n
end

return Canvas
