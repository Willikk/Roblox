--!strict
--[[
	Sprite3D (client)
	Pixel-art sprites in the 3D world, animated "on twos": the flipbook AND the motion
	advance in discrete steps (default 12 fps) like hand-drawn animation, instead of the
	smooth interpolation that screams "default Roblox".

	  Sprite3D.play("BloodBurst", position, { scale = 1.2, rotation = 30 })
	  Sprite3D.play("Droplet", p, { velocity = v, gravity = 60, lifetime = 0.6 })
	  Sprite3D.ground("BloodPool", hitPosition, hitNormal, 4, 8)

	One art pixel = Sprite3D.PIXEL studs everywhere, so every sprite shares the same
	pixel density (the key to a cohesive pixel-art look in 3D).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpriteBank = require(script.Parent.SpriteBank)
local VFX = ReplicatedStorage:WaitForChild("VFX")
local Animator = require(VFX:WaitForChild("Animator"))
local Assets = require(VFX:WaitForChild("Assets"))
local Pool = require(VFX:WaitForChild("Pool"))
local VFXMath = require(VFX:WaitForChild("VFXMath"))

export type PlayOptions = {
	scale: number?, -- multiplies the pixel density size
	rotation: number?, -- degrees, screen-space
	fps: number?, -- flipbook rate (default: sprite fps)
	stepFps: number?, -- motion stepping (default Sprite3D.stepFps, 0 = smooth)
	velocity: Vector3?,
	gravity: number?, -- studs/s^2 downward
	lifetime: number?, -- default: one flipbook cycle
	lightInfluence: number?, -- 0 = emissive (sparks), ~0.6 = lit (blood, smoke)
	brightness: number?,
	tint: Color3?,
	loop: boolean?,
	group: string?, -- Animator time group ("world" freezes with hitstop)
}

type Holder = { part: BasePart, gui: BillboardGui, label: ImageLabel }
type GroundHolder = { part: BasePart, gui: SurfaceGui, label: ImageLabel }

local Sprite3D = {}

Sprite3D.PIXEL = 0.12 -- studs per art pixel
Sprite3D.stepFps = 12

local billboardPool: Pool.Pool<Holder>? = nil
local groundPool: Pool.Pool<GroundHolder>? = nil

local function visualPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	Pool.makeVisual(part)
	part.CFrame = Pool.PARK_CFRAME
	return part
end

local function getBillboardPool(): Pool.Pool<Holder>
	if billboardPool == nil then
		billboardPool = Pool.new(function(): Holder
			local part = visualPart("PixelSprite", Vector3.new(0.1, 0.1, 0.1))
			local gui = Instance.new("BillboardGui")
			gui.Adornee = part
			gui.AlwaysOnTop = false
			gui.ResetOnSpawn = false
			gui.Enabled = false
			local label = Instance.new("ImageLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.Parent = gui
			gui.Parent = part
			part.Parent = Assets.workspaceFolder()
			return { part = part, gui = gui, label = label }
		end, {
			prewarm = 24,
			onRelease = function(h: Holder)
				h.gui.Enabled = false
				h.part.CFrame = Pool.PARK_CFRAME
			end,
		})
	end
	return billboardPool :: Pool.Pool<Holder>
end

local function getGroundPool(): Pool.Pool<GroundHolder>
	if groundPool == nil then
		groundPool = Pool.new(function(): GroundHolder
			local part = visualPart("PixelDecal", Vector3.new(1, 0.05, 1))
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.Adornee = part
			gui.LightInfluence = 1
			gui.Enabled = false
			local label = Instance.new("ImageLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.Parent = gui
			gui.Parent = part
			part.Parent = Assets.workspaceFolder()
			return { part = part, gui = gui, label = label }
		end, {
			prewarm = 6,
			onRelease = function(h: GroundHolder)
				h.gui.Enabled = false
				h.part.CFrame = Pool.PARK_CFRAME
			end,
		})
	end
	return groundPool :: Pool.Pool<GroundHolder>
end

local function quantize(t: number, fps: number): number
	return if fps > 0 then math.floor(t * fps) / fps else t
end

-- Plays a sprite at `position`. Returns false if the sprite is not loaded yet.
function Sprite3D.play(name: string, position: Vector3, options: PlayOptions?): boolean
	local entry = SpriteBank.get(name)
	if entry == nil then
		return false
	end
	local o: PlayOptions = options or {}
	local pool = getBillboardPool()
	local h = pool:acquire()
	local scale = (o.scale or 1) * Sprite3D.PIXEL
	h.gui.Size = UDim2.fromScale(entry.frameSize.X * scale, entry.frameSize.Y * scale)
	h.gui.LightInfluence = o.lightInfluence or 0
	h.gui.Brightness = o.brightness or 1
	h.label.Rotation = o.rotation or 0
	h.label.ImageColor3 = o.tint or Color3.new(1, 1, 1)
	SpriteBank.apply(h.label, entry, 1)
	h.part.CFrame = CFrame.new(position)
	h.gui.Enabled = true

	local fps = o.fps or entry.fps
	local loop = if o.loop == nil then entry.loop else o.loop
	local lifetime = o.lifetime or (entry.frames / fps)
	local stepFps = o.stepFps or Sprite3D.stepFps
	local velocity = o.velocity or Vector3.zero
	local gravity = o.gravity or 0
	local lastFrame, lastStep = 1, -1

	Animator.play(lifetime, function(_t, _dt, elapsed)
		local frame = math.floor(elapsed * fps)
		frame = if loop then frame % entry.frames + 1 else math.min(frame + 1, entry.frames)
		if frame ~= lastFrame then
			lastFrame = frame
			h.label.ImageRectOffset = Vector2.new((frame - 1) * entry.frameSize.X, 0)
		end
		if velocity ~= Vector3.zero or gravity ~= 0 then
			local tq = quantize(elapsed, stepFps)
			if tq ~= lastStep then
				lastStep = tq
				Animator.move(
					h.part,
					CFrame.new(position + velocity * tq + Vector3.new(0, -0.5 * gravity * tq * tq, 0))
				)
			end
		end
	end, {
		group = o.group,
		onComplete = function()
			pool:release(h)
		end,
	})
	return true
end

-- Flat sprite on the ground (blood pools, scorch marks), fading out in hard steps.
function Sprite3D.ground(name: string, position: Vector3, normal: Vector3, sizeStuds: number, lifetime: number): boolean
	local entry = SpriteBank.get(name)
	if entry == nil then
		return false
	end
	local pool = getGroundPool()
	local h = pool:acquire()
	local aspect = entry.frameSize.Y / entry.frameSize.X
	h.part.Size = Vector3.new(sizeStuds, 0.05, sizeStuds * aspect)
	h.part.CFrame = VFXMath.alignToNormal(position + normal * 0.03, normal)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	SpriteBank.apply(h.label, entry, 1)
	h.label.ImageTransparency = 0
	h.gui.Enabled = true
	Animator.play(lifetime, function(t)
		-- Four hard opacity steps in the last 30% (pixel-art fade, no smooth alpha).
		local k = math.clamp((t - 0.7) / 0.3, 0, 1)
		h.label.ImageTransparency = math.floor(k * 4) / 4
	end, {
		group = "debris",
		onComplete = function()
			pool:release(h)
		end,
	})
	return true
end

-- Screen-space rotation (degrees) that aligns a sprite's X axis with `worldDirection`.
function Sprite3D.screenAngle(worldDirection: Vector3): number
	local camera = workspace.CurrentCamera
	if camera == nil then
		return 0
	end
	local d = camera.CFrame:VectorToObjectSpace(worldDirection)
	return -math.deg(math.atan2(d.Y, d.X))
end

function Sprite3D.preload()
	getBillboardPool()
	getGroundPool()
end

return Sprite3D
