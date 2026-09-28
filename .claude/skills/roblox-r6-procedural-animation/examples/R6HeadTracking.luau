--!strict
--[[
    R6HeadTracking.luau
    Smooth procedural head and neck tracking for R6 avatars.
    Must run on the Client (LocalScript inside StarterCharacterScripts).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera

local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
local torso = character:WaitForChild("Torso") :: BasePart
local neck = torso:WaitForChild("Neck") :: Motor6D

local defaultNeckC0 = neck.C0

local currentYaw = 0
local currentPitch = 0

local maxAngle = math.rad(60)

RunService.RenderStepped:Connect(function(dt: number)
    if humanoid.Health <= 0 then return end

    local camLook = camera.CFrame.LookVector
    local rootCF = rootPart.CFrame
    local localLook = rootCF:VectorToObjectSpace(camLook)

    -- Calculate yaw (horizontal) and pitch (vertical)
    local targetYaw = math.clamp(-math.atan2(localLook.X, -localLook.Z), -maxAngle, maxAngle)
    local targetPitch = math.clamp(math.asin(localLook.Y), -math.rad(40), math.rad(40))

    -- Smooth lerp
    local lerpFactor = 12 * dt
    currentYaw = currentYaw + (targetYaw - currentYaw) * lerpFactor
    currentPitch = currentPitch + (targetPitch - currentPitch) * lerpFactor

    -- Apply to R6 Neck Motor6D
    neck.C0 = defaultNeckC0 * CFrame.Angles(currentPitch, 0, currentYaw)
end)
