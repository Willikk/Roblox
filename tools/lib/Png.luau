--!nocheck
--[[
	Minimal PNG encoder (RGBA8, no interlace) for Lune.
	`compress` must be a zlib compressor: (string) -> string (serde.compress("zlib", ...)).
]]

local Png = {}

local crcTable = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	crcTable[n] = c
end

function Png.crc32(s: string): number
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function u32(n: number): string
	return string.char(
		bit32.band(bit32.rshift(n, 24), 0xFF),
		bit32.band(bit32.rshift(n, 16), 0xFF),
		bit32.band(bit32.rshift(n, 8), 0xFF),
		bit32.band(n, 0xFF)
	)
end

local function chunk(kind: string, data: string): string
	return u32(#data) .. kind .. data .. u32(Png.crc32(kind .. data))
end

-- rgba: buffer of w*h*4 bytes.
function Png.encode(w: number, h: number, rgba: buffer, compress: (string) -> string): string
	local rows = table.create(h)
	for y = 0, h - 1 do
		rows[y + 1] = "\0" .. buffer.readstring(rgba, y * w * 4, w * 4)
	end
	local ihdr = u32(w) .. u32(h) .. string.char(8, 6, 0, 0, 0)
	return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr) .. chunk("IDAT", compress(table.concat(rows))) .. chunk("IEND", "")
end

return Png
