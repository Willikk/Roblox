# R6 Joint Math

## Forward kinematics

For every joint (`Motor6D` or `AnimationConstraint`):

```
Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
```

The Animator writes `Transform` every frame (after `PreAnimation`, before `PreSimulation`).
`C0`/`C1` are the static joint frames.

## Default R6 joints

| Joint (parent) | Part0 → Part1 | C0 | C1 |
|---|---|---|---|
| `RootJoint` (HumanoidRootPart) | HRP → Torso | `(0, 0, 0)`, `Angles(-π/2, 0, π)` | same as C0 |
| `Neck` (Torso) | Torso → Head | `(0, 1, 0)`, `Angles(-π/2, 0, π)` | `(0, -0.5, 0)`, `Angles(-π/2, 0, π)` |
| `Right Hip` (Torso) | Torso → Right Leg | `(1, -1, 0)`, `Angles(0, π/2, 0)` | `(0.5, 1, 0)`, `Angles(0, π/2, 0)` |
| `Left Hip` (Torso) | Torso → Left Leg | `(-1, -1, 0)`, `Angles(0, -π/2, 0)` | `(-0.5, 1, 0)`, `Angles(0, -π/2, 0)` |
| `Right Shoulder` (Torso) | Torso → Right Arm | `(1, 0.5, 0)`, `Angles(0, π/2, 0)` | `(-0.5, 0.5, 0)`, `Angles(0, π/2, 0)` |
| `Left Shoulder` (Torso) | Torso → Left Arm | `(-1, 0.5, 0)`, `Angles(0, -π/2, 0)` | `(0.5, 0.5, 0)`, `Angles(0, -π/2, 0)` |

Exact matrices: `R6Math.DEFAULT_C0/C1`. Rest pose (checked in tests): head at (0, 1.5, 0), legs at
(±0.5, −2, 0), arms at (±1.5, 0, 0) relative to the root. Hip joints sit at the *outer* edge
(x = ±1), the leg center line is x = ±0.5, the hip line (torso bottom) is y = −1.

## Axis trap

`Angles(-π/2, 0, π)` maps C0's local axes to Part0 space as:

| C0 local | Part0 space |
|---|---|
| +X | −X |
| +Y | **+Z (backward)** |
| +Z | **+Y (up)** |

So `C0 * CFrame.new(0, -d, 0)` moves the torso **forward/backward**, and
`C0 * CFrame.Angles(pitch, 0, roll)` pitches the wrong way and turns roll into yaw.
Hips/shoulders are only rotated about Y, which is why hip-Y translations "worked" by luck.

## Part0-space offsets (what the library does)

Want: `Part1 = Part0 * W * C0 * T * C1⁻¹` with `W` expressed in Part0 space. Since
`W * C0 = C0 * (C0⁻¹ W C0)`:

```lua
joint.Transform = (C0:Inverse() * W * C0) * animatedTransform    -- R6Math.jointOffset(C0, W)
```

- Translation in Part0 space: `W = CFrame.new(v)`.
- Rotation `R` about a Part0-space pivot `p`: `W = CFrame.new(p) * R * CFrame.new(-p)`
  (`R6Math.rotationAbout`). For a rotation about the joint itself use `p = C0.Position`.
- Several layers compose by left-multiplication (`rig:add` does `offset = W * offset`).

## Pivots used by the layers (torso / root space)

| Motion | Joint | Pivot | Rotation |
|---|---|---|---|
| Forward lean (bend at waist) | RootJoint | hip line `(0, hipLineY, 0)` | `Angles(-lean, 0, 0)` |
| Leg compensation for lean | hips | hip line | `Angles(lean·k, 0, 0)` |
| Bank into a turn | RootJoint | feet `(0, restFootY, 0)` | `Angles(0, 0, bank)` (+ = left) |
| Torso twist (look) | RootJoint | torso center | `Angles(0, yaw, 0)` |
| Leg counter-twist | hips | torso center axis `(0, hipLineY, 0)` | `Angles(0, -yaw, 0)` |
| Head look | Neck | `C0.Position` (top of torso) | `fromEulerAnglesYXZ(pitch, yaw, roll)` |
| Leg raise | hip | hip line | tuck `CFrame.new(0, tuck, 0)` then `Angles(bend, 0, 0)` (+ = foot forward) |

Sign conventions (Roblox, right-handed, −Z forward): `Angles(+θ, 0, 0)` on a -Z facing part looks
**up**; on a hanging limb it swings the end **forward**. `Angles(0, +θ, 0)` turns **left**.
`Angles(0, 0, +θ)` tilts the top towards **−X (left)**.

## Foot planting derivation

Errors per foot `e = groundY − restFootY` (root space; > 0 ground above the resting foot):

```
drop   = clamp(−min(eL, eR, 0), 0, maxDrop)    -- lower the body until the lowest foot lands
raiseX = clamp(eX + drop, 0, maxRaise)          -- then lift each foot that now clips
tuck   = min(raise, maxTuck)                    -- slide the leg into the torso (hidden on R6)
bend   = acos(1 − (raise − tuck) / legLength)   -- a rigid leg rotated by θ lifts its end by L(1 − cos θ)
```

`restFootY = −(LeftLeg.Size.Y + ½·RootPart.Size.Y + HipHeight)` (Humanoid docs, R6 formula).

## Lean physics

- Forward: `lean = speedLean · clamp(v_fwd / v_ref, −1, 1.5) + accelLean · atan(a_fwd / g)`.
- Bank: `bank = bankScale · atan(ω_yaw · v / g)` — the lean of a body in a coordinated turn
  (centripetal acceleration `ω·v`).
- Slope: `+ slopeLean · asin(n_z)` with the ground normal in root space (uphill → lean in).
- All targets go through an under-damped `Spring` (natural overshoot on stops).
