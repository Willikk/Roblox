# Art Direction: Berserk × Fear & Hunger in Roblox

## Pillars

1. **Ink and paper** (Berserk): heavy black shapes, paper-white highlights, extreme contrast,
   manga speed lines and impact panels on the biggest hits.
2. **Rot and dread** (Fear & Hunger): near-black ambient, sickly sepia, fog that hides what
   comes next, grain that never stops boiling, gore that stays on the floor.
3. **Limited animation**: everything moves in steps (12 fps): poses snap, sprites flip,
   blood falls in stutters, the camera shakes in jolts. Smoothness reads as "default Roblox".
4. **Weight**: long anticipation, instant strike, long recovery; hitstop on every contact.

## Palette usage

| Ramp | Use |
|---|---|
| INK / PAPER | outlines, impact panels, speed lines, grain |
| steel | blades, sparks, armor highlights |
| blood | wounds, pools, perilous slashes (red = danger, keep it rare elsewhere) |
| ichor | black blood (gentler maturity rating, eldritch enemies) |
| ember | torches, parry sparks, the only warm light in the world |
| bone / rot | environment props, corpses, Fear & Hunger sickness |
| smoke | dust, grit, blocked hits |

Keep the world desaturated (ScreenStyle presets do it) so red and ember are the only
saturated notes on screen: the eye always finds blood and fire.

## Lighting recipes (ScreenStyle presets)

| Preset | Look | Key settings |
|---|---|---|
| Berserk | ink monochrome at dusk | Saturation −0.72, Contrast 0.6, hard shadows, cold fog |
| FearAndHunger | dungeon rot | Ambient ~16/255, Brightness 0.35, sepia tint, FogEnd 120, grain 0.6 |
| Eclipse | nightmare set piece | red Atmosphere + ambient, bloom 0.8, for boss fights / cutscenes |

- `Lighting.Technology` is not scriptable: set it in Studio / Rojo. **Future** gives hard torch
  shadows (best for dungeons); **Voxel** gives chunky retro light (strong pixel vibe outdoors).
- `ShadowSoftness = 0` and `EnvironmentDiffuse/SpecularScale = 0` remove the soft, glossy
  modern PBR feel.
- Light the scene with few, warm, flickering torches (`DarkTorch` tag); leave the rest dark.

## World assets that match

- Low-poly, chunky geometry; big flat faces.
- Textures: small (32–128 px) pixel-art textures on MeshParts via `SurfaceAppearance`
  with `ResampleMode = Pixelated` (nearest filtering), or plain materials (Slate, Cobblestone,
  CorrodedMetal, Wood) in dark shades.
- Avoid Neon, Glass and ForceField except for rare supernatural moments.
- Characters: R6, dark clothing, simple faces; armor as blocky accessories.

## Animation direction

- Author custom animations at 12 fps with **Constant** easing (Moon Animator / Blender
  stepped interpolation) so they match the procedural `R6_StepFps = 12` layers.
- Poses: extreme silhouettes on key frames (windup reads from far away), 2–3 frame strikes,
  heavy follow-through that drags the body (see the Greatsword poses).
- Hold the impact pose during hitstop; let the camera jolt, not glide.

## Horror pacing (Fear & Hunger)

- Fog hides enemies until they are close; sound before sight.
- Grain intensity and vignette can rise with low health (drive `ScreenStyle` overlay
  transparency from Humanoid.Health).
- Keep blood pools (`Settings.poolLifetime`) long enough that fights leave a mark.
- Perilous attacks: the red eye (`DarkTelegraph`) is the only UI warning; everything else is diegetic.

## Things that break the style

Smooth tweens on anything visible, bilinear-filtered images, bright saturated UI, glowing
neon trails, particles with soft gradients, mixed pixel densities, and too many impact frames.
