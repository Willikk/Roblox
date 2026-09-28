--!strict
--[[
	Demo client: Q = slash (alternating diagonals), E = ground slam.
	Effects are predicted locally (zero input lag) and the server broadcasts them to the
	other players with `exclude = attacker`. Both sides share the random seed, so the
	crater rocks are identical on every screen.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFX = ReplicatedStorage:WaitForChild("VFX")
local VFXClient = require(VFX:WaitForChild("Client"))
local DemoMoves = require(ReplicatedStorage:WaitForChild("VFXDemo"):WaitForChild("DemoMoves"))

local request = ReplicatedStorage:WaitForChild("VFXDemoRequest") :: RemoteEvent
local player = Players.LocalPlayer

VFXClient.start()

local slashVariant = 0
local lastUse: { [string]: number } = {}

local function ready(action: string): boolean
	local now = os.clock()
	if now - (lastUse[action] or -math.huge) < DemoMoves.COOLDOWNS[action] then
		return false
	end
	lastUse[action] = now
	return true
end

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function onSlash(_name: string, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin or not ready("Slash") then
		return Enum.ContextActionResult.Pass
	end
	local hrp = root()
	if hrp == nil then
		return Enum.ContextActionResult.Pass
	end
	slashVariant = 1 - slashVariant
	local seed = math.random(0, 65535)
	VFXClient.play("Slash", {
		cframe = DemoMoves.slashFrame(hrp.CFrame, slashVariant),
		power = 1.2,
		variant = slashVariant,
		seed = seed,
		source = player.Character,
	})
	request:FireServer("Slash", slashVariant, seed)
	return Enum.ContextActionResult.Sink
end

local function onGroundSlam(_name: string, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin or not ready("GroundSlam") then
		return Enum.ContextActionResult.Pass
	end
	local hrp = root()
	if hrp == nil then
		return Enum.ContextActionResult.Pass
	end
	local seed = math.random(0, 65535)
	VFXClient.play("GroundSlam", {
		cframe = DemoMoves.groundSlamFrame(hrp.CFrame),
		power = 2,
		seed = seed,
		source = player.Character,
	})
	request:FireServer("GroundSlam", 0, seed)
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("VFXDemoSlash", onSlash, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
ContextActionService:BindAction("VFXDemoGroundSlam", onGroundSlam, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("VFXDemoSlash", "Slash")
ContextActionService:SetTitle("VFXDemoGroundSlam", "Slam")

-- On-screen help.
local gui = Instance.new("ScreenGui")
gui.Name = "VFXDemoHelp"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 1, -24)
label.Size = UDim2.fromOffset(460, 36)
label.BackgroundTransparency = 0.4
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.Text = "Q: Slash (hit the dummy, every 3rd hit crits)   E: Ground slam"
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")
