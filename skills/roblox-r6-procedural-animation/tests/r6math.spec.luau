--!nocheck
--[[
	Geometry proofs on a simulated R6 rig (real default C0/C1 constants):
	forward kinematics = Part0 * C0 * Transform * C1^-1, exactly like the engine.
]]
return function(t)
	local expect = t.expect
	local h = t.harness.new()
	local root = h:mount(`{t.skillsRoot}/roblox-r6-procedural-animation/src/shared/R6Procedural`, "R6Procedural")
	local R6Math = h:require(root.R6Math)
	local CFrame, Vector3 = t.harness.roblox.CFrame, t.harness.roblox.Vector3
	local C0, C1 = R6Math.DEFAULT_C0, R6Math.DEFAULT_C1

	-- offsets: { [joint] = Part0-space CFrame }, returns world CFrames of every part.
	local function pose(offsets)
		offsets = offsets or {}
		local function transform(joint)
			local o = offsets[joint]
			return if o then R6Math.jointOffset(C0[joint], o) else CFrame.new()
		end
		local hrp = CFrame.new()
		local torso = hrp * C0.RootJoint * transform("RootJoint") * C1.RootJoint:Inverse()
		return {
			Torso = torso,
			Head = torso * C0.Neck * transform("Neck") * C1.Neck:Inverse(),
			RightLeg = torso * C0.RightHip * transform("RightHip") * C1.RightHip:Inverse(),
			LeftLeg = torso * C0.LeftHip * transform("LeftHip") * C1.LeftHip:Inverse(),
			RightArm = torso * C0.RightShoulder * transform("RightShoulder") * C1.RightShoulder:Inverse(),
			LeftArm = torso * C0.LeftShoulder * transform("LeftShoulder") * C1.LeftShoulder:Inverse(),
		}
	end

	t.test("default constants reproduce the R6 rest pose", function()
		local p = pose()
		expect.vecNear(p.Torso.Position, Vector3.zero)
		expect.vecNear(p.Head.Position, Vector3.new(0, 1.5, 0))
		expect.vecNear(p.RightLeg.Position, Vector3.new(0.5, -2, 0))
		expect.vecNear(p.LeftLeg.Position, Vector3.new(-0.5, -2, 0))
		expect.vecNear(p.RightArm.Position, Vector3.new(1.5, 0, 0))
		expect.vecNear(p.LeftArm.Position, Vector3.new(-1.5, 0, 0))
		for name, cf in p do
			expect.vecNear(cf.LookVector, Vector3.new(0, 0, -1), 1e-5, name .. " faces forward")
		end
	end)

	t.test("RootJoint.C0 local axes: Y points BACKWARD, Z points UP (why the legacy lean broke)", function()
		expect.vecNear(C0.RootJoint:VectorToWorldSpace(Vector3.yAxis), Vector3.new(0, 0, 1), 1e-5)
		expect.vecNear(C0.RootJoint:VectorToWorldSpace(Vector3.zAxis), Vector3.new(0, 1, 0), 1e-5)
	end)

	t.test("legacy `C0 * CFrame.new(0, -drop, 0)` moves the torso horizontally, not down", function()
		local hrp = CFrame.new()
		local legacyTorso = hrp * (C0.RootJoint * CFrame.new(0, -1, 0)) * C1.RootJoint:Inverse()
		expect.near(legacyTorso.Position.Y, 0, 1e-5, "no vertical drop at all")
		expect.near(math.abs(legacyTorso.Position.Z), 1, 1e-5, "slides along Z instead")
	end)

	t.test("jointOffset pelvis drop lowers the whole body straight down", function()
		local p = pose({ RootJoint = CFrame.new(0, -0.8, 0) })
		expect.vecNear(p.Torso.Position, Vector3.new(0, -0.8, 0))
		expect.vecNear(p.RightLeg.Position, Vector3.new(0.5, -2.8, 0))
		expect.vecNear(p.Torso.LookVector, Vector3.new(0, 0, -1), 1e-5)
	end)

	t.test("neck rotation aims the head and keeps the neck point fixed", function()
		for _, angles in { { 0.4, 0 }, { -0.3, 0.9 }, { 0.2, -1.1 } } do
			local pitch, yaw = angles[1], angles[2]
			local neckPivot = C0.Neck.Position
			local p = pose({ Neck = R6Math.rotationAbout(neckPivot, CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)) })
			local expected = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
			expect.vecNear(p.Head.LookVector, expected, 1e-4, "head direction")
			-- The bottom-center of the head stays on the neck point.
			expect.vecNear(p.Head:PointToWorldSpace(Vector3.new(0, -0.5, 0)), Vector3.new(0, 1, 0), 1e-4)
		end
	end)

	t.test("lookAngles: left is +yaw, up is +pitch, round-trips through fromEulerAnglesYXZ", function()
		local yaw, pitch = R6Math.lookAngles(Vector3.new(-1, 0, 0))
		expect.near(yaw, math.pi / 2, 1e-6)
		expect.near(pitch, 0, 1e-6)
		yaw, pitch = R6Math.lookAngles(Vector3.new(0, 1, -1))
		expect.near(pitch, math.pi / 4, 1e-6)
		local rng = t.harness.Random.new(4)
		for _ = 1, 100 do
			local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
			local y, p = R6Math.lookAngles(d)
			expect.vecNear(CFrame.fromEulerAnglesYXZ(p, y, 0).LookVector, d, 1e-4)
		end
	end)

	t.test("legRaise + hip offset lifts the foot by exactly `raise`", function()
		local hipPivot = Vector3.new(0, -1, 0)
		for _, raise in { 0.2, 0.6, 1, 1.4 } do
			local tuck, angle = R6Math.legRaise(raise, 2, 0.6)
			local offset = CFrame.new(0, tuck, 0) * R6Math.rotationAbout(hipPivot, CFrame.Angles(angle, 0, 0))
			local p = pose({ RightHip = offset })
			local footBottom = p.RightLeg:PointToWorldSpace(Vector3.new(0, -1, 0))
			expect.near(footBottom.Y, -3 + raise, 1e-4, `raise {raise}`)
			expect.truthy(footBottom.Z <= 1e-6, "foot swings forward, never backward")
		end
	end)

	t.test("solveFeet: stairs, slopes, ledges", function()
		local drop, l, r = R6Math.solveFeet(0, 0, 1.2, 1.5)
		expect.eq(drop, 0)
		expect.eq(l, 0)
		expect.eq(r, 0)
		-- Standing on a step with the right foot over the lower step (1 stud below).
		drop, l, r = R6Math.solveFeet(0, -1, 1.2, 1.5)
		expect.near(drop, 1)
		expect.near(l, 1, 1e-9, "left foot re-raised onto the step")
		expect.near(r, 0)
		-- Slope: uphill foot clips (+0.3), downhill foot floats (-0.3).
		drop, l, r = R6Math.solveFeet(0.3, -0.3, 1.2, 1.5)
		expect.near(drop, 0.3)
		expect.near(l, 0.6)
		expect.near(r, 0)
		-- Ledge: no ground under one foot -> no adjustment from that foot.
		drop, l, r = R6Math.solveFeet(nil, 0, 1.2, 1.5)
		expect.eq(drop, 0)
		-- Clamped.
		drop = R6Math.solveFeet(0, -5, 1.2, 1.5)
		expect.near(drop, 1.2)
	end)

	t.test("forward lean about the hip line + hip compensation keeps legs planted and vertical", function()
		local lean = math.rad(12)
		local hipLine = Vector3.new(0, -1, 0)
		local p = pose({
			RootJoint = R6Math.rotationAbout(hipLine, CFrame.Angles(-lean, 0, 0)),
			RightHip = R6Math.rotationAbout(hipLine, CFrame.Angles(lean, 0, 0)),
			LeftHip = R6Math.rotationAbout(hipLine, CFrame.Angles(lean, 0, 0)),
		})
		local torsoTop = p.Torso:PointToWorldSpace(Vector3.new(0, 1, 0))
		expect.truthy(torsoTop.Z < -0.3, "torso top moved forward")
		expect.vecNear(p.RightLeg.Position, Vector3.new(0.5, -2, 0), 1e-4, "right leg did not move")
		expect.vecNear(p.LeftLeg.UpVector, Vector3.yAxis, 1e-4, "left leg vertical")
	end)

	t.test("torso twist with hip counter-twist leaves the legs untouched", function()
		local twist = math.rad(20)
		local axis = Vector3.new(0, -1, 0)
		local p = pose({
			RootJoint = R6Math.rotationAbout(Vector3.zero, CFrame.Angles(0, twist, 0)),
			RightHip = R6Math.rotationAbout(axis, CFrame.Angles(0, -twist, 0)),
			LeftHip = R6Math.rotationAbout(axis, CFrame.Angles(0, -twist, 0)),
		})
		expect.vecNear(p.Torso.LookVector, CFrame.Angles(0, twist, 0).LookVector, 1e-5)
		expect.vecNear(p.RightLeg.Position, Vector3.new(0.5, -2, 0), 1e-4)
		expect.vecNear(p.LeftLeg.LookVector, Vector3.new(0, 0, -1), 1e-4)
	end)

	t.test("leanAngles: accelerate -> lean in, left turn -> bank left, clamped", function()
		local s = {
			referenceSpeed = 16,
			speedLean = math.rad(6),
			accelLean = 0.5,
			bankScale = 1,
			maxForward = math.rad(18),
			maxBackward = math.rad(10),
			maxBank = math.rad(14),
		}
		local lean, bank = R6Math.leanAngles(Vector3.new(0, 0, -16), Vector3.new(0, 0, -60), 0, 196.2, s)
		expect.truthy(lean > math.rad(6), "accelerating adds lean")
		expect.near(bank, 0)
		lean = R6Math.leanAngles(Vector3.new(0, 0, -16), Vector3.new(0, 0, 200), 0, 196.2, s)
		expect.truthy(lean < 0, "hard braking leans back")
		local _, bankLeft = R6Math.leanAngles(Vector3.new(0, 0, -16), Vector3.zero, 3, 196.2, s)
		expect.truthy(bankLeft > 0, "left turn banks left")
		local _, huge = R6Math.leanAngles(Vector3.new(0, 0, -100), Vector3.zero, 50, 196.2, s)
		expect.near(huge, s.maxBank, 1e-9, "clamped")
	end)

	t.test("yawDelta sign and slopeLean", function()
		expect.truthy(R6Math.yawDelta(Vector3.new(0, 0, -1), Vector3.new(-0.1, 0, -1)) > 0, "left is positive")
		expect.near(R6Math.slopeLean(Vector3.new(0, 1, 0)), 0)
		expect.truthy(R6Math.slopeLean(Vector3.new(0, 0.95, 0.3).Unit) > 0, "uphill leans forward")
	end)
end
