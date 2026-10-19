# 2. Target envelope (normative)

The protocol is designed against a range of links, from a local network to a
lossy long-haul radio link. This section states that range as tiers, so
every other number in this document has an envelope it belongs to.

## 2.1 Tiers

| Tier | Down / up | RTT | Loss | Jitter | Outage | Usable means |
|---|---|---|---|---|---|---|
| **T0 LAN** | ≥100 Mbps / ≥10 Mbps | ≤10 ms | 0 % | ≤2 ms | none | 30 fps of updates; an anchor visible <100 ms; zero dropped objects; full content fidelity |
| **T1 Broadband** | ≥5 Mbps / ≥1 Mbps | 50 ms | ≤0.1 % | ≤10 ms | ≤5 s | echo ≤ 2×RTT+250 ms (≈350 ms); pending cells → 0 ≤1 s after motion stops; no session loss |
| **T2 Poor Wi-Fi / hotspot** | ≥1 Mbps / ≥256 kbps | 150 ms | ≤2 % | ≤40 ms | ≤5 s | 8–15 effective fps; echo ≤ 2×RTT+250 ms (≈550 ms); a scroll converges ≤3 s; ≤1 repair plan per 2 s; no session loss |
| **T3 Long-haul / degraded** | 256–512 kbps / ≥128 kbps | 400 ms | 5–10 % | ≤100 ms | ≤10 s | 2–5 fps of updates; echo ≤ 2×RTT+250 ms (≈1.05 s); a full-surface change completes ≤8 s (progressive anchors, pending cells monotone to 0); a session survives |
| **T4 Extreme** | 32–64 kbps / ≥32 kbps | 800–2000 ms | 20–50 % | 250–1000 ms | ≤30 s and 5× (10 s down / 10 s up) | text-first: ≥1 fps; echo ≤ 2×RTT+250 ms (≤4.25 s); no session loss and no operator action across the outage/flap pattern; convergence within 2×RTT + 30 s of link restoration |

## 2.2 Refinements

These four properties sharpen the tiers. They are the protocol's
distinguishing claims, and each is measurable.

- **N-1 (measurable echo).** The sender stamps each update with
  `reflects_input_seq` — the highest input sequence whose effect the
  update's content includes — and the receiver computes
  `echo_ms = render_time − send_time(input_seq)`. The tiers are asserted on
  the echo series' p95.

- **N-2 (convergence is a set, not a feeling).** "Eventually consistent" is
  operationalized as `pending_cells(V) = ∅` plus
  `applied_update_id == last_sent_update_id(V)`. Both are exported. No
  requirement in this document is phrased with "looks right".

- **N-3 (the T4 floor is text-first, and a stream carrier may not sustain
  it).** At 20–50 % loss the goodput a stream carrier achieves may fall
  below 32 kbps. The properties that are structural — continuity, input,
  honest state, repair — are guaranteed on every carrier; the T4 goodput
  floor is *measured and reported* on a stream carrier and guaranteed on a
  datagram carrier (§6.8).

- **N-4 (outage budget arithmetic).** Every idle or watchdog timeout on the
  live path exceeds the outage target with margin, and the continuity
  machinery bounds recovery rather than the timeout:
  `idle_timeout ≥ 2 × outage_target + 4 × RTT` (T4's 30 s ⇒ ≥ 68 s at 2 s
  RTT). The arithmetic is asserted at startup and by tests.

## 2.3 What a stream carrier guarantees versus what a datagram carrier adds

| Property | Stream carrier | Datagram carrier |
|---|---|---|
| A session survives a 30 s outage / 5× flapping, with no operator action | **guaranteed** | guaranteed |
| Input: no stuck keys, deadline-bounded, deduplicated, prioritised | **guaranteed** | guaranteed |
| Honest state and observable attribution | **guaranteed** | guaranteed |
| No reset on reconnect; per-receiver convergence | **guaranteed** | guaranteed |
| T0–T3 stories | **guaranteed** | guaranteed |
| T4 ≥1 fps text-first at 20–50 % loss | measured; may fall below 32 kbps effective | **guaranteed** (loss-tolerant carrier) |
| T4 echo ≤ 4.25 s at 2 s RTT | measured | guaranteed |

Both are live behaviours rather than a plan: a session's carrier is selected
per receiver by the measurement-driven selector of §6.8, and the stream
carrier is always able to carry the session.

## 2.4 What an implementation may assume

A conforming implementation MUST behave correctly at every tier, and MUST
NOT assume a tier in advance: the estimator of §6.2 discovers the link, and
every timeout in this document is a function of the round-trip time it
measured.
