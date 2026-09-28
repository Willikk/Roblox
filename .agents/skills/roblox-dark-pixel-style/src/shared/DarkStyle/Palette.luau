--!strict
--!native
--[[
	Palette
	Dark-fantasy ramps (Berserk ink + Fear & Hunger rot). Every generated sprite uses
	ONLY these colors (enforced by tests): a restricted palette is what makes pixel art
	look intentional and cohesive. Ramps go dark -> light.
]]

local Canvas = require(script.Parent.Canvas)

export type Ramp = { number }

local Palette = {}

Palette.INK = 0x0c090a -- warm near-black: outlines, Berserk ink
Palette.PAPER = 0xe9dfc7 -- aged paper white: manga highlights

Palette.blood = { 0x1f0507, 0x4b0b0e, 0x7f1416, 0xb3211c, 0xe0472e } :: Ramp
Palette.steel = { 0x1b1e24, 0x3f4650, 0x7a8591, 0xc3ccd3, 0xf4f1e6 } :: Ramp
Palette.ember = { 0x2a0c05, 0x6e1f08, 0xb8470f, 0xef8a2a, 0xffd27a } :: Ramp
Palette.bone = { 0x2a241d, 0x5a4e3e, 0x8f7f63, 0xc4b594, 0xece0c0 } :: Ramp
Palette.smoke = { 0x121014, 0x25212a, 0x3a3440, 0x57505c, 0x7a7280 } :: Ramp
Palette.rot = { 0x14160c, 0x2f3419, 0x555c2c, 0x868a4a, 0xb3b06a } :: Ramp -- Fear & Hunger sickness
Palette.ichor = { 0x050506, 0x121218, 0x24222e, 0x3c3548, 0x5e4f6e } :: Ramp -- black blood

-- Nearest ramp step for t in [0, 1] (no dithering).
function Palette.pick(ramp: Ramp, t: number): number
	local i = math.clamp(math.floor(t * (#ramp - 1) + 0.5), 0, #ramp - 1)
	return ramp[i + 1]
end

-- Ordered-dithered ramp step: smooth gradients with hard pixels.
function Palette.dither(ramp: Ramp, t: number, x: number, y: number): number
	local v = math.clamp(t, 0, 1) * (#ramp - 1)
	local lower = math.floor(v)
	if lower >= #ramp - 1 then
		return ramp[#ramp]
	end
	local step = if Canvas.bayer(x, y) < v - lower then lower + 1 else lower
	return ramp[step + 1]
end

-- All colors a sprite may use (for validation).
function Palette.all(): { [number]: boolean }
	local set: { [number]: boolean } = { [Palette.INK] = true, [Palette.PAPER] = true }
	for _, ramp in
		{ Palette.blood, Palette.steel, Palette.ember, Palette.bone, Palette.smoke, Palette.rot, Palette.ichor }
	do
		for _, c in ramp do
			set[c] = true
		end
	end
	return set
end

function Palette.toColor3(color: number): Color3
	return Color3.fromRGB(bit32.rshift(color, 16), bit32.band(bit32.rshift(color, 8), 0xFF), bit32.band(color, 0xFF))
end

return Palette
