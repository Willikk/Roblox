--!strict
--[[
	Demo arena: three R6 training NPCs driven by the same CombatService API as players.
	  Dummy_Guard   : holds block, faces you  -> practice posture damage / guard breaks
	  Dummy_Parry   : parries your swings on reaction -> learn to feint (M2)
	  Dummy_Fighter : sword chains + perilous criticals -> practice parry (F) and dodge (Q)
	They respawn 3 s after dying. Delete this script in production.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatService = require(ServerScriptService:WaitForChild("CombatServer"):WaitForChild("CombatService"))
local Weapons = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Weapons"))

CombatService.start()

type Mode = "Guard" | "Parry" | "Fighter"

local function nearestPlayer(position: Vector3, range: number): (Model?, BasePart?)
	local best: Model?, bestRoot: BasePart? = nil, nil
	local bestDistance = range
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local d = (root.Position - position).Magnitude
			if d < bestDistance then
				best, bestRoot, bestDistance = character, root, d
			end
		end
	end
	return best, bestRoot
end

local function face(root: BasePart, target: Vector3)
	local flat = Vector3.new(target.X, root.Position.Y, target.Z)
	if (flat - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

local function moveInfo(clip: string): (Weapons.Weapon?, Weapons.Move?)
	for _, name in Weapons.NAMES do
		local weapon = Weapons.get(name)
		if weapon then
			for _, move in weapon.chain do
				if move.name == clip then
					return weapon, move
				end
			end
			if weapon.critical.name == clip then
				return weapon, weapon.critical
			end
		end
	end
	return nil, nil
end

local spawnNpc: (mode: Mode, position: Vector3) -> ()

local function runAi(npc: Model, mode: Mode, humanoid: Humanoid, root: BasePart)
	local decisions = 0
	local watching: { [Model]: RBXScriptConnection } = {}
	while npc.Parent and humanoid.Health > 0 do
		local target, targetRoot = nearestPlayer(root.Position, 40)
		if target and targetRoot then
			local distance = (targetRoot.Position - root.Position).Magnitude
			if mode == "Guard" then
				face(root, targetRoot.Position)
				if npc:GetAttribute("CombatState") == "Idle" then
					CombatService.act(npc, "GuardDown")
				end
			elseif mode == "Parry" then
				face(root, targetRoot.Position)
				local existing: RBXScriptConnection? = watching[target]
				if existing == nil then
					-- React to the player's swings: parry right before the active frames.
					watching[target] = target:GetAttributeChangedSignal("R6_ActionStart"):Connect(function()
						local clip = target:GetAttribute("R6_Action")
						if type(clip) ~= "string" or (root.Position - targetRoot.Position).Magnitude > 12 then
							return
						end
						local weapon, move = moveInfo(clip)
						if weapon and move and not move.perilous then
							local windup = Weapons.timing(weapon, move)
							task.delay(math.max(windup - 0.1, 0), function()
								CombatService.act(npc, "GuardDown")
								task.delay(0.12, function()
									CombatService.act(npc, "GuardUp")
								end)
							end)
						end
					end)
				end
			else -- Fighter
				if distance > 6 then
					humanoid:MoveTo(targetRoot.Position)
				else
					humanoid:MoveTo(root.Position)
					face(root, targetRoot.Position)
					decisions += 1
					if decisions % 7 == 0 then
						CombatService.act(npc, "Critical", workspace:GetServerTimeNow())
					else
						CombatService.act(npc, "M1", workspace:GetServerTimeNow())
					end
				end
			end
		end
		task.wait(if mode == "Fighter" then 0.35 else 0.1)
	end
	for _, connection in watching do
		connection:Disconnect()
	end
end

function spawnNpc(mode: Mode, position: Vector3)
	local ok, created = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or created == nil then
		warn("[CombatArena] cannot create NPC:", created)
		return
	end
	local npc = created :: Model
	npc.Name = `Dummy_{mode}`
	npc:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = 400
	humanoid.Health = 400
	humanoid.DisplayName = mode
	npc.Parent = workspace
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil)
	CollectionService:AddTag(npc, "R6Procedural")
	CollectionService:AddTag(npc, CombatService.NPC_TAG)
	task.wait(0.2) -- let CombatService register it
	if mode == "Fighter" then
		CombatService.act(npc, "Equip", "Sword")
	end
	humanoid.Died:Connect(function()
		task.wait(3)
		npc:Destroy()
		spawnNpc(mode, position)
	end)
	task.spawn(runAi, npc, mode, humanoid, root)
end

spawnNpc("Guard", Vector3.new(-12, 0, -18))
spawnNpc("Parry", Vector3.new(0, 0, -22))
spawnNpc("Fighter", Vector3.new(14, 0, -18))
