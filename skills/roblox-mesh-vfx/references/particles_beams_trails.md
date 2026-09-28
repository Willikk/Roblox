# Particles, Beams & Trails

## ParticleEmitter bursts

- Keep emitters `Enabled = false` and call `:Emit(n)` for bursts; move the holder part **directly**
  (`part.CFrame = …`) before `Emit`, because emission samples the position immediately.
- Particles emit along the emitter's parent **UpVector** (`EmissionDirection = Top`). To spray
  along a direction `d`: `VFXMath.lookAlong(pos, d) * CFrame.Angles(-math.pi / 2, 0, 0)`.
- `Color`, `Size`, `Transparency` sequences are evaluated live for every particle: do **not**
  recolor an emitter while its previous burst is still alive. `Particles.burst` pools one holder
  per burst for that reason.
- Streaks: `Orientation = VelocityParallel` + `Squash` + high `Drag` + short `Lifetime`.
- Flipbooks: `FlipbookLayout` (Grid2x2/4x4/8x8), `FlipbookMode` (Loop/OneShot/PingPong/Random),
  `FlipbookFramerate`; the texture must be a matching grid (e.g. 1024² for 8x8 of 128²).
- `LightEmission = 1` for additive glow (sparks, fire); `LightInfluence = 1` for dust/smoke so it
  matches the scene lighting.
- Built-in textures usable without uploads: `rbxasset://textures/particles/sparkles_main.dds`,
  `rbxasset://textures/particles/smoke_main.dds`, `rbxasset://textures/particles/fire_main.dds`.
- Scale counts by `ctx.quality`; ~20 sparks per hit is plenty.

Override the procedural kinds by adding `ParticleEmitter`s named `Sparks`, `Dust`, `Embers` to
`ReplicatedStorage.Assets.VFX.Particles`.

## Beams

- Cubic Bézier: P0 = Attachment0, P1 = `CurveSize0` along **+X of Attachment0**, P2 = `CurveSize1`
  along **−X of Attachment1**, P3 = Attachment1.
- Circle-fitting handles: `k = 4/3 · tan(θ/4) · r` for an arc of angle θ; accurate for θ ≤ 90°
  (`VFXMath.arcCurveSize`, used by `BeamArc`, verified in tests to < 0.03% radius error).
- `FaceCamera = true` for ribbons readable from any angle (fallback slashes/rings). With it off,
  orientation depends on the attachments: verify the facing in Studio.
- `Segments`: enough for the curve and ≥ (keypoints − 1) for Color/Transparency sequences.
- `TextureSpeed`: texture cycles per second (negative reverses). Cheapest flowing energy.
- `ZOffset` separates overlapping beams (core over body) without z-fighting.
- `Width0/Width1` per beam → split an arc into pieces to build a crescent width profile.

## Trails

Weapon trails: two Attachments on the blade (base, tip), `Trail.Lifetime` 0.1–0.2 s,
`WidthScale` tapering to 0, `LightEmission = 1`, `FaceCamera = true`, enable only during the
active frames of the swing (AnimationTrack markers: `track:GetMarkerReachedSignal("SlashStart")`).
