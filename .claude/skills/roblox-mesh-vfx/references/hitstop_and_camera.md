# Hitstop, Camera Shake & Post-Processing Impact

The "weight" of a hit is half visuals, half feedback: a few frozen frames, a camera reaction
and a very short post-processing punch.

## 1. Hitstop (`Hitstop.luau`)

```lua
Hitstop.apply({ attackerCharacter, victimCharacter }, 0.07)                   -- freeze
Hitstop.apply({ attacker, victim }, 0.12, { speed = 0.05, freezeVFX = true }) -- heavy slow-mo + frozen slashes
```

| Hit | Duration |
|---|---|
| Light M1 | 0.04–0.06 s |
| Heavy / critical | 0.08–0.12 s |
| Parry / perfect block | 0.12–0.16 s |
| Blocked | ~0.035 s |

Implementation details that matter:

- Freezes **every** playing track (`Animator:GetPlayingAnimationTracks()`): idle, walk and attack
  layers would otherwise keep moving.
- Stores each track's **original** `Speed` and restores it (a 1.3× attack stays 1.3×).
- Overlapping hitstops **extend** the release time instead of un-freezing early.
- Restores in `RunService.PreAnimation` — the documented place to change track speed before the
  Animator steps.
- `freezeVFX` sets `Animator` group `"world"` time scale to the hitstop speed: slashes freeze
  mid-swing and resume. UI flashes use group `"ui"`, debris physics are never frozen.
- Apply it on every client within ~90 studs so observers see the same freeze (`ImpactBurst` does).

## 2. Camera shake (`CameraShaker.luau`)

Trauma model (Squirrel Eiserloh, GDC 2016 "Juicing Your Cameras With Math"):

- `addTrauma(x)` adds to `trauma ∈ [0, 1]`, which decays linearly (`traumaDecay` per second).
- Shake amount = `trauma²`: small hits barely move the camera, stacked hits escalate.
- Offsets come from `math.noise` (smooth Perlin), never `math.random` jitter.
- `kick(worldDirection, strength)`: directional punch on an under-damped spring (the view jerks
  along the blow, then settles). `fovPunch(-4)`: zoom-in punch that springs back.
- `addTraumaAt(amount, origin, radius)`: squared distance falloff for explosions/slams.

No drift, no fighting the camera script: the offset is removed at `RenderPriority.Camera - 1`
(only if nothing else moved the camera) and re-applied at `Camera + 1`.

Typical values: jab 0.08–0.12, heavy hit 0.25–0.35, ground slam 0.4–0.6 (with falloff), ultimate 0.8.

## 3. Post-processing punch (`ScreenFlash.luau`)

```lua
ScreenFlash.impact({ duration = 0.18, contrast = 0.2, bloom = 1.2, blur = 6 })
ScreenFlash.impactFrame(0.05) -- manga-style monochrome frames on critical hits
```

- Uses its own neutral `ColorCorrectionEffect` / `BlurEffect` in Lighting: never overwrites the
  game's grading.
- Bloom is modulated **relative to a base captured once** (legacy code captured `Intensity`
  mid-flash on rapid hits and drifted brighter forever).
- Overlapping impulses sum with individual envelopes, then clamp.

## 4. Accessibility

`GuiService.ReducedMotionEnabled` is honored: camera shake scaled to 25%, flashes halved, impact
frames skipped. Also expose `CameraShaker.settings.intensity` in your settings menu.

## 5. Who gets what

| Feedback | Attacker | Victim | Bystanders |
|---|---|---|---|
| Sparks / flash / highlight | ✓ | ✓ | ✓ (culled by distance) |
| Hitstop (animation freeze) | ✓ | ✓ | ✓ within ~90 studs |
| Camera trauma | small + FOV punch | strong + directional kick | only for slams/explosions (falloff) |
| Impact frame | critical only | critical only | ✗ |
