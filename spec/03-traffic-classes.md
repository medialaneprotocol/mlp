# 3. Traffic classes and isolation model

A lane carries several kinds of traffic at once, and the protocol's ability
to keep them apart is what makes it usable for interactive media: a stalled
acknowledgement must never delay a control message, and a large media update
must never delay either.

## 3.1 Classes

| Class | Name | Objects | Carrier | Delivery semantics | Priority |
|---|---|---|---|---|---|
| **C0** | Control and lifecycle | the lane handshake, the hello exchange, resume, lane state, session state, errors, closes, capability reports | control lane | reliable, ordered | 0 (highest) |
| **C1** | Input and command feedback | input objects, acknowledgements, repair requests, clipboard, input toggles | control lane | reliable, ordered, deadline-bounded, deduplicated | 1 |
| **C2** | Pointer | pointer position samples, pointer state corrections | media lane (unordered on a datagram carrier) | unreliable, latest-wins | 5 |
| **C3** | Media | MLP-framed media updates, path probes | media lane | atomic objects, repair by re-encode, coalescible | 6 (interactive), 7 (background refresh) |
| **C4** | Feedback and telemetry | `MediaFeedback`, `MediaAck`, `MediaHopReport`, `MediaProbe` echoes | media lane (a report may ride the control lane when the media lane is down, and **every hop forwards it**, §3.2 rule 1) | reliable within a reporting window; the loss of one report is harmless | 0 for acknowledgements, 2 for reports |

Two classes do not appear on the media lane: **input** and **session
control** stay on the control lane, where their ordering guarantees matter
and their volume does not.

## 3.2 Isolation rules (normative)

1. **Two physical connections per session** at every hop. Peers address
   media objects by `media_session_id`; the control lane never carries a
   media fragment larger than 16 KiB
   (`MAX_CONTROL_LANE_OBJECT_BYTES`), enforced at every hop with a counted
   drop.

   **The feedback class is the control lane's own traffic when the media
   lane is down.** A report that rides the control lane is forwarded by every
   hop, and a hop that drops it starves the sender's estimator (§6.2.6): with
   no feedback the lane falls into its no-feedback safety net, its rate
   collapses to the floor, and a plan that owes the receiver a whole picture
   (§6.6) can never finish inside its deadline — the receiver's picture stays
   incomplete, the acknowledgement that names the applied update never
   arrives, and the echo grows behind it.

   The media **bulk** does not travel on the control lane: an update that
   arrived there would bypass the media lane's pacing, coalescing and
   isolation, so a hop drops and counts it. A payload the hop cannot parse
   carries no class it may vouch for, and it is dropped as well.

2. **Strict priority within a lane.** A lane's writer drains
   C0 → C1 → C2 → C4 → C3(priority 6) → C3(priority 7). The MLP priority
   field is the single authority. A class that is not droppable — C0, C1 and
   C4 — is never dropped behind the droppable classes: the queue that holds
   them is sized for the class's own window (a reporting window for C4), and
   the media bulk has its own slot, so a full lane never costs a report.

   **The echo's carrier is not the bulk.** An object that carries the input
   sequence the receiver answers (§6.3.5) is a fact the sender cannot wait
   for, exactly like the report that names it (§6.2.1): the echo's promise is
   a quarter of a round trip (§9.1), and the bulk's queue is a whole frame
   time at best. A writer therefore drains an echo-critical object before the
   media bulk it would otherwise wait behind, and a sender's own write queue
   never refuses one because the bulk filled the queue (§6.3.5).

3. **Reserved rate.** The media-lane pacer reserves
   `reserved_rate = max(2 kbps, 10 % × pace_bps)`; a media object may not be
   scheduled if doing so would starve the reserve for more than
   `max(1 × RTT, 250 ms)`.

4. **Bounded in-flight, earned pipelining.** A sender starts conservative —
   one media object being sent plus one replacement may be unacknowledged
   per receiver per hop — and earns depth up to `in_flight_cap` (default 8)
   after three consecutive healthy *filled* windows under 1 % loss, with the
   evidence weighted by time rather than by window count. Any other window
   revokes the earned depth. The *sender's own queue* is the authority: no
   hop may write into a transport with more than
   `in_flight_cap × max_object_bytes` outstanding.

5. **Coalescing policy.** A lane's pending slot holds whole objects and
   never parts of two (§4.4). A waiting **anchor** object is never evicted
   by a chained one: the anchor is the only thing that can repair a
   receiver, so an incomplete anchor is protected and a chained update
   offered in its place is refused whole. An **echo-critical** object — one
   carrying the input sequence the receiver answers (§6.3.5) — is protected
   the same way: the echo it carries is a fact the sender cannot wait for,
   and a coalesced-away carrier is an echo that never comes back. The
   reasons a slot may drop an object are `coalesced`, `replaced_incomplete`,
   `anchor_protected`, `fragment_gap`, `missed_first_fragment`, `incomplete`,
   `invalid`, and `superseded_by_plan` — the last meaning a queued object for
   a cell set a newer plan already covers was dropped, which is not a loss
   because the accounting never counted it as sent.

6. **Lane-mode fallback.** If the media lane cannot be established, both
   lanes share the control connection and the lane is in `single` mode.
   Every isolation rule except head-of-line isolation still holds: priority,
   the reserved rate, and the in-flight cap are all enforced. The mode is
   observable, so a session that fell back says so.

## 3.3 Why the control lane is safe to share

After the split, the control lane carries only small objects. Its own
head-of-line blocking is bounded by its queue: 16 KiB per object and a
256-object FIFO. A 16 KiB object at 32 kbps is 4 s, which is why a
deployment defers bulk operations — a still image, a clipboard payload —
during T4, with a typed state rather than a silent stall. The lane's shared
budget is paced too: the control lane gets the reserved rate when the media
lane exists, and the full pace when it does not.
