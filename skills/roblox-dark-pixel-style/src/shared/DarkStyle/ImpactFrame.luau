--!strict
--[[
	ImpactFrame (client)
	Manga / Berserk impact panel: for 3-4 stepped frames (12 fps) the screen becomes
	ink-and-paper: a paper-white flash, radial ink speed lines, an ink burst over a red
	core, and a monochrome contrast punch. Reserve it for heavy moments (guard break,
	critical, parry of a perilous attack) or it stops meaning anything.
	Skipped entirely when GuiService.ReducedMotionEnabled is on.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(script.Parent.Palette)
local SpriteBank = require(script.Parent.SpriteBank)
local ScreenFlash = require(ReplicatedStorage:WaitForChild("VFX"):WaitForChild("ScreenFlash"))

export type Options = {
	lines: boolean?,
	burst: boolean?,
	flash: boolean?,
	frames: number?, -- stepped frames (default 4)
}

local ImpactFrame = {}

local STEP = 1 / 12
local gui: ScreenGui? = nil
local playing = false

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "DarkStyleImpact"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 50
	screen.Enabled = false

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = screen

	local lines = Instance.new("ImageLabel")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromScale(1, 1)
	lines.ZIndex = 2
	lines.Parent = screen

	local burst = Instance.new("ImageLabel")
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(0.5, 0.5)
	burst.SizeConstraint = Enum.SizeConstraint.RelativeYY
	burst.ZIndex = 3
	burst.Parent = screen

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

function ImpactFrame.play(options: Options?)
	if playing or GuiService.ReducedMotionEnabled then
		return
	end
	local screen = ensureGui()
	if screen == nil then
		return
	end
	local o: Options = options or {}
	local flash = screen:FindFirstChild("Flash") :: Frame
	local lines = screen:FindFirstChild("Lines") :: ImageLabel
	local burst = screen:FindFirstChild("Burst") :: ImageLabel
	local linesEntry = SpriteBank.get("SpeedLines")
	local burstEntry = SpriteBank.get("InkBurst")
	local frames = o.frames or 4

	playing = true
	screen.Enabled = true
	ScreenFlash.impact({ duration = STEP * frames, saturation = -1, contrast = 1.6, peak = 0.05 })

	task.spawn(function()
		for step = 1, frames do
			-- Frame 1: paper flash. Frame 2: ink flash. Then lines + burst dissolve.
			local showFlash = o.flash ~= false and step <= 2
			flash.Visible = showFlash
			flash.BackgroundColor3 = Palette.toColor3(if step == 1 then Palette.PAPER else Palette.INK)
			flash.BackgroundTransparency = if step == 1 then 0.15 else 0.55
			lines.Visible = o.lines ~= false and linesEntry ~= nil
			if linesEntry then
				SpriteBank.apply(lines, linesEntry, 1)
			end
			burst.Visible = o.burst ~= false and burstEntry ~= nil and step >= 2
			if burstEntry and step >= 2 then
				SpriteBank.apply(burst, burstEntry, math.min(step - 1, burstEntry.frames))
			end
			task.wait(STEP)
		end
		screen.Enabled = false
		playing = false
	end)
end

return ImpactFrame
