--!nocheck
--[[
	Exports the procedural pixel-art library as PNG sprite sheets:
	  lune run tools/export-sprites.luau [outDir]
	Writes <outDir>/<Name>.png (frames laid out horizontally), manifest.json (frame sizes,
	fps, loop) and _preview.png (every sheet scaled x5 on a dark background).
	Upload the PNGs to Roblox and paste the ids into DarkStyle SpriteBank.assetIds to run
	in published games without EditableImage.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("./test/harness")
local Png = require("./lib/Png")

local out = process.args[1] or "builds/sprites"
fs.writeDir(out)

local h = harness.new()
local root = h:mount(`{process.cwd}/.claude/skills/roblox-dark-pixel-style/src/shared/DarkStyle`, "DarkStyle")
local SpriteGen = h:require(root.SpriteGen)
local Canvas = h:require(root.Canvas)

local function compress(s: string): string
	return serde.compress("zlib", s)
end

local manifest = {}
local sheets = {}
for _, sprite in SpriteGen.catalog() do
	local sheet = SpriteGen.sheet(sprite)
	fs.writeFile(`{out}/{sprite.name}.png`, Png.encode(sheet.w, sheet.h, sheet.px, compress))
	manifest[sprite.name] =
		{ frameWidth = sprite.w, frameHeight = sprite.h, frames = #sprite.frames, fps = sprite.fps, loop = sprite.loop }
	table.insert(sheets, { name = sprite.name, sheet = sheet })
end
fs.writeFile(`{out}/manifest.json`, serde.encode("json", manifest, true))

-- Preview: stack every sheet, scale x5, on a dark stone background.
local SCALE, PAD = 5, 6
local width, height = 0, PAD
for _, s in sheets do
	width = math.max(width, s.sheet.w * SCALE + PAD * 2)
	height += s.sheet.h * SCALE + PAD
end
local preview = Canvas.new(width, height)
for y = 0, height - 1 do
	for x = 0, width - 1 do
		Canvas.set(preview, x, y, if (math.floor(x / 20) + math.floor(y / 20)) % 2 == 0 then 0x2b2724 else 0x322d29)
	end
end
local oy = PAD
for _, s in sheets do
	for y = 0, s.sheet.h - 1 do
		for x = 0, s.sheet.w - 1 do
			local color = Canvas.get(s.sheet, x, y)
			if color then
				for sy = 0, SCALE - 1 do
					for sx = 0, SCALE - 1 do
						Canvas.set(preview, PAD + x * SCALE + sx, oy + y * SCALE + sy, color)
					end
				end
			end
		end
	end
	oy += s.sheet.h * SCALE + PAD
end
fs.writeFile(`{out}/_preview.png`, Png.encode(preview.w, preview.h, preview.px, compress))
print(`Exported {#sheets} sprite sheets to {out}`)
