# Blender → Roblox Mesh Pipeline

## Conventions expected by the library

| Mesh | Plane / axis | Origin | Template name |
|---|---|---|---|
| Slash crescent | lies in the **XZ plane** (Y = plane normal), bulges towards **−Z** | arc center | `Assets/VFX/Meshes/Slashes/Slash`, optional `SlashCore` |
| Shockwave ring | flat ring in **XZ**, Y up | ring center | `Assets/VFX/Meshes/Shockwaves/Shockwave` |
| Rocks / spikes | Y up, base at Y ≈ −height/2 | center | any MeshPart in `Assets/VFX/Meshes/Spikes` |

Blender is Z-up / −Y forward; Roblox is Y-up / −Z forward. Export FBX with **Forward: −Z, Up: Y**
(or apply a −90° X rotation before export) and **Apply Transforms**, so the template imports with an
identity orientation. The template's **Size** is the look at `scale = 1`.

## Modeling tips

- Slash: a thin, tapered crescent (wide in the middle, sharp ends); 32–64 segments along the arc,
  1–2 across. Keep it paper-thin; thickness comes from the animation (Y scale).
- Rings: 48–64 segments, a few loops across the width for smoother squash.
- Low poly: effects are on screen for 0.3 s; < 1k triangles per mesh.
- Duplicate with an inward offset for a "core" layer instead of a second texture.

## UVs for gradients and alpha

- Unwrap arcs so **U runs along the arc** and **V across the width**. A texture with an alpha
  gradient along V gives soft edges; along U gives a head-to-tail fade.
- Keep UVs inside 0–1 when using `MeshPart.TextureID` (no tiling). For flipbooks, every frame
  uses the same UV layout.
- Bake gradients into the texture (white → transparent) and tint in Roblox with `MeshPart.Color`
  (textures are multiplied by Color) — one texture serves every element color.

## Import & template setup (Studio)

1. Import 3D (File → Import 3D), check scale and that the mesh faces −Z.
2. On the MeshPart template: `Anchored`, `CanCollide/CanTouch/CanQuery = false`, `CastShadow = false`,
   `CollisionFidelity = Box`, `RenderFidelity = Precise` for large slashes (Automatic is fine for
   rocks), `DoubleSided = true` for domes/rings seen from inside.
3. Material: `Neon` for glowing solids, `ForceField` for energy shells, `SmoothPlastic` + texture
   for painted anime slashes.
4. Put it under `ReplicatedStorage/Assets/VFX/Meshes/...` with the exact name above. The effect
   switches from the procedural fallback to the mesh automatically (pools are built on first use).
