# VFX Performance Playbook

## Budgets (rules of thumb per client, mid-range phone — measure on your own target devices)

| Resource | Comfortable | Hard ceiling |
|---|---|---|
| Animated effect parts alive | ~150 | ~400 |
| Particles alive | ~1,500 | ~4,000 |
| Beams / Trails alive | ~60 | ~150 |
| Highlights visible | ≤ 31 (engine limit) | 31 |
| Post-processing effects toggled per frame | 1–2 | — |

## Rules

1. **Pool** every repeated instance (`Pool.new`, `Pool.fromTemplate`). Keep parked parts
   parented far away; re-parenting and `Instance.new`/`Destroy` per hit are the expensive part.
2. **One loop**: all effects share `Animator`'s single `PreRender` connection, which disconnects
   itself when idle. Never create a `RenderStepped` connection per effect.
3. **Batch CFrame writes** with `Animator.move` (one `workspace:BulkMoveTo` per frame,
   `FireCFrameChanged` mode).
4. **Cache lookups**: `Assets.find` caches, pools resolve templates once. No `WaitForChild` in `play`.
5. **Preload** meshes/textures (`Assets.preloadAsync()` at client start) or the first hit hitches
   while the asset downloads.
6. **Cull and scale**: `Effect.maxDistance` + `Client.settings.distanceScale`; multiply particle
   and debris counts by `ctx.quality` (adaptive: drops when FPS < 40, recovers above 55).
7. Visual parts: `CanCollide/CanTouch/CanQuery = false`, `CastShadow = false`, `Anchored = true`
   (`Pool.makeVisual`). Only debris are physical, in collision group `VFXDebris` (no self collision,
   no collision with a `Characters` group if the game defines one).
8. Prefer native animation (Beam `TextureSpeed`, ParticleEmitter flipbooks) over script-driven
   property writes.
9. `Fade.apply` skips no-op frames; NumberSequence rebuilds are not free, keep beam counts low.

## Profiling

- MicroProfiler (Ctrl+F6): look for `PreRender` script time (the Animator), `Render/Particles`.
- `Animator.activeCount()` and `Pool:size()` in a debug overlay to spot leaks (jobs that never end,
  pools that only grow).
- Test at 30 FPS (Studio "Emulation" devices) — spring and Animator math is frame-rate independent,
  your curves should look identical.
