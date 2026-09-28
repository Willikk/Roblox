# Combat Design Notes (Deepwoken reference)

## Mechanics being modeled

| Mechanic | Deepwoken behavior | Implementation |
|---|---|---|
| M1 chain | consecutive light attacks, the last one is a stronger finisher | 4-move `chain`, `finisher` → longer stun + knockback, combo resets after `chainResetTime` |
| Parry | tap F at the right time: big yellow spark, negates damage, punishes the attacker, reduces your posture | `Parrying` for `parryWindow`; attacker gets `parriedStun` + "Parried" recoil; defender recovers `parryPostureReward`; `Parry` VFX + 0.12 s hitstop |
| Block | hold F: damage negated but posture fills | `Blocking` → posture += move.postureDamage |
| Posture / guard break | full posture bar → guard break, extra stun | `GuardBreak` outcome, `guardBreakStun`, posture reset, shards VFX |
| Posture regen | drains when not taking guarded hits | `postureRegenDelay` then `postureRegenRate` |
| Feint | M2 cancels your swing to bait a parry | `Feint` only in windup, `feintCooldown` |
| Dodge / roll cancel | Q, i-frames, can cancel your own windup | `dodgeIFrames`, `Dodge` allowed during own windup |
| Perilous attacks | red flash, cannot be parried/blocked: dodge | `perilous = true`, `Telegraph` VFX at windup start, long windup |
| Weapon classes | light (fists: fast, shortest reach), medium (sword: balanced) | `speed`, hitbox depth, damage |
| Parry whiff | spamming parry is punished | `parryWhiffCooldown` lockout (block still possible) |

Deepwoken's parry system is heavily inspired by Sekiro (posture bar, perilous attacks):
favor readable windups, tight parry windows and posture pressure over raw DPS.

## Hit feel checklist (per outcome)

| Outcome | Animation | VFX | Hitstop | Camera |
|---|---|---|---|---|
| Hit | victim `Stagger` | ImpactBurst (sword) / FistImpact (fists), heavy variant on finishers | 0.05–0.15 s | victim kick + trauma, attacker FOV punch |
| Blocked | defender holds guard | Block sparks | 0.035 s | defender light kick |
| Parried | attacker `Parried` recoil | Parry: yellow star + ring + light | 0.12 s + frozen VFX | both: trauma + FOV punch + bloom |
| Guard break | defender `GuardBroken` | shards + rings + red highlight | 0.16 s + frozen VFX | impact frame + desaturation |
| Perilous start | attacker windup | Telegraph red flash | — | — |

## Netcode choices

- Server authority with client prediction (industry standard for Roblox melee): input and
  pose are instant locally, the server validates `canStart` and resolves hits.
- Lag compensation: server keeps 1.5 s of root CFrames per fighter; hit tests rewind the
  defenders to the attacker's timestamp, capped at 0.25 s.
- Everything visual is derived on each client from replicated attributes + server time:
  zero per-frame animation traffic.

## Extending toward a full Deepwoken-like game

- **Mantras / skills**: new `Move`s with custom `vfx` and `hitboxSize`, triggered by other
  keys; reuse `startAttack` with a move parameter.
- **Running / aerial attacks**: choose the move by `Humanoid.MoveDirection` magnitude /
  `FloorMaterial == Air` in `startAttack`.
- **Ragdoll on knockdown**: on `finisher` hits with low health, disable R6 layers
  (`R6_Disabled`) and switch the Humanoid to physics ragdoll.
- **Stamina / ether**: add fields to `Fighter`, gate `Rules.canStart`, show in the HUD.
- **Clashes**: when two `active` windows overlap between two fighters, resolve both as a
  mutual Block with a clash VFX.
