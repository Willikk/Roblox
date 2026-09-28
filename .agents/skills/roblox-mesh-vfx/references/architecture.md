# VFX Architecture & Networking

## Flow of one hit

```text
Attacker client                     Server                                  Other clients
───────────────                     ──────                                  ─────────────
input → play Slash locally  ──────► RemoteEvent (intent: action, variant, seed)
        (prediction, 0 ms)          validate types / NaN / ranges / cooldown
                                    recompute frames from server character
                                    hit detection (GetPartBoundsInBox…)
                                    VFXService.play("Slash", …, {exclude = attacker}) ──► Slash
                                    VFXService.play("ImpactBurst", {source, target}) ───► ImpactBurst
                                         (attacker receives it too: the hit is server truth)
```

Rules:

- The client never sends a position/CFrame to be trusted. It sends *what it wants to do*; the
  server derives geometry from its own copy of the character (`DemoMoves` shows the shared
  formula used by both sides so prediction matches).
- Random effects are deterministic from `seed` (u16). The attacker picks it, the server clamps it
  and forwards it: every client builds the same crater.
- The server decides *who* receives an effect (interest radius, default 500 studs). The client
  additionally culls by camera distance (`Effect.maxDistance`) and scales counts by quality.

## Record format (`Net.luau`)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | effect id (`Registry`, positional; append only) |
| 1 | u16 | seed |
| 3 | f32 ×3 | position |
| 15 | i16 ×3 | YXZ Euler rotation, quantized to π/32767 rad |
| 21 | u16 | scale × 100 |
| 23 | u8 ×3 + u8 | color + has-color flag |
| 27 | u8 | power × 50 (0–5.1) |
| 28 | u8 | variant (effect-specific bit flags) |
| 29 | u8 ×2 | source / target index in the Instance array argument (0 = none) |

Packet = `u8 count` + records. Instance references travel as a second remote argument (an array),
deduplicated per packet. `Net.decode` rejects any payload whose length does not match exactly.

## Limits that shape the design (from the engine docs)

- `UnreliableRemoteEvent`: unordered, may drop, payload above ~900 bytes (docs: 1000 with overhead)
  is dropped. `VFXService` keeps unreliable packets under an 820-byte estimate including
  Instance refs (estimated at 12 bytes each).
- Remote events are rate-limited (~500 requests/s per client, shared by RemoteEvent and
  UnreliableRemoteEvent) → batch per frame (one packet per player per Heartbeat, not one per effect).
- Changes to a client-created Instance never replicate: that is exactly why effects are
  client-side, and why the same logic cannot be used for gameplay state.

## Server validation checklist (copy into every ability handler)

1. `type()` of every argument; reject NaN (`x ~= x`) and infinities; `math.clamp` ranges; `math.floor` integers.
2. Character alive, root part present, not stunned/dead (game state).
3. Per-player per-ability cooldown with ~10% latency grace.
4. Recompute every CFrame from the server's character; hit detection on the server.
5. Rate-limit unreliable inputs too (see `LookRelay` in the R6 skill for a token-window example).

## When to use reliable delivery

`VFXService.play(name, params, { reliable = true })` for: ultimate cutscene beats, effects whose
absence breaks readability of a mechanic (telegraphs for dodgeable attacks). Everything else:
unreliable (latest-wins, no head-of-line blocking behind other traffic).

## Prediction & reconciliation

- Cosmetic prediction only: if the server rejects the action, the predicted slash simply already
  played; do not predict damage numbers or hit sparks on the attacker before the server confirms.
- For hits, the server broadcasts `ImpactBurst` to everyone including the attacker (the server is
  the authority on whether something was hit).
