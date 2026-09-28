# Replication Model

## What replicates on its own

| Data | Replicates? | Consequence |
|---|---|---|
| Character position/orientation (HRP) | yes (physics replication, interpolated) | every client can compute lean, bank, foot planting, landing locally |
| AnimationTracks played by the owner | yes (Animator replication) | base pose is identical everywhere |
| `Motor6D.C0/C1` / `Transform` edited on a client | **no** | procedural offsets must be recomputed on every client |
| C0 edited on the server every frame | yes, but floods the network and lags by the ping | never do this |
| Attributes set by the server | yes | gameplay weights (`R6_HeadLook = 0`), NPC `R6_LookAt` |

The only thing a client knows that others cannot compute is **where its camera looks** → that is
the only data sent.

## Head-look protocol (`LookNet` + `LookRelay`)

```
client ──(4 bytes: i16 yaw, i16 pitch)──► server        on change > 1°, at most 15 Hz, keep-alive 1 s
server ──(u8 n + n × {f64 userId, i16 yaw, i16 pitch})──► all clients   batched at 15 Hz
```

- Angles are relative to the character root (not world), so they stay valid when interpolated
  positions differ slightly between clients.
- Server validation: `buffer` type, exact length, NaN sanitized, yaw ∈ [−π, π], pitch ∈ [−π/2, π/2],
  ≤ 30 packets/s per player (token window), entries dropped on `PlayerRemoving`.
- Only dirty entries are broadcast, plus a full refresh every 2 s so late joiners converge.
- ≤ 70 players per packet (841 bytes, under the ~900-byte UnreliableRemoteEvent cap); larger
  servers are chunked.
- The receiving `HeadLook` layer smooths the target with a critically damped spring, which hides
  the 15 Hz update rate.

## NPCs

Server: `CollectionService:AddTag(npc, "R6Procedural")` and update `npc:SetAttribute("R6_LookAt", headPosition)`
a few times per second (see `TestCourse.server.luau`). Clients animate NPCs exactly like players;
for dozens of NPCs the LOD tiers keep the cost bounded.

## Why not IKControl?

`IKControl` targets R15-style chains (upper/lower limbs with a middle joint). R6 legs are a single
rigid part, so a pelvis drop + tuck/bend solver is both cheaper and better looking.
