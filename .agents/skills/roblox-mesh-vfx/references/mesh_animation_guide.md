# Mesh VFX Animation Guide in Luau

In top-tier Roblox action games, visual effects are driven by animating 3D `MeshPart` models rather than spawning flat 2D particles.

## 1. The "Squash & Stretch" Rule
Never scale a mesh uniformly (e.g. `Vector3.new(x, x, x)`).
Realistic slashes and shockwaves use aggressive non-uniform scaling:
- **Slash mesh**: Starts very thin along the transversal axis (`0.1`), expands rapidly to full width (`1.0`) in ~0.08 seconds, then stretches out as it dissolves.
- **Shockwave ring**: Starts with a small radius and high vertical thickness (`Vector3.new(1, 4, 1)`), rapidly flattens onto the ground while expanding outwardly (`Vector3.new(18, 0.2, 18)`).

## 2. Easing Styles for Snappy Impact
Always use sharp easing directions:
- **`Enum.EasingStyle.Exponential`** or **`Enum.EasingStyle.Quad`** with **`Enum.EasingDirection.Out`** for expansion.
- The effect must reach 80% of its size in the first 20% of its lifetime.

## 3. Ground Normal Alignment (Raycasting)
When spawning ground shockwaves, dust, or rocks, the effect MUST be aligned to the terrain angle:

```lua
local function getGroundCFrame(position: Vector3): (CFrame?, boolean)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    
    local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -15, 0), raycastParams)
    if result then
        local hitNormal = result.Normal
        local right = Vector3.yAxis:Cross(hitNormal)
        if right.Magnitude == 0 then
            right = Vector3.xAxis
        else
            right = right.Unit
        end
        local up = hitNormal
        local look = right:Cross(up).Unit
        
        local alignedCFrame = CFrame.fromMatrix(result.Position, right, up, -look)
        return alignedCFrame, true
    end
    return nil, false
end
```

## 4. Double-Sided Rendering & Inverted Meshes
- For dome shields or shockwave balls, Blender meshes should have inverted face normals or `MeshPart.DoubleSided = true` enabled in Roblox to ensure the camera can see the inside when standing within the effect radius.
