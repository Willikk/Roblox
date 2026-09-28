# R6 Motor6D Transformation Math Guide

In an R6 avatar, the skeleton is composed of 6 parts connected by 5 main `Motor6D` instances:

## Default R6 Joint Hierarchy & Coordinate Offsets

| Joint Name | Parent Part | Part0 | Part1 | Default C0 |
| :--- | :--- | :--- | :--- | :--- |
| **RootJoint** | `HumanoidRootPart` | `HumanoidRootPart` | `Torso` | `CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi/2, 0, math.pi)` |
| **Neck** | `Torso` | `Torso` | `Head` | `CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi/2, 0, math.pi)` |
| **Left Hip** | `Torso` | `Torso` | `Left Leg` | `CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi/2, 0)` |
| **Right Hip** | `Torso` | `Torso` | `Right Leg` | `CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi/2, 0)` |
| **Left Shoulder** | `Torso` | `Torso` | `Left Arm` | `CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi/2, 0)` |
| **Right Shoulder** | `Torso` | `Torso` | `Right Arm` | `CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi/2, 0)` |

## Procedural Offset Rule
When applying procedural offsets on R6:
1. Store the **original** `C0` at initialization (`defaultC0`).
2. Never overwrite `motor.C0 = newCFrame` directly without preserving the joint's original rotation/translation basis.
3. Always multiply relative transforms:
   ```lua
   -- Example: Tilting the torso forward
   rootJoint.C0 = defaultRootC0 * CFrame.Angles(math.rad(tiltAngle), 0, 0)
   ```
4. Always apply modifications in **`RunService.Stepped`** (or `RunService.PreRender` on modern Roblox engines) so that the Roblox animation engine calculates keyframe tracks first, and your procedural code offsets them without being overwritten.
