--!strict
--[[
    SlashEffect.luau
    Spawns and animates a 3D crescent slash mesh along a sword swing trajectory.
    Must be called on the client.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type SlashConfig = {
    SlashMeshName: string,
    OriginCFrame: CFrame,
    InitialSize: Vector3,
    TargetSize: Vector3,
    Color: Color3?,
    Duration: number,
    RotationOffsetAngle: number?,
}

local SlashEffect = {}

function SlashEffect.Play(config: SlashConfig)
    -- 1. Fetch template mesh from ReplicatedStorage
    local vfxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("VFX") :: Folder
    local meshesFolder = vfxFolder:WaitForChild("Meshes"):WaitForChild("Slashes") :: Folder
    local template = meshesFolder:FindFirstChild(config.SlashMeshName) :: MeshPart?
    
    if not template then
        warn("[SlashEffect] Mesh not found: " .. config.SlashMeshName)
        return
    end

    -- 2. Clone and configure instance
    local slash = template:Clone()
    slash.Anchored = true
    slash.CanCollide = false
    slash.CanTouch = false
    slash.CanQuery = false
    slash.CastShadow = false
    slash.Transparency = 0
    slash.Size = config.InitialSize
    slash.CFrame = config.OriginCFrame

    if config.Color then
        slash.Color = config.Color
    end

    -- Parent to client VFX container
    slash.Parent = workspace:FindFirstChild("VFX") or workspace

    -- 3. Prepare Tween for squash & stretch and dissipation
    local rotAngle = config.RotationOffsetAngle or 45
    local targetCFrame = config.OriginCFrame * CFrame.Angles(0, math.rad(rotAngle), 0)

    local tweenInfo = TweenInfo.new(
        config.Duration,
        Enum.EasingStyle.Exponential,
        Enum.EasingDirection.Out
    )

    local tween = TweenService:Create(slash, tweenInfo, {
        Size = config.TargetSize,
        CFrame = targetCFrame,
        Transparency = 1,
    })

    tween:Play()

    -- 4. Cleanup safely
    Debris:AddItem(slash, config.Duration + 0.1)
end

return SlashEffect
