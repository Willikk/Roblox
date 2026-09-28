--!nocheck
-- Spring, Animator scheduler, Pool and TextureAnimator behaviour with mocked services.
return function(t)
	local expect = t.expect
	local Vector3, CFrame = t.harness.roblox.Vector3, t.harness.roblox.CFrame

	local function fresh()
		local h = t.harness.new()
		local VFX = h:mount(`{t.skillsRoot}/roblox-mesh-vfx/src/shared/VFX`, "VFX")
		return h, VFX
	end

	t.test("spring: closed form is exact (two half steps == one full step)", function()
		local h, VFX = fresh()
		local Spring = h:require(VFX.Spring)
		for _, zeta in { 0.3, 1, 2.5 } do
			local p, v = Vector3.new(3, -2, 1), Vector3.new(0, 5, -1)
			local pa, va = Spring.step(p, v, Vector3.zero, 3, zeta, 0.1)
			pa, va = Spring.step(pa, va, Vector3.zero, 3, zeta, 0.1)
			local pb, vb = Spring.step(p, v, Vector3.zero, 3, zeta, 0.2)
			expect.vecNear(pa, pb, 1e-4, `position zeta={zeta}`)
			expect.vecNear(va, vb, 1e-3, `velocity zeta={zeta}`)
		end
	end)

	t.test("spring: stable under a 0.5 s hitch and converges", function()
		local h, VFX = fresh()
		local Spring = h:require(VFX.Spring)
		local s = Spring.new(Vector3.new(10, 0, 0), 4, 0.4)
		s.target = Vector3.zero
		for _ = 1, 20 do
			local p = s:update(0.5)
			expect.truthy(p.Magnitude < 10.001, "never grows")
		end
		expect.truthy(s.position.Magnitude < 1e-3, "settled")
	end)

	t.test("spring: critical damping never overshoots", function()
		local h, VFX = fresh()
		local Spring = h:require(VFX.Spring)
		local s = Spring.new(Vector3.new(1, 0, 0), 5, 1)
		s.target = Vector3.zero
		for _ = 1, 240 do
			expect.truthy(s:update(1 / 60).X >= -1e-6, "no overshoot")
		end
	end)

	t.test("animator: last step receives t == 1, then onComplete(false)", function()
		local h, VFX = fresh()
		local Animator = h:require(VFX.Animator)
		local seen, completed = {}, nil
		Animator.play(0.1, function(tt)
			table.insert(seen, tt)
		end, {
			onComplete = function(cancelled)
				completed = cancelled
			end,
		})
		for _ = 1, 10 do
			h:step(1 / 60)
		end
		expect.eq(seen[#seen], 1)
		expect.eq(completed, false)
		expect.eq(Animator.activeCount(), 0)
		expect.eq(h.RunService.PreRender:ConnectedCount(), 0, "loop disconnects when idle")
	end)

	t.test("animator: time scale 0 freezes a group (hitstop)", function()
		local h, VFX = fresh()
		local Animator = h:require(VFX.Animator)
		local last = 0
		Animator.play(1, function(tt)
			last = tt
		end)
		h:step(0.25)
		Animator.setTimeScale("world", 0)
		h:step(0.25)
		h:step(0.25)
		expect.near(last, 0.25, 1e-9, "frozen")
		Animator.setTimeScale("world", 1)
		h:step(0.25)
		expect.near(last, 0.5, 1e-9, "resumed")
	end)

	t.test("animator: a throwing effect is isolated and still cleaned up", function()
		local h, VFX = fresh()
		local Animator = h:require(VFX.Animator)
		local cleaned, other = nil, 0
		Animator.play(1, function()
			error("boom")
		end, {
			onComplete = function(cancelled)
				cleaned = cancelled
			end,
		})
		Animator.play(1, function(tt)
			other = tt
		end)
		h:step(0.5)
		expect.eq(cleaned, true)
		expect.near(other, 0.5)
		expect.truthy(#h.warnings >= 1, "error was reported")
	end)

	t.test("animator: queued moves flush before completion callbacks", function()
		local h, VFX = fresh()
		local Animator = h:require(VFX.Animator)
		local part = { CFrame = CFrame.new() }
		local park = CFrame.new(0, -5e4, 0)
		Animator.play(0.01, function()
			Animator.move(part, CFrame.new(1, 2, 3))
		end, {
			onComplete = function()
				part.CFrame = park -- what Pool:release does
			end,
		})
		h:step(0.1)
		expect.vecNear(part.CFrame.Position, park.Position, 1e-6, "park wins over the last move")
		expect.eq(#h.bulkMoves, 1, "one BulkMoveTo per frame")
	end)

	t.test("animator: delay respects time scale", function()
		local h, VFX = fresh()
		local Animator = h:require(VFX.Animator)
		local fired = false
		Animator.delay(0.2, function()
			fired = true
		end)
		Animator.setTimeScale("world", 0)
		h:step(1)
		expect.eq(fired, false)
		Animator.setTimeScale("world", 1)
		h:step(0.25)
		expect.eq(fired, true)
	end)

	t.test("pool: reuse, prewarm, double-release guard, max", function()
		local h, VFX = fresh()
		local Pool = h:require(VFX.Pool)
		local made, released, destroyed = 0, 0, 0
		local pool = Pool.new(function()
			made += 1
			return { id = made }
		end, {
			prewarm = 2,
			max = 2,
			onRelease = function()
				released += 1
			end,
			onDestroy = function()
				destroyed += 1
			end,
		})
		expect.eq(made, 2)
		local a, b, c = pool:acquire(), pool:acquire(), pool:acquire()
		expect.eq(made, 3, "third acquire allocates")
		pool:release(a)
		pool:release(a) -- ignored
		pool:release(b)
		pool:release(c) -- beyond max -> destroyed
		expect.eq(destroyed, 1)
		local total, free = pool:size()
		expect.eq(total, 2)
		expect.eq(free, 2)
		expect.eq(pool:acquire(), b, "LIFO reuse keeps caches warm")
	end)

	t.test("texture wrap keeps offsets inside one tile", function()
		local h, VFX = fresh()
		local TextureAnimator = h:require(VFX.TextureAnimator)
		expect.near(TextureAnimator._wrap(12.5, 4), 0.5)
		expect.near(TextureAnimator._wrap(-0.5, 4), 3.5)
		expect.near(TextureAnimator._wrap(3, 0), 3)
	end)
end
