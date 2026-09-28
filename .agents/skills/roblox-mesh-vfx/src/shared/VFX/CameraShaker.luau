--!strict
--[[
	CameraShaker
	Trauma-based Perlin shake + directional kick springs + FOV punch.

	Model ("Juicing your cameras", Squirrel Eiserloh, GDC 2016):
	  trauma in [0, 1] is added by hits and decays linearly; shake = trauma^2, so small hits
	  barely move the camera while stacked heavy hits escalate. Offsets come from smooth
	  math.noise (not random jitter), which reads as "impact" instead of "glitch".

	Integration with the default (or any) camera script, without drift:
	  * Camera.Value - 1 : remove last frame's offset if nothing else moved the camera;
	  * Camera.Value + 1 : apply this frame's offset on top of the camera script's result.
	  The camera scripts therefore never see (nor accumulate) our offset.

	Respects GuiService.ReducedMotionEnabled (accessibility) by scaling everything down.

	Usage (client only):
		CameraShaker.addTrauma(0.4)
		CameraShaker.kick(hitDirection, 1)   -- world direction the blow travels
		CameraShaker.fovPunch(-6)            -- degrees, springs back
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Spring = require(script.Parent.Spring)

local CameraShaker = {}

CameraShaker.settings = {
	maxAngles = Vector3.new(math.rad(2.2), math.rad(2.2), math.rad(3.5)), -- pitch, yaw, roll
	maxOffset = Vector3.new(0.25, 0.25, 0.1), -- studs, camera space
	frequency = 16, -- noise samples per second (higher = more violent)
	traumaDecay = 1.3, -- trauma removed per second
	exponent = 2,
	kickScale = math.rad(4), -- radians of rotation for kick strength 1
	intensity = 1, -- global user setting (0 disables)
	reducedMotionScale = 0.25,
}

local BIND_UNDO = "VFX_CameraShakeUndo"
local BIND_APPLY = "VFX_CameraShakeApply"

local trauma = 0
local elapsed = 0
local rotationKick = Spring.new(Vector3.zero, 6.5, 0.42)
local fovSpring = Spring.new(Vector3.zero, 4.5, 0.55)

local bound = false
local lastBase: CFrame? = nil
local lastApplied: CFrame? = nil
local lastFovBase: number? = nil
local lastFovApplied: number? = nil

local function scale(): number
	local s = CameraShaker.settings.intensity
	if GuiService.ReducedMotionEnabled then
		s *= CameraShaker.settings.reducedMotionScale
	end
	return s
end

local function nearlyEqual(a: CFrame, b: CFrame): boolean
	return a.Position:FuzzyEq(b.Position, 1e-4)
		and a.LookVector:FuzzyEq(b.LookVector, 1e-5)
		and a.UpVector:FuzzyEq(b.UpVector, 1e-5)
end

local function isSettled(): boolean
	return trauma <= 0
		and rotationKick.position.Magnitude < 1e-4
		and rotationKick.velocity.Magnitude < 1e-3
		and math.abs(fovSpring.position.X) < 1e-3
		and math.abs(fovSpring.velocity.X) < 1e-2
end

local function undo()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if lastApplied and lastBase and nearlyEqual(camera.CFrame, lastApplied) then
		camera.CFrame = lastBase
	end
	if lastFovApplied and lastFovBase and math.abs(camera.FieldOfView - lastFovApplied) < 1e-3 then
		camera.FieldOfView = lastFovBase
	end
	lastApplied, lastBase, lastFovApplied, lastFovBase = nil, nil, nil, nil
end

local unbind: () -> ()

local function apply(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local cfg = CameraShaker.settings
	elapsed += dt
	trauma = math.max(trauma - cfg.traumaDecay * dt, 0)

	local s = scale()
	local shake = (trauma ^ cfg.exponent) * s
	local t = elapsed * cfg.frequency

	local pitch = cfg.maxAngles.X * shake * math.noise(t, 11.3, 0.5) * 2
	local yaw = cfg.maxAngles.Y * shake * math.noise(t, 27.1, 0.5) * 2
	local roll = cfg.maxAngles.Z * shake * math.noise(t, 43.7, 0.5) * 2
	local offset = Vector3.new(
		cfg.maxOffset.X * shake * math.noise(t, 59.9, 0.5) * 2,
		cfg.maxOffset.Y * shake * math.noise(t, 71.3, 0.5) * 2,
		cfg.maxOffset.Z * shake * math.noise(t, 83.1, 0.5) * 2
	)

	local kick = rotationKick:update(dt) * s
	local fovDelta = fovSpring:update(dt).X * s

	local base = camera.CFrame
	local shaken = base * CFrame.new(offset) * CFrame.fromEulerAnglesYXZ(pitch + kick.X, yaw + kick.Y, roll + kick.Z)
	camera.CFrame = shaken
	lastBase, lastApplied = base, shaken

	if math.abs(fovDelta) > 1e-3 then
		local fovBase = camera.FieldOfView
		camera.FieldOfView = math.clamp(fovBase + fovDelta, 1, 120)
		lastFovBase, lastFovApplied = fovBase, camera.FieldOfView
	end

	if isSettled() then
		unbind()
	end
end

local undoBound = false

local function bind()
	if not undoBound then
		-- The undo step stays bound for the session: it is a no-op when idle.
		undoBound = true
		RunService:BindToRenderStep(BIND_UNDO, Enum.RenderPriority.Camera.Value - 1, undo)
	end
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(BIND_APPLY, Enum.RenderPriority.Camera.Value + 1, apply)
end

function unbind()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep(BIND_APPLY)
end

-- amount: 0.1 light jab, 0.3 heavy hit, 0.6 explosion, 1 = max.
function CameraShaker.addTrauma(amount: number)
	if amount <= 0 or CameraShaker.settings.intensity <= 0 then
		return
	end
	trauma = math.clamp(trauma + amount, 0, 1)
	bind()
end

-- Trauma with linear distance falloff (for shockwaves felt by bystanders).
function CameraShaker.addTraumaAt(amount: number, origin: Vector3, radius: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local d = (camera.CFrame.Position - origin).Magnitude
	local falloff = 1 - math.clamp(d / radius, 0, 1)
	CameraShaker.addTrauma(amount * falloff * falloff)
end

-- Directional punch: the view jerks along `worldDirection` (direction the blow travels).
function CameraShaker.kick(worldDirection: Vector3, strength: number)
	local camera = workspace.CurrentCamera
	if camera == nil or worldDirection.Magnitude < 1e-4 or CameraShaker.settings.intensity <= 0 then
		return
	end
	local d = camera.CFrame:VectorToObjectSpace(worldDirection.Unit)
	local k = CameraShaker.settings.kickScale * strength * 12 -- velocity impulse (rad/s)
	rotationKick:impulse(Vector3.new(d.Y * k, -d.X * k, -d.X * k * 0.6))
	bind()
end

-- Negative = zoom in punch (feels like a heavy impact), positive = zoom out (dash).
function CameraShaker.fovPunch(degrees: number)
	if CameraShaker.settings.intensity <= 0 then
		return
	end
	fovSpring.position += Vector3.new(degrees, 0, 0)
	bind()
end

function CameraShaker.stop()
	trauma = 0
	rotationKick:reset(Vector3.zero)
	fovSpring:reset(Vector3.zero)
	unbind()
end

function CameraShaker.getTrauma(): number
	return trauma
end

return CameraShaker
