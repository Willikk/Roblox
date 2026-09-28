---
name: roblox-mesh-vfx
description: >-
  Production Roblox Luau combat VFX library and playbook (Deepwoken / Jujutsu Shenanigans /
  Type Soul style): mesh and beam weapon slashes, ground shockwaves, crater rocks and debris,
  hit sparks, hitstop (frame freeze), trauma camera shake, impact frames and screen flashes,
  UV texture scrolling and flipbooks, particle bursts, object pooling, and client/server VFX
  replication with compact UnreliableRemoteEvent packets. Use it whenever the user wants to
  create, script, fix, optimize or network visual effects or hit feedback in Roblox
  (FR: effets visuels, VFX, slash, onde de choc, cratère, impact, hitstop, secousse caméra,
  écran flash, texture qui défile, particules, "game feel").
---

# Roblox Mesh VFX & Combat Feel

A complete, tested, drop-in library lives in `src/` (a Rojo project: `default.project.json`).
**Start from it instead of writing effects from scratch.** Every effect works in an empty
baseplate (procedural Beam/Part fallbacks) and upgrades automatically to authored Blender
meshes when they exist in `ReplicatedStorage.Assets.VFX`.

## Quick start

1. Copy `src/shared/VFX` → `ReplicatedStorage.VFX`, `src/server` → `ServerScriptService.VFXServer`,
   `src/client` → `StarterPlayerScripts` (or `rojo serve default.project.json`).
   `src/demo` is a playable demo (Q = slash, E = ground slam, a training dummy to hit).
2. Server, after validating the gameplay action:
   ```lua
   local VFXService = require(ServerScriptService.VFXServer.VFXService)
   VFXService.play("ImpactBurst", {
       cframe = CFrame.lookAt(hitPos, hitPos + swingDirection),
       source = attacker.Character, target = victim.Character, power = 1.5,
   })
   VFXService.play("GroundSlam", { cframe = CFrame.new(slamPos), power = 2, seed = seed }, { exclude = attacker })
   ```
3. Attacker client, for zero-latency feedback (prediction), with the SAME seed sent to the server:
   ```lua
   VFXClient.play("Slash", { cframe = slashFrame, power = 1.2, variant = 1, seed = seed })
   ```

Built-in effects: `Slash`, `Shockwave`, `CraterRocks`, `ImpactBurst` (sparks + flash + victim
highlight + hitstop + camera), `GroundSlam` (shockwave + crater + dust + distance shake), and the
melee-combat set used by `roblox-deepwoken-combat`: `Parry` (yellow star spark + ring + light,
heavy hitstop), `Block`, `GuardBreak` (shards, rings, impact frame), `FistImpact` (air-pressure
rings), `Telegraph` (red flash for perilous attacks). Building blocks: `Shapes` (flash, ring,
star, shards, highlight).

## Non-negotiable architecture

- **Render on clients only.** The server validates, then sends *records* (31 bytes: effect id,
  seed, CFrame, scale, color, power, variant, source/target refs) batched per frame, only to
  players within `radius`. Never create/tween effect parts on the server.
- **Clients send intent, never positions.** The server recomputes frames from its own view of the
  character (see `src/demo/server/DemoServer.server.luau`: type/NaN/range checks, cooldowns).
- **Seeded randomness.** `params.seed` → `ctx.rng` makes crater rocks identical on every screen.
  Never use `math.random` inside an effect.
- **Prediction:** attacker plays locally, server broadcasts with `{ exclude = attacker }`.
- **Unreliable by default** (cosmetic, ~900-byte payload cap, unordered); `{ reliable = true }`
  only for effects that must never be lost (ultimates, cutscene beats).
- Details and packet layout: [architecture.md](references/architecture.md).

## Pick the right primitive

| Need | Use | Library entry |
|---|---|---|
| Crescent slash, ring, dome, spike | MeshPart + squash/stretch curves | `Pool.fromTemplate`, `Animator.play`, `Ease.phase` |
| Arc / ring with zero assets, sword arcs, wind rings | Beams with circle-fitting Bézier | `BeamArc` |
| Flowing energy along a path | `Beam.TextureSpeed` / `Trail` (native, cheapest) | [particles_beams_trails.md](references/particles_beams_trails.md) |
| Scrolling texture on a surface | `Texture.OffsetStudsU/V` (face-projected) | `TextureAnimator.scroll` |
| Animated texture on true mesh UVs | frame swap on `MeshPart.TextureID` / spritesheet on Decal | `TextureAnimator.flipbook` / `.spritesheet` |
| Sparks, dust, embers bursts | `ParticleEmitter:Emit(n)` on pooled holders | `Particles.burst` |
| Victim body flash | `Highlight` (max 31 visible at once) | `ImpactBurst` |
| Impact weight | hitstop + trauma shake + FOV punch + post FX | `Hitstop`, `CameraShaker`, `ScreenFlash` |

## Writing a new effect (template)

```lua
--!strict
-- ReplicatedStorage/VFX/Effects/MyEffect.luau  (+ append "MyEffect" to Registry.luau NAMES)
local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Assets = require(VFX.Assets)
local Ease = require(VFX.Ease)
local Fade = require(VFX.Fade)
local Pool = require(VFX.Pool)
local Types = require(VFX.Types)

local MyEffect = {} :: Types.Effect
MyEffect.maxDistance = 300
local pool: Pool.PartPool? = nil

function MyEffect.preload()
    local template = Assets.findPart("Meshes/Shockwaves/MyRing")
    if template then pool = Pool.fromTemplate(template, Assets.workspaceFolder(), 4) end
end

function MyEffect.play(params: Types.EffectParams, ctx: Types.EffectContext)
    local p = pool; if p == nil then return end
    local part = p:acquire()
    local snapshot = p.snapshotOf[part]
    local base = p.template.Size * params.scale
    Animator.play(0.5, function(t)
        local grow = Ease.outExpo(t)                                  -- 80% of size in 20% of life
        local thin = Ease.lerp(1, 0.2, Ease.inQuad(Ease.phase(t, 0.3, 1)))
        part.Size = Vector3.new(base.X * grow, base.Y * thin, base.Z * grow)
        Animator.move(part, params.cframe * CFrame.Angles(0, t * 0.6, 0)) -- batched BulkMoveTo
        Fade.apply(snapshot, 1 - Ease.inQuad(Ease.phase(t, 0.25, 1)))    -- fades decals/beams too
    end, { onComplete = function() p:release(part) end })              -- always runs, even on error
end

return MyEffect
```

Rules the template encodes: pool everything; one `Animator` loop (time-scaled, error-isolated);
drive every property from ONE normalized `t` split into phases with `Ease.phase`; fade with
`Fade` (tweening only `MeshPart.Transparency` leaves Decals/Textures visible); use `ctx.rng` and
`ctx.quality` (scale particle/debris counts by it); release in `onComplete`.

## Feel cheat sheet

| Beat | Values that read well |
|---|---|
| Slash | 0.26–0.4 s, width snaps in first 14%, fade from 40% |
| Shockwave | 0.5–0.6 s, ring delay 0.07 s, `Ease.outExpo` radius |
| Hitstop | light 0.04–0.06 s · heavy 0.08–0.12 s · parry 0.12–0.16 s |
| Trauma (`CameraShaker.addTrauma`) | jab 0.1 · heavy 0.3 · explosion 0.6; shake = trauma² |
| Critical | `ScreenFlash.impactFrame(0.05)` + `freezeVFX = true` hitstop |

More in [hitstop_and_camera.md](references/hitstop_and_camera.md) and
[mesh_animation_guide.md](references/mesh_animation_guide.md).

## Verified pitfalls (each one is a real bug this library fixes)

- `CFrame.fromMatrix(pos, right, up, -right:Cross(up))` builds a **mirrored** matrix. Use
  `VFXMath.alignToNormal(pos, normal, forward)` (right-handed, tested).
- `Texture` on a MeshPart is **face-projected**, not UV-mapped. Only MeshPart.TextureID follows
  mesh UVs, and it cannot be offset → flipbook or Decal `UVOffset/UVScale` (newer API; profile it).
- Rapid-fire bloom flashes that capture `Intensity` mid-flash **drift upwards forever** → capture
  the base once (`ScreenFlash`).
- Hitstop must freeze **all** playing tracks and restore each **original speed**, and overlapping
  hitstops must extend, not cancel (`Hitstop`). Change speeds in `RunService.PreAnimation`.
- Camera shake applied as `camera.CFrame *= offset` every frame **accumulates / fights** the camera
  script → undo at `Camera-1`, apply at `Camera+1` (`CameraShaker`).
- A queued CFrame write can un-park a pooled part released in the same frame → `Animator` flushes
  moves before completion callbacks.
- UnreliableRemoteEvent payloads over ~900 bytes are silently dropped; Instance references in the
  payload count too (`VFXService` budgets bytes).
- Beam Bézier arcs are only circular for ≤ 90° pieces (`BeamArc` splits them).
- `WaitForChild` per hit, `Instance.new` per hit, `Debris` for hundreds of parts, per-effect
  `RenderStepped` connections: all replaced by caches, pools and the shared loop.

## Performance

Budgets, pooling, preloading, LOD and profiling: [performance.md](references/performance.md).
Authoring meshes in Blender (pivot, axes, UVs for gradients, import settings):
[blender_pipeline.md](references/blender_pipeline.md).

## Verify your changes

From the repo root: `tools/check.sh` (StyLua, Selene, luau-lsp strict type check with Roblox
definitions and Rojo sourcemaps, Lune unit tests). Pure logic (math, packing, scheduling) belongs in
modules without services so it can be tested in `tests/*.spec.luau`.

## File map

| Path | Role |
|---|---|
| `src/shared/VFX/Client.luau` | client dispatcher: packets, distance culling, adaptive quality, `play` |
| `src/server/VFXService.luau` | server batching, interest radius, reliable/unreliable, debris collision group |
| `src/shared/VFX/Net.luau` · `Registry.luau` · `Types.luau` | wire format, effect ids, types |
| `src/shared/VFX/Animator.luau` · `Ease.luau` · `Spring.luau` | frame loop + curves + analytic spring |
| `src/shared/VFX/Pool.luau` · `Fade.luau` · `Assets.luau` | pooling, whole-effect fades, templates/preload/raycast filters |
| `src/shared/VFX/BeamArc.luau` · `Particles.luau` · `TextureAnimator.luau` | beam arcs, particle bursts, UV scroll/flipbooks |
| `src/shared/VFX/Hitstop.luau` · `CameraShaker.luau` · `ScreenFlash.luau` | impact weight |
| `src/shared/VFX/Effects/*.luau` | Slash, Shockwave, CraterRocks, ImpactBurst, GroundSlam |
| `src/demo/**` | playable demo with server-side validation |
| `tests/*.spec.luau` | Lune tests (math, packets, spring, scheduler, pool) |
