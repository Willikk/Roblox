---
name: roblox-mesh-vfx
description: >-
  Use this skill when the user wants to create, script, or optimize high-end custom Mesh VFX,
  weapon slashes, ground shockwaves, UV texture scrolling, flipbooks, or Deepwoken-style
  combat visual effects in Roblox using Luau and 3D assets.
---

# Roblox High-End Mesh VFX & Combat Effects Guide

This skill teaches the agent how to implement AAA-quality, performant visual effects (VFX) in Roblox Luau, specifically designed for fast-paced action RPGs (such as *Deepwoken*, *Jujutsu Shenanigans*, *Type Soul*).

## Core Principles

1. **Client-Side Rendering Only**:
   - NEVER create, tween, or parent visual effect parts on the server.
   - The server validates hits and fires an `UnreliableRemoteEvent` (or `RemoteEvent`) containing only coordinates, direction vectors, and hit metadata.
   - All clients receive the event and render the visual effect locally in `Workspace.Camera` or a dedicated client-only folder (e.g. `Workspace.VFX`).

2. **Mesh-Driven Effects (Not Pure Particles)**:
   - High-end VFX rely on 3D meshes (slashes, hollow cylinders, toruses, crescents) designed in Blender.
   - The Luau code controls:
     - Non-uniform rapid scaling (*Squash & Stretch*) via `TweenService`.
     - Axial rotations (`CFrame.Angles`).
     - Transparency and color fades.
     - Orientation aligned to weapon bones or surface normals via Raycasting.

3. **Performance & Memory**:
   - Always clean up instances using `Debris:AddItem(part, lifetime)` or an Object Pool.
   - Always disconnect any `RunService.RenderStepped` connections when an effect finishes.

---

## Directory Structure & Asset Conventions

The game's `ReplicatedStorage` should contain the following asset hierarchy:

```text
ReplicatedStorage/
└── Assets/
    └── VFX/
        ├── Meshes/
        │   ├── Slashes/       # Blender 3D crescent/arc meshes
        │   ├── Shockwaves/    # Blender flat rings, toruses, hollow cylinders
        │   └── Spikes/        # Rock spikes, ice shards, ground debris
        ├── Textures/
        │   ├── Flipbooks/     # Animated 4x4 or 8x8 spritesheets (smoke, blood, fire)
        │   └── Noise/         # Seamless seamless energy/lightning noise for UV scrolling
        └── Sounds/            # Impact audio, whooshes, parry clangs
```

---

## Technical Guides in this Skill

* **[Mesh Animation Guide](./references/mesh_animation_guide.md)**: Detailed patterns for scaling, orienting, and fading 3D slash and impact meshes.
* **[UV Texture Scrolling Guide](./references/uv_scrolling_guide.md)**: How to animate energy and aura textures continuously over meshes.
* **[Hitstop & Camera Impact Guide](./references/hitstop_and_camera.md)**: Deepwoken-style frame freezing (*hitstop*), screen shake, and post-processing flashes.

---

## Ready-to-Use Code Examples

* **[`SlashEffect.luau`](./examples/SlashEffect.luau)**: Full client implementation of a weapon swing slash mesh with tweening and cleanup.
* **[`ShockwaveEffect.luau`](./examples/ShockwaveEffect.luau)**: Ground shockwave aligned to terrain normal with raycasting.
* **[`UVScroller.luau`](./examples/UVScroller.luau)**: Modular controller for continuous texture scrolling on meshes.
* **[`HitstopModule.luau`](./examples/HitstopModule.luau)**: Hitstop frame-freeze, micro camera shake, and bloom impulse module.
