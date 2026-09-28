---
name: roblox-deepwoken-combat
description: >-
  Server-authoritative Deepwoken/Sekiro-style melee combat framework for Roblox Luau, for
  sword and fist (unarmed) RPGs: 4-hit M1 chains with finishers, criticals, perilous
  (red-flash, dodge-only) attacks, feints, parry (tap F) / block (hold F) with posture and
  guard breaks, dodges with i-frames and roll cancel, hitstun, knockback, hyper armor,
  lag-compensated hitboxes, client prediction, procedural attack animations with zero
  animation assets, and matching VFX. Use it for any combat system, weapon moveset,
  hitbox, parry/block/dodge, posture, stun or PvP netcode work in a Roblox action RPG
  (FR: système de combat, épée, poings, M1, parade, garde, posture, guard break, feinte,
  esquive, hitbox, combo, Deepwoken).
---

# Deepwoken-style Combat (sword & fists)

Complete, tested framework in `src/` (Rojo project `default.project.json`, which also mounts
the `roblox-mesh-vfx` and `roblox-r6-procedural-animation` skills it builds on).
**Extend it (new weapons, moves, mantras) instead of rewriting a combat system.**

## Quick start

1. `rojo build default.project.json -o Combat.rbxlx` (or `rojo serve`), open, Game Settings →
   Avatar → **R6**, Play. The arena spawns three NPCs: `Guard` (holds block → break its posture),
   `Parry` (parries on reaction → feint it with M2), `Fighter` (sword chains + red-flash
   criticals → parry with F, dodge the red ones with Q).
2. Controls: M1 attack · M2 feint · R critical · F tap parry / hold block · Q dodge · 1 fists ·
   2 sword · 3 greatsword (Dragonslayer-style: slow, huge reach, 3-hit chain, spinning perilous).
3. Visual theme: `Config.vfxTheme` or workspace attribute `CombatVFXTheme` (`Default` glow
   VFX, `Dark` pixel-art effects from `roblox-dark-pixel-style`). `Config.effect(kind, fallback)`
   resolves every outcome's effect name.

## Architecture

```
client (CombatClient)                server (CombatService)                        every client
input → Rules.canStart (mirror)  →  Rules.canStart (authority)
ActionPose.playLocal (instant)       timers: windup → active → recovery (actionId cancels)
predicted Slash VFX                  active: rewind defenders (≤ 0.25 s) → Hitbox.contains
                                     Rules.resolve → damage / stun / posture / knockback
                                     attributes R6_Action/R6_ActionStart ───────────────→ ActionPose (same frame)
                                     VFXService.play(Parry/Block/GuardBreak/...) ───────→ VFX + hitstop + camera
```

- **One data table drives everything**: `Weapons.luau` moves hold timings, damage, posture
  damage, hitbox and poses. `Clips.luau` generates the animation from the timings, so the
  strike frame IS the hitbox window. Never hand-time an animation separately.
- **Rules are pure** (`Rules.luau`): `canStart`, `nextCombo`, `facing`, `resolve`,
  `regenPosture`. Server and client prediction call the same functions; tests cover them.
- Resolution order (Deepwoken): i-frames → perilous (only dodge) → parry window → block
  (posture, guard break at max) → hit. Guard only works inside `blockFacingAngle`.
- Clients send intent + their server-clock timestamp; the server rewinds defenders to
  that time, capped by `maxRewind` (anti-cheat), and validates rate (`maxInputsPerSecond`).
- Movement you own (dodge dash, knockback on players) is applied by the owning client
  (`Knockback` remote); NPC movement by the server.

## Tuning (Config.luau)

| Knob | Default | Feel |
|---|---|---|
| `parryWindow` | 0.18 s | tighter = harder, more rewarding |
| `parryWhiffCooldown` | 0.65 s | punishes parry spam (block still allowed) |
| `postureMax` / move `postureDamage` | 100 / 9–20 | hits to break a guard (~6 sword M1s) |
| `hitStun` / `finisherStun` | 0.45 / 0.85 s | true-combo length |
| `chainResetTime` / `chainBuffer` | 0.9 / 0.3 s | chain rhythm and input buffering |
| `dodgeIFrames` / `dodgeCooldown` | 0.26 / 1.8 s | dodge power |
| Weapon `speed` | fists 1.18, sword 1 | global tempo per class |
| Perilous `windup` | ≥ 0.6 s | reaction time to see the red flash and dodge |

## Adding a weapon or move

1. Add a `Weapon` in `Weapons.luau` (copy Sword): 4-move `chain` (last `finisher = true`),
   a `critical`, `blockPose`, `parryPose`, `hitEffect`, `hasBlade`.
2. Pose angles use the PoseLibrary conventions (shoulder X+ forward, 90 = horizontal,
   170 = overhead; horizontal sweeps use Y; RootJoint Y+ twists left). Split big rotations
   between torso and arm (the test suite catches hands ending behind the body).
3. Add its name to the lists in `Clips.registerAll` and `CombatClient` (moveByName).
4. `tools/check.sh`: `tests/combat.spec.luau` checks timings, uniqueness, reach and hand
   positions of every strike via forward kinematics.

## Pitfalls handled

- Animations and hit windows drifting apart (generated clips).
- Late/early hits across ping (rewind with cap) and spam (rate limit, whiff lockout).
- Stale timers firing after a stun/feint/dodge (`actionId` token checked in every delay).
- Parry spam (whiff cooldown), guard from behind (facing cone), perilous unparryable.
- Client-owned physics: players' dodge/knockback are applied on their own client.

## Files

| Path | Role |
|---|---|
| `src/shared/Combat/Config.luau` | all timings and limits |
| `src/shared/Combat/Weapons.luau` | Fists and Sword movesets (data + poses) |
| `src/shared/Combat/Rules.luau` | pure rulebook (tested) |
| `src/shared/Combat/Hitbox.luau` | OBB test + position history for lag compensation (tested) |
| `src/shared/Combat/Clips.luau` | registers move clips into the R6 PoseLibrary |
| `src/server/CombatService.luau` | authority: state machine, hits, stun, posture, VFX, blade |
| `src/client/CombatClient.client.luau` | input, prediction, trails, knockback, dodge, posture HUD |
| `src/demo/Arena.server.luau` | training NPCs (Guard / Parry / Fighter) |

Mechanics research and design notes: [combat_design.md](references/combat_design.md).
