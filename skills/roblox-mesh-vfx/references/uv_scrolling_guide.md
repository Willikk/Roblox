# UV Scrolling, Flipbooks & Animated Textures

## What can actually scroll (engine facts)

| Object | Property | Mapping | Notes |
|---|---|---|---|
| `Texture` (child of Part/MeshPart) | `OffsetStudsU/V`, `StudsPerTileU/V` | **projected on one face** (`Face`) | Not the mesh UV map. Great on flat-ish surfaces and boxes. |
| `Decal` | `UVOffset`, `UVScale` (Vector2) | face projection | Newer API; reports of perf/distance artifacts: profile on target devices. |
| `Beam` | `TextureSpeed` (cycles/s), `TextureMode`, `TextureLength` | along the beam | Native scrolling, zero script cost. Best for energy flows, auras, lasers. |
| `Trail` | `TextureMode`, `TextureLength`, `Lifetime` | along the trail | Native. Weapon trails. |
| `MeshPart.TextureID` | — | **true mesh UVs** | Cannot be offset. Animate by swapping frames (flipbook). |
| `ParticleEmitter` | `FlipbookLayout`, `FlipbookMode`, `FlipbookFramerate` | per particle | Native flipbooks (2x2, 4x4, 8x8). |

## Library API (`TextureAnimator`)

```lua
local stop = TextureAnimator.scroll(texture, Vector2.new(0, 12))        -- studs/second
TextureAnimator.scrollDecal(decal, Vector2.new(0.5, 0))                  -- UV/second
TextureAnimator.flipbook(meshPart, frameIds, 24, true)                   -- TextureID swap
TextureAnimator.spritesheet(decal, 4, 4, 16, 30, false)                  -- one sheet, UVScale/UVOffset
stop()
```

All of them run on the shared `Animator` loop: they pause during a `freezeVFX` hitstop, a thrown
error cannot kill other effects, and offsets are wrapped by `StudsPerTile` (or 1 UV) so long-lived
auras never lose float precision nor visibly jump (the legacy `% 100` wrap jumped unless the tile
size divided 100).

## Best practices

1. Client only. Never animate texture properties from the server (replication spam).
2. Multiply by `dt` (frame-rate independence) — handled by the Animator.
3. Preload flipbook frames (`ContentProvider:PreloadAsync`, or put them under
   `ReplicatedStorage.Assets.VFX` so `Assets.preloadAsync()` covers them) or the first loop flickers.
4. Prefer Beams for anything that flows along a path: no script, GPU-side scrolling.
5. Seamless textures (tileable in the scroll direction) for scrolling; alpha gradients baked in
   the texture for fades along a mesh (see `blender_pipeline.md` for UV layouts).
