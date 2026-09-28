---
name: roblox-r6-procedural-animation
description: >-
  Production procedural animation system for Roblox R6 rigs in Luau (Deepwoken style): foot
  planting on stairs/rocks/slopes (pelvis drop + leg tuck/bend), physically-based body lean and
  turn banking, head/torso look-at with camera tracking and multiplayer replication, landing
  crouch, idle breathing, layered on top of animations through Motor6D/AnimationConstraint
  Transform, with LOD for every visible character and NPC. Use it whenever the user wants to
  create, fix, tune or network procedural character motion, IK-like foot placement, head
  tracking or leaning on R6 (or asks why Motor6D C0 edits look wrong or do not replicate)
  (FR: animation procédurale, pieds sur les escaliers, inclinaison, pencher, suivi de la tête,
  regarder la caméra, atterrissage, R6).
---

# R6 Procedural Animation

A complete, tested layered system lives in `src/` (Rojo project: `default.project.json`).
**Use it as the base** and add/tune layers rather than writing a new monolithic script.

## Quick start

1. Copy `src/shared/R6Procedural` → `ReplicatedStorage.R6Procedural`,
   `src/server` → `ServerScriptService.R6ProceduralServer` (head-look relay),
   `src/client` → `StarterPlayerScripts` (or `rojo serve default.project.json`).
2. Game Settings → Avatar → **R6** (the system ignores R15 characters).
3. `src/demo/TestCourse.server.luau` builds stairs, a 25° ramp, rocks and two patrolling NPCs
   that look at you — delete it in production.

```lua
-- LocalScript (StarterPlayerScripts)
local Controller = require(ReplicatedStorage.R6Procedural.Controller)
Controller.start({ head = { armPitchShare = 0.4 } }) -- overrides merge into Config.defaults
```

## The one rule: layer on `Transform`, in Part0 space

```
Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
joint.Transform = R6Math.jointOffset(C0, part0SpaceOffset) * animatedTransform   -- PreSimulation
```

- Write offsets **in Part0 space** ("lower the torso in HumanoidRootPart space", "rotate the head
  about the neck point in Torso space") and convert with `R6Math.jointOffset(c0, offset)`
  (`c0⁻¹ · offset · c0`). Rotations about a joint/pivot: `R6Math.rotationAbout(pivot, rotation)`.
- Do it in `RunService.PreSimulation` (after the Animator wrote the pose, before physics). This is
  the officially recommended layering and it works for **Motor6D and AnimationConstraint**
  (Avatar Joint Upgrade) joints; `AnimationConstraint.C0` is read-only.
- Never multiply offsets in C0's own frame: for `RootJoint`/`Neck`, C0's local **Y points
  backward and Z points up** (proven in `tests/r6math.spec.luau`). That is why the classic
  `RootJoint.C0 = C0 * CFrame.new(0, -drop, 0) * CFrame.Angles(pitch, 0, roll)` slides the
  torso backward and turns "roll" into a yaw.
- `Rig` detects frames where the Animator did not rewrite `Transform` (no track on the joint,
  `Animator.EvaluationThrottled`, LOD) and re-applies on the stored base: offsets never accumulate.

Full math, default C0/C1 table and pivots: [r6_motor6d_math.md](references/r6_motor6d_math.md).

## Layers (run in this order, each writes Part0-space offsets through `rig:add`)

| Layer | What it does | Key math |
|---|---|---|
| `BodyLean` | lean = speed posture + `atan(a_forward/g)`, bank = `atan(yawRate·speed/g)`, lean into slopes; pivot on hip line with leg compensation, bank pivots on feet | `R6Math.leanAngles`, spring |
| `TerrainAdaptation` | pelvis drop so the lowest foot lands, then tuck + hip bend the other leg | `R6Math.solveFeet`, `R6Math.legRaise` |
| `LandingImpact` | bouncy crouch proportional to fall speed (pelvis dips, legs tuck) | spring impulse |
| `HeadLook` | camera / replicated / NPC target; torso takes 30% of yaw (legs counter-twist); neck compensates lean & bank; optional arm aim | `R6Math.lookAngles` |
| `Breathing` | idle chest + arm sway; the minimal example of a custom layer | sine |
| `ActionPose` | keyframed procedural poses (attacks, block, parry, stagger, dodge) from `PoseLibrary`, synced on server time via `R6_Action` / `R6_ActionStart` attributes, local prediction with `ActionPose.playLocal` | `PoseLibrary.sample` |

`PoseLibrary` = animation without assets: per-joint degrees in Part0 space (shoulder X+ forward,
90 horizontal, 170 overhead, Y for horizontal sweeps; RootJoint X+ back, Y+ twist left).
`PoseLibrary.attack(poses, timing)` builds a clip whose strike frame matches gameplay timings
(used by the `roblox-deepwoken-combat` skill).

Custom layer = a module `{ name = "X", update = function(rig, sensor, dt, cfg, ctx) ... end }`
appended to `Controller.layers`. Read `sensor` (velocity, acceleration, yawRate, grounded,
foot errors, ground normal, landingImpact, stateWeight), write with
`rig:add("RootJoint" | "Neck" | "LeftHip" | "RightHip" | "LeftShoulder" | "RightShoulder", part0Offset)`,
scale by `sensor.stateWeight * ctx.weight("R6_X")`, smooth with `Spring` (analytic, frame-rate
independent, stable under hitches).

## Multiplayer model

- Every client animates **every** visible R6 character locally from replicated positions
  (velocity is derived from position history, identical for local, remote and NPC rigs).
- Only head-look angles travel: client → server 4 bytes at ≤ 15 Hz (on change + 1 s keep-alive),
  server → clients one batched packet at 15 Hz (12 bytes/player, full refresh every 2 s),
  validated and rate-limited (`LookRelay`). Details: [replication.md](references/replication.md).
- NPCs: `CollectionService:AddTag(model, "R6Procedural")`, head target via attribute
  `R6_LookAt` (Vector3). Server-set attributes replicate.

## Gameplay control (attributes on the character Model)

`R6_Lean`, `R6_Terrain`, `R6_HeadLook`, `R6_Landing`, `R6_Breathing` = weight 0..1 (default 1),
`R6_Disabled = true` to turn everything off. Typical: set `R6_HeadLook = 0` during attack
animations, `R6_Disabled` during cutscenes/ragdoll. Sit, PlatformStand, death (and for the local
player Swimming, Climbing, Ragdoll, FallingDown, Physics) fade the system out automatically.

## Performance

Sensing (2 raycasts) runs every frame within 60 studs, 30 Hz to 120, 15 Hz to 200, 10 Hz off
screen, disabled beyond (offsets restored). `rig:apply()` runs every frame for active rigs
because the Animator resets `Transform` each frame. Tunables: `Config.luau`
([tuning_and_debugging.md](references/tuning_and_debugging.md)).

## Verified pitfalls

- C0/C1 edits on the client do not replicate; server-side C0 edits every frame flood the network
  and lag → local animation + angle replication.
- Offsets in C0's frame use rotated axes (see the rule above).
- `x += (target - x) * k * dt` overshoots/explodes on frame hitches → `R6Math.expAlpha` or `Spring`.
- Raycasts must exclude every character and effect folder and respect `CanCollide`.
- Rigid legs cannot stretch: lower the pelvis, then raise the other foot (tuck into the torso is
  invisible on R6 because legs and torso share the same depth).
- Resting foot height depends on the rig: `-(LeftLeg.Size.Y + RootPart.Size.Y/2 + HipHeight)`
  (Humanoid docs), so scaled R6 rigs work.
- Test-only: Lune's `CFrame.lookAt` is wrong in most directions; library code uses `fromMatrix`.

## Verify your changes

`tools/check.sh` from the repo root: StyLua, Selene, luau-lsp strict type check (Roblox
definitions + Rojo sourcemap) and Lune tests. `tests/rig.spec.luau` runs the real layers on a
mock R6 rig and checks the resulting pose with forward kinematics (feet on the steps, head on
target, legs planted) — add a case there for every new layer.

## File map

| Path | Role |
|---|---|
| `src/shared/R6Procedural/Controller.luau` | tracking, LOD, frame loop, look replication (client) |
| `src/shared/R6Procedural/Rig.luau` | joint discovery (Motor6D / AnimationConstraint), Transform layering |
| `src/shared/R6Procedural/Sensor.luau` | velocity/acceleration/yaw rate, foot rays, grounded/landing, state weight |
| `src/shared/R6Procedural/R6Math.luau` | pure math (tested): jointOffset, pivots, solvers, lean physics |
| `src/shared/R6Procedural/Layers/*.luau` | BodyLean, TerrainAdaptation, LandingImpact, HeadLook, Breathing |
| `src/shared/R6Procedural/Config.luau` | all tunables with rationale |
| `src/shared/R6Procedural/LookNet.luau` · `src/server/LookRelay.luau` | wire format + server relay |
| `src/demo/TestCourse.server.luau` | stairs, ramp, rocks, NPCs |
