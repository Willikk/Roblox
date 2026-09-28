---
name: roblox-dark-pixel-style
description: >-
  Dark-fantasy pixel-art art direction for Roblox (Berserk ink + Fear & Hunger rot): a
  procedural pixel-art generator (brushed ink-outlined slashes, blood/ichor bursts, ink
  impact bursts, sparks, dithered smoke, torch flames, manga speed lines, film grain,
  dithered vignette) with a strict palette, 1-px outlines, Bayer dithering and binary
  alpha; 3D billboard sprites animated "on twos" (stepped 12 fps motion and flipbooks);
  screen presets (lighting, grading, atmosphere, grain overlays); manga impact frames;
  limited-animation stepping for R6 poses and camera shake; and dark combat effects
  (DarkSlash, DarkHit, DarkParry, DarkBlock, DarkGuardBreak, DarkTelegraph). Use it for any
  visual style, pixel art, sprite, post-processing, mood, horror/grimdark ambience or
  retro look work in Roblox (FR: pixel art, style, direction artistique, dark fantasy,
  Berserk, Fear and Hunger, ambiance, rétro, sang, grain, impact frame).
---

# Dark Pixel Style (Berserk × Fear & Hunger)

Tested library in `src/` (Rojo project `default.project.json` mounts the combat, VFX and R6
skills too: it IS the full game demo). **Build on it; keep the rules below or the style breaks.**

## Quick start

1. `rojo build default.project.json -o DarkArena.rbxlx`, open, Game Settings → Avatar → R6, Play.
   A ruined arena with torches, three training NPCs, pixel VFX, Berserk grading.
   Keys: combat keys (see `roblox-deepwoken-combat`) + `3` greatsword + `P` cycles presets.
2. In your own place, set three workspace attributes (server script or Studio):
   `DarkStylePreset` = `Berserk` | `FearAndHunger` | `Eclipse`, `CombatVFXTheme` = `Dark`,
   `R6_StepFps` = `12`. Put `src/client` in StarterPlayerScripts and `src/shared/DarkStyle`
   in ReplicatedStorage. Tag torch parts `DarkTorch`.
3. Published games: EditableImage needs a 13+ ID-verified owner + "Enable Mesh / Image APIs".
   Otherwise run `lune run tools/export-sprites.luau builds/sprites`, upload the PNGs (import
   them in Studio / Asset Manager) and fill `SpriteBank.assetIds` (`manifest.json` lists sizes).

## The style rules (non-negotiable)

| Rule | Why | Where enforced |
|---|---|---|
| Only `Palette` colors (INK, PAPER, blood, steel, ember, bone, smoke, rot, ichor) | cohesion; pixel art lives on restricted palettes | `tests/pixel.spec.luau` fails on off-palette pixels |
| Binary alpha, fades by Bayer dithering (`erode`) or 4 hard steps | soft alpha = "Roblox 2010" look | tests + `Sprite3D.ground` |
| 1-px outline on every sprite (INK, PAPER around ink, darkest ramp for blood/smoke) | readability at low resolution | `Canvas.outline` |
| One art pixel = `Sprite3D.PIXEL` (0.12) studs everywhere | mixed pixel sizes look cheap | `Sprite3D.play` sizes from frame pixels |
| `ResampleMode = Pixelated` on every image | no bilinear blur | `SpriteBank.apply` |
| Motion and flipbooks advance in steps (12 fps, "on twos") | limited animation = hand-drawn feel | `Sprite3D` stepFps, `R6_StepFps`, `CameraShaker.settings.stepFps` |
| Impact frames only for heavy moments | overuse kills their punch | `DarkHit` (heavy only), `DarkGuardBreak`, `DarkParry` |

Full art-direction guide (palette usage, lighting recipes, what to model/texture, animation
posing for Berserk weight, horror pacing): [art_direction.md](references/art_direction.md).

## Modules

| Module | Role |
|---|---|
| `Canvas` / `Palette` | pixel buffer, outline, Bayer dither, ramps (pure, tested) |
| `SpriteGen` | procedural sprite library, lazy `builders()`, `sheet()` packing (pure, tested) |
| `SpriteBank` | EditableImage generation (1 sprite per frame, no hitch) or uploaded PNG ids |
| `Sprite3D` | pooled billboard sprites: stepped flipbook + stepped ballistic motion; ground decals |
| `ScreenStyle` | presets (lighting, ColorCorrection, Bloom, Atmosphere) + grain / vignette / dither overlays, torch flicker |
| `ImpactFrame` | manga panel: paper flash, ink flash, speed lines, ink burst, monochrome punch |
| `Settings` | `blood` = blood / ichor / none, stepFps, impactFrames, pool lifetime |
| `Effects/Dark*` | combat effects registered into the VFX client (`CombatVFXTheme = "Dark"`) |

## Adding a sprite

Write a generator in `SpriteGen` (use `Palette.dither`, `Canvas.outline`, `erode` for fades,
seeded `rng`), add it to `SpriteGen.builders()`, run `lune run tools/export-sprites.luau`, and
LOOK at `builds/sprites/_preview.png` (the agent can read PNGs). Iterate until it reads well at
x1, then `tools/check.sh` (palette/alpha/determinism tests).

## Content maturity

Blood and gore must be declared in the Roblox Maturity & Compliance questionnaire.
`Settings.blood = "ichor"` (black blood) keeps the grimdark mood with a gentler rating;
`"none"` removes it.
