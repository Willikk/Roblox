--!strict
--[[
	ScreenStyle (client)
	Whole-screen art direction: lighting, grading, atmosphere and pixel overlays.

	Presets
	  Berserk       : ink-and-paper monochrome, brutal contrast, cold dusk.
	  FearAndHunger : rotting sepia, near-black ambient, thick fog, heavy grain.
	  Eclipse       : blood-red sky and haze, the nightmare set piece.
	ScreenStyle.apply("Berserk"); ScreenStyle.clear() restores the original lighting.

	Overlays (ScreenGui, pixelated): stepped film grain (random tile offset at 12 fps),
	dithered vignette, optional Bayer screen-door. Lighting.Technology is not scriptable:
	set it in Studio/Rojo (Voxel = chunky retro light, Future = hard torch shadows).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpriteBank = require(script.Parent.SpriteBank)
local Animator = require(ReplicatedStorage:WaitForChild("VFX"):WaitForChild("Animator"))

export type Preset = {
	lighting: { [string]: any },
	color: { brightness: number, contrast: number, saturation: number, tint: Color3 },
	bloom: { intensity: number, size: number, threshold: number },
	atmosphere: { density: number, offset: number, color: Color3, decay: Color3, glare: number, haze: number },
	grain: number, -- overlay opacity 0..1
	vignette: number,
	dither: number,
	pixelScale: number, -- screen pixels per art pixel for tiled overlays
}

local ScreenStyle = {}

ScreenStyle.presets = {
	Berserk = {
		lighting = {
			Ambient = Color3.fromRGB(22, 22, 26),
			OutdoorAmbient = Color3.fromRGB(40, 40, 46),
			Brightness = 1.1,
			ClockTime = 18.3,
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
			GlobalShadows = true,
			ShadowSoftness = 0,
			ExposureCompensation = -0.15,
			FogColor = Color3.fromRGB(20, 20, 22),
			FogStart = 30,
			FogEnd = 260,
		},
		color = { brightness = 0, contrast = 0.6, saturation = -0.72, tint = Color3.fromRGB(236, 232, 238) },
		bloom = { intensity = 0.35, size = 16, threshold = 1.2 },
		atmosphere = {
			density = 0.33,
			offset = 0.05,
			color = Color3.fromRGB(88, 86, 92),
			decay = Color3.fromRGB(40, 34, 34),
			glare = 0,
			haze = 1.6,
		},
		grain = 0.45,
		vignette = 0.85,
		dither = 0.06,
		pixelScale = 3,
	},
	FearAndHunger = {
		lighting = {
			Ambient = Color3.fromRGB(16, 14, 12),
			OutdoorAmbient = Color3.fromRGB(22, 19, 16),
			Brightness = 0.35,
			ClockTime = 0.6,
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
			GlobalShadows = true,
			ShadowSoftness = 0,
			ExposureCompensation = -0.3,
			FogColor = Color3.fromRGB(14, 12, 10),
			FogStart = 8,
			FogEnd = 120,
		},
		color = { brightness = -0.02, contrast = 0.35, saturation = -0.5, tint = Color3.fromRGB(232, 222, 190) },
		bloom = { intensity = 0.6, size = 20, threshold = 0.9 },
		atmosphere = {
			density = 0.45,
			offset = 0.1,
			color = Color3.fromRGB(58, 50, 42),
			decay = Color3.fromRGB(30, 25, 20),
			glare = 0,
			haze = 2.6,
		},
		grain = 0.6,
		vignette = 1,
		dither = 0.08,
		pixelScale = 3,
	},
	Eclipse = {
		lighting = {
			Ambient = Color3.fromRGB(40, 10, 10),
			OutdoorAmbient = Color3.fromRGB(70, 18, 14),
			Brightness = 1,
			ClockTime = 12,
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
			GlobalShadows = true,
			ShadowSoftness = 0,
			ExposureCompensation = -0.2,
			FogColor = Color3.fromRGB(40, 6, 6),
			FogStart = 20,
			FogEnd = 220,
		},
		color = { brightness = -0.03, contrast = 0.5, saturation = -0.25, tint = Color3.fromRGB(255, 205, 195) },
		bloom = { intensity = 0.8, size = 24, threshold = 0.8 },
		atmosphere = {
			density = 0.42,
			offset = 0.2,
			color = Color3.fromRGB(125, 32, 26),
			decay = Color3.fromRGB(60, 8, 8),
			glare = 0.4,
			haze = 3,
		},
		grain = 0.5,
		vignette = 0.9,
		dither = 0.05,
		pixelScale = 3,
	},
} :: { [string]: Preset }

local original: { [string]: any }? = nil
local originalAtmosphere: { [string]: any }? = nil
local gui: ScreenGui? = nil
local grainHandle: Animator.Handle? = nil
local current: string? = nil

local LIGHTING_KEYS = {
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"ClockTime",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GlobalShadows",
	"ShadowSoftness",
	"ExposureCompensation",
	"FogColor",
	"FogStart",
	"FogEnd",
}

local function owned<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = Lighting
	return created :: any
end

local function atmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		return existing
	end
	local created = Instance.new("Atmosphere")
	created.Parent = Lighting
	return created
end

local function overlayLabel(parent: Instance, name: string, zIndex: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ZIndex = zIndex
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = parent
	return label
end

local function buildOverlays(preset: Preset)
	SpriteBank.loadAsync()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	if gui then
		gui:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "DarkStyleOverlay"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	gui = screen

	local vignette = SpriteBank.get("Vignette")
	if vignette and preset.vignette > 0 then
		local label = overlayLabel(screen, "Vignette", 1)
		SpriteBank.apply(label, vignette, 1)
		label.ImageTransparency = 1 - preset.vignette
	end

	local dither = SpriteBank.get("DitherTile")
	if dither and preset.dither > 0 then
		local label = overlayLabel(screen, "Dither", 2)
		SpriteBank.apply(label, dither, 1)
		label.ScaleType = Enum.ScaleType.Tile
		label.TileSize = UDim2.fromOffset(4 * preset.pixelScale, 4 * preset.pixelScale)
		label.ImageTransparency = 1 - preset.dither
	end

	local grain = SpriteBank.get("Grain")
	if grain and preset.grain > 0 then
		local tile = 64 * preset.pixelScale
		local label = overlayLabel(screen, "Grain", 3)
		SpriteBank.apply(label, grain, 1)
		label.ScaleType = Enum.ScaleType.Tile
		label.TileSize = UDim2.fromOffset(tile, tile)
		label.Size = UDim2.new(1, tile, 1, tile)
		label.ImageTransparency = 1 - preset.grain
		local rng = Random.new()
		local accumulator = 0
		if grainHandle then
			grainHandle:cancel()
		end
		grainHandle = Animator.bind(function(dt)
			accumulator += dt
			if accumulator >= 1 / 12 then -- stepped: grain "boils" at 12 fps
				accumulator = 0
				label.Position = UDim2.fromOffset(-rng:NextInteger(0, tile), -rng:NextInteger(0, tile))
			end
		end, { group = "ui" })
	end

	screen.Parent = player:WaitForChild("PlayerGui")
end

function ScreenStyle.apply(name: string)
	local preset = ScreenStyle.presets[name]
	if preset == nil then
		warn(`[DarkStyle] unknown preset {name}`)
		return
	end
	if original == nil then
		local saved = {}
		for _, key in LIGHTING_KEYS do
			saved[key] = (Lighting :: any)[key]
		end
		original = saved
		local a = atmosphere()
		originalAtmosphere = {
			Density = a.Density,
			Offset = a.Offset,
			Color = a.Color,
			Decay = a.Decay,
			Glare = a.Glare,
			Haze = a.Haze,
		}
	end
	for key, value in preset.lighting do
		(Lighting :: any)[key] = value
	end
	local cc = owned("ColorCorrectionEffect", "DarkStyle_Grade") :: ColorCorrectionEffect
	cc.Brightness = preset.color.brightness
	cc.Contrast = preset.color.contrast
	cc.Saturation = preset.color.saturation
	cc.TintColor = preset.color.tint
	local bloom = owned("BloomEffect", "DarkStyle_Bloom") :: BloomEffect
	bloom.Intensity = preset.bloom.intensity
	bloom.Size = preset.bloom.size
	bloom.Threshold = preset.bloom.threshold
	local a = atmosphere()
	a.Density = preset.atmosphere.density
	a.Offset = preset.atmosphere.offset
	a.Color = preset.atmosphere.color
	a.Decay = preset.atmosphere.decay
	a.Glare = preset.atmosphere.glare
	a.Haze = preset.atmosphere.haze
	current = name
	task.spawn(buildOverlays, preset)
end

function ScreenStyle.clear()
	if original then
		for key, value in original do
			(Lighting :: any)[key] = value
		end
	end
	if originalAtmosphere then
		local a = atmosphere()
		for key, value in originalAtmosphere do
			(a :: any)[key] = value
		end
	end
	for _, name in { "DarkStyle_Grade", "DarkStyle_Bloom" } do
		local effect = Lighting:FindFirstChild(name)
		if effect then
			effect:Destroy()
		end
	end
	if grainHandle then
		grainHandle:cancel()
		grainHandle = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	current = nil
end

function ScreenStyle.current(): string?
	return current
end

-- Cycles through presets (debug / settings menu).
function ScreenStyle.cycle(): string
	local order = { "Berserk", "FearAndHunger", "Eclipse" }
	local index = table.find(order, current or "") or 0
	local nextName = order[index % #order + 1]
	ScreenStyle.apply(nextName)
	return nextName
end

--[[
	Torch flicker: brightness/range jump between values at 10 fps (stepped, like a
	low-framerate game), never a smooth sine.
]]
function ScreenStyle.flicker(light: Light, baseBrightness: number, amount: number): Animator.Handle
	local rng = Random.new()
	local accumulator = 0
	return Animator.bind(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			light.Brightness = baseBrightness * (1 + (rng:NextNumber() - 0.5) * 2 * amount)
		end
	end, { group = "ui" })
end

return ScreenStyle
