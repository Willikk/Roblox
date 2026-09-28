# UV Scrolling (Texture Panning) Guide

UV scrolling creates flowing energy, fire blades, running water, and electric aura effects by translating the texture coordinates of a 3D mesh over time.

## 1. How It Works in Roblox
Roblox `Texture` objects placed inside a `MeshPart` have `OffsetStudsU` and `OffsetStudsV` properties.
By updating these offsets on `RunService.RenderStepped` on the client, textures appear to rush across the surface of the blade or beam.

## 2. Best Practices
1. **Always run on Client**: Never update texture offsets from the server.
2. **Delta Time Multiplication**: Always multiply speed by `deltaTime` to ensure constant speed regardless of the player's framerate (60 FPS, 144 FPS, 240 FPS).
3. **Modulo Wrapping**: To prevent floating-point precision loss when an effect stays active for a long time, wrap offsets with `math.fmod(offset, textureStudsLength)`.
4. **Cleanup Connection**: Always disconnect the `RenderStepped` listener when the effect is destroyed to avoid memory leaks.

## 3. Example Usage Pattern
```lua
local connection: RBXScriptConnection?
local currentOffset = 0
local scrollSpeed = 15 -- studs per second

connection = RunService.RenderStepped:Connect(function(dt: number)
    currentOffset = currentOffset + (scrollSpeed * dt)
    texture.OffsetStudsV = currentOffset
end)

-- On effect finish:
if connection then
    connection:Disconnect()
    connection = nil
end
```
