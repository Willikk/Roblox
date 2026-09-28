--!strict
--[[
	ImpactBurst
	Weapon hit: sparks + flash sphere + point light + white Highlight flash on the victim,
	plus the "weight" layer: hitstop on attacker/victim and camera feedback for the two
	players involved.

	params.cframe : hit point, LookVector = direction the blow travels.
	params.power  : 0.5 light .. 3 heavy (sparks, flash size, hitstop length, shake).
	params.source : attacker character (optional)  params.target : victim (optional)
	params.variant: bit 0 = critical (impact frame + stronger feedback), bit 1 = blocked
	                (no victim flash, sparks only, short hitstop).
]]

local Players = game:GetService("Players")

local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Assets = require(VFX.Assets)
local CameraShaker = require(VFX.CameraShaker)
local Ease = require(VFX.Ease)
local Fade = require(VFX.Fade)
local Hitstop = require(VFX.Hitstop)
local Particles = require(VFX.Particles)
local Pool = require(VFX.Pool)
local ScreenFlash = require(VFX.ScreenFlash)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local ImpactBurst = {} :: Types.Effect
ImpactBurst.maxDistance = 250

local DEFAULT_COLOR = Color3.fromRGB(255, 225, 170)
local HITSTOP_RADIUS = 90 -- observers farther than this do not freeze animations

local flashPool: Pool.PartPool? = nil
-- Weak keys: destroyed characters are collected, no leak.
local activeHighlights: { [Instance]: Highlight } = setmetatable({}, { __mode = "k" }) :: any
local activeFades: { [Instance]: Animator.Handle } = setmetatable({}, { __mode = "k" }) :: any

local function getFlashPool(): Pool.PartPool
	local pool = flashPool
	if pool == nil then
		local template = Instance.new("Part")
		template.Name = "ImpactFlash"
		template.Shape = Enum.PartType.Ball
		template.Material = Enum.Material.Neon
		template.Size = Vector3.one
		local light = Instance.new("PointLight")
		light.Brightness = 6
		light.Range = 14
		light.Shadows = false
		light.Parent = template
		pool = Pool.fromTemplate(template, Assets.workspaceFolder(), 6)
		flashPool = pool
	end
	return pool :: Pool.PartPool
end

local function flashSphere(position: Vector3, color: Color3, size: number)
	local pool = getFlashPool()
	local part = pool:acquire()
	local snapshot = pool.snapshotOf[part]
	part.Color = color
	local light = part:FindFirstChildWhichIsA("PointLight")
	if light then
		light.Color = color
	end
	part.CFrame = CFrame.new(position)
	Animator.play(0.14, function(t)
		part.Size = Vector3.one * size * Ease.lerp(0.35, 1, Ease.outExpo(t))
		Fade.apply(snapshot, 1 - Ease.inQuad(t))
	end, {
		onComplete = function()
			pool:release(part)
		end,
	})
end

-- White body flash on the victim (one Highlight per character, restarted on re-hit).
local function highlightFlash(target: Instance)
	if not target:IsA("Model") then
		return
	end
	local highlight: Highlight? = activeHighlights[target]
	if highlight == nil or highlight.Parent == nil then
		local created = Instance.new("Highlight")
		created.Name = "VFX_HitFlash"
		created.FillColor = Color3.new(1, 1, 1)
		created.OutlineTransparency = 1
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Adornee = target
		created.Parent = target
		activeHighlights[target] = created
		highlight = created
	end
	local h = highlight :: Highlight
	local previous = activeFades[target]
	if previous then
		previous:cancel() -- a re-hit restarts the flash instead of fighting the old fade
	end
	h.Enabled = true
	h.FillTransparency = 0.15
	activeFades[target] = Animator.play(0.18, function(t)
		h.FillTransparency = Ease.lerp(0.15, 1, Ease.outQuad(t))
	end, {
		group = "ui", -- keep flashing through hitstop
		onComplete = function(cancelled)
			if not cancelled then
				h.Enabled = false
				activeFades[target] = nil
			end
		end,
	})
end

local function isLocalCharacter(inst: Instance?): boolean
	local player = Players.LocalPlayer
	return inst ~= nil and player ~= nil and player.Character == inst
end

function ImpactBurst.preload()
	getFlashPool()
	Particles.prewarm({ "Sparks" }, 4)
end

function ImpactBurst.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local critical = bit32.band(params.variant, 1) == 1
	local blocked = bit32.band(params.variant, 2) == 2
	local power = math.clamp(params.power, 0.25, 5)
	local color = params.color or DEFAULT_COLOR
	local position = params.cframe.Position
	local direction = params.cframe.LookVector

	-- Sparks spray along the blow direction (emitters shoot along UpVector).
	local sprayFrame = VFXMath.lookAlong(position, direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	Particles.burst("Sparks", sprayFrame, (10 + 8 * power) * ctx.quality, {
		color = color,
		speedScale = 0.8 + 0.2 * power,
		spread = if blocked then 70 else 45,
	})
	flashSphere(position, color, 1.6 + 0.9 * power)

	if not blocked and params.target then
		highlightFlash(params.target)
	end

	-- Weight: hitstop for everyone close enough to read it, camera for the two players.
	if ctx.distance < HITSTOP_RADIUS then
		local duration = if blocked then 0.035 else 0.045 + 0.02 * power + (if critical then 0.05 else 0)
		Hitstop.apply({ params.source, params.target }, duration, { freezeVFX = critical })
	end

	local involvedTarget = ctx.isLocalTarget or isLocalCharacter(params.target)
	local involvedSource = ctx.isLocalSource or isLocalCharacter(params.source)
	if involvedTarget then
		CameraShaker.addTrauma(0.22 + 0.1 * power)
		CameraShaker.kick(direction, 0.6 + 0.3 * power)
	elseif involvedSource then
		CameraShaker.addTrauma(0.08 + 0.05 * power)
		CameraShaker.fovPunch(-(1.5 + power))
	end
	if critical and (involvedTarget or involvedSource) then
		ScreenFlash.impactFrame(0.05)
		ScreenFlash.impact({ duration = 0.18, contrast = 0.2, bloom = 1.2, blur = 6 })
	end
end

return ImpactBurst
