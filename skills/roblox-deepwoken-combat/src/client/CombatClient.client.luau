--!strict
--[[
	CombatClient (StarterPlayerScripts)
	Controls (Deepwoken layout):
	  M1 = attack chain      M2 = feint (during windup)     R = critical
	  F  = tap: parry / hold: block                          Q = dodge (uses move direction)
	  1  = fists             2 = sword

	Prediction: the local player's pose, slash VFX and dodge movement start instantly; the
	server stays authoritative (hits, stuns, posture). Every client also enables sword
	trails from the replicated R6_Action attribute, synchronized on server time.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Clips = require(Combat:WaitForChild("Clips"))
local Config = require(Combat:WaitForChild("Config"))
local Rules = require(Combat:WaitForChild("Rules"))
local Weapons = require(Combat:WaitForChild("Weapons"))
local R6Procedural = ReplicatedStorage:WaitForChild("R6Procedural")
local ActionPose = require(R6Procedural:WaitForChild("Layers"):WaitForChild("ActionPose"))
local Controller = require(R6Procedural:WaitForChild("Controller"))
local VFXClient = require(ReplicatedStorage:WaitForChild("VFX"):WaitForChild("Client"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local input = remotes:WaitForChild("Input") :: RemoteEvent
local knockbackRemote = remotes:WaitForChild("Knockback") :: RemoteEvent

Clips.registerAll()
Controller.start()
VFXClient.start()

-- Local mirror of the server fighter, for instant feedback only.
local fighter = Rules.newFighter()
local serverNow = function(): number
	return workspace:GetServerTimeNow()
end

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return model, root, humanoid
	end
	return nil, nil, nil
end

local function currentWeapon(model: Model): Weapons.Weapon
	local name = model:GetAttribute("Weapon")
	return (type(name) == "string" and Weapons.get(name)) or Weapons.Fists
end

------------------------------------------------------------------------------------
-- Sword trails for every character (driven by the replicated action)
------------------------------------------------------------------------------------

local moveByName: { [string]: { weapon: Weapons.Weapon, move: Weapons.Move } } = {}
for _, name in Weapons.NAMES do
	local weapon = Weapons.get(name)
	if weapon then
		for _, move in weapon.chain do
			moveByName[move.name] = { weapon = weapon, move = move }
		end
		moveByName[weapon.critical.name] = { weapon = weapon, move = weapon.critical }
	end
end

local function pulseTrail(model: Model, clipName: string, startedAgo: number)
	local info = moveByName[clipName]
	local blade = model:FindFirstChild("CombatBlade")
	local trail = blade and blade:FindFirstChild("SwingTrail")
	if info == nil or trail == nil or not trail:IsA("Trail") then
		return
	end
	local windup, active = Weapons.timing(info.weapon, info.move)
	local onAt = math.max(windup - 0.05 - startedAgo, 0)
	local offAt = math.max(windup + active + 0.07 - startedAgo, 0)
	trail.Color =
		ColorSequence.new(if info.move.perilous then Color3.fromRGB(255, 80, 70) else Color3.fromRGB(215, 235, 255))
	task.delay(onAt, function()
		trail.Enabled = true
	end)
	task.delay(offAt, function()
		trail.Enabled = false
	end)
end

local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function watchCharacter(model: Model)
	if watched[model] then
		return
	end
	watched[model] = true
	model:GetAttributeChangedSignal("R6_ActionStart"):Connect(function()
		if model == player.Character then
			return -- already pulsed by prediction
		end
		local clip = model:GetAttribute("R6_Action")
		local start = model:GetAttribute("R6_ActionStart")
		if type(clip) == "string" and type(start) == "number" then
			pulseTrail(model, clip, serverNow() - start)
		end
	end)
end

local function watchPlayer(p: Player)
	if p.Character then
		watchCharacter(p.Character)
	end
	p.CharacterAdded:Connect(watchCharacter)
end
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)
workspace.DescendantAdded:Connect(function(inst)
	if inst.Name == "CombatBlade" and inst.Parent and inst.Parent:IsA("Model") then
		watchCharacter(inst.Parent :: Model)
	end
end)

------------------------------------------------------------------------------------
-- Actions (predicted locally, confirmed by the server)
------------------------------------------------------------------------------------

local guardHeld = false

local function syncFromServer(model: Model)
	local state = model:GetAttribute("CombatState")
	if state == "Stunned" or state == "GuardBroken" then
		fighter.state = state
		fighter.stateUntil = serverNow() + 0.2
	end
end

local function attack(critical: boolean)
	local model, root = character()
	if model == nil or root == nil then
		return
	end
	syncFromServer(model)
	local t = serverNow()
	if not Rules.canStart(fighter, if critical then "Critical" else "M1", t, Config) then
		return
	end
	local weapon = currentWeapon(model)
	local move: Weapons.Move
	if critical then
		move = weapon.critical
		fighter.combo = 0
	else
		local index = Rules.nextCombo(fighter, t, #weapon.chain, Config)
		move = weapon.chain[index]
		fighter.combo = index
	end
	local windup, active, recovery = Weapons.timing(weapon, move)
	fighter.state = "Attacking"
	fighter.phase = "windup"
	fighter.stateUntil = t + windup + active + recovery
	fighter.recoveryStart = t + windup + active
	task.delay(windup + active, function()
		fighter.phase = "recovery"
	end)
	task.delay(windup + active + recovery, function()
		if fighter.state == "Attacking" and serverNow() >= fighter.stateUntil - 0.01 then
			fighter.state = "Idle"
			fighter.lastAttackEnd = serverNow()
			if move.finisher then
				fighter.combo = 0
			end
		end
	end)

	ActionPose.playLocal(model, move.name)
	pulseTrail(model, move.name, 0)
	if move.vfx == "Slash" then
		task.delay(windup, function()
			if fighter.state ~= "Attacking" then
				return -- feinted / interrupted
			end
			local _, r = character()
			if r then
				VFXClient.play(Config.effect("Slash", "Slash"), {
					cframe = r.CFrame * CFrame.new(0, 0.6, -2.4) * CFrame.Angles(0, 0, math.rad(move.slashTilt or 0)),
					power = if critical then 2.2 else 1.2,
					variant = if move.slashMirror then 1 else 0,
					color = if move.perilous then Color3.fromRGB(255, 70, 60) else nil,
					source = model,
				})
			end
		end)
	end
	input:FireServer(if critical then "Critical" else "M1", t)
end

local function feint()
	local model = character()
	if model == nil or not Rules.canStart(fighter, "Feint", serverNow(), Config) then
		return
	end
	fighter.state = "Idle"
	fighter.feintReadyAt = serverNow() + Config.feintCooldown
	ActionPose.stopLocal(model)
	input:FireServer("Feint")
end

local function guard(down: boolean)
	local model = character()
	if model == nil then
		return
	end
	guardHeld = down
	if down then
		local weapon = currentWeapon(model)
		ActionPose.playLocal(model, Clips.parryName(weapon))
		input:FireServer("GuardDown")
	else
		input:FireServer("GuardUp")
	end
end

local function dodge()
	local model, root, humanoid = character()
	if model == nil or root == nil or humanoid == nil then
		return
	end
	local t = serverNow()
	if not Rules.canStart(fighter, "Dodge", t, Config) then
		return
	end
	fighter.dodgeReadyAt = t + Config.dodgeCooldown
	fighter.state = "Dodging"
	fighter.stateUntil = t + Config.dodgeDuration
	local move = humanoid.MoveDirection
	local direction = if move.Magnitude > 0.1 then move.Unit else -root.CFrame.LookVector
	local localDir = root.CFrame:VectorToObjectSpace(direction)
	local clip = if math.abs(localDir.X) > math.abs(localDir.Z)
		then (if localDir.X < 0 then "DodgeLeft" else "DodgeRight")
		else "DodgeBack"
	ActionPose.playLocal(model, clip)

	-- Owner-side movement (the server only grants i-frames).
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(1, 0, 1) * 1e5
	velocity.VectorVelocity = direction * Config.dodgeSpeed
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root
	task.delay(Config.dodgeDuration * 0.75, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
	input:FireServer("Dodge", direction)
end

knockbackRemote.OnClientEvent:Connect(function(velocity: unknown)
	local _, root = character()
	if root and typeof(velocity) == "Vector3" then
		root.AssemblyLinearVelocity = velocity
	end
end)

------------------------------------------------------------------------------------
-- Bindings
------------------------------------------------------------------------------------

local function bind(name: string, fn: (Enum.UserInputState) -> (), ...: Enum.KeyCode | Enum.UserInputType)
	ContextActionService:BindAction(name, function(_, state)
		fn(state)
		return Enum.ContextActionResult.Pass
	end, false, ...)
end

bind("CombatM1", function(state)
	if state == Enum.UserInputState.Begin then
		attack(false)
	end
end, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
bind("CombatFeint", function(state)
	if state == Enum.UserInputState.Begin then
		feint()
	end
end, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
bind("CombatCritical", function(state)
	if state == Enum.UserInputState.Begin then
		attack(true)
	end
end, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
bind("CombatGuard", function(state)
	if state == Enum.UserInputState.Begin then
		guard(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if guardHeld then
			guard(false)
		end
	end
end, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
bind("CombatDodge", function(state)
	if state == Enum.UserInputState.Begin then
		dodge()
	end
end, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
bind("CombatFists", function(state)
	if state == Enum.UserInputState.Begin then
		input:FireServer("Equip", "Fists")
	end
end, Enum.KeyCode.One)
bind("CombatSword", function(state)
	if state == Enum.UserInputState.Begin then
		input:FireServer("Equip", "Sword")
	end
end, Enum.KeyCode.Two)
bind("CombatGreatsword", function(state)
	if state == Enum.UserInputState.Begin then
		input:FireServer("Equip", "Greatsword")
	end
end, Enum.KeyCode.Three)

------------------------------------------------------------------------------------
-- HUD: posture bar (fills with blocked damage; full = guard break)
------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 1)
frame.Position = UDim2.new(0.5, 0, 1, -70)
frame.Size = UDim2.fromOffset(260, 8)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Parent = gui
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(235, 200, 90)
fill.BorderSizePixel = 0
fill.Parent = frame
local help = Instance.new("TextLabel")
help.AnchorPoint = Vector2.new(0.5, 1)
help.Position = UDim2.new(0.5, 0, 1, -84)
help.Size = UDim2.fromOffset(520, 20)
help.BackgroundTransparency = 1
help.TextColor3 = Color3.new(1, 1, 1)
help.TextStrokeTransparency = 0.5
help.Font = Enum.Font.GothamMedium
help.TextSize = 14
help.Text = "M1 attack · M2 feint · R critical · F parry/hold block · Q dodge · 1 fists · 2 sword · 3 greatsword"
help.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

RunService.RenderStepped:Connect(function()
	local model = player.Character
	if model == nil then
		return
	end
	local posture = model:GetAttribute("Posture")
	local max = model:GetAttribute("PostureMax")
	if type(posture) == "number" and type(max) == "number" and max > 0 then
		local k = math.clamp(posture / max, 0, 1)
		fill.Size = UDim2.fromScale(k, 1)
		fill.BackgroundColor3 = Color3.fromRGB(235, 200, 90):Lerp(Color3.fromRGB(230, 60, 50), k)
	end
	-- Local mirror follows server-imposed states.
	local state = model:GetAttribute("CombatState")
	if (state == "Idle") and fighter.state ~= "Idle" and serverNow() >= fighter.stateUntil then
		fighter.state = "Idle"
	end
end)

player.CharacterAdded:Connect(function()
	fighter = Rules.newFighter()
end)
