--!strict
--[[
    UVScroller.luau
    Manages real-time UV texture panning/scrolling for energy beams, magical blade auras,
    and flowing energy on 3D meshes.
]]

local RunService = game:GetService("RunService")

export type ScrollerInstance = {
    Texture: Texture,
    SpeedU: number,
    SpeedV: number,
    Connection: RBXScriptConnection?,
    Stop: (self: any) -> (),
}

local UVScroller = {}

function UVScroller.Start(texture: Texture, speedU: number, speedV: number): ScrollerInstance
    local instance: ScrollerInstance = {
        Texture = texture,
        SpeedU = speedU,
        SpeedV = speedV,
        Connection = nil,
        Stop = function(self)
            if self.Connection then
                self.Connection:Disconnect()
                self.Connection = nil
            end
        end,
    }

    local offsetU = 0
    local offsetV = 0

    instance.Connection = RunService.RenderStepped:Connect(function(dt: number)
        offsetU = (offsetU + (speedU * dt)) % 100
        offsetV = (offsetV + (speedV * dt)) % 100
        texture.OffsetStudsU = offsetU
        texture.OffsetStudsV = offsetV
    end)

    return instance
end

return UVScroller
