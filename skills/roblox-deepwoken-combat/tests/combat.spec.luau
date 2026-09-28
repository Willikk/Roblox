--!nocheck
-- Combat rulebook, lag-compensated hitboxes, weapon data and pose geometry.
return function(t)
	local expect = t.expect
	local roblox = t.harness.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

	local h = t.harness.new()
	local Combat = h:mount(`{t.skillsRoot}/roblox-deepwoken-combat/src/shared/Combat`, "Combat")
	local Config = h:require(Combat.Config)
	local Rules = h:require(Combat.Rules)
	local Hitbox = h:require(Combat.Hitbox)
	local Weapons = h:require(Combat.Weapons)
	local R6 = h:mount(`{t.skillsRoot}/roblox-r6-procedural-animation/src/shared/R6Procedural`, "R6Procedural")
	local PoseLibrary = h:require(R6.PoseLibrary)
	local R6Math = h:require(R6.R6Math)

	local attack = { postureDamage = 15 }

	t.test("parry inside the window beats the hit, outside it only blocks", function()
		local d = Rules.newFighter()
		d.state = "Parrying"
		d.parryStart = 10
		local outcome = Rules.resolve(attack, d, true, 10 + Config.parryWindow - 0.01, Config)
		expect.eq(outcome, "Parried")
		outcome = Rules.resolve(attack, d, true, 10 + Config.parryWindow + 0.05, Config)
		expect.eq(outcome, "Blocked", "late parry still guards")
	end)

	t.test("blocking fills posture until a guard break", function()
		local d = Rules.newFighter()
		d.state = "Blocking"
		local hits = 0
		local outcome
		repeat
			outcome, d.posture = Rules.resolve(attack, d, true, 5, Config)
			hits += 1
		until outcome ~= "Blocked" or hits > 20
		expect.eq(outcome, "GuardBreak")
		expect.eq(hits, math.ceil(Config.postureMax / attack.postureDamage))
		expect.eq(d.posture, 0, "posture resets on break")
	end)

	t.test("guard does not work from behind", function()
		local d = Rules.newFighter()
		d.state = "Blocking"
		local facing = Rules.facing(Vector3.new(0, 0, -1), Vector3.zero, Vector3.new(0, 0, 5), Config.blockFacingAngle)
		expect.eq(facing, false)
		expect.eq(Rules.resolve(attack, d, facing, 1, Config), "Hit")
		expect.eq(Rules.facing(Vector3.new(0, 0, -1), Vector3.zero, Vector3.new(1, 0, -5), 100), true)
	end)

	t.test("i-frames dodge everything, perilous ignores guard", function()
		local d = Rules.newFighter()
		d.state = "Parrying"
		d.parryStart = 1
		d.iframesUntil = 2
		expect.eq(Rules.resolve({ postureDamage = 0, perilous = true }, d, true, 1.5, Config), "Dodged")
		d.iframesUntil = 0
		expect.eq(
			Rules.resolve({ postureDamage = 0, perilous = true }, d, true, 1.05, Config),
			"Hit",
			"cannot parry perilous"
		)
	end)

	t.test("canStart: stun locks, chain buffer, feint only in windup, roll cancel", function()
		local f = Rules.newFighter()
		f.state, f.stateUntil = "Stunned", 5
		expect.eq(Rules.canStart(f, "M1", 4, Config), false)
		expect.eq(Rules.canStart(f, "M1", 5.01, Config), true)
		f.state, f.stateUntil, f.phase = "Attacking", 10, "windup"
		f.recoveryStart = 9
		expect.eq(Rules.canStart(f, "M1", 8, Config), false, "no attack during windup")
		expect.eq(Rules.canStart(f, "Feint", 8, Config), true)
		expect.eq(Rules.canStart(f, "Dodge", 8, Config), true, "roll cancel")
		f.phase = "recovery"
		expect.eq(Rules.canStart(f, "M1", 9 - Config.chainBuffer + 0.01, Config), true, "buffered chain")
		expect.eq(Rules.canStart(f, "Feint", 9.5, Config), false)
		expect.eq(Rules.canStart(f, "Dodge", 9.5, Config), false)
	end)

	t.test("parry whiff is punished with a short lockout", function()
		local f = Rules.newFighter()
		f.lastParryWhiff = 3
		expect.eq(Rules.canStart(f, "Parry", 3 + Config.parryWhiffCooldown - 0.1, Config), false)
		expect.eq(Rules.canStart(f, "Block", 3.1, Config), true, "can still block")
		expect.eq(Rules.canStart(f, "Parry", 3 + Config.parryWhiffCooldown + 0.01, Config), true)
	end)

	t.test("M1 chain advances then resets", function()
		local f = Rules.newFighter()
		expect.eq(Rules.nextCombo(f, 0, 4, Config), 1)
		f.combo, f.lastAttackEnd = 1, 10
		expect.eq(Rules.nextCombo(f, 10.3, 4, Config), 2)
		expect.eq(Rules.nextCombo(f, 10 + Config.chainResetTime + 0.1, 4, Config), 1, "too slow resets")
		f.combo = 4
		expect.eq(Rules.nextCombo(f, 10.1, 4, Config), 1, "after the finisher")
	end)

	t.test("posture regenerates only after the delay", function()
		local f = Rules.newFighter()
		f.posture, f.lastPostureHit = 50, 10
		expect.eq(Rules.regenPosture(f, 10.5, 0.1, Config), 50)
		expect.near(Rules.regenPosture(f, 12, 1, Config), 50 - Config.postureRegenRate)
	end)

	t.test("hitbox: oriented box with padding", function()
		local root = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(90), 0) -- facing -X
		local box = Hitbox.boxFor(root, 4)
		expect.eq(Hitbox.contains(box, Vector3.new(9, 6, 8), Vector3.new(-4, 3, 0), 0), true, "in front")
		expect.eq(Hitbox.contains(box, Vector3.new(9, 6, 8), Vector3.new(4, 3, 0), 0), false, "behind")
		expect.eq(Hitbox.contains(box, Vector3.new(9, 6, 8), Vector3.new(-8.9, 3, 0), 0), false)
		expect.eq(Hitbox.contains(box, Vector3.new(9, 6, 8), Vector3.new(-8.9, 3, 0), 1.2), true, "padding")
	end)

	t.test("history rewinds and interpolates, wraps its ring buffer", function()
		local hist = Hitbox.newHistory(10)
		for i = 0, 25 do
			Hitbox.push(hist, i * 0.1, CFrame.new(i, 0, 0))
		end
		expect.vecNear(Hitbox.sample(hist, 2.5).Position, Vector3.new(25, 0, 0))
		expect.vecNear(Hitbox.sample(hist, 2.25).Position, Vector3.new(22.5, 0, 0), 1e-3)
		expect.vecNear(Hitbox.sample(hist, 0).Position, Vector3.new(16, 0, 0), 1e-3, "clamped to oldest kept")
		expect.eq(Hitbox.sample(Hitbox.newHistory(4), 1), nil)
	end)

	t.test("weapon data is consistent", function()
		local seen = {}
		for _, name in Weapons.NAMES do
			local w = Weapons.get(name)
			expect.truthy(w, name)
			expect.truthy(#w.chain >= 3, "3+ hit chain")
			expect.truthy(w.chain[#w.chain].finisher, "last hit is a finisher")
			local moves = table.clone(w.chain)
			table.insert(moves, w.critical)
			for _, move in moves do
				expect.truthy(not seen[move.name], "unique clip names")
				seen[move.name] = true
				local windup, active, recovery = Weapons.timing(w, move)
				expect.truthy(windup > 0.1 and active > 0 and recovery > 0, move.name .. " timings")
				expect.truthy(windup > Config.parryWindow, move.name .. " is reactable")
			end
		end
		expect.truthy(Weapons.Fists.speed > Weapons.Sword.speed, "fists are faster")
		expect.truthy(Weapons.Fists.chain[1].hitboxSize.Z < Weapons.Sword.chain[1].hitboxSize.Z, "fists are shorter")
		expect.truthy(Weapons.Sword.critical.perilous, "sword critical is perilous")
		expect.truthy(Weapons.Sword.critical.windup >= 0.6, "perilous windup leaves time to dodge")
		expect.truthy(Weapons.Greatsword.speed < Weapons.Sword.speed, "greatsword is slowest")
		expect.truthy(
			Weapons.Greatsword.chain[1].hitboxSize.X > Weapons.Sword.chain[1].hitboxSize.X,
			"greatsword is widest"
		)
	end)

	-- Pose geometry: where does the hand end up?
	local C0, C1 = R6Math.DEFAULT_C0, R6Math.DEFAULT_C1
	local function hand(pose, side)
		local joint = side .. "Shoulder"
		local entry = pose[joint]
		local offset = if entry then PoseLibrary.jointCFrame(entry, C0[joint].Position, 1) else CFrame.new()
		local torsoOffset = if pose.RootJoint
			then PoseLibrary.jointCFrame(pose.RootJoint, Vector3.new(0, -1, 0), 1)
			else CFrame.new()
		local torso = CFrame.new()
			* C0.RootJoint
			* R6Math.jointOffset(C0.RootJoint, torsoOffset)
			* C1.RootJoint:Inverse()
		local arm = torso * C0[joint] * R6Math.jointOffset(C0[joint], offset) * C1[joint]:Inverse()
		return arm:PointToWorldSpace(Vector3.new(0, -1, 0))
	end

	t.test("pose conventions: X+ forward, overhead, right Z+ outward", function()
		expect.vecNear(
			hand({ RightShoulder = { rot = Vector3.new(90, 0, 0) } }, "Right"),
			Vector3.new(1.5, 0.5, -1.5),
			1e-3
		)
		expect.truthy(hand({ RightShoulder = { rot = Vector3.new(175, 0, 0) } }, "Right").Y > 1.8, "overhead")
		expect.truthy(hand({ RightShoulder = { rot = Vector3.new(0, 0, 60) } }, "Right").X > 2, "outward")
		expect.truthy(hand({ LeftShoulder = { rot = Vector3.new(0, 0, -60) } }, "Left").X < -2, "left outward is Z-")
	end)

	t.test("sword attacks: windup raises the blade hand, strike brings it forward", function()
		for i, move in Weapons.Sword.chain do
			local w = hand(move.poses.windup, "Right")
			local s = hand(move.poses.strike, "Right")
			expect.truthy(s.Z < -0.5, `strike {i} reaches forward (got {s})`)
			expect.truthy((w - s).Magnitude > 1.5, `strike {i} travels`)
		end
		expect.truthy(hand(Weapons.Sword.chain[3].poses.windup, "Right").Y > 1.8, "overhead windup")
	end)

	t.test("greatsword swings end in front of the body", function()
		for i, move in Weapons.Greatsword.chain do
			local s = hand(move.poses.strike, "Right")
			expect.truthy(s.Z < -0.5 or s.Y > 1.5, `greatsword strike {i} (got {s})`)
		end
	end)

	t.test("fist chain alternates hands and extends forward", function()
		local order = { "Left", "Right", "Left", "Right" }
		for i = 1, 3 do
			local s = hand(Weapons.Fists.chain[i].poses.strike, order[i])
			expect.truthy(s.Z < -1.2, `punch {i} reaches forward`)
		end
		expect.truthy(hand(Weapons.Fists.chain[4].poses.strike, "Right").Y > 1.5, "uppercut ends high")
	end)

	t.test("attack clips line up with gameplay timings", function()
		local move = Weapons.Sword.chain[1]
		local windup, active, recovery = Weapons.timing(Weapons.Sword, move)
		local clip = PoseLibrary.attack(
			{ windup = move.poses.windup, strike = move.poses.strike },
			{ windup = windup, active = active, recovery = recovery }
		)
		expect.near(clip.duration, windup + active + recovery, 1e-9)
		local atWindup = PoseLibrary.sample(clip, windup)
		expect.vecNear(
			atWindup.RightShoulder.rot,
			move.poses.windup.RightShoulder.rot,
			1e-3,
			"windup pose at windup end"
		)
		local atStrike = PoseLibrary.sample(clip, windup + active)
		expect.vecNear(
			atStrike.RightShoulder.rot,
			move.poses.strike.RightShoulder.rot,
			1e-3,
			"strike pose at active end"
		)
		local _, weight = PoseLibrary.sample(clip, clip.duration + 0.1)
		expect.eq(weight, 0, "finished")
	end)
end
