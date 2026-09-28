--!nocheck
-- Pixel-art discipline and generator correctness.
return function(t)
	local expect = t.expect
	local h = t.harness.new()
	local root = h:mount(`{t.skillsRoot}/roblox-dark-pixel-style/src/shared/DarkStyle`, "DarkStyle")
	local Canvas = h:require(root.Canvas)
	local Palette = h:require(root.Palette)
	local SpriteGen = h:require(root.SpriteGen)

	local catalog = SpriteGen.catalog()
	local allowed = Palette.all()

	t.test("catalog: unique names, consistent frame sizes, sane fps", function()
		local seen = {}
		expect.truthy(#catalog >= 15)
		for _, s in catalog do
			expect.truthy(not seen[s.name], s.name .. " unique")
			seen[s.name] = true
			expect.truthy(#s.frames >= 1)
			expect.truthy(s.fps >= 1 and s.fps <= 24, s.name .. " fps")
			for _, f in s.frames do
				expect.eq(f.w, s.w)
				expect.eq(f.h, s.h)
			end
		end
	end)

	t.test("every pixel is either fully transparent or a palette color (true pixel art)", function()
		for _, s in catalog do
			for fi, f in s.frames do
				for y = 0, f.h - 1 do
					for x = 0, f.w - 1 do
						local a = Canvas.alpha(f, x, y)
						expect.truthy(a == 0 or a == 255, `{s.name}#{fi} binary alpha`)
						if a == 255 then
							local c = Canvas.get(f, x, y)
							if not allowed[c] then
								error(`{s.name}#{fi} off-palette color {string.format("%06x", c)} at {x},{y}`)
							end
						end
					end
				end
			end
		end
	end)

	t.test("generation is deterministic", function()
		local a = SpriteGen.catalog()
		local b = SpriteGen.catalog()
		for i, s in a do
			for fi, f in s.frames do
				expect.eq(buffer.tostring(f.px), buffer.tostring(b[i].frames[fi].px), `{s.name}#{fi}`)
			end
		end
	end)

	t.test("animated effects start visible and dissolve (fewer pixels at the end)", function()
		for _, s in catalog do
			if #s.frames >= 4 and not s.loop and s.name ~= "BloodBurst" and s.name ~= "IchorBurst" then
				local first = Canvas.opaqueCount(s.frames[2])
				local last = Canvas.opaqueCount(s.frames[#s.frames])
				expect.truthy(first > 0, s.name .. " visible")
				expect.truthy(last < first, s.name .. " dissolves")
			end
		end
	end)

	t.test("slash frames differ from one another (real motion, not a still)", function()
		for _, s in catalog do
			if string.sub(s.name, 1, 5) == "Slash" then
				for i = 2, #s.frames do
					expect.truthy(
						buffer.tostring(s.frames[i].px) ~= buffer.tostring(s.frames[i - 1].px),
						`{s.name} frame {i}`
					)
				end
			end
		end
	end)

	t.test("outline and dithering primitives", function()
		local c = Canvas.new(5, 5)
		Canvas.set(c, 2, 2, 0xffffff)
		Canvas.outline(c, Palette.INK)
		expect.eq(Canvas.get(c, 2, 1), Palette.INK)
		expect.eq(Canvas.get(c, 1, 1), nil, "4-neighbourhood only")
		local seen = {}
		for y = 0, 3 do
			for x = 0, 3 do
				seen[Canvas.bayer(x, y)] = true
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		expect.eq(n, 16, "Bayer 4x4 has 16 distinct thresholds")
		expect.eq(Palette.dither(Palette.blood, 0, 0, 0), Palette.blood[1])
		expect.eq(Palette.dither(Palette.blood, 1, 3, 3), Palette.blood[#Palette.blood])
	end)

	t.test("sheet packs frames horizontally", function()
		local s = SpriteGen.slash("T", Palette.steel, 4)
		local sheet = SpriteGen.sheet(s)
		expect.eq(sheet.w, s.w * 4)
		expect.eq(sheet.h, s.h)
		expect.eq(Canvas.get(sheet, s.w * 2 + 10, 5), Canvas.get(s.frames[3], 10, 5))
	end)
end
