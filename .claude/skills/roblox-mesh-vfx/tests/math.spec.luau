--!nocheck
-- Pure math: easing, surface alignment, beam arcs, cone sampling, deterministic rings.
return function(t)
	local expect = t.expect
	local h = t.harness.new()
	local VFX = h:mount(`{t.skillsRoot}/roblox-mesh-vfx/src/shared/VFX`, "VFX")
	local Ease = h:require(VFX.Ease)
	local VFXMath = h:require(VFX.VFXMath)
	local CFrame, Vector3 = t.harness.roblox.CFrame, t.harness.roblox.Vector3

	local function determinant(cf)
		return cf.XVector:Cross(cf.YVector):Dot(cf.ZVector)
	end

	t.test("easing curves hit 0 and 1 at the ends", function()
		for _, name in
			{
				"linear",
				"inQuad",
				"outQuad",
				"inOutQuad",
				"outCubic",
				"outQuart",
				"outQuint",
				"outExpo",
				"inExpo",
				"outBack",
				"outElastic",
				"inOutSine",
				"outSine",
			}
		do
			expect.near(Ease[name](0), 0, 1e-6, name .. "(0)")
			expect.near(Ease[name](1), 1, 1e-6, name .. "(1)")
		end
	end)

	t.test("phase maps sub-ranges and clamps", function()
		expect.eq(Ease.phase(0.05, 0.1, 0.5), 0)
		expect.near(Ease.phase(0.3, 0.1, 0.5), 0.5)
		expect.eq(Ease.phase(0.9, 0.1, 0.5), 1)
		expect.eq(Ease.phase(0.5, 0.5, 0.5), 1) -- degenerate range
	end)

	t.test("cubicBezier matches CSS `ease` and is monotonic", function()
		local ease = Ease.cubicBezier(0.25, 0.1, 0.25, 1)
		expect.near(ease(0.5), 0.8024, 2e-3)
		local previous = 0
		for i = 1, 100 do
			local v = ease(i / 100)
			expect.truthy(v >= previous - 1e-9, "monotonic")
			previous = v
		end
	end)

	t.test("expAlpha never overshoots even with huge dt", function()
		expect.truthy(Ease.expAlpha(20, 5) <= 1)
		expect.near(Ease.expAlpha(10, 0), 0)
	end)

	t.test("alignToNormal: up = normal, right-handed, forward follows the hint", function()
		local rng = t.harness.Random.new(7)
		for _ = 1, 200 do
			local normal = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.05, 1), rng:NextNumber(-1, 1)).Unit
			local hint = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			local cf = VFXMath.alignToNormal(Vector3.new(1, 2, 3), normal, hint)
			expect.vecNear(cf.UpVector, normal, 1e-4, "UpVector")
			expect.near(determinant(cf), 1, 1e-4, "right-handed")
			local projected = (hint - normal * hint:Dot(normal)).Unit
			expect.vecNear(cf.LookVector, projected, 1e-3, "LookVector")
			expect.vecNear(cf.Position, Vector3.new(1, 2, 3), 1e-6, "Position")
		end
	end)

	t.test("alignToNormal survives a hint parallel to the normal", function()
		local cf = VFXMath.alignToNormal(Vector3.zero, Vector3.yAxis, Vector3.yAxis)
		expect.vecNear(cf.UpVector, Vector3.yAxis)
		expect.near(determinant(cf), 1, 1e-4)
	end)

	t.test("the legacy fromMatrix(pos, right, up, -look) pattern is mirrored (regression proof)", function()
		local normal = Vector3.new(0.3, 0.9, 0.1).Unit
		local right = Vector3.yAxis:Cross(normal).Unit
		local look = right:Cross(normal).Unit
		local legacy = CFrame.fromMatrix(Vector3.zero, right, normal, -look)
		expect.near(determinant(legacy), -1, 1e-4, "legacy matrix is left-handed")
	end)

	t.test("beam arc Bezier stays on the circle (<= 90 deg pieces)", function()
		local radius = 7
		for _, sweepDeg in { 30, 60, 90 } do
			local sweep = math.rad(sweepDeg)
			local a0 = VFXMath.arcAttachmentCFrame(radius, 0)
			local a1 = VFXMath.arcAttachmentCFrame(radius, sweep)
			local k = VFXMath.arcCurveSize(radius, sweep)
			-- Beam control points: P1 along +X of attachment0, P2 along -X of attachment1.
			local p0, p3 = a0.Position, a1.Position
			local p1 = p0 + a0.XVector * k
			local p2 = p3 - a1.XVector * k
			for i = 0, 20 do
				local p = VFXMath.bezier(p0, p1, p2, p3, i / 20)
				expect.near(p.Magnitude, radius, radius * 3e-4, `radius at {sweepDeg} deg`)
			end
		end
	end)

	t.test("arc attachments keep Y up and X tangent", function()
		for i = 0, 12 do
			local angle = i * math.pi / 6
			local cf = VFXMath.arcAttachmentCFrame(5, angle)
			expect.vecNear(cf.YVector, Vector3.yAxis, 1e-5)
			expect.near(cf.XVector:Dot(cf.Position.Unit), 0, 1e-5, "tangent is perpendicular to radius")
			expect.near(determinant(cf), 1, 1e-4)
		end
		-- Angle 0 is straight ahead (-Z) and angles grow towards -X.
		expect.vecNear(VFXMath.arcPoint(1, 0), Vector3.new(0, 0, -1), 1e-6)
		expect.vecNear(VFXMath.arcPoint(1, math.pi / 2), Vector3.new(-1, 0, 0), 1e-6)
	end)

	t.test("lookAlong looks exactly along the direction, right-handed", function()
		local rng = t.harness.Random.new(9)
		for _ = 1, 200 do
			local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			local cf = VFXMath.lookAlong(Vector3.new(4, 5, 6), d)
			expect.vecNear(cf.LookVector, d.Unit, 1e-4)
			expect.near(determinant(cf), 1, 1e-4)
			expect.truthy(cf.UpVector.Y >= -1e-6, "up stays on the upper side")
		end
		-- Degenerate: looking straight up.
		local up = VFXMath.lookAlong(Vector3.zero, Vector3.yAxis)
		expect.vecNear(up.LookVector, Vector3.yAxis, 1e-5)
		expect.near(determinant(up), 1, 1e-4)
	end)

	t.test("randomInCone stays inside the cone", function()
		local rng = t.harness.Random.new(3)
		local dir = Vector3.new(0.2, 1, 0.4).Unit
		for _ = 1, 500 do
			local v = VFXMath.randomInCone(rng, dir, math.rad(30))
			expect.near(v.Magnitude, 1, 1e-4)
			expect.truthy(v:Dot(dir) >= math.cos(math.rad(30)) - 1e-4, "inside cone")
		end
	end)

	t.test("ringAngles is deterministic for a seed", function()
		local a = VFXMath.ringAngles(t.harness.Random.new(42), 10, 0.6)
		local b = VFXMath.ringAngles(t.harness.Random.new(42), 10, 0.6)
		expect.eq(#a, 10)
		for i = 1, 10 do
			expect.eq(a[i], b[i])
		end
	end)
end
