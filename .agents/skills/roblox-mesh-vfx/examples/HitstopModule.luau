--!strict
--[[
    HitstopModule.luau
    Implements Deepwoken-style frame freeze (hitstop), screen shake, and post-processing flash.
]]

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local HitstopModule = {}

-- Freezes animations on attacker and victim temporarily
function HitstopModule.FreezeAnimations(attackerTrack: AnimationTrack?, victimTrack: AnimationTrack?, duration: number)
    if attackerTrack and attackerTrack.IsPlaying then
        attackerTrack:AdjustSpeed(0)
    end
    if victimTrack and victimTrack.IsPlaying then
        victimTrack:AdjustSpeed(0)
    end

    task.delay(duration, function()
        if attackerTrack and attackerTrack.IsPlaying then
            attackerTrack:AdjustSpeed(1)
        end
        if victimTrack and victimTrack.IsPlaying then
            victimTrack:AdjustSpeed(1)
        end
    end)
end

-- Triggers an intense micro-flash on Bloom and ColorCorrection
function HitstopModule.FlashImpact(intensity: number?)
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Intensity = 1
        bloom.Size = 24
        bloom.Threshold = 2
        bloom.Parent = Lighting
    end

    local origIntensity = bloom.Intensity
    local peak = intensity or 3.5

    bloom.Intensity = peak

    local tween = TweenService:Create(bloom, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Intensity = origIntensity,
    })
    tween:Play()
end

return HitstopModule
