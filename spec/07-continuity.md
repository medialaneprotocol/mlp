# 7. Session continuity

A session that dies is not necessarily over. This section states how a
lane's state survives a broken transport, and what a peer does when it
cannot.

The protocol's mechanisms are deliberately generic: a **resume token** the
peer treats as opaque, a **park** that retains the state, and a **reconnect
ladder** that is bounded but never gives up.

## 7.1 The resume token

A resume token is an opaque bearer string that a peer presents to resume a
session it held. The protocol does not define its format — that is the
deployment's, because the token is a statement about *its* sessions.

What the protocol requires of a token:

- it MUST be unforgeable by anyone who does not hold the session's
  identity;
- it MUST carry, or be bound to: the session, the peer that may resume it,
  and a **single-use generation**;
- the generation MUST advance on every use, so a replayed token is
  detectable and refused;
- it MUST expire, and the expiry MUST be enforced by the party that
  validates it.

A conforming implementation MUST validate the token, MUST refuse a replayed
one, and MUST return a typed reason when it refuses: `token_expired`,
`token_invalid`, `session_unknown`, `viewer_mismatch`, `epoch_stale`.

The bearer of the token — a browser, in the usual case — MUST treat it as
opaque: it MUST NOT parse it, MUST NOT construct one, and MUST NOT send
it anywhere but to the party that issued it.

**A deployment without tokens.** A deployment that cannot mint a token
still works: every reconnect starts a fresh session, which is degraded but
never dead. The protocol requires that this path exists, because a
deployment that cannot issue tokens must not be unable to serve at all.

## 7.2 Parking

Parking retains a session's state after its transport died, so that a peer
that comes back can resume it rather than start over.

Where the state is kept is the deployment's choice, but the protocol
requires that a parked session's *sender-side* state survives, because
that state is what makes the resume cheap: the pending set, the update id
counter, the chain epoch, the budget and pace, the pressed set, and the
path statistics.

| Where | State kept | TTL | Eviction metric |
|---|---|---|---|
| The session's owner | the session record: the peer's identity, the media session id, the lane's tokens, the last lane statistics, the lane mode | the resume TTL (900 s by default) | `park_evictions_total{reason="ttl"}` |
| The intermediary | the parked-session index: media session id → (the session it belongs to, the route to it, when it was parked) | `clamp(2 × outage_target + 60 s, 120 s, 900 s)` | `park_evictions_total{reason}` |
| The sender | the per-receiver session: the epoch, the pending set, the ring, the budget and pace, the prior, the pressed set, the path statistics, the update id counter | the same park TTL | `park_evictions_total{reason}` |
| The receiver | its content, the applied update id, the epoch, the input queue, the pressed set, the path statistics | in memory; it survives the socket | — |

**A parked session holds a plan.** Content production continues, and the
sender's emitted state advances, but nothing is sent to the parked peer.
Its pending set grows exactly by the cells it missed — which is how the
resume knows what to re-send.

A lane that names a parked session resumes it, and the park is consumed. A
lane that ends inside the resume grace keeps the park, so a peer that
re-registers does not cost its counterpart the session.

## 7.3 The resume sequence

```
receiver                    the session's owner            intermediary           sender
  |-- reconnect control ------>|                               |                     |
  |   handshake{resume_token} |                               |                     |
  |<-- handshake{resumed, session_id, lane_token} ----------|                     |
  |-- open media lane -------->|                               |                     |
  |   MediaHello{} + MediaResume{token, applied_update_id, epoch, ack_bitmap, pressed_*}  |
  |                               |-- connect{resume_token, media_session_id} -------->|
  |                               |                               |  attach to the parked session
  |                               |                               |  MediaResume ---------->|
  |                               |                               |<-- MediaResumeAck{pending_cells,
  |                               |                               |     pace, budget, plan_started}
  |<-- MediaHelloAck + MediaResumeAck ------------------------------------------------|
  |-- (the receiver continues: the same content, the same chain) ---------------------|
```

- If the resume is refused with `park_evicted`, the sender starts a fresh
  session for the same receiver: a new media session id, `chain_epoch++`,
  and one anchor plan. There is still no control-lane re-handshake.
- **Sequence continuity**: the `object_id` counter continues — it is the
  sender's own and is never reset by a resume; the update id continues per
  receiver; and the input sequence space continues, with
  `input_seq_next` in `MediaResume` as the deduplication boundary.
- A receiver that resumes MUST NOT clear its content. The honest
  degradation of a lost link is to keep showing what it has and mark it
  stale, not to go blank.

## 7.4 The reconnect ladder

```
attempt 0:  delay 0
delay_n   = clamp( max(500 ms, 1 × rtt_smoothed) × 2^(n-1), 500 ms, 30 000 ms ) + jitter(0..250 ms)
escalation: attempts 1-2  ⇒ retry the control lane
            attempt 3+   ⇒ also re-resolve the session (a fresh route, a fresh credential)
            attempt 6+   ⇒ the suspended state; the cadence is capped at 30 s; retries continue
terminal (⇒ failed, no retry): an authorization failure, the session's owner
            retired or revoked, an explicit disconnect, an unsupported protocol
            version, the park TTL expired twice in a row, an explicit operator action.
```

For any finite outage the peer reconnects. The T4 story of a 30 s outage
and five 10 s flaps needs at most six attempts — about 31 s of ladder time
at a 1 s base, and about 60 s worst case at a 2 s round-trip time, which is
why the park TTL's floor is 120 s.

The ladder never gives up on a *transport* failure. It gives up only on a
failure that retrying cannot fix, and it says so with a typed reason
rather than a silent stop.

## 7.5 Content production under degradation

A sender's content production is a deployment's business, but the protocol
constrains how it responds to a degraded link:

| Condition | Production | Encoding | Sending |
|---|---|---|---|
| ≥1 receiver live or parked | on | at the current budget; never paused by a stall | to live receivers only |
| No receiver, the park window not expired | on, at ≥1/s and the floor budget | idle objects, plus the pending cells of parked receivers | none; a parked receiver's pending set grows only |
| No receiver, the park window expired | off | none | none |
| The content source stalled (nothing for `max(10 s, 10 × capture_interval)`) | restart the source | none | none |
| The link is known-degraded (`loss > 5 %` or `pace < 64 kbps`) | on | P0 and P1 only; no speculative refresh | pacer-bound |
| The pace is at the floor and more than half the cells are pending | on | P0 only | pacer-bound; the receiver is told it is converging |

**A stall is a repair trigger and a metric — never a pause, and never a
reset.** A sender that stops producing because the link is slow has
converted a transport problem into a content problem.

## 7.6 The receiver's component lifecycle

A receiver's state MUST survive its transport. A reconnect re-attaches the
transport; it does not recreate the receiver, so the applied update id,
the content, and the receiver's own estimate of its staleness all survive.

Every recovery step MUST produce an observable state transition, and the
receiver's state machine MUST be checked against the same scenario corpus
as the sender's machines.
