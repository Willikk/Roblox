--!strict
--[[
	Demo server: validated combat requests -> VFXService broadcasts.

	Security model shown here (copy it for real abilities):
	  * the client sends only intent: action name, variant and a random seed;
	  * the server checks types/ranges, per-action cooldowns and character state;
	  * every position is recomputed from the server's view of the character;
	  * hits are detected server-side, then ImpactBurst is sent to everyone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local VFXService = require(ServerScriptService:WaitForChild("VFXServer"):WaitForChild("VFXService"))
local DemoMoves = require(ReplicatedStorage:WaitForChild("VFXDemo"):WaitForChild("DemoMoves"))

VFXService.start()

local request = Instance.new("RemoteEvent")
request.Name = "VFXDemoRequest"
request.Parent = ReplicatedStorage

local lastUse: { [Player]: { [string]: number } } = {}
local comboCount: { [Player]: number } = {}

local function spawnDummy()
	local ok, dummy = pcall(function()
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not ok or dummy == nil then
		warn("[VFXDemo] could not create a training dummy:", dummy)
		return
	end
	local model = dummy :: Model
	model.Name = "TrainingDummy"
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.new(0, 0, 0)
	model:PivotTo(CFrame.new(origin + Vector3.new(0, 4, -16)) * CFrame.Angles(0, math.pi, 0))
	model.Parent = workspace
end

local function characterRoot(player: Player): (Model?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

local function onCooldown(player: Player, action: string): boolean
	local cooldown = DemoMoves.COOLDOWNS[action]
	if cooldown == nil then
		return true
	end
	local uses = lastUse[player]
	if uses == nil then
		uses = {}
		lastUse[player] = uses
	end
	local now = os.clock()
	local usesTable = uses :: { [string]: number }
	if now - (usesTable[action] or -math.huge) < cooldown * 0.9 then -- 10% latency grace
		return true
	end
	usesTable[action] = now
	return false
end

local function findVictim(attacker: Model, root: BasePart): Model?
	local boxCFrame, boxSize = DemoMoves.hitBox(root.CFrame)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	local best: Model? = nil
	local bestDistance = math.huge
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, boxSize, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if model and humanoid and humanoid.Health > 0 then
			local distance = (part.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

request.OnServerEvent:Connect(function(player: Player, action: unknown, variant: unknown, seed: unknown)
	if type(action) ~= "string" or type(variant) ~= "number" or type(seed) ~= "number" then
		return
	end
	if variant ~= variant or seed ~= seed then -- NaN guard
		return
	end
	local safeVariant = math.clamp(math.floor(variant), 0, 3)
	local safeSeed = math.clamp(math.floor(seed), 0, 65535)
	local character, root = characterRoot(player)
	if character == nil or root == nil or onCooldown(player, action) then
		return
	end

	if action == "Slash" then
		VFXService.play("Slash", {
			cframe = DemoMoves.slashFrame(root.CFrame, safeVariant),
			power = 1.2,
			variant = safeVariant,
			seed = safeSeed,
			source = character,
		}, { exclude = player }) -- the attacker already predicted it

		local victim = findVictim(character, root)
		if victim then
			local combo = (comboCount[player] or 0) + 1
			comboCount[player] = combo
			local victimRoot = victim:FindFirstChild("HumanoidRootPart")
			local hitPosition = if victimRoot and victimRoot:IsA("BasePart")
				then victimRoot.Position
				else root.Position + root.CFrame.LookVector * 3
			VFXService.play("ImpactBurst", {
				cframe = CFrame.lookAt(hitPosition, hitPosition + root.CFrame.LookVector),
				power = if combo % 3 == 0 then 2.5 else 1.2,
				variant = if combo % 3 == 0 then 1 else 0, -- every 3rd hit is a critical
				seed = safeSeed,
				source = character,
				target = victim,
			})
		end
	elseif action == "GroundSlam" then
		VFXService.play("GroundSlam", {
			cframe = DemoMoves.groundSlamFrame(root.CFrame),
			power = 2,
			seed = safeSeed,
			source = character,
		}, { exclude = player })
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastUse[player] = nil
	comboCount[player] = nil
end)

spawnDummy()
