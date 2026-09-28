--!strict
--[[
	ScreenFlash
	Post-processing impulses for impacts: color punch, bloom spike, blur pop and the
	anime-style black & white "impact frame".

	* Owns dedicated effects in Lighting ("VFX_ImpactColor", "VFX_ImpactBlur") that are
	  neutral when idle, so the game's own grading is never overwritten.
	* An existing BloomEffect is modulated relative to its captured base value, which fixes
	  the classic drift bug (capturing `Intensity` mid-flash on rapid hits).
	* Overlapping impulses are summed with per-impulse envelopes, then clamped.
	* Honors GuiService.ReducedMotionEnabled: no impact frames, halved intensity.

	Usage (client only):
		ScreenFlash.impact({ duration = 0.12, contrast = 0.25, bloom = 1.5 })
		ScreenFlash.impactFrame(0.06) -- 3-4 frames of high-contrast monochrome
]]

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Ease = require(script.Parent.Ease)

export type ImpactOptions = {
	duration: number?,
	brightness: number?,
	contrast: number?,
	saturation: number?,
	tint: Color3?,
	bloom: number?, -- added to the existing BloomEffect.Intensity
	blur: number?, -- BlurEffect.Size at peak
	peak: number?, -- 0..1 position of the envelope peak (default 0.1)
}

type Impulse = {
	start: number,
	duration: number,
	options: ImpactOptions,
}

local ScreenFlash = {}

local impulses: { Impulse } = {}
local connection: RBXScriptConnection? = nil
local bloomBase: number? = nil
local bloomEffect: BloomEffect? = nil

local function ownedColor(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("VFX_ImpactColor")
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "VFX_ImpactColor"
	cc.Parent = Lighting
	return cc
end

local function ownedBlur(): BlurEffect
	local existing = Lighting:FindFirstChild("VFX_ImpactBlur")
	if existing and existing:IsA("BlurEffect") then
		return existing
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "VFX_ImpactBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
	return blur
end

local function onFrame()
	local now = os.clock()
	local reduce = if GuiService.ReducedMotionEnabled then 0.5 else 1

	local brightness, contrast, saturation, blurSize, bloom = 0, 0, 0, 0, 0
	local tintR, tintG, tintB, tintWeight = 0, 0, 0, 0

	local write = 0
	for _, impulse in impulses do
		local t = (now - impulse.start) / impulse.duration
		if t >= 1 then
			continue
		end
		write += 1
		impulses[write] = impulse
		local o = impulse.options
		local e = Ease.pulse(math.max(t, 1e-3), o.peak or 0.1) * reduce
		brightness += (o.brightness or 0) * e
		contrast += (o.contrast or 0) * e
		saturation += (o.saturation or 0) * e
		blurSize += (o.blur or 0) * e
		bloom += (o.bloom or 0) * e
		if o.tint then
			tintR += o.tint.R * e
			tintG += o.tint.G * e
			tintB += o.tint.B * e
			tintWeight += e
		end
	end
	for i = #impulses, write + 1, -1 do
		impulses[i] = nil
	end

	local cc = ownedColor()
	cc.Brightness = math.clamp(brightness, -1, 1)
	cc.Contrast = math.clamp(contrast, -1, 3)
	cc.Saturation = math.clamp(saturation, -1, 1)
	if tintWeight > 0 then
		local w = math.min(tintWeight, 1)
		local tint = Color3.new(tintR / tintWeight, tintG / tintWeight, tintB / tintWeight)
		cc.TintColor = Color3.new(1, 1, 1):Lerp(tint, w)
	else
		cc.TintColor = Color3.new(1, 1, 1)
	end

	local blur = ownedBlur()
	blur.Size = blurSize
	blur.Enabled = blurSize > 0.05

	local bloomFx = bloomEffect
	if bloomFx and bloomBase then
		bloomFx.Intensity = bloomBase + bloom
	end

	if #impulses == 0 then
		if bloomFx and bloomBase then
			bloomFx.Intensity = bloomBase
		end
		bloomBase = nil
		bloomEffect = nil
		cc.Brightness, cc.Contrast, cc.Saturation = 0, 0, 0
		blur.Enabled = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

function ScreenFlash.impact(options: ImpactOptions)
	local duration = options.duration or 0.12
	if bloomBase == nil and (options.bloom or 0) ~= 0 then
		local bloomFx = Lighting:FindFirstChildWhichIsA("BloomEffect")
		if bloomFx then
			bloomEffect = bloomFx
			bloomBase = bloomFx.Intensity -- captured only while no impulse is running
		end
	end
	table.insert(impulses, { start = os.clock(), duration = duration, options = options })
	if connection == nil then
		connection = RunService.PreRender:Connect(onFrame)
	end
end

-- Manga "impact frame": a few frames of harsh monochrome. Skipped for reduced motion.
function ScreenFlash.impactFrame(duration: number?)
	if GuiService.ReducedMotionEnabled then
		return
	end
	ScreenFlash.impact({
		duration = duration or 0.06,
		saturation = -1,
		contrast = 2.2,
		brightness = 0.08,
		peak = 0.02,
	})
end

return ScreenFlash
