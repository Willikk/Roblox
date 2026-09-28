--!strict
--[[
    R6TerrainAdaptation.luau
    Deepwoken-style terrain adaptation and procedural leaning for R6 avatars.
    Must run on the Client (LocalScript inside StarterCharacterScripts).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
local torso = character:WaitForChild("Torso") :: BasePart

local rootJoint = rootPart:WaitForChild("RootJoint") :: Motor6D
local leftHip = torso:WaitForChild("Left Hip") :: Motor6D
local rightHip = torso:WaitForChild("Right Hip") :: Motor6D

-- Cache default C0 transformations
local defaultRootC0 = rootJoint.C0
local defaultLeftHipC0 = leftHip.C0
local defaultRightHipC0 = rightHip.C0

-- Raycast filter setup
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { character }
raycastParams.IgnoreWater = true

local legLength = 2.0
local raycastDistance = 3.5

-- Current lerped values
local currentPelvisDrop = 0
local currentLeftLegOffset = 0
local currentRightLegOffset = 0
local currentPitch = 0
local currentRoll = 0

-- Cast a ray downwards from a position
local function castRay(origin: Vector3): (number, Vector3)
    local result = workspace:Raycast(origin, Vector3.new(0, -raycastDistance, 0), raycastParams)
    if result then
        local distance = (origin.Y - result.Position.Y)
        return distance, result.Normal
    end
    return raycastDistance, Vector3.yAxis
end

local function updateProceduralMotion(dt: number)
    if humanoid.Health <= 0 then return end

    local rootCF = rootPart.CFrame
    local rootPos = rootCF.Position

    -- 1. Compute leg ground heights via Raycasting
    local leftHipOrigin = (rootCF * CFrame.new(-1, 0, 0)).Position
    local rightHipOrigin = (rootCF * CFrame.new(1, 0, 0)).Position

    local leftDist, leftNormal = castRay(leftHipOrigin)
    local rightDist, rightNormal = castRay(rightHipOrigin)

    -- Calculate difference relative to default standing leg length
    local targetLeftOffset = math.clamp(legLength - leftDist, -1.5, 1.5)
    local targetRightOffset = math.clamp(legLength - rightDist, -1.5, 1.5)

    -- Pelvis drop: drop the root if at least one leg needs to reach down or step high
    local targetPelvisDrop = math.min(targetLeftOffset, targetRightOffset)
    if targetPelvisDrop > 0 then
        targetPelvisDrop = targetPelvisDrop * 0.5
    end

    -- Smooth lerping
    local lerpSpeed = 15 * dt
    currentPelvisDrop = currentPelvisDrop + (targetPelvisDrop - currentPelvisDrop) * lerpSpeed
    currentLeftLegOffset = currentLeftLegOffset + (targetLeftOffset - currentLeftLegOffset) * lerpSpeed
    currentRightLegOffset = currentRightLegOffset + (targetRightOffset - currentRightLegOffset) * lerpSpeed

    -- 2. Compute Body Leaning (Velocity & Slope)
    local velocity = rootPart.AssemblyLinearVelocity
    local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
    local speed = flatVel.Magnitude

    local targetPitch = 0
    local targetRoll = 0

    if speed > 1 then
        local moveDir = rootCF:VectorToObjectSpace(flatVel.Unit)
        -- Pitch: Lean forward when running forward, backward when running backward
        targetPitch = math.rad(-moveDir.Z * math.clamp(speed * 1.2, 0, 14))
        -- Roll: Bank into turns
        targetRoll = math.rad(-moveDir.X * math.clamp(speed * 0.8, 0, 10))
    end

    currentPitch = currentPitch + (targetPitch - currentPitch) * (10 * dt)
    currentRoll = currentRoll + (targetRoll - currentRoll) * (10 * dt)

    -- 3. Apply offsets to Motor6D joints
    -- Torso & Pelvis
    rootJoint.C0 = defaultRootC0 
        * CFrame.new(0, -currentPelvisDrop, 0)
        * CFrame.Angles(currentPitch, 0, currentRoll)

    -- Left Leg
    leftHip.C0 = defaultLeftHipC0 
        * CFrame.new(0, currentLeftLegOffset, 0)

    -- Right Leg
    rightHip.C0 = defaultRightHipC0 
        * CFrame.new(0, currentRightLegOffset, 0)
end

-- Connect to Stepped (after animations evaluate, before physics render)
RunService.Stepped:Connect(function(_, dt: number)
    updateProceduralMotion(dt)
end)
