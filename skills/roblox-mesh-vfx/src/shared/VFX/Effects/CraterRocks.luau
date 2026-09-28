--!strict
--[[
	CraterRocks
	Ring of rocks bursting out of the ground (+ optional flying debris), the signature
	"ground slam" read of Deepwoken / JJS style games.

	* Every rock samples the REAL surface under it (raycast): material and color come
	  from the Terrain material or the BasePart that was hit, so a slam on grass, sand or
	  a brick floor produces matching debris.
	* params.seed drives a Random: every client builds the exact same crater.
	* Rocks are pooled Parts (or clones of "Meshes/Spikes/Rock*" MeshParts if present).

	params.cframe : impact point (client re-aligns to the local ground).
	params.scale  : ring radius multiplier (1 = 6 studs) and rock size.
	params.power  : rock count (8 + 4 * power) and debris count.
]]

local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Assets = require(VFX.Assets)
local Ease = require(VFX.Ease)
local Pool = require(VFX.Pool)
local Types = require(VFX.Types)
local VFXMath = require(VFX.VFXMath)

local CraterRocks = {} :: Types.Effect
CraterRocks.maxDistance = 300

local BASE_RADIUS = 6
local RISE_TIME = 0.14
local HOLD_TIME = 3.2
local SINK_TIME = 0.8
local DEBRIS_LIFETIME = 2.4

local rockPool: Pool.Pool<BasePart>? = nil
local debrisPool: Pool.Pool<BasePart>? = nil

local function rockTemplates(): { BasePart }
	local list = {}
	local folder = Assets.find("Meshes/Spikes")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function getRockPool(): Pool.Pool<BasePart>
	local pool = rockPool
	if pool == nil then
		local templates = rockTemplates()
		local counter = 0
		pool = Pool.new(function(): BasePart
			local part: BasePart
			if #templates > 0 then
				counter += 1
				part = templates[(counter - 1) % #templates + 1]:Clone()
			else
				local block = Instance.new("Part")
				block.Shape = Enum.PartType.Block
				block.TopSurface = Enum.SurfaceType.Smooth
				block.BottomSurface = Enum.SurfaceType.Smooth
				part = block
			end
			part.Name = "CraterRock"
			Pool.makeVisual(part)
			part.CFrame = Pool.PARK_CFRAME
			part.Parent = Assets.workspaceFolder()
			return part
		end, {
			prewarm = 12,
			onRelease = function(part: BasePart)
				part.CFrame = Pool.PARK_CFRAME
			end,
		})
		rockPool = pool
	end
	return pool :: Pool.Pool<BasePart>
end

local function getDebrisPool(): Pool.Pool<BasePart>
	local pool = debrisPool
	if pool == nil then
		pool = Pool.new(function(): BasePart
			local part = Instance.new("Part")
			part.Name = "CraterDebris"
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Anchored = true
			part.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.6, 0.2)
			-- Optional group created by VFXServer so debris never push characters.
			local PhysicsService = game:GetService("PhysicsService")
			local ok, registered = pcall(function()
				return PhysicsService:IsCollisionGroupRegistered("VFXDebris")
			end)
			if ok and registered then
				part.CollisionGroup = "VFXDebris"
			end
			part.CFrame = Pool.PARK_CFRAME
			part.Parent = Assets.workspaceFolder()
			return part
		end, {
			onRelease = function(part: BasePart)
				part.Anchored = true
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
				part.Transparency = 0
				part.CFrame = Pool.PARK_CFRAME
			end,
		})
		debrisPool = pool
	end
	return pool :: Pool.Pool<BasePart>
end

local function spawnRock(result: RaycastResult, radial: Vector3, rng: Random, scale: number)
	local pool = getRockPool()
	local rock = pool:acquire()
	local color, material = Assets.surfaceLook(result)
	rock.Color = color
	rock.Material = material
	rock.Transparency = 0

	local s = scale * VFXMath.randomRange(rng, 1.1, 1.9)
	local size = Vector3.new(
		s * VFXMath.randomRange(rng, 0.8, 1.3),
		s * VFXMath.randomRange(rng, 0.8, 1.35),
		s * VFXMath.randomRange(rng, 0.8, 1.3)
	)
	rock.Size = size

	-- Lean outwards (rotation about the tangent = local X), random roll and yaw.
	local tilt = math.rad(VFXMath.randomRange(rng, 22, 48))
	local roll = math.rad(VFXMath.randomRange(rng, -18, 18))
	local yaw = math.rad(VFXMath.randomRange(rng, -25, 25))
	local surface = VFXMath.alignToNormal(result.Position, result.Normal, radial)
	local final = surface * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, roll) * CFrame.new(0, size.Y * 0.18, 0)
	local sunk = final * CFrame.new(0, -size.Y * 1.25, 0)
	rock.CFrame = sunk

	local rise = RISE_TIME * VFXMath.randomRange(rng, 0.8, 1.25)
	local hold = HOLD_TIME + VFXMath.randomRange(rng, 0, 1)
	local total = rise + hold + SINK_TIME

	Animator.play(total, function(_t, _dt, elapsed)
		if elapsed < rise then
			local k = Ease.outBack(elapsed / rise)
			Animator.move(rock, sunk:Lerp(final, k))
		elseif elapsed < rise + hold then
			Animator.move(rock, final)
		else
			local k = Ease.inQuad(math.clamp((elapsed - rise - hold) / SINK_TIME, 0, 1))
			rock.Size = size * Ease.lerp(1, 0.55, k)
			Animator.move(rock, final:Lerp(sunk, k))
		end
	end, {
		onComplete = function()
			pool:release(rock)
		end,
	})
end

local function spawnDebris(
	origin: Vector3,
	up: Vector3,
	color: Color3,
	material: Enum.Material,
	rng: Random,
	scale: number
)
	local pool = getDebrisPool()
	local part = pool:acquire()
	local s = scale * VFXMath.randomRange(rng, 0.35, 0.75)
	part.Size = Vector3.new(s, s * VFXMath.randomRange(rng, 0.7, 1.1), s)
	part.Color = color
	part.Material = material
	part.CFrame = CFrame.new(origin + up * (s + 0.2))
		* CFrame.Angles(rng:NextNumber() * 6.28, rng:NextNumber() * 6.28, rng:NextNumber() * 6.28)
	part.Anchored = false
	local direction = VFXMath.randomInCone(rng, up, math.rad(38))
	part.AssemblyLinearVelocity = direction * VFXMath.randomRange(rng, 38, 62) * math.sqrt(scale)
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
		* 30

	local baseSize = part.Size
	Animator.play(DEBRIS_LIFETIME, function(t)
		local k = Ease.inQuad(Ease.phase(t, 0.7, 1))
		if k > 0 then
			part.Size = baseSize * (1 - 0.8 * k)
			part.Transparency = k
		end
	end, {
		group = "debris", -- physics is not time-scaled, so keep fades on real time too
		onComplete = function()
			pool:release(part)
		end,
	})
end

function CraterRocks.preload()
	getRockPool()
	getDebrisPool()
end

function CraterRocks.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local rng = ctx.rng
	local groundParams = Assets.groundParams()
	local origin = params.cframe.Position
	local centerHit = workspace:Raycast(origin + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), groundParams)
	if centerHit == nil then
		return -- slammed in the air: no crater
	end
	local frame = VFXMath.alignToNormal(centerHit.Position, centerHit.Normal, params.cframe.LookVector)
	local up = frame.UpVector
	local radius = BASE_RADIUS * params.scale
	local quality = math.clamp(ctx.quality, 0.25, 1)
	local count = math.floor((8 + 4 * params.power) * quality + 0.5)

	for _, angle in VFXMath.ringAngles(rng, count, 0.6) do
		local ringRadius = radius * VFXMath.randomRange(rng, 0.85, 1.15)
		local point = frame:PointToWorldSpace(VFXMath.arcPoint(ringRadius, angle))
		local result = workspace:Raycast(point + up * 4, -up * 9, groundParams)
		if result then
			local radial = (result.Position - frame.Position)
			spawnRock(result, if radial.Magnitude > 1e-3 then radial.Unit else frame.LookVector, rng, params.scale)
		end
	end

	local debrisCount = math.floor((3 + 2 * params.power) * quality + 0.5)
	if debrisCount > 0 then
		local color, material = Assets.surfaceLook(centerHit)
		for _ = 1, debrisCount do
			spawnDebris(centerHit.Position, up, color, material, rng, params.scale)
		end
	end
end

return CraterRocks
