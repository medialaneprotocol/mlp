# 5. Class bodies

The fragment header and the TLV registry are not protobuf: they are the
byte-level grammar of §4. This section covers the *bodies* — the
class-specific payloads a peer may need to decode.

The bodies are defined in [`mlp-proto`](https://github.com/medialaneprotocol/mlp-proto)
under the package `mlp.v1`. This section states their semantics; the schema
is the normative field list.

## 5.1 Class MEDIA (C3) — opaque

The `MEDIA` class carries **opaque bytes**. The protocol does not define
their content, does not validate them, and does not look inside them. A
codec defines them.

This is deliberate, and it is the protocol's central design decision
(§1.3): the transport must be able to move content it does not understand,
and it must be able to account for that content without interpreting it.

What the protocol does with a `MEDIA` object:

- it fragments it across the carrier (§4.2) and reassembles it (§4.4);
- it paces it, coalesces it, and bounds it (§6.3, §6.4);
- it accounts for it against the receiver's repair grid (§6.5).

What a codec does with it: everything else.

**Update → fragment mapping.** A sender serializes one update into an
opaque body and hands it to the protocol with the meta of §4.3
(`update_id`, `update_base`, `part_index`, `part_count`, `update_bytes`,
`chain_epoch`, `reflects_input_seq`, `priority`). The protocol segments the
body into `ceil(len / fragment_payload_max)` fragments;
`fragment_payload_max` is 65 536 on a stream carrier and 1 150 on a
datagram carrier. Only the last fragment carries `FIN`.

On a datagram carrier a body must never need segmentation
(`fragment_count == 1`): the codec is required to produce a body within
the carrier's cap. A violation is a **sender invariant breach**: it is
counted as an oversize object and dropped rather than sent, because a
datagram carrier cannot carry it and a partial object must never be
assembled from a re-cut body.

**The application rules.** Three rules in the header govern how a receiver
applies a `MEDIA` object. They are the protocol's, not a codec's, because
they are about *the receiver's state* rather than about content:

- **`flags.ANCHOR`** — the object's content is absolute: it may be applied
  onto **any** held state. A receiver that does not hold the named base
  applies it anyway and reports the gap in its acknowledgement. The
  sender's per-receiver accounting is what makes this safe: it knows which
  cells it sent in objects the receiver did not apply, and re-sends them
  (§6.6).

- **`flags.DUP`** — the object is a deliberate duplicate. A receiver that
  already applied the object named by `ECHO_OF_OBJECT_ID` MUST NOT apply
  it twice. Application is idempotent by `object_id` and by
  `(update_id, part_index)`.

- **`CHAIN_EPOCH`** (TLV `0x05`) — a monotone u32 per media session,
  incremented by the sender when it breaks the chain: the surface changed
  shape, the sender's history was lost, or the receiver's cells were
  reset. A receiver that sees an epoch greater than its own resets its
  *trust* in the surface to "all stale" — it does not clear the content,
  because the honest degradation is to keep showing what it has and mark
  it — reports the epoch in its next acknowledgement, and the sender
  starts an anchor plan. Epochs are never compared across media sessions.

  The epoch does not touch the receiver's **applied-update window** (§6.5.2):
  an epoch is not an update, and the updates the receiver applied are still
  applied. The window says what the receiver holds, and the trust says how
  much of it the receiver still believes.

  **The epoch is the sender's, and it only moves forward.** A receiver
  adopts a *greater* epoch and never a smaller one. An acknowledgement
  that names an epoch **older** than the sender's is a stale
  acknowledgement — the receiver has not seen the break yet — and the
  sender MUST NOT obey it: moving the epoch back would reset the
  sender's applied-update watermark and re-mark every emitted cell due,
  which is a re-send storm for a chain the receiver still holds. The
  sender counts the stale acknowledgement and leaves its epoch alone
  (§6.5.3).

### 5.1.1 The identities (normative)

A lane carries objects from **several senders**: the media sender, and the
intermediaries that originate their own objects (a hop report, a lane
error, a close). Each of them numbers its own objects. The protocol
therefore has two identities, and they mean different things:

| identity | space | what it identifies | what it must not be read as |
|---|---|---|---|
| `object_id` (header) | monotone per (lane, direction, sender epoch) — **per sender** | one object, for deduplication (§4.4) and for `ECHO_OF_OBJECT_ID` | a loss signal: the space is per sender, so a gap in it is not a lost object |
| `UPDATE_ID` (TLV `0x01`) | monotone per (lane, direction, receiver) — the media sender's own | one media update, for the acknowledgement window (§5.2), the repair accounting (§6.5) and the loss accounting (§5.2) | a codec's private counter |

**The acknowledgement credits the protocol's update id.** A receiver's
applied-update window, the `highest_applied_update_id` it reports, and
the loss it reports are all in the **update-id** space, because that is
the space the sender numbers its media in and the only space in which a
gap means "the peer never saw this".

A codec's body MAY carry its own update id, and it MUST mirror the
protocol's: a body whose id disagrees with the TLV is the `META_MISMATCH`
of §4.3. An application that drives a receiver therefore uses the
protocol's update id, and the body's id is the codec's own bookkeeping.

**The part index is the transport's.** `PART` (TLV `0x03`) names the
part within its update, `0..part_count-1`; a codec's body mirrors it the
same way the update id is mirrored. The idempotence record of §5.1 is
therefore keyed by the protocol's `(update_id, part_index)`.

**The chain epoch is the sender's**, as §5.1 says: it is raised by the
sender, adopted by a receiver only when it is greater, and never moved
backwards by an acknowledgement.

Everything else — the validation order, the atomicity, the
acknowledge-on-apply rule — belongs to the codec, and the codec's
specification owns it.

## 5.2 Class CURSOR (C2) and class FEEDBACK (C4)

`MediaCursor` is unordered, latest-wins, and never retransmitted. It
carries a position, a visibility flag, a shape generation, the sender's
session-relative time, and optionally the shape itself.

Validation: `shape_rgba.len() <= 8192` ⇒ else `BODY_INVALID`. A position
outside the current surface is **clamped, not rejected** — a pointer
outside the surface is normal during a geometry change. Cursor objects are
never fragmented: `fragment_count == 1` and the payload is within the
carrier's cap; the shape is sent only when it fits, and a receiver that
cannot use it keeps its local shape.

`MediaAck` is the receiver's acknowledgement: the highest update it
applied, a 64-bit window of which updates around it were applied, the
chain epoch it is on, its repair-grid size, its own count of cells it
believes stale, and whether it believes it has converged.

**The window.** Bit `i` of `ack_bitmap` names the update
`highest_applied_update_id − i`, for `i` in `0..64`. The window is 64
updates wide, and it is a `uint64`: a receiver that reports fewer bits
than the field holds is a different receiver, because the sender reads
the missing bits as "not applied" and re-sends cells the receiver
already holds.

**The update ids.** The update ids start at 1. A window that names an
update id of 0 names an update that does not exist, so a set bit `i`
MUST satisfy `i < highest_applied_update_id`; the peer refuses the
acknowledgement otherwise (`ACK_BAD_BITMAP`). A receiver that is told
about the update id 0 records it as it was told — the window says what
the receiver was told, and the id 0 is not an update the receiver can
report as applied.

**The belief.** `converged` is the receiver's own belief about the
surface, and it is reported as the receiver holds it; the sender's
accounting is the authoritative one (§6.5.5). The same is true of
`applied_cell_count` and `stale_cells`: they are the receiver's numbers.
The peer refuses an acknowledgement whose stale count exceeds its
applied count (`ACK_BAD_COUNT`).

**The echo.** `echo_of_input_seq` is the highest input sequence
*visible in the applied cells*, and it is the receiver's own report: the
receiver's application says what its content reflects, and the report is
taken as it comes — a rebase drops the content that reflected the older
input. The sender's stamp on an update (TLV `0x06`, §5.1) is the
sender's claim about that update, and it is what the receiver computes
the echo *from* (annex N, N-1); it is not the applied content's echo.

A new echo is a fact the sender cannot wait for: the report that names it
goes out at once, not at the idle cadence (§6.2.1).

Validation: bits above `highest_applied_update_id` MUST be 0 ⇒
`ACK_BAD_BITMAP`; `stale_cells <= applied_cell_count` ⇒ `ACK_BAD_COUNT`.

`MediaFeedback` is the receiver's only quality channel: its measured round-
trip time, the running minimum, the jitter, the bytes and objects it
received, the gaps, duplicates and reorderings it saw, the window those
counters cover, the acknowledgement, the probe echoes, its own outbound
backlog, its measured frame rate and render times, its input queue depth
and input counters, its path switches, the active carrier, and an
application identifier for diagnostics.

**The window may be open.** A report that goes out before its measurement
window closed carries no window at all (`window_ms = 0`): it is an
acknowledgement and a sign of life, not a measurement, and the sender reads
it as such (§6.2.1). The report that closes the window carries the
window's counters and the window's length.

**The gaps are the gaps in the update-id space.** The `lost_objects` a
receiver reports is the number of media updates it never saw, counted in
the **update-id** sequence of §5.1.1 — the space the media sender numbers
its updates in, and the only space in which a gap is a lost update. The
object-id sequence is **not** that space: it is per sender (§5.1.1), so a
gap in it is an intermediary's own object arriving, not a loss. A
receiver that reports the object-id gap instead reports billions of lost
objects the moment an intermediary originates an object, and the sender's
estimator then pins itself at its floor on a clean link.

`received_objects` counts the objects the receiver received, and
`duplicated_objects` counts the ones it saw twice, in the object-id
space: the duplicate is a property of one sender's stream.

`MediaHopReport` is what an intermediary reports: how many objects and
bytes it discarded in the window, how many it coalesced, its queue depths,
the window, its own round-trip time to the next hop, and the total time
its writer waited on capacity.

A hop that cannot produce a report — no clock, no data — sends none. The
sender then attributes the window to an unknown hop and counts it.

`MediaProbe` is a path probe: it never carries content. It carries the
sender's session-relative epoch in `SEND_EPOCH_MS`, and the peer quotes that
epoch verbatim in its echo — the round trip is then measured on the
sender's own clock, with no wall clock and no assumption that the two ends'
session clocks agree.

**The echo names the object it answers.** The answer to an object sent
with `ECHO_REQUESTED` carries the answered object's `object_id` in
`ECHO_OF_OBJECT_ID` (§4.3) and the prober's epoch verbatim in
`SEND_EPOCH_MS`. That object id is the whole correlation: a probe's own
`probe_id` is a body field, and a body field is not an identity — a peer
that correlates by it cannot recognise the answer to its own probe when
the two counters differ, and a probe's counter is the prober's own space,
not the lane's.

The echo is an object of its own, so a hop that never decodes a body —
every hop in this protocol forwards objects byte for byte — can match the
answer to the probe it sent and measure its own round trip. A peer that
carries the echo inside a report's `probes` field carries the same object
id there; the field and the TLV are one fact in two carriers, and the TLV
is the one a hop can read.

## 5.3 Class CONTROL (C0) and class PATH (C5)

`MediaControlObject` is the oneof wrapper of the control class:

| body | meaning |
|---|---|
| `MediaHello` | the first object a media lane sends |
| `MediaHelloAck` | the answer: the lane is admitted, with the negotiated parameters |
| `MediaResume` | what the receiver held when the lane died |
| `MediaResumeAck` | the answer: the lane resumed, with the sender's next parameters |
| `MediaLaneState` | the sender's authoritative lane state |
| `MediaAnchorPlan` | the announcement of a repair plan |
| `MediaClose` | the teardown, with a "come back" signal |
| `MediaError` | a typed protocol error |
| `MediaPathChange` | the carrier changed; the update chain continues |

`MediaHello` carries the protocol version, the media session id (empty for
a fresh session), the control-lane session id, the sender's fragment
payload cap, its repair grid, the capabilities it offers, its maximum
update rate, and its start time.

`MediaHelloAck` mirrors it, and adds the assigned media session id, the
accepted fragment payload (the minimum of the two sides' caps), the
negotiated grid, the resume time-to-live, and — when the lane is refused —
a typed reason: `protocol`, `disabled_by_policy`, or `no_sender_capability`.

`MediaResume` carries the opaque resume token, the update the receiver
applied, the chain epoch, the acknowledgement window, the receiver's next
input sequence (the deduplication boundary), the keys and buttons it
currently holds, the active carrier, and a negotiation id when the
receiver renegotiated.

`MediaResumeAck` says whether the resume was accepted and why not
(`ok`, `unknown_session`, `token_expired`, `token_invalid`,
`peer_mismatch`, `epoch_stale`, `epoch_mismatch`, `park_evicted`), the
update id the sender will use next, how many cells it will re-send, the
pace, the budget, the target rate, and whether the resume had to start a
plan.

`MediaLaneState` is the sender's authoritative state: `STARTING`, `LIVE`,
`DEGRADED`, `CONVERGING`, `STALE`, `PARKED`, `DISABLED`, `DECODE_BOUND`,
`NO_FEEDBACK`, `MEDIA_UNSUPPORTED`.

`MediaClose` carries a code — `normal`, `server_shutdown`, `policy`,
`superseded`, `park` — and a `park` flag that is the "come back" signal:
the receiver MUST NOT treat it as a failure.

`MediaError` carries a code from the protocol's error vocabulary (§10) and
the object it concerns.

`MediaPathChange` says the carrier changed and why. The update chain
continues across the change: the carrier is transparent to the content.

## 5.4 Class INPUT (C1)

The input path's object is `MediaInputEnvelope`: a monotone sequence
number, an absolute session-relative deadline, a kind, flags, and the
input's own serialized payload.

`kind` and `flags` are transport-level, so every hop can coalesce or drop
an input object without decoding the payload. The kinds are
`pointer_move`, `pointer_button`, `key`, `wheel`, `clipboard`,
`release_all`, `pressed_set`; the flags are `RELEASE`, `REPEAT`, and
`CRITICAL` (never dropped).

§8 states the path's rules in full.
