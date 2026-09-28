--!nocheck
--[[
	End-to-end: mock R6 rig -> real layers -> Rig:apply() writes Transform ->
	forward kinematics (Part0 * C0 * Transform * C1^-1) -> assertions on the pose.
]]
return function(t)
	local expect = t.expect
	local roblox = t.harness.roblox
	local CFrame, Vector3, Enum = roblox.CFrame, roblox.Vector3, roblox.Enum

	local function load()
		local h = t.harness.new()
		local root = h:mount(`{t.skillsRoot}/roblox-r6-procedural-animation/src/shared/R6Procedural`, "R6Procedural")
		return h, root
	end

	-- Minimal Instance stand-ins with the members Rig.new / layers use.
	local function instance(className, props)
		local obj = props or {}
		obj.ClassName = className
		obj.__children = obj.__children or {}
		function obj:IsA(name)
			if name == className then
				return true
			end
			if name == "BasePart" then
				return className == "Part"
			end
			return false
		end
		function obj:FindFirstChild(name)
			return self.__children[name]
		end
		function obj:FindFirstChildOfClass(name)
			for _, child in self.__children do
				if child.ClassName == name then
					return child
				end
			end
			return nil
		end
		function obj:GetDescendants()
			local list = {}
			local function walk(node)
				for _, child in node.__children do
					table.insert(list, child)
					walk(child)
				end
			end
			walk(self)
			return list
		end
		function obj:GetAttribute()
			return nil
		end
		return obj
	end

	local function makeCharacter(R6Math, rigType)
		local model = instance("Model", { Name = "Dummy", Parent = true })
		local humanoid = instance("Humanoid", {
			Name = "Humanoid",
			RigType = rigType or Enum.HumanoidRigType.R6,
			HipHeight = 0,
			Health = 100,
			Sit = false,
			PlatformStand = false,
			Parent = model,
		})
		local hrp = instance(
			"Part",
			{ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), CFrame = CFrame.new(), Parent = model }
		)
		local torso =
			instance("Part", { Name = "Torso", Size = Vector3.new(2, 2, 1), CFrame = CFrame.new(), Parent = model })
		local parts = { HumanoidRootPart = hrp, Torso = torso, Humanoid = humanoid }
		for _, name in { "Head", "Left Leg", "Right Leg", "Left Arm", "Right Arm" } do
			parts[name] = instance("Part", {
				Name = name,
				Size = if name == "Head" then Vector3.new(2, 1, 1) else Vector3.new(1, 2, 1),
				CFrame = CFrame.new(),
				Parent = model,
			})
		end
		for name, part in parts do
			model.__children[name] = part
		end
		local jointDefs = {
			{ "RootJoint", hrp, "RootJoint" },
			{ "Neck", torso, "Neck" },
			{ "Left Hip", torso, "LeftHip" },
			{ "Right Hip", torso, "RightHip" },
			{ "Left Shoulder", torso, "LeftShoulder" },
			{ "Right Shoulder", torso, "RightShoulder" },
		}
		local motors = {}
		for _, def in jointDefs do
			local motor = instance("Motor6D", {
				Name = def[1],
				C0 = R6Math.DEFAULT_C0[def[3]],
				C1 = R6Math.DEFAULT_C1[def[3]],
				Transform = CFrame.new(),
				Parent = def[2],
			})
			def[2].__children[def[1]] = motor
			motors[def[3]] = motor
		end
		return model, motors
	end

	local function fk(motors)
		local function link(parent, motor)
			return parent * motor.C0 * motor.Transform * motor.C1:Inverse()
		end
		local torso = link(CFrame.new(), motors.RootJoint)
		return {
			Torso = torso,
			Head = link(torso, motors.Neck),
			LeftLeg = link(torso, motors.LeftHip),
			RightLeg = link(torso, motors.RightHip),
		}
	end

	local function ctxWith(lookTarget)
		return {
			isLocal = false,
			lookTarget = lookTarget,
			weight = function()
				return 1
			end,
		}
	end

	t.test("Rig.new reads R6 geometry and rejects R15", function()
		local h, root = load()
		local R6Math, Rig = h:require(root.R6Math), h:require(root.Rig)
		local model = makeCharacter(R6Math)
		local rig = Rig.new(model)
		expect.truthy(rig, "rig built")
		expect.near(rig.legLength, 2)
		expect.near(rig.restFootY, -3)
		expect.near(rig.hipLineY, -1)
		expect.near(rig.hipHalfWidth, 0.5)
		local r15 = makeCharacter(R6Math, Enum.HumanoidRigType.R15)
		expect.eq(Rig.new(r15), nil)
	end)

	t.test("offsets layer on top of a fresh animation pose every frame (no accumulation)", function()
		local h, root = load()
		local R6Math, Rig = h:require(root.R6Math), h:require(root.Rig)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		local anim = CFrame.Angles(0.3, 0, 0)
		local offset = CFrame.new(0, -0.5, 0)
		for _ = 1, 5 do
			motors.RootJoint.Transform = anim -- the Animator writes its pose each frame
			rig:begin()
			rig:add("RootJoint", offset)
			rig:apply()
		end
		local expected = R6Math.jointOffset(motors.RootJoint.C0, offset) * anim
		expect.vecNear(motors.RootJoint.Transform.Position, expected.Position, 1e-5)
		expect.vecNear(motors.RootJoint.Transform.LookVector, expected.LookVector, 1e-5)
	end)

	t.test("throttled Animator (Transform not rewritten): offset re-applied on the stored base", function()
		local h, root = load()
		local R6Math, Rig = h:require(root.R6Math), h:require(root.Rig)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		local offset = CFrame.new(0, -0.5, 0)
		for _ = 1, 10 do
			rig:begin()
			rig:add("RootJoint", offset)
			rig:apply()
		end
		local p = fk(motors)
		expect.vecNear(p.Torso.Position, Vector3.new(0, -0.5, 0), 1e-5, "dropped once, not 10 times")
		rig:restore()
		expect.vecNear(fk(motors).Torso.Position, Vector3.zero, 1e-5, "restore removes it")
	end)

	t.test("TerrainAdaptation plants both feet on a stair edge", function()
		local h, root = load()
		local R6Math, Rig, Sensor, Config =
			h:require(root.R6Math), h:require(root.Rig), h:require(root.Sensor), h:require(root.Config)
		local Terrain = h:require(root.Layers.TerrainAdaptation)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		local cfg = Config.resolve(nil)
		local sensor = Sensor.new()
		-- Right foot above a step that is 0.8 studs lower; left foot on the upper step.
		sensor.leftError, sensor.rightError = 0, -0.8
		for _ = 1, 240 do
			rig:begin()
			Terrain.update(rig, sensor, 1 / 60, cfg, ctxWith(nil))
			rig:apply()
		end
		local p = fk(motors)
		local leftFoot = p.LeftLeg:PointToWorldSpace(Vector3.new(0, -1, 0))
		local rightFoot = p.RightLeg:PointToWorldSpace(Vector3.new(0, -1, 0))
		expect.near(rightFoot.Y, -3.8, 0.02, "right foot reaches the lower step")
		expect.near(leftFoot.Y, -3.0, 0.02, "left foot stays on the upper step")
	end)

	t.test("HeadLook aims the head at the target and keeps the legs still", function()
		local h, root = load()
		local R6Math, Rig, Sensor, Config =
			h:require(root.R6Math), h:require(root.Rig), h:require(root.Sensor), h:require(root.Config)
		local HeadLook = h:require(root.Layers.HeadLook)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		local cfg = Config.resolve(nil)
		local sensor = Sensor.new()
		local target = { yaw = 0.6, pitch = 0.3 }
		for _ = 1, 300 do
			rig:begin()
			HeadLook.update(rig, sensor, 1 / 60, cfg, ctxWith(target))
			rig:apply()
		end
		local p = fk(motors)
		expect.vecNear(p.Head.LookVector, CFrame.fromEulerAnglesYXZ(0.3, 0.6, 0).LookVector, 2e-3)
		expect.vecNear(p.LeftLeg.LookVector, Vector3.new(0, 0, -1), 1e-4, "legs keep facing forward")
		expect.vecNear(p.RightLeg.Position, Vector3.new(0.5, -2, 0), 1e-4)
	end)

	t.test("HeadLook relaxes when the target is behind the character", function()
		local h, root = load()
		local R6Math, Rig, Sensor, Config =
			h:require(root.R6Math), h:require(root.Rig), h:require(root.Sensor), h:require(root.Config)
		local HeadLook = h:require(root.Layers.HeadLook)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		for _ = 1, 300 do
			rig:begin()
			HeadLook.update(rig, Sensor.new(), 1 / 60, Config.resolve(nil), ctxWith({ yaw = 3, pitch = 0 }))
			rig:apply()
		end
		expect.vecNear(fk(motors).Head.LookVector, Vector3.new(0, 0, -1), 1e-3)
	end)

	t.test("BodyLean: running forward bends at the waist, legs stay vertical", function()
		local h, root = load()
		local R6Math, Rig, Sensor, Config =
			h:require(root.R6Math), h:require(root.Rig), h:require(root.Sensor), h:require(root.Config)
		local BodyLean = h:require(root.Layers.BodyLean)
		local model, motors = makeCharacter(R6Math)
		local rig = Rig.new(model)
		local cfg = Config.resolve({ lean = { legCompensation = 1 } })
		local sensor = Sensor.new()
		sensor.velocity = Vector3.new(0, 0, -16)
		for _ = 1, 300 do
			rig:begin()
			BodyLean.update(rig, sensor, 1 / 60, cfg, ctxWith(nil))
			rig:apply()
		end
		expect.truthy(rig.pose.lean > math.rad(3), "leaning forward")
		local p = fk(motors)
		expect.truthy(p.Torso:PointToWorldSpace(Vector3.new(0, 1, 0)).Z < -0.05, "chest ahead of the hips")
		expect.vecNear(p.LeftLeg.UpVector, Vector3.yAxis, 1e-3, "legs vertical")
	end)

	t.test("Config.resolve deep-merges overrides without touching defaults", function()
		local h, root = load()
		local Config = h:require(root.Config)
		local cfg = Config.resolve({ head = { maxYaw = 1 } })
		expect.near(cfg.head.maxYaw, 1)
		expect.near(cfg.head.maxUp, Config.defaults.head.maxUp)
		expect.truthy(Config.defaults.head.maxYaw ~= 1, "defaults untouched")
	end)

	t.test("LookNet round-trips and rejects hostile payloads", function()
		local h, root = load()
		local LookNet = h:require(root.LookNet)
		local yaw, pitch = LookNet.decodeLocal(LookNet.encodeLocal(1.234, -0.567))
		expect.near(yaw, 1.234, 1e-4)
		expect.near(pitch, -0.567, 1e-4)
		expect.eq(LookNet.decodeLocal("x"), nil)
		expect.eq(LookNet.decodeLocal(buffer.create(3)), nil)
		local nanYaw = LookNet.decodeLocal(LookNet.encodeLocal(0 / 0, 0))
		expect.near(nanYaw, 0, 1e-9, "NaN sanitized")
		local entries = {}
		for i = 1, LookNet.MAX_ENTRIES do
			entries[i] = { userId = 1e9 + i * 7919, yaw = i / 100, pitch = -i / 200 }
		end
		local packet = LookNet.encodeBatch(entries)
		expect.truthy(buffer.len(packet) <= 900, "fits an unreliable packet")
		local decoded = LookNet.decodeBatch(packet)
		expect.eq(#decoded, LookNet.MAX_ENTRIES)
		expect.eq(decoded[70].userId, entries[70].userId)
		expect.near(decoded[70].yaw, entries[70].yaw, 1e-4)
		local broken = buffer.create(5)
		buffer.writeu8(broken, 0, 3)
		expect.eq(LookNet.decodeBatch(broken), nil)
	end)
end
