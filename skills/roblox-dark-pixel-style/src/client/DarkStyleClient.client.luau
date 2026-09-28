--!strict
--[[
	DarkStyleClient (StarterPlayerScripts)
	Boots the dark pixel-art direction:
	  * generates / loads the pixel sprite library (SpriteBank);
	  * registers the Dark* combat effects with the VFX client;
	  * applies the screen preset from workspace attribute DarkStylePreset
	    (Berserk / FearAndHunger / Eclipse), P cycles presets;
	  * makes the camera shake choppy (stepped) to match the limited animation;
	  * turns every part tagged "DarkTorch" into a pixel flame with a flickering light.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = ReplicatedStorage:WaitForChild("DarkStyle")
local ScreenStyle = require(DarkStyle:WaitForChild("ScreenStyle"))
local Settings = require(DarkStyle:WaitForChild("Settings"))
local SpriteBank = require(DarkStyle:WaitForChild("SpriteBank"))
local Sprite3D = require(DarkStyle:WaitForChild("Sprite3D"))
local VFX = ReplicatedStorage:WaitForChild("VFX")
local CameraShaker = require(VFX:WaitForChild("CameraShaker"))
local VFXClient = require(VFX:WaitForChild("Client"))

local Effects = DarkStyle:WaitForChild("Effects")
for _, module in Effects:GetChildren() do
	if module:IsA("ModuleScript") then
		VFXClient.registerEffect(module.Name, (require :: any)(module))
	end
end
VFXClient.start()

SpriteBank.loadAsync()
Sprite3D.preload()
CameraShaker.settings.stepFps = Settings.stepFps

local preset = workspace:GetAttribute("DarkStylePreset")
ScreenStyle.apply(if type(preset) == "string" then preset else "Berserk")

ContextActionService:BindAction("DarkStyleCycle", function(_, state)
	if state == Enum.UserInputState.Begin then
		print("[DarkStyle] preset:", ScreenStyle.cycle())
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.P)

-- Torches: pixel flame billboard + stepped flicker on its light.
local function setupTorch(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local light = part:FindFirstChildWhichIsA("PointLight")
	if light == nil then
		local created = Instance.new("PointLight")
		created.Color = Color3.fromRGB(255, 150, 70)
		created.Range = 22
		created.Brightness = 2.2
		created.Shadows = true
		created.Parent = part
		light = created
	end
	ScreenStyle.flicker(light :: PointLight, (light :: PointLight).Brightness, 0.25)
	local flame = SpriteBank.get("Flame")
	if flame then
		local gui = Instance.new("BillboardGui")
		gui.Name = "PixelFlame"
		gui.Adornee = part
		gui.Size = UDim2.fromScale(flame.frameSize.X * Sprite3D.PIXEL * 1.4, flame.frameSize.Y * Sprite3D.PIXEL * 1.4)
		gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
		gui.LightInfluence = 0
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = gui
		SpriteBank.apply(label, flame, 1)
		gui.Parent = part
		local frame, accumulator = 1, math.random() * 0.1
		game:GetService("RunService").PreRender:Connect(function(dt)
			accumulator += dt
			if accumulator >= 1 / flame.fps then
				accumulator = 0
				frame = frame % flame.frames + 1
				label.ImageRectOffset = Vector2.new((frame - 1) * flame.frameSize.X, 0)
			end
		end)
	end
end

for _, torch in CollectionService:GetTagged("DarkTorch") do
	setupTorch(torch)
end
CollectionService:GetInstanceAddedSignal("DarkTorch"):Connect(setupTorch)
