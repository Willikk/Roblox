--!strict
--!native
--[[
	SpriteGen
	Procedural dark-fantasy pixel art (pure Luau, deterministic, tested).

	Every sprite follows pixel-art discipline: restricted Palette ramps, 1-px outlines,
	ordered (Bayer) dithering for shading and for fading out (no soft alpha), few frames
	played "on twos" (8-12 fps). Frames are packed horizontally into one sheet per sprite
	(SpriteBank uploads one EditableImage per sheet; tools/export-sprites writes PNGs).

	Catalog (name -> sprite): SlashSteel, SlashBlood, SlashEmber, BloodBurst, IchorBurst,
	Spark, SparkEmber, InkBurst, Smoke, BloodPool, Droplet, Flame, SpeedLines, Grain,
	Vignette, DitherTile, DangerEye.
]]

local Canvas = require(script.Parent.Canvas)
local Palette = require(script.Parent.Palette)

export type Sprite = {
	name: string,
	w: number,
	h: number,
	frames: { Canvas.Canvas },
	fps: number,
	loop: boolean,
}

local SpriteGen = {}

-- Deterministic RNG (xorshift32), independent of Roblox `Random` so it runs anywhere.
local function rng(seed: number): () -> number
	local s = bit32.band(seed * 2654435761 + 1, 0xFFFFFFFF)
	if s == 0 then
		s = 0x9E3779B9
	end
	return function(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return s / 4294967296
	end
end
SpriteGen.rng = rng

local function hash(x: number, y: number, seed: number): number
	local h = bit32.bxor(x * 374761393 + y * 668265263, seed * 2246822519)
	h = bit32.band(h, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = bit32.band(h * 1274126177, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Smooth value noise in [0, 1).
function SpriteGen.noise(x: number, y: number, seed: number): number
	local ix, iy = math.floor(x), math.floor(y)
	local fx, fy = x - ix, y - iy
	local sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	local a = hash(ix, iy, seed)
	local b = hash(ix + 1, iy, seed)
	local c = hash(ix, iy + 1, seed)
	local d = hash(ix + 1, iy + 1, seed)
	return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
end

local function outExpo(t: number): number
	return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
end
local function inQuad(t: number): number
	return t * t
end

local function sprite(name: string, w: number, h: number, fps: number, loop: boolean): Sprite
	return { name = name, w = w, h = h, frames = {}, fps = fps, loop = loop }
end

-- Drops pixels by ordered dither: the pixel-art way to fade (0 = keep all, 1 = none).
local function erode(c: Canvas.Canvas, amount: number)
	if amount <= 0 then
		return
	end
	for y = 0, c.h - 1 do
		for x = 0, c.w - 1 do
			if Canvas.bayer(x, y) < amount then
				Canvas.erase(c, x, y)
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Slash: crescent with an ink outline and manga speed lines, drawn then wiped.
------------------------------------------------------------------------------------
function SpriteGen.slash(name: string, ramp: Palette.Ramp, frames: number?): Sprite
	local n = frames or 6
	local s = sprite(name, 64, 32, 12, false)
	local cx, cy = s.w / 2, s.h + 11
	local R = cy - 2
	local A = math.asin(math.min(1, (s.w / 2 - 3) / R))
	local maxT = 12
	local seed = #name * 7919
	-- Polar coordinates of every pixel, shared by all frames.
	local radii = table.create(s.w * s.h)
	local angles = table.create(s.w * s.h)
	for y = 0, s.h - 1 do
		for x = 0, s.w - 1 do
			local dx, dy = x + 0.5 - cx, y + 0.5 - cy
			radii[y * s.w + x + 1] = math.sqrt(dx * dx + dy * dy)
			angles[y * s.w + x + 1] = math.atan2(dx, -dy)
		end
	end
	for k = 1, n do
		local p = k / n
		-- Head sweeps across (clearly different first frames), tail follows and wipes.
		local reveal = math.min(1, p / 0.6)
		local head = -A + 2 * A * (1 - (1 - reveal) ^ 2)
		local tail = -A + 2 * A * inQuad(math.max(0, (p - 0.35) / 0.65))
		local c = Canvas.new(s.w, s.h)
		for y = 0, s.h - 1 do
			for x = 0, s.w - 1 do
				local r = radii[y * s.w + x + 1]
				local theta = angles[y * s.w + x + 1]
				if theta >= tail and theta <= head and head - tail > 1e-3 and r >= R - maxT - 2 and r <= R + 2 then
					local u = (theta - tail) / (head - tail)
					-- Heavier towards the leading end, torn edges.
					local profile = math.sin(math.pi * u ^ 0.8) ^ 0.7
					local torn = 0.8 + 0.4 * SpriteGen.noise(theta * 26, r * 0.25, seed)
					local thickness = maxT * profile * torn * (1 - 0.3 * p)
					local depth = R - r + (SpriteGen.noise(theta * 18, 3, seed + 1) - 0.5) * 2
					if depth >= 0 and depth <= thickness then
						local edge = 1 - depth / math.max(thickness, 1)
						-- Brush streaks running along the arc.
						local streak = (SpriteGen.noise(theta * 45, depth * 0.6, seed + 2) - 0.5) * 0.45
						local shade = 0.1 + 0.9 * edge ^ 1.6 + streak + (if u > 0.85 then 0.15 else 0)
						local color = if depth < 1.2 and u > 0.25 then ramp[5] else Palette.dither(ramp, shade, x, y)
						Canvas.set(c, x, y, color)
					end
				end
			end
		end
		Canvas.outline(c, Palette.INK)
		-- Motion streaks behind the blade and a dissolving tail of shards.
		for _, radius in { R - maxT - 2, R - maxT - 5, R - maxT - 8 } do
			for step = 0, math.floor(2 * A * radius) do
				local theta = -A + step / radius
				if theta >= tail and theta <= head and (step + radius) % 9 < 5 then
					Canvas.set(c, cx + radius * math.sin(theta) - 0.5, cy - radius * math.cos(theta) - 0.5, ramp[2])
				end
			end
		end
		local shardStart = math.max(-A, tail - 0.35)
		for step = 0, 40 do
			local theta = shardStart + (tail - shardStart) * step / 40
			local rr = R - 2 - SpriteGen.noise(step, k, seed + 3) * maxT * 0.6
			if SpriteGen.noise(step * 0.7, k * 2, seed + 4) > 0.55 then
				Canvas.set(c, cx + rr * math.sin(theta) - 0.5, cy - rr * math.cos(theta) - 0.5, ramp[3])
			end
		end
		erode(c, math.max(0, (p - 0.65) / 0.35) * 0.85)
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------
-- Blood burst: central splat + droplets with gravity and streaks.
------------------------------------------------------------------------------------
function SpriteGen.burst(name: string, ramp: Palette.Ramp, seed: number, frames: number?): Sprite
	local n = frames or 7
	local s = sprite(name, 48, 48, 12, false)
	local random = rng(seed)
	local drops = {}
	for i = 1, 18 do
		local angle = math.rad(-90 + (random() - 0.5) * 200)
		local speed = 10 + random() * 16
		drops[i] = {
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed,
			size = 1 + math.floor(random() * 2.99),
		}
	end
	local cx, cy = 24, 26
	for k = 1, n do
		local t = (k - 1) / (n - 1)
		local c = Canvas.new(s.w, s.h)
		-- Splat core: flat fill, light rim top-left, shadow bottom-right, torn edge.
		local radius = 3 + 6 * math.min(1, t / 0.35)
		local reach = math.ceil(radius + 4)
		for y = math.max(0, cy - reach), math.min(s.h - 1, cy + reach) do
			for x = math.max(0, cx - reach), math.min(s.w - 1, cx + reach) do
				local dx, dy = x + 0.5 - cx, y + 0.5 - cy
				local d = math.sqrt(dx * dx + dy * dy)
				local wobble = (SpriteGen.noise(math.atan2(dy, dx) * 3, 0, seed) - 0.5) * 5
				if d <= radius + wobble then
					local color = ramp[3]
					if d > radius + wobble - 1.5 and dx + dy < 0 then
						color = ramp[4]
					elseif dx + dy > radius * 0.6 then
						color = ramp[2]
					end
					Canvas.set(c, x, y, color)
				end
			end
		end
		-- Crown: short spikes flung from the rim in the first frames.
		if t < 0.5 then
			local random2 = rng(seed + 99)
			for _ = 1, 10 do
				local a = random2() * 2 * math.pi
				local len = (radius + 2 + random2() * 6) * (0.5 + t)
				Canvas.line(
					c,
					cx + math.cos(a) * radius * 0.8,
					cy + math.sin(a) * radius * 0.8,
					cx + math.cos(a) * len,
					cy + math.sin(a) * len,
					ramp[3]
				)
			end
		end
		if t > 0.45 then
			erode(c, (t - 0.45) / 0.55)
		end
		-- Droplets.
		for _, d in drops do
			local px = cx + d.vx * t * 1.1
			local py = cy + d.vy * t * 1.1 + 22 * t * t
			local size = math.max(0.6, d.size * (1 - 0.45 * t))
			local tx = cx + d.vx * math.max(t - 0.12, 0) * 1.1
			local ty = cy + d.vy * math.max(t - 0.12, 0) * 1.1 + 22 * math.max(t - 0.12, 0) ^ 2
			Canvas.line(c, tx, ty, px, py, ramp[2])
			Canvas.fillCircle(c, px, py, size, ramp[3])
			if size >= 1.5 then
				Canvas.set(c, px - 1, py - 1, ramp[5])
			end
		end
		Canvas.outline(c, ramp[1])
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------
-- Spark: four-point star with shorter diagonals, collapsing.
------------------------------------------------------------------------------------
function SpriteGen.spark(name: string, ramp: Palette.Ramp, frames: number?): Sprite
	local n = frames or 4
	local s = sprite(name, 24, 24, 14, false)
	local cx, cy = 11.5, 11.5
	for k = 1, n do
		local t = (k - 1) / n
		local c = Canvas.new(s.w, s.h)
		local L = 11 * (1 - 0.55 * t)
		for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			Canvas.line(c, cx, cy, cx + dir[1] * L, cy + dir[2] * L, ramp[4])
			Canvas.line(c, cx, cy, cx + dir[1] * L * 0.45, cy + dir[2] * L * 0.45, ramp[5], 2)
		end
		for _, dir in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
			Canvas.line(c, cx, cy, cx + dir[1] * L * 0.45, cy + dir[2] * L * 0.45, ramp[3])
		end
		Canvas.fillCircle(c, cx + 0.5, cy + 0.5, 2 * (1 - t) + 0.8, ramp[5])
		Canvas.outline(c, Palette.INK)
		erode(c, math.max(0, t - 0.4) * 1.5)
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------
-- Ink burst: Berserk-style jagged ink spikes around a red core, paper-edged.
------------------------------------------------------------------------------------
function SpriteGen.inkBurst(name: string, seed: number, frames: number?): Sprite
	local n = frames or 5
	local s = sprite(name, 64, 64, 12, false)
	local random = rng(seed)
	local spikes = {}
	for i = 1, 18 do
		spikes[i] = { angle = random() * 2 * math.pi, length = 14 + random() * 17, width = 2.5 + random() * 3.5 }
	end
	local cx, cy = 32, 32
	local cache: { [number]: Canvas.Canvas } = {}
	for k = 1, n do
		local grow = outExpo(math.min(1, k / 2))
		local cached = cache[grow]
		if cached then
			local c = Canvas.new(s.w, s.h)
			buffer.copy(c.px, 0, cached.px)
			erode(c, math.max(0, (k - 3) / (n - 2)))
			s.frames[k] = c
			continue
		end
		local c = Canvas.new(s.w, s.h)
		for y = 0, s.h - 1 do
			for x = 0, s.w - 1 do
				local dx, dy = x + 0.5 - cx, y + 0.5 - cy
				local d = math.sqrt(dx * dx + dy * dy)
				local theta = math.atan2(dy, dx)
				local ink = d <= 8 * grow
				for _, sp in spikes do
					local delta = math.abs((theta - sp.angle + math.pi) % (2 * math.pi) - math.pi)
					local len = sp.length * grow
					if d <= len and d * math.sin(delta) <= sp.width * (1 - d / len) and math.cos(delta) > 0 then
						ink = true
						break
					end
				end
				if ink then
					Canvas.set(c, x, y, Palette.INK)
				end
				if d <= 5.5 * grow then
					Canvas.set(c, x, y, Palette.dither(Palette.blood, 0.9 - d / 7, x, y))
				end
			end
		end
		Canvas.outline(c, Palette.PAPER)
		local keep = Canvas.new(s.w, s.h)
		buffer.copy(keep.px, 0, c.px)
		cache[grow] = keep
		erode(c, math.max(0, (k - 3) / (n - 2)))
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------
-- Smoke puff: lumpy dithered cloud, lit from the top-left, dissolving.
------------------------------------------------------------------------------------
function SpriteGen.smoke(name: string, ramp: Palette.Ramp, seed: number, frames: number?): Sprite
	local n = frames or 6
	local s = sprite(name, 32, 32, 10, false)
	local random = rng(seed)
	local lumps = {}
	for i = 1, 5 do
		lumps[i] = { x = 16 + (random() - 0.5) * 12, y = 18 + (random() - 0.5) * 8, r = 4 + random() * 3 }
	end
	for k = 1, n do
		local t = (k - 1) / (n - 1)
		local c = Canvas.new(s.w, s.h)
		for y = 0, s.h - 1 do
			for x = 0, s.w - 1 do
				for _, l in lumps do
					local r = l.r * (0.6 + 0.8 * t)
					local dx, dy = x + 0.5 - l.x, y + 0.5 - (l.y - 6 * t)
					if dx * dx + dy * dy <= r * r then
						local light = 0.55 - (dx + dy) / (4 * r)
						Canvas.set(c, x, y, Palette.dither(ramp, light, x, y))
						break
					end
				end
			end
		end
		Canvas.outline(c, ramp[1])
		erode(c, math.max(0, t - 0.35) / 0.65)
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------
-- Small single-frame sprites.
------------------------------------------------------------------------------------
function SpriteGen.pool(name: string, ramp: Palette.Ramp, seed: number): Sprite
	local s = sprite(name, 32, 16, 1, false)
	local c = Canvas.new(s.w, s.h)
	for y = 0, s.h - 1 do
		for x = 0, s.w - 1 do
			local dx, dy = (x + 0.5 - 16) / 13, (y + 0.5 - 8) / 5.5
			local edge = 1 + (SpriteGen.noise(x * 0.4, y * 0.4, seed) - 0.5) * 0.6
			if dx * dx + dy * dy <= edge then
				Canvas.set(c, x, y, Palette.dither(ramp, 0.3 + 0.25 * (1 - (dx * dx + dy * dy)), x, y))
			end
		end
	end
	Canvas.set(c, 11, 6, ramp[5])
	Canvas.set(c, 12, 6, ramp[4])
	Canvas.outline(c, ramp[1])
	s.frames[1] = c
	return s
end

function SpriteGen.droplet(name: string, ramp: Palette.Ramp): Sprite
	local s = sprite(name, 6, 6, 1, false)
	local c = Canvas.new(6, 6)
	Canvas.fillCircle(c, 3, 3, 1.7, ramp[3])
	Canvas.set(c, 2, 2, ramp[5])
	Canvas.outline(c, ramp[1])
	s.frames[1] = c
	return s
end

-- Torch flame: looping, irregular licking tongues with a hot core.
function SpriteGen.flame(name: string, seed: number, frames: number?): Sprite
	local n = frames or 6
	local s = sprite(name, 16, 24, 10, true)
	for k = 1, n do
		local c = Canvas.new(s.w, s.h)
		local phase = k / n * 2 * math.pi
		for y = 0, s.h - 1 do
			for x = 0, s.w - 1 do
				local h = (s.h - 1 - y) / (s.h - 1) -- 0 bottom .. 1 top
				local sway = math.sin(phase + h * 5) * 1.6 * h
				local dx = math.abs(x + 0.5 - 8 - sway)
				local turbulence = SpriteGen.noise(x * 0.45, y * 0.3 + math.sin(phase) * 2 + k * 1.3, seed)
				local v = (1 - h) * 1.35 - dx / 5 - turbulence * 0.75 * h - 0.05
				if v > 0 then
					Canvas.set(c, x, y, Palette.dither(Palette.ember, 0.15 + v * 1.1, x, y))
				end
			end
		end
		-- Loose embers above the flame.
		local random = rng(seed + k)
		for _ = 1, 2 do
			Canvas.set(c, 5 + random() * 6, 1 + random() * 6, Palette.ember[4])
		end
		Canvas.outline(c, Palette.ember[1])
		s.frames[k] = c
	end
	return s
end

-- Radial manga speed lines for impact frames (transparent centre). Drawn line by line.
function SpriteGen.speedLines(name: string, seed: number): Sprite
	local s = sprite(name, 128, 128, 1, false)
	local c = Canvas.new(128, 128)
	local random = rng(seed)
	for _ = 1, 90 do
		local angle = random() * 2 * math.pi
		local inner = 36 + random() * 22
		local width = 0.012 + random() * 0.03
		local d = inner
		while d < 92 do
			local half = (width * (d - inner) / 40 + 0.004) * d -- half-width in pixels
			local o = -half
			repeat
				local a2 = angle + o / d
				Canvas.set(c, 64 + math.cos(a2) * d - 0.5, 64 + math.sin(a2) * d - 0.5, Palette.INK)
				o += 0.5
			until o > half
			d += 0.5
		end
	end
	s.frames[1] = c
	return s
end

function SpriteGen.grain(name: string, seed: number): Sprite
	local s = sprite(name, 64, 64, 12, true)
	local c = Canvas.new(64, 64)
	local random = rng(seed)
	for y = 0, 63 do
		for x = 0, 63 do
			local v = random()
			if v < 0.045 then
				Canvas.set(c, x, y, Palette.INK)
			elseif v < 0.07 then
				Canvas.set(c, x, y, Palette.PAPER)
			end
		end
	end
	s.frames[1] = c
	return s
end

function SpriteGen.vignette(name: string): Sprite
	local s = sprite(name, 48, 48, 1, false)
	local c = Canvas.new(48, 48)
	for y = 0, 47 do
		for x = 0, 47 do
			local dx, dy = (x + 0.5 - 24) / 24, (y + 0.5 - 24) / 24
			local d = math.sqrt(dx * dx + dy * dy)
			if Canvas.bayer(x, y) < (d - 0.62) / 0.38 * 1.15 then
				Canvas.set(c, x, y, Palette.INK)
			end
		end
	end
	s.frames[1] = c
	return s
end

function SpriteGen.ditherTile(name: string): Sprite
	local s = sprite(name, 4, 4, 1, false)
	local c = Canvas.new(4, 4)
	for y = 0, 3 do
		for x = 0, 3 do
			if Canvas.bayer(x, y) < 0.5 then
				Canvas.set(c, x, y, Palette.INK)
			end
		end
	end
	s.frames[1] = c
	return s
end

-- Pulsing red eye glyph: danger mark for perilous attacks.
function SpriteGen.dangerEye(name: string, frames: number?): Sprite
	local n = frames or 4
	local s = sprite(name, 20, 14, 10, true)
	for k = 1, n do
		local c = Canvas.new(20, 14)
		local open = 0.55 + 0.45 * math.sin(k / n * math.pi)
		for y = 0, 13 do
			for x = 0, 19 do
				local dx, dy = (x + 0.5 - 10) / 9, (y + 0.5 - 7) / (5.5 * open)
				if math.abs(dx) + dy * dy <= 1 then
					Canvas.set(c, x, y, Palette.dither(Palette.blood, 0.55 + 0.4 * (1 - math.abs(dx)), x, y))
				end
			end
		end
		for y = 2, 11 do
			Canvas.set(c, 9, y, Palette.INK)
			Canvas.set(c, 10, y, Palette.INK)
		end
		Canvas.outline(c, Palette.INK)
		s.frames[k] = c
	end
	return s
end

------------------------------------------------------------------------------------

-- Packs frames horizontally into one sheet.
function SpriteGen.sheet(s: Sprite): Canvas.Canvas
	local sheet = Canvas.new(s.w * #s.frames, s.h)
	for i, frame in s.frames do
		Canvas.blit(sheet, frame, (i - 1) * s.w, 0)
	end
	return sheet
end

export type Builder = { name: string, build: () -> Sprite }

-- Lazy builders: SpriteBank builds one per frame so loading never hitches.
function SpriteGen.builders(): { Builder }
	return {
		{
			name = "SlashSteel",
			build = function()
				return SpriteGen.slash("SlashSteel", Palette.steel)
			end,
		},
		{
			name = "SlashBlood",
			build = function()
				return SpriteGen.slash("SlashBlood", Palette.blood)
			end,
		},
		{
			name = "SlashEmber",
			build = function()
				return SpriteGen.slash("SlashEmber", Palette.ember)
			end,
		},
		{
			name = "BloodBurst",
			build = function()
				return SpriteGen.burst("BloodBurst", Palette.blood, 7)
			end,
		},
		{
			name = "IchorBurst",
			build = function()
				return SpriteGen.burst("IchorBurst", Palette.ichor, 11)
			end,
		},
		{
			name = "Spark",
			build = function()
				return SpriteGen.spark("Spark", Palette.steel)
			end,
		},
		{
			name = "SparkEmber",
			build = function()
				return SpriteGen.spark("SparkEmber", Palette.ember)
			end,
		},
		{
			name = "InkBurst",
			build = function()
				return SpriteGen.inkBurst("InkBurst", 3)
			end,
		},
		{
			name = "Smoke",
			build = function()
				return SpriteGen.smoke("Smoke", Palette.smoke, 5)
			end,
		},
		{
			name = "BloodPool",
			build = function()
				return SpriteGen.pool("BloodPool", Palette.blood, 9)
			end,
		},
		{
			name = "Droplet",
			build = function()
				return SpriteGen.droplet("Droplet", Palette.blood)
			end,
		},
		{
			name = "Flame",
			build = function()
				return SpriteGen.flame("Flame", 13)
			end,
		},
		{
			name = "SpeedLines",
			build = function()
				return SpriteGen.speedLines("SpeedLines", 21)
			end,
		},
		{
			name = "Grain",
			build = function()
				return SpriteGen.grain("Grain", 17)
			end,
		},
		{
			name = "Vignette",
			build = function()
				return SpriteGen.vignette("Vignette")
			end,
		},
		{
			name = "DitherTile",
			build = function()
				return SpriteGen.ditherTile("DitherTile")
			end,
		},
		{
			name = "DangerEye",
			build = function()
				return SpriteGen.dangerEye("DangerEye")
			end,
		},
	}
end

-- The full library used by the dark effects (deterministic seeds).
function SpriteGen.catalog(): { Sprite }
	local list = {}
	for _, builder in SpriteGen.builders() do
		table.insert(list, builder.build())
	end
	return list
end

return SpriteGen
