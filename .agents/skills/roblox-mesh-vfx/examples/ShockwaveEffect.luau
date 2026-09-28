--!strict
--[[
    ShockwaveEffect.luau
    Spawns a ground impact shockwave mesh, dynamically aligned to ground normal.
    Must be called on the client.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type ShockwaveConfig = {
    Position: Vector3,
    MeshName: string,
    InitialSize: Vector3,
    FinalSize: Vector3,
    Duration: number,
    Color: Color3?,
}

local ShockwaveEffect = {}

-- Cast ray downwards to detect ground normal
local function getGroundOrientation(position: Vector3): CFrame
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local rayResult = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
    if rayResult then
        local normal = rayResult.Normal
        local right = Vector3.yAxis:Cross(normal)
        if right.Magnitude == 0 then
            right = Vector3.xAxis
        else
            right = right.Unit
        end
        local up = normal
        local look = right:Cross(up).Unit
        return CFrame.fromMatrix(rayResult.Position + (normal * 0.05), right, up, -look)
    end
    return CFrame.new(position)
end

function ShockwaveEffect.Play(config: ShockwaveConfig)
    local vfxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("VFX") :: Folder
    local meshesFolder = vfxFolder:WaitForChild("Meshes"):WaitForChild("Shockwaves") :: Folder
    local template = meshesFolder:FindFirstChild(config.MeshName) :: MeshPart?

    if not template then
        warn("[ShockwaveEffect] Template mesh not found: " .. config.MeshName)
        return
    end

    local shockwave = template:Clone()
    shockwave.Anchored = true
    shockwave.CanCollide = false
    shockwave.CanTouch = false
    shockwave.CanQuery = false
    shockwave.CastShadow = false
    shockwave.Size = config.InitialSize
    shockwave.CFrame = getGroundOrientation(config.Position)
    shockwave.Transparency = 0

    if config.Color then
        shockwave.Color = config.Color
    end

    shockwave.Parent = workspace:FindFirstChild("VFX") or workspace

    local tweenInfo = TweenInfo.new(
        config.Duration,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )

    local tween = TweenService:Create(shockwave, tweenInfo, {
        Size = config.FinalSize,
        Transparency = 1,
    })

    tween:Play()
    Debris:AddItem(shockwave, config.Duration + 0.1)
end

return ShockwaveEffect
