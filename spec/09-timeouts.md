# 9. The timeout framework

Every absolute constant on the path becomes a rule of the form
`f(RTT_est, jitter_est, k)`, clamped to a floor — equal to the previous
literal, so a fast link does not regress — and to a ceiling, so a broken
estimator can neither hang a session nor spin.

Throughout this section: `RTT` is the smoothed round-trip time,
`J` is the jitter, and `RTT_min` is the window minimum.

**Stall detection is progress-based.** "No acknowledgement progress for
`3 × RTT + 250 ms` **and** no known-degraded link" starts a repair plan.
It never pauses content production, and it never triggers a reset.

## 9.1 The rule shapes

| Site | Rule |
|---|---|
| The lane's heartbeat | `clamp(3 × RTT, 2 s, 30 s)` |
| The lane's stream idle | `clamp(4 × HB + 2 × J, 15 s, 300 s)` |
| The lane's handshake | `clamp(2 × RTT + 2 s, 5 s, 60 s)` |
| The lane's connect | `clamp(2 × RTT + 1 s, 3 s, 30 s)` |
| The lane's reconnect | base `clamp(1 × RTT, 500 ms, 5 s)`, max `clamp(30 × RTT, 10 s, 60 s)`, full jitter, unlimited attempts |
| The lane's attach | `clamp(2 × RTT + 2 s, 5 s, 45 s)` from the dial to the first accepted inbound message |
| The session's idle | `clamp(2 × outage_target + 4 × RTT, 60 s, 300 s)` |
| The peer's heartbeat | `clamp(0.5 × session_idle, 5 s, 60 s)` and `< session_idle / 4` |
| The transport's idle | `≥ 2 × session_idle` — derived, never a literal |
| The park TTL | `clamp(2 × outage + 60 s, 120 s, 900 s)` |
| The resume grace | `2 × RTT + 2 s` |
| The assembly timeout | `3 × RTT + 500 ms` |
| The report cadence | `clamp(4 × RTT, 250 ms, 2 s)` — the **idle** cadence; a report goes out at once when it carries an input echo or a loss attribution (§6.2.1) |
| The prompt report | `clamp(RTT / 4, 25 ms, 250 ms)` — the shortest wait between two prompt reports (§6.2.1) |
| The lane handshake | `clamp(2 × RTT + 2 s, 5 s, 45 s)` |
| The session's idle at the edge | `clamp(2 × outage + 60 s, 120 s, 600 s)`; **any inbound byte resets it** |
| The keepalive | `clamp(3 × RTT, 5 s, 60 s)` |
| The stall and repair window | `clamp(3 × RTT + 250 ms, 500 ms, 8 s)` — a repair delay, never a reset trigger |
| The repair delay | stream `clamp(RTT + update_interval, 250 ms, 3 s)`; datagram `clamp(2 × RTT, 250 ms, 5 s)` |
| The probe's deadline | `2 × RTT + 250 ms` — the echo promise; a probe sent before the first round-trip measurement has no deadline |
| The idle object | `clamp(1 000 ms, 2 × RTT, 3 000 ms)` |
| The input deadline | `clamp(2 × RTT, 5 s, 30 s)` for the pressed-set heartbeat; the per-object deadline is a deployment's setting, 5 000 ms by default |
| The pointer-move dispatch | `clamp(RTT / 8, 16 ms, 100 ms)` — never send pointer moves faster than the link can carry them |
| The waiting-object timeout | `clamp(2 × RTT + 500 ms, 1 s, 10 s)` ⇒ request a repair plan |
| The datagram carrier's establishment | `clamp(2 × RTT + 1 s, 3 s, 30 s)`; its startup `clamp(10 × RTT, 10 s, 60 s)`; its negotiation `clamp(20 × RTT, 30 s, 120 s)`; its disconnect `clamp(4 × RTT, 4 s, 30 s)` |
| The audit tap's publish | `clamp(3 × RTT, 500 ms, 10 s)`, never awaited on a session path |

## 9.2 The arithmetic assertions

These are asserted at startup and by tests, for every tier:

- `session_idle ≥ 2 × outage + 4 × RTT`
- `park_ttl ≥ outage + max_reconnect_ladder_time`
- `edge_idle ≥ session_idle`
- `heartbeat × 4 ≤ session_idle`
- `repair_delay ≥ RTT`
- no intermediate hop's idle timeout is below the session's idle timeout

A deployment that cannot satisfy them has a session that will be torn down
by a timeout rather than by a decision, which is the failure mode the
framework exists to prevent.
