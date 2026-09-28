# Mesh VFX Animation Guide

High-end Roblox combat effects are animated 3D meshes (crescents, rings, domes, spikes),
not flat particles. The code controls size, orientation and opacity from one normalized time.

## 1. One timeline, several phases

Drive everything from `t` (0 → 1 over the lifetime) and carve phases with `Ease.phase(t, a, b)`:

```lua
Animator.play(lifetime, function(t)
    local spawn  = Ease.outExpo(Ease.phase(t, 0.00, 0.14)) -- snap in
    local settle = Ease.outQuart(t)                         -- motion over the whole life
    local vanish = Ease.inQuad(Ease.phase(t, 0.40, 1.00))  -- dissolve
    part.Size = base * Vector3.new(Ease.lerp(0.7, 1.1, settle), Ease.lerp(0.12, 1, spawn) * (1 - 0.7 * vanish), Ease.lerp(0.7, 1.1, settle))
    Fade.apply(snapshot, (1 - vanish) * Ease.outQuad(Ease.phase(t, 0, 0.06)))
end)
```

Why not chained Tweens: phases can overlap, one function owns the look, the effect freezes as a
whole during hitstop (`Animator.setTimeScale("world", 0)`), and `Ease.cubicBezier(x1, y1, x2, y2)`
lets you paste curves from After Effects / cubic-bezier.com.

## 2. Squash & stretch

Never scale uniformly.

- **Slash**: thickness (Y) 0.12 → 1 within the first ~14% (`outExpo`), width/depth 0.72 → 1.12
  over the life, thickness thins to ~0.3 while it dissolves. Spin a little around the plane normal
  (−38° → +22°, `outQuart`) so the arc "travels".
- **Shockwave ring**: radius 0.15R → R with `outExpo` (80% of the size in the first 20% of life),
  thickness 1.6 → 0.12 (tall then flat), fade after 25%.
- **Spikes / rocks**: rise with `Ease.outBack` (overshoot), hold, sink with `inQuad` while shrinking.

## 3. Orientation conventions

Effect frame = CFrame with **UpVector = surface or slash-plane normal** and **LookVector = forward**.

- Ground effects: raycast locally, then `VFXMath.alignToNormal(hit.Position + hit.Normal * 0.05, hit.Normal, forward)`.
  Use `Assets.groundParams()` (ignores characters and other effects, respects CanCollide).
- Diagonal slashes: tilt the frame around its LookVector (`* CFrame.Angles(0, 0, ±28°)`).
- Mirrored slashes: negate the spin (variant bit 0 in `Slash`).
- `VFXMath.lookAlong(position, direction)` = `CFrame.lookAt(position, position + direction)`.

⚠ The widespread snippet
`CFrame.fromMatrix(pos, right, up, -right:Cross(up))` passes a Z column that is the negation of
X × Y: the result is a **mirrored (left-handed) matrix** (see `tests/math.spec.luau`). Use
`alignToNormal`, which builds `fromMatrix(pos, right, up, -forward)` with `right = forward × up`.

## 4. Fading the whole effect

`MeshPart.Transparency` does not fade its Decals, Textures, Beams, Trails, ParticleEmitters,
Lights or Highlights. `Fade.capture(root)` records each authored value once;
`Fade.apply(snapshot, opacity)` multiplies all of them (NumberSequence envelopes included) and
skips no-op frames.

## 5. Materials that read well

- `Neon`: bright core, glows with Bloom. Keep it thin or it becomes a flat blob.
- `ForceField`: animated edge glow for energy domes/discs (used by the Shockwave fallback disc).
- `Glass` with transparency: refractive shells (costly on low-end: gate by `ctx.quality`).
- Textured MeshParts (`TextureID` with alpha gradients) + `Color` tint give painted, anime-style slashes.

## 6. Double-sided & inside views

Domes and rings seen from inside need `MeshPart.DoubleSided = true` (set on the template, not at
runtime) or inverted normals in Blender. Set `CastShadow = false`, `CanCollide/CanTouch/CanQuery = false`
(done by `Pool.makeVisual`).

## 7. Adding secondary motion

Layer 2–3 meshes with small delays (15–70 ms) and different scales/colors: a white thin core over
a colored wide body (Slash), several rings (Shockwave). Offset timing is what sells "AAA".
