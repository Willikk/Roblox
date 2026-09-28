--!strict
--[[
	Demo: a ruined gothic arena for the dark pixel style + Deepwoken combat.
	Sets the art-direction switches (workspace attributes) and builds stone, pillars,
	torches and debris. Delete in production and set the attributes yourself:
	  DarkStylePreset = "Berserk" | "FearAndHunger" | "Eclipse"
	  CombatVFXTheme  = "Dark"
	  R6_StepFps      = 12   (limited animation "on twos")
]]

local CollectionService = game:GetService("CollectionService")

workspace:SetAttribute("DarkStylePreset", "Berserk")
workspace:SetAttribute("CombatVFXTheme", "Dark")
workspace:SetAttribute("R6_StepFps", 12)

local folder = Instance.new("Folder")
folder.Name = "DarkArena"
folder.Parent = workspace

local rng = Random.new(666)

local function stone(name: string, size: Vector3, cframe: CFrame, shade: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Material = Enum.Material.Slate
	local s = shade or rng:NextNumber(0.75, 1)
	part.Color = Color3.fromRGB(math.floor(62 * s), math.floor(58 * s), math.floor(54 * s))
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

-- Cracked flagstone floor.
for x = -5, 5 do
	for z = -5, 5 do
		local tile = stone(
			"Flag",
			Vector3.new(7.8, 1, 7.8),
			CFrame.new(x * 8, -0.5 + rng:NextNumber(-0.12, 0.12), z * 8)
				* CFrame.Angles(0, 0, rng:NextNumber(-0.02, 0.02))
		)
		tile.Material = Enum.Material.Cobblestone
	end
end

-- Ring of broken pillars with torches.
for i = 0, 9 do
	local angle = i / 10 * math.pi * 2
	local position = Vector3.new(math.cos(angle) * 36, 0, math.sin(angle) * 36)
	local height = if i % 3 == 0 then rng:NextNumber(4, 7) else rng:NextNumber(12, 18)
	stone(
		"Pillar",
		Vector3.new(3.5, height, 3.5),
		CFrame.new(position + Vector3.new(0, height / 2, 0))
			* CFrame.Angles(0, rng:NextNumber(0, 1), rng:NextNumber(-0.05, 0.05))
	)
	if i % 2 == 0 then
		local torch =
			stone("Torch", Vector3.new(0.5, 2.4, 0.5), CFrame.new(position * 0.9 + Vector3.new(0, 4.5, 0)), 0.5)
		torch.Material = Enum.Material.Wood
		torch.Color = Color3.fromRGB(45, 32, 24)
		CollectionService:AddTag(torch, "DarkTorch")
	end
	-- Rubble.
	for _ = 1, 3 do
		local size = Vector3.new(rng:NextNumber(1, 3), rng:NextNumber(0.6, 1.6), rng:NextNumber(1, 3))
		stone(
			"Rubble",
			size,
			CFrame.new(
				position * rng:NextNumber(0.75, 1.05)
					+ Vector3.new(rng:NextNumber(-3, 3), size.Y / 2, rng:NextNumber(-3, 3))
			) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4))
		)
	end
end
