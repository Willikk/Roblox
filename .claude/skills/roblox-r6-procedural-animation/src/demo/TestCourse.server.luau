--!strict
--[[
	Demo: builds a test course next to the spawn (stairs, ramp, rocks) and two patrolling
	R6 NPCs tagged "R6Procedural" that look at the nearest player. Delete this script in
	a real game. Set Game Settings > Avatar > R6 to test on your own character too.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local R6_WALK = "rbxassetid://180426354" -- default R6 walk
local R6_IDLE = "rbxassetid://180435571" -- default R6 idle

local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
local origin = if spawnLocation then spawnLocation.Position else Vector3.zero

local function groundHeight(x: number, z: number): number
	local result = workspace:Raycast(Vector3.new(x, origin.Y + 100, z), Vector3.new(0, -500, 0))
	return if result then result.Position.Y else origin.Y
end

local courseFolder = Instance.new("Folder")
courseFolder.Name = "R6TestCourse"
courseFolder.Parent = workspace

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = courseFolder
	return part
end

local baseX, baseZ = origin.X + 24, origin.Z
local floorY = groundHeight(baseX, baseZ)

-- Stairs: 8 steps of 1 stud (the classic case where one R6 foot floats).
for i = 0, 7 do
	block(
		`Step{i + 1}`,
		Vector3.new(12, (i + 1) * 1, 2.5),
		CFrame.new(baseX, floorY + (i + 1) * 0.5, baseZ - 6 - i * 2.5),
		Color3.fromRGB(165, 160, 150)
	)
end
local topY = floorY + 8
block(
	"Landing",
	Vector3.new(12, 8, 10),
	CFrame.new(baseX, floorY + 4, baseZ - 6 - 8 * 2.5 - 3.75),
	Color3.fromRGB(150, 145, 135)
)

-- Ramp (25 deg) back down to the floor.
local rampLength = 8 / math.sin(math.rad(25))
local rampRun = 8 / math.tan(math.rad(25))
block(
	"Ramp",
	Vector3.new(12, 1, rampLength),
	CFrame.new(baseX + 12, floorY + 4 - 0.5, baseZ - 6 - 8 * 2.5 - 3.75 + 5 + rampRun / 2)
		* CFrame.Angles(math.rad(25), 0, 0),
	Color3.fromRGB(120, 150, 110),
	Enum.Material.Grass
)
block(
	"RampTop",
	Vector3.new(12, 8, 10),
	CFrame.new(baseX + 12, floorY + 4, baseZ - 6 - 8 * 2.5 - 3.75),
	Color3.fromRGB(150, 145, 135)
)

-- Scattered rocks.
local rng = Random.new(1234)
for i = 1, 14 do
	local size = Vector3.new(rng:NextNumber(1.5, 3.5), rng:NextNumber(0.4, 1.4), rng:NextNumber(1.5, 3.5))
	block(
		`Rock{i}`,
		size,
		CFrame.new(baseX - 16 + rng:NextNumber(-7, 7), floorY + size.Y / 2 - 0.1, baseZ - 12 + rng:NextNumber(-10, 10))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)),
		Color3.fromRGB(105, 100, 95),
		Enum.Material.Slate
	)
end
local _ = topY

-- NPCs --------------------------------------------------------------------------------

local function loadTrack(humanoid: Humanoid, id: string, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = looped
		return track
	end
	return nil
end

local function nearestHead(position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = 60
	for _, player in Players:GetPlayers() do
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local d = (head.Position - position).Magnitude
			if d < bestDistance then
				best, bestDistance = head.Position, d
			end
		end
	end
	return best
end

local function spawnNpc(name: string, waypoints: { Vector3 }, walkSpeed: number)
	local ok, created = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or created == nil then
		warn("[R6Demo] cannot create NPC:", created)
		return
	end
	local npc = created :: Model
	npc.Name = name
	npc:PivotTo(CFrame.new(waypoints[1] + Vector3.new(0, 3, 0)))
	npc.Parent = workspace
	CollectionService:AddTag(npc, "R6Procedural")

	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.WalkSpeed = walkSpeed
	root:SetNetworkOwner(nil)

	local walk = loadTrack(humanoid, R6_WALK, true)
	local idle = loadTrack(humanoid, R6_IDLE, true)
	if idle then
		idle:Play()
	end
	humanoid.Running:Connect(function(speed)
		if walk then
			if speed > 0.5 and not walk.IsPlaying then
				walk:Play(0.2)
			elseif speed <= 0.5 and walk.IsPlaying then
				walk:Stop(0.2)
			end
			if walk.IsPlaying then
				walk:AdjustSpeed(speed / 16)
			end
		end
	end)

	task.spawn(function()
		local index = 1
		while npc.Parent and humanoid.Health > 0 do
			index = index % #waypoints + 1
			humanoid:MoveTo(waypoints[index])
			humanoid.MoveToFinished:Wait()
			task.wait(1.5)
		end
	end)
	task.spawn(function()
		while npc.Parent do
			npc:SetAttribute("R6_LookAt", nearestHead(root.Position))
			task.wait(0.2)
		end
	end)
end

local stairsBottom = Vector3.new(baseX, floorY, baseZ - 2)
local stairsTop = Vector3.new(baseX, topY, baseZ - 6 - 8 * 2.5 - 3.75)
local rampTop = Vector3.new(baseX + 12, topY, baseZ - 6 - 8 * 2.5 - 3.75)
local rampBottom = Vector3.new(baseX + 12, floorY, baseZ - 6 - 8 * 2.5 - 3.75 + 5 + rampRun + 3)
local rocks = Vector3.new(baseX - 16, floorY, baseZ - 12)

spawnNpc("StairWalker", { stairsBottom, stairsTop, rampTop, rampBottom }, 10)
spawnNpc("RockWalker", { rocks + Vector3.new(0, 0, 9), rocks + Vector3.new(0, 0, -9) }, 7)
