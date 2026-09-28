# Tuning & Debugging

## Most useful knobs (`Config.luau`)

| Want | Change |
|---|---|
| More dramatic sprint lean | `lean.speedLean` (5° → 8°), `lean.accelLean` |
| Stronger banking | `lean.bankScale`, `lean.maxBank` |
| Snappier / softer body motion | `lean.frequency` (Hz), `lean.damping` (< 1 = overshoot) |
| Legs follow torso lean | `lean.legCompensation` → 0 (whole body tilts like a plank) |
| Foot planting also while walking | raise `terrain.plantFadeStart/End` |
| Bigger stair steps | `terrain.maxPelvisDrop` (keep < 2), `terrain.maxFootRaise` |
| Head turns more / less | `head.maxYaw`, `head.torsoShare` |
| Aim weapons with the camera pitch | `head.armPitchShare` 0.3–0.7 |
| Heavier landings | `landing.impulseScale`, `landing.maxDip`, lower `landing.minImpactSpeed` |
| Cheaper on crowded servers | `lod.*Distance`, `lod.offscreenInterval` |

## Symptom → cause

| Symptom | Cause / fix |
|---|---|
| Torso slides backward instead of dropping | offset applied in C0's frame; use `R6Math.jointOffset` |
| Pose keeps drifting/rotating over time | offset re-multiplied onto its own previous output; use `Rig` (overwrite detection) |
| Nothing moves | R15 rig, joints renamed, `R6_Disabled`, or the character is beyond `lod.lowRateDistance` |
| Works for me, others see a stiff character | C0 edits do not replicate; run the Controller on every client (StarterPlayerScripts) |
| Head never turns for other players | `LookRelay` not started (server `Main.server.luau`) |
| Foot floats on stairs | ray origin blocked by the character's own parts (filter), or `CanCollide = false` stairs with `RespectCanCollide` |
| Jitter at low FPS | naive lerp; use `Spring` / `R6Math.expAlpha` |
| Legs pop when an attack animation starts | set `R6_Terrain`/`R6_Lean` to 0 for the attack via attributes, they fade through the springs |

## Visual debugging

Temporarily draw the foot rays and ground hits:

```lua
local function debugRay(origin: Vector3, direction: Vector3, hit: RaycastResult?)
    local part = Instance.new("Part")
    part.Anchored, part.CanCollide, part.CanQuery = true, false, false
    part.Size = Vector3.new(0.05, 0.05, direction.Magnitude)
    part.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -direction.Magnitude / 2)
    part.Color = if hit then Color3.new(0, 1, 0) else Color3.new(1, 0, 0)
    part.Parent = workspace
    game:GetService("Debris"):AddItem(part, 0.1)
end
```

`Controller.stats()` returns (tracked, active) rigs for an on-screen counter.
