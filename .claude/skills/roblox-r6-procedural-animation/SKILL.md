---
name: roblox-r6-procedural-animation
description: >-
  Use this skill when the user wants to create, script, or optimize procedural animations,
  terrain adaptation (foot placement, slope alignment, pelvis drop), body leaning, and head tracking
  specifically for R6 character rigs in Roblox Luau (Deepwoken style).
---

# R6 Procedural Animation & Terrain Adaptation Guide

Deepwoken and top-tier Roblox action games famously use the **R6 rig** for its snappy combat, clean silhouette, and iconic anime aesthetic.

Unlike R15 rigs which have knees and support `IKControl`, R6 has single-block legs and 6 rigid parts connected by `Motor6D` joints. Procedural terrain adaptation in R6 is achieved by dynamically offsetting `Motor6D.C0` transforms in real-time.

## The 4 Pillars of R6 Procedural Motion

1. **Foot & Slope Alignment (Left & Right Hip C0)**:
   - Cast two vertical rays downwards from each hip position.
   - Adjust `Left Hip.C0` and `Right Hip.C0` along Y to match the floor height difference.
   - Tilt the legs along Pitch and Roll to match the ground surface normal (`hit.Normal`), preventing the blocky legs from clipping into slopes or stairs.

2. **Pelvis Drop (RootJoint C0 Translation)**:
   - When one leg steps onto a rock or stair, lower the `RootJoint.C0` along the Y axis by the step difference so the character's upper leg doesn't stretch artificially.

3. **Body Leaning (Torso Banking & Incline)**:
   - Rotate `RootJoint.C0` based on character velocity and acceleration:
     - **Pitch (Forward/Backward)**: Tilt forward when accelerating/sprinting, tilt back when braking, tilt along terrain slope.
     - **Roll (Left/Right)**: Bank into sharp turns based on centripetal acceleration.

4. **Head Tracking (Neck C0)**:
   - Rotate `Torso.Neck.C0` smoothly towards the camera direction or target with angle clamps (`math.clamp`) to avoid unnatural neck-breaking angles.

---

## Directory Hierarchy & Reference Files

* **[R6 Motor6D Coordinate Math Guide](./references/r6_motor6d_math.md)**: Precise reference for default C0/C1 matrices of R6 joints.
* **[`R6TerrainAdaptation.luau`](./examples/R6TerrainAdaptation.luau)**: Complete client-side controller for terrain adaptation, foot alignment, and body leaning.
* **[`R6HeadTracking.luau`](./examples/R6HeadTracking.luau)**: Smooth neck tracking module for camera orientation.
