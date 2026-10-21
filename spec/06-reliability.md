# 6. Reliability architecture

The protocol's central claim is this: **a receiver is never given a state
it cannot verify, and a sender always knows what to re-send, under a rate it
measured.** Everything in this section exists to make that true.

## 6.1 The three loops

```
        ┌─────────────────────────── sender ───────────────────────────┐
        │  content ─▶ diff(E,C)  ─▶ per-receiver scheduler ─▶ encoder ─▶ sender ─▶ pacer
        │      ▲                        ▲                      │                    │
        │      │                        │                      ▼                    ▼
        │  emitted state E              │            per-receiver cell accounting   carrier
        │      ▲                        │                      ▲
        │      └──── ack window ────────┴──── feedback ◀────────┘
        └──────────────────────────────────────────────────────────────────────────┘
   loop 1 (per capture):    freshness — what changed now              → P2/P3 objects
   loop 2 (per receiver ack): convergence — what this receiver misses → P1 repair
   loop 3 (per report):     capacity — how fast may we send           → budget/pace/rate
```

## 6.2 Bandwidth estimator (normative)

The estimator turns what the receiver measured into what the sender may
send. It is a pure function of the reports it receives and the state it
keeps; it never reads a clock of its own and never assumes a link.

**Inputs.** `on_feedback(feedback, now)`, `on_hop_report(report, now)`,
`on_send(bytes, object_id, now)`, `on_probe_echo(echo, now)`,
`on_timeout(now)`.

**Output.** An estimate: `pace_bps`, `budget_bytes`, `max_object_bytes`,
`target_fps`, `mode`, `loss_ratio`, `rtt_ms`, `jitter_ms`.

### 6.2.1 Cadence

`report_interval_ms = clamp(4 × rtt_min_ms, 250, 2 000)` is the **idle**
cadence: the rate at which a receiver reports when it has nothing to say.
The hops report at the same cadence.

A report is **due at once** when the receiver holds a fact the sender cannot
wait for:

- an **input echo** — the acknowledgement names an input sequence the sender
  has not been told about (§5.2, annex N-1);
- a **loss attribution** — the receiver observed a gap in the update-id space
  since the last report (§5.2).

Everything else waits for the idle cadence.

**Why.** The acknowledgement's echo is the receiver's answer to the sender's
input, and the echo's promise (annex INV-8) bounds the whole echo at
`2 × RTT + 250 ms`. A report that waits for the cadence spends that budget
before the answer leaves: at T2 the cadence is 600 ms and the promise is
550 ms, and at T4 the cadence is 2 s. No link, however fast, meets the
promise behind a fixed wait, so the wait must not be fixed. The same wait
delays the answer to a probe, whose own deadline is `2 × RTT + 250 ms`
(§6.2.6), and the acknowledgement that tells the sender which of its cells
the receiver still misses.

**The prompt report is not a measurement.** The measurement window is the
idle cadence's: a report that closes the window carries the window's counters
and the window's length, and a report that goes out before the window closed
carries **no window at all** (`window_ms = 0`) and says so. The sender reads
a window-less report as an acknowledgement and a sign of life (§6.2.8) and
does not move its estimate on it: a goodput over an open window is whatever
the last burst carried, and a loss ratio over one lost object in three is a
third. The estimator's state machine advances on the reports that close a
window, and on those only.

**The bound.** The prompt report leaves as soon as the fact exists, and its
rate is bounded by `prompt_interval = clamp(rtt_min_ms / 4, 25, 250)`: one
report per new echo and per observed loss, and never more often than that.
The bound keeps three promises at once — the echo's budget (the wait is a
quarter of a round trip, so the whole echo stays inside
`2 × RTT + 250 ms`), the link's share (a report is a hundred bytes or so, so
the feedback class stays a small part of the budget even at the floor), and
the idle cadence's own purpose (a lane with nothing to say still reports at
`report_interval_ms`, and the prompt does not replace it — it is an extra
report, and the next window still closes on the cadence).

A receiver that has measured no round trip yet uses the floor of the prompt
interval, so the first prompt is never later than 25 ms after the fact
exists.

### 6.2.2 Measurements

- The round-trip samples are the **sender's own**: each probe echo answers one
  of the sender's probes, and the sample is `now − SEND_EPOCH_MS` on the
  sender's own clock (§6.2.6). The receiver's reported round trip is a
  second view of the same path, measured on the receiver's clock and at most
  one probe interval old; it is compared with the sender's own and the
  disagreement is counted, never mixed into the filters. A minimum, an EWMA
  and their difference are only meaningful when every sample is the same
  measurement taken on one clock.
- `goodput_bps = received_bytes × 8 000 / window_ms` — the receiver's
  reported payload bytes only.
- `delivered_ratio = received_objects / (received_objects + lost_objects)`,
  and `loss_ratio = 1 − delivered_ratio`, from gap detection on the
  **update-id** space (§5.2). The update id is the protocol's identity of a
  media update, and it is monotone per receiver, so a gap in it is a media
  update the receiver never saw. The object id cannot carry that meaning:
  its space is per sender (§5.1.1), and a lane carries objects from several
  senders — the media sender and the intermediaries that originate their own
  objects — so a gap in it is an intermediary's object arriving, not a loss.
  A lane's writer drains strictly by priority (D-3), so a media update may
  overtake an older one on the wire: the expectation is one past the highest
  update id seen, an id at or below the highest is **reordered** and not
  lost, and a reordered update never lowers the expectation.
- `rtt_min` is the minimum over a 60 s horizon; `rtt_ewma` is
  `EWMA(α = 1/8)`; `jitter` is `EWMA(|rtt_sample − rtt_ewma|, α = 1/4)`.
- `queue_delay = rtt_ewma − rtt_min` — the delay-based congestion signal.

### 6.2.3 The max-filter with decay

```
on_report:
  if capacity_limited and (loss_ratio > 0.02 or
                           queue_delay > max(50 ms, 0.5 × rtt_min)):
      btlbw = 0.85 × btlbw        # decay: the link is telling us something
  btlbw = max(btlbw, min(goodput_bps, ceiling_bps))
```

A window is **capacity-limited** when the sender sent at (or above) its own
pace during it. A window the sender did not fill was application-limited:
the link was never asked to carry more, so the window carries no capacity
signal and the estimate stands. Without that condition a quiet lane ratchets
its own estimate down — a window with two objects in it reports the loss of
one of them as fifty percent, and the sender concludes that a link it never
used is a slow one.

### 6.2.4 The state machine

| state | entered when | pace | exits when |
|---|---|---|---|
| `StartUp` | session start | `2 × pace`, doubling per report while `loss < 0.01` and `goodput ≥ 0.9 × pace` | after 4 reports, or the first loss, or a report below `0.9 × pace` |
| `Steady` | leaving `StartUp` | `0.9 × btlbw` | `loss > 0.05` or `queue_delay > 1 × rtt_min` |
| `Degraded` | `loss > 0.05` or `queue_delay > 1 × rtt_min` | `0.7 × pace` per report, floored at `pace_floor` | 3 consecutive reports with `loss < 0.01` **and** `queue_delay < 0.5 × rtt_min` ⇒ `StartUp` |
| `Floor` | `pace < pace_floor` | `pace_floor` (8 kbps), with media disabled except P0 and the idle heartbeat | reports resume ⇒ `StartUp` |

The pace is clamped to `[pace_floor (8 000), min(ceiling_bps, 50 000 000)]`.

The `0.7 ×` decay of the degraded state applies to capacity-limited windows
only (§6.2.3): a window the sender did not fill says nothing about the
link's capacity, and a link that keeps delivering must not be ratcheted
below what it demonstrably carries.

### 6.2.5 The budgets

```
budget_bytes     = clamp((pace_bps / 8) × update_interval_ms / 1000, 256, 1 048 576)
max_object_bytes = clamp((pace_bps / 8) × max(0.5 s, rtt_min), 1 024, 524 288)
target_fps       = clamp(requested_fps, 0.5, 30)
update_interval_ms = 1000 / target_fps
```

`max_object_bytes` is bounded by roughly one round-trip time of airtime: an
object larger than that cannot be delivered before the sender must decide
what to do about it.

`requested_fps` starts at 30 and the scheduler reduces it when
`budget_bytes < min_delta_bytes (8 192 B)`:
`target_fps = max(0.5, 30 × budget_bytes / 8 192)`, floored at 1 while any
receiver is live — an idle object at ≥1/s keeps the acknowledgement timeline
alive.

### 6.2.6 Probes

A probe is how the sender measures a link the receiver's
reports do not describe. It is triggered in `Steady` **and in `Degraded`**
when `demand_bps > pace_bps` for `max(3 × rtt_min, 1 s)`, or every 30 s. A
degraded estimator needs the measurement most: with the probe reserved for
the steady state, an estimator that fell into `Degraded` could never find
out that the link carries more than it is sending, and the state would be
a one-way ratchet down.

The probe is a feedback-class object with
`payload_bytes = min(8 192, 0.25 × pace_bps/8)`, sent at
`min(1.25 × btlbw, 1.25 × pace)` with `ECHO_REQUESTED`. It carries
`SEND_EPOCH_MS` — the sender's session-relative ms at emission — and the
peer quotes that epoch verbatim in its echo. The round trip is therefore
`now − SEND_EPOCH_MS` on the sender's own clock: one clock, one
measurement, and no assumption that the two ends' session clocks agree.

A delivered probe raises `btlbw` to `max(btlbw, probe_rate ×
delivered_ratio / 1.25)`; a probe whose echo did not come back within
`2 × RTT + 250 ms` (§9.1) multiplies `btlbw` by 0.9 and is counted. A probe
sent before the sender measured a round trip has no deadline: its answer
*is* the measurement, and a link that has never answered anything is the
no-feedback case, not a lost probe. A probe never carries content and is
never counted into `budget_bytes`.

**The probe confirms the rate it tested, not the step it was paced at.**
The probe is offered at `min(1.25 × btlbw, 1.25 × pace)` — a *step above*
the estimate — so what a delivered probe proves is that the link carried
the step, and the estimate it may be raised to is the step's **base**: the
rate the probe tested. Raising the estimate to the step itself would
ratchet it by the probe's own headroom every time a probe came back, and a
healthy link would climb to the ceiling on its own. The estimate grows
through the goodput (§6.2.3), which is a measurement of what the link
actually delivered.

**The receiver probes too.** The round trip a receiver reports is its own
measurement, taken with its own probe; a receiver that has not measured
one has no figure to report, and the sender does not read the report's
figure as a measurement in any case (§6.2.2).

### 6.2.7 Priors

A sender MAY remember the rate a receiver's link sustained and
start a new session at `pace_0 = clamp(remembered_bps / 4, pace_floor,
2 Mbps)`. With no prior, `pace_0 = pace_floor` and `StartUp` doubles per
round-trip time, so a cold start on a T4 link costs ≈ 3 RTT (≈ 6 s) before
the rate is useful. That is why the first object is always an anchor plan
at the floor rate: the receiver gets something honest immediately.

### 6.2.8 Missing feedback

If no **sign of life** arrives for `3 × report_interval + 2 s`, the mode
becomes `NoFeedback`, the pace drops to `pace_floor × 2`, `target_fps` to
1, `max_object_bytes` to 1 024, and only P0 and P1 objects are scheduled.
One sign of life clears it. The stall is counted.

**A sign of life is any object the peer sends: a report, an
acknowledgement, or the echo of a probe this sender sent.** A report is the
estimator's *measurement*; the proof that the lane is alive is the traffic
itself. Class C4 is "reliable within a reporting window" (§3.1) and the loss
of one report is harmless, so a lane whose acknowledgements keep arriving is
a live lane whose measurement is late — not a dead one. A grace that only a
report can move is a grace a single lost report resets to its floor, and
the link then looks dead while it is merely quiet.

The grace is a function of the **last known** round trip (§6.2.2) with a
floor: a link that has measured a round trip keeps the grace that
measurement earned, and a link that has never answered one gets the floor.
Every sign of life extends the grace; the grace's own expiry never shortens
it.

**A cap that dropped takes the objects it forbids with it.** The cap is
the sender's own bound on what one object may carry, so an object the
sender admitted under the old cap is still an object the current cap
forbids: the sender drops it and counts it rather than putting it on the
wire. Its cells stay pending, and the repair plan covers them (§6.5.3,
§6.6).

### 6.2.9 Hop attribution

**The attribution is made in the update-id space.** The receiver's
`lost_objects` counts the media updates it never saw (§5.2), and a hop's
report names the media objects it discarded — a discarded object is one part
of one media update, and it is the content of an update the receiver never
saw. The two account for the same losses, and the attribution subtracts one
from the other.

The receiver's `loss_ratio` minus the sum of the
hops' reported `objects_dropped` is the unattributed loss — the number that
answers "is it the last mile, or is it us?".

## 6.3 The scheduler

### 6.3.1 The priorities

| priority | source | budget share |
|---|---|---|
| P0 | the input-pulse region (the bounding box of the last input, plus a focus region maintained from the input), and cells pending longer than `2 × repair_delay` | ≥ 50 % of the budget |
| P1 | pending cells (sent, unacknowledged, due) | next |
| P2 | fresh changes | next |
| P3 | background refresh (cells never sent this epoch, and a slow scan of the rest to bound drift) | the remainder |

### 6.3.2 Update construction

Per capture cycle the sender computes the changed
cells once and shares them. Per receiver, the due set is the union of the
changed cells and that receiver's pending cells, ordered by (priority, cell
index) and truncated to `budget_bytes` and `max_object_bytes`.

### 6.3.3 Emission

The sender's emitted state `E` advances exactly at the cells
an emitted object carried, and the receiver's pending set gains those cells
with the time they were sent and the update they were sent in. The update
id increments per receiver; `update_base` is the last update id the
receiver **confirmed** — its last applied update id, as the
acknowledgement reports it (§5.2). The sender never chains onto an update
the receiver has not confirmed: an unconfirmed update may never have been
applied, and a delta that extends an update the receiver does not hold
would be refused. `flags.ANCHOR` is set whenever the sender knows the
receiver cannot chain — a gap, a resume, an epoch change, or anything it
sent that is still unacknowledged — and an anchor applies onto any held
state (§5.1), so it is the frame that heals a broken chain.

### 6.3.4 Fragmentation

`parts = ceil(payload_bytes / min(MAX_CHUNK_WIRE_BYTES,
budget_bytes, path_chunk_cap))`, and `parts ≤ max_chunks_per_frame`, which
is 8 on a stream carrier, 1 when `loss_ratio > 0.05`, and 4 otherwise. If
the content exceeds the budget, the sender produces several objects rather
than one oversized one.

### 6.3.5 The input pulse

When an input is applied for a receiver, the sender marks
the P0 region and schedules an immediate object, bypassing the update
timer, with
`budget = min(budget_bytes, max(1 024, pace_bps/8 × 0.25 s))` and
`target_fps` temporarily raised to
`input_pulse_fps = min(30, max(4, target_fps × 2))` for
`input_pulse_window = max(300 ms, 1 × RTT)`. The pulse carries
`REFLECTS_INPUT_SEQ`. The pacer still enforces the pace, so a pulse can
delay — but it can never violate the rate.

## 6.4 Pacing (normative)

### 6.4.1 The token bucket

Each lane has one token bucket per direction:

- `capacity = max(2 × max_object_bytes, (pace_bps/8) × 20 ms)`;
- refill at `pace_bps/8` bytes per second, plus the reserved rate for the
  non-media classes;
- the release unit is one fragment. On a stream carrier the pacer releases
  up to `min(64 KiB, tokens)` per tick; on a datagram carrier it releases
  exactly one fragment per tick, spaced by the token rate.

### 6.4.2 The transport is never filled

The pacer holds the queue, and the writer
may not hand the carrier more than `2 × max_object_bytes` beyond what the
carrier has accepted. Queue contents are reclaimable: when a new plan
supersedes a queued object, the object is dropped with
`superseded_by_plan`.

The reserved rate is `max(2 000, 0.10 × pace_bps)` bits per second. The
non-media classes may borrow from the media tokens; the reverse never
happens.

An **idle object** — an empty update, `update_bytes = 0`, chained onto the
current surface — is emitted at most once per
`IDLE_FRAME_INTERVAL_MS = clamp(1 000 ms, 2 × RTT, 3 000 ms)`. It keeps
the acknowledgement timeline and the lane alive, and it costs about 60
bytes.

## 6.5 Per-receiver convergence accounting (normative)

This is how a sender knows what to re-send.

### 6.5.1 The grid

`cell_size` is the smallest power of two at least
`sqrt(cells / 2048)`, clamped to `[32, 256]`; the grid has
`ceil(width / cell_size) × ceil(height / cell_size)` cells, at most 2048.
The grid is the sender's *repair* grid: the unit the protocol accounts
for. What a cell contains is the codec's business.

### 6.5.2 The state

Per receiver: the pending cells (each with the update they
were sent in and the time), the acknowledged window, the last applied
update id, and the chain epoch.

The acknowledged window is the 64-bit bitmap of §5.2: bit `i` names the
update `highest − i`. It slides one id at a time, it holds the last 64
ids, an update that fell out of it is no longer marked, and a jump of 64
ids or more leaves it holding the new update alone. The window is what
the receiver *holds*; the chain epoch (§5.1) is how much of it the
receiver still believes, and the two move independently.

### 6.5.3 Acknowledgement processing

On an acknowledgement, every cell of every
applied update is cleared from the pending set. A cell that was sent but
not acknowledged stays pending until `repair_delay` passes, at which point
it becomes due (P1).

The mapping from updates to cells is kept in a ring of
`ACK_RING = max(64, ceil(2 × RTT_MS / update_interval_ms) + 8)` updates
per receiver. If an acknowledgement arrives for an update that fell out of
the ring, the sender conservatively marks every cell emitted after the last
acknowledged update as due — correct at the cost of re-sending, and
counted.

**The epoch moves forward only.** The chain epoch belongs to the sender
(§5.1): the sender raises it when it breaks the chain, and a receiver
adopts a greater one. An acknowledgement that names an epoch **older**
than the sender's is a stale acknowledgement — the receiver has not seen
the break yet — and the sender counts it and leaves its epoch alone.
Adopting it would reset the applied-update watermark and re-mark every
emitted cell due: a re-send storm for a chain the receiver still holds.
An acknowledgement that names a **greater** epoch is the receiver
reporting a break the sender did not make, and the sender adopts it and
starts an anchor plan, as §5.1 says.

### 6.5.4 The repair delay

`repair_delay = clamp(2 × rtt_ewma, 250 ms, 5 s)` on a
datagram carrier and `clamp(rtt_ewma + update_interval_ms, 250 ms, 3 s)` on
a stream carrier. A cell that passes the repair delay more than
`repair_max_rounds = 4` times is escalated to P0; a cell still due after
`2 × repair_delay` is counted as stuck and included in the next anchor
plan.

### 6.5.5 Convergence

A receiver has converged when its pending set is empty and
the last applied update id equals the last update sent to it. Both are
exported (§10). This is the operational form of N-2.

### 6.5.6 Many receivers

The grid is shared; the pending set is per receiver. A
receiver on a slow link never slows a receiver on a fast one. The number
of concurrent receivers per sender is bounded; beyond it, a new receiver is
refused with a typed `no_host_capability`.

## 6.6 Anchors and repair plans (normative)

An **anchor** is an object whose content is absolute: it may be applied
onto any held state. A **plan** is a sender-side schedule of anchor
objects, each covering a contiguous band of the plan's cell list, each
within the current budget.

A plan starts when:

1. a receiver's pending set exceeds `anchor_threshold = max(16, cells / 4)`;
2. the chain epoch does not match on resume;
3. a cell is stuck after the escalation ladder;
4. the surface changed shape (a new grid; `chain_epoch++`; the receiver
   resizes on the first anchor object with the new shape).

Plans are rate-limited to one per `RESET_MIN_INTERVAL_MS` (250 ms) per
receiver, never globally. A plan that cannot finish within
`plan_deadline = 2 × RTT + 30 s` is reported as overdue and restarted with
the newest cell set: on a collapsing link, freshness beats completeness.

**Why a plan rather than a reset.** A reset is full-coverage by definition;
on a 32 kbps link no budget makes it timely, and it remains the only object
that can lose a receiver's whole progress. A plan re-sends the cells the
receiver is missing, band by band, at the current rate, and every band is
an improvement rather than a wager.

## 6.7 Playout and honest degradation

- **No presentation delay at T3/T4**: freshness wins. At T0–T2 the
  receiver keeps a de-jitter queue of depth
  `max(1, ceil(jitter_ms / update_interval_ms))` objects, capped at 3; an
  object that arrives after its slot is applied immediately and the drop is
  counted, not hidden.
- **Skip-ahead**: a receiver never applies an object older than the newest
  ready one by more than one update interval.
- **Decode budget**: the receiver reports its decode time; when it exceeds
  half an update interval, the sender clamps `target_fps` accordingly and
  marks the lane `DECODE_BOUND`.
- **Honest states**: the lane's state (§5.3) says what is happening. A
  frozen picture with the "has content" flag still set is explicitly not a
  state.

## 6.8 Carrier selection and hysteresis

A receiver MAY be served over a datagram carrier when one is available.
Promotion to a datagram carrier requires all of:

- the carrier's connection is established;
- the media channel is open;
- a probe window of `2 × rtt_min` has passed with
  `delivered_ratio ≥ 0.5`.

**Promotion** happens when the datagram carrier's goodput is at least
`1.2 ×` the stream carrier's, sustained for `3 × rtt_min`.

**Demotion** happens when the datagram carrier's goodput falls below
`0.8 ×` the stream carrier's for `3 × rtt_min`, when the channel closes, or
when a probe window shows `delivered_ratio < 0.2`.

A switch costs one round-trip time: both carriers stay open during the
switch, the lane announces `MediaPathChange`, and the update chain
continues. The carrier is transparent to the content.

**Sticky once**: after three demotions in ten minutes, the datagram
carrier is disabled for the session and the oscillation is counted.

A switch MUST NOT happen during an anchor plan or an input pulse.
