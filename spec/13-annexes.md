# Annexes

## 13. The annexes

### 13.1 Annex D — the decisions

The protocol's design decisions, in the order they were made. Each is a
choice that a later decision could have reversed, and each is referenced
from the sections and from the reference implementation.

| id | Decision | Why |
|---|---|---|
| D-2 | The media lane is a **separate transport path** from the control lane, not a priority on the same one. | A large media object on the control lane head-of-line blocks the acknowledgements and input that keep the session alive. Separating them makes the isolation structural rather than a priority argument. |
| D-3 | A lane's writer drains **strictly by priority**, and the media pacer holds a **reserved rate** for everything else. | A media burst must not be able to starve the control path. A reserved rate is the only guarantee that survives a sender that is wrong about its own budget. |
| D-4 | A peer that does not speak this version is **refused with a typed reason**, and there is no fallback. | A silent fallback is a session that appears to work and is subtly wrong. A typed refusal is a failure an operator can see. |
| D-5 | The protocol moves content it **does not interpret**; the codec owns the content. | A transport that understands its content cannot be reused for the next content type, and cannot be implemented by a party that did not write the codec. |
| D-5c | A receiver that holds a stale state is repaired by an **anchor plan over the cells it is missing**, not by a reset. | A reset is full-coverage by definition: on a slow link no budget makes it timely, and it remains the only object that can lose a receiver's whole progress. |
| D-6 | A lost echo-critical update is **repaired** — the cells the receiver is missing are encoded again into a new update — rather than retransmitted. | A retransmission costs the whole object a second time, and the object it repeats may no longer be the one the receiver needs; a repair carries only what is missing. |
| D-7 | The sender keeps **per-receiver accounting of which cells each receiver may be stale in**, and repairs exactly those. | Convergence becomes a set difference rather than a feeling (§2.2, N-2). |
| D-8 | The input path is **deadline-bounded, deduplicated, and prioritised**, and a release is never dropped. | A dropped release is a stuck key, and a stuck key is the one failure a user cannot work around. |
| D-9 | A stall is a **repair trigger**, never a pause of content production. | A transport problem that stops the content turns into a content problem. |
| D-16 | An intermediary **reports what it dropped**, so a loss is attributable. | "The last mile or our stack?" is unanswerable without per-hop attribution. |
| D-17 | The media lane carries **no audio**: the tier envelope's budget belongs to the screen. | A media lane at the T4 envelope carries less than one second of audio, so an audio stream on it would spend the whole budget on something the envelope does not promise. |
| D-19 | A frame is **decomposed into several objects** rather than sent oversize. | The carrier's cap is not negotiable, and an oversize object is a permanent loss rather than a delay. |
| D-20 | The lane's state is decided by the **facts both ends can measure** — the content's freshness, its convergence and its loss — and **neither end's claim overrides the other's staleness**. | A lane that one end calls `LIVE` while the other calls `STALE` shows two users two truths. The pace is not a fact about the link: it is the sender's output, and a sender with little to send sits at the floor on a perfect link (§6.7.1). |

### 13.2 Annex N — the normative refinements

The four properties that sharpen the tiers (§2.2). Each is measurable, and
each is asserted.

| id | Refinement |
|---|---|
| N-1 | **Measurable echo.** The sender stamps the update that carries the input's effect with the highest input sequence its content includes, and the receiver computes the echo from it. The carrier is protected: it is never refused by the sender's write queue, never released behind the bulk, and never replaced by a hop's coalescing slot (§6.3.5, §3.2). |
| N-2 | **Convergence is a set, not a feeling.** `pending_cells(V) = ∅` and `applied_update_id == last_sent_update_id(V)`, both exported. |
| N-3 | **The T4 floor is text-first**, and a stream carrier may not sustain it. The structural properties hold on every carrier; the goodput floor is guaranteed only where a loss-tolerant carrier is in use. |
| N-4 | **The outage budget arithmetic.** Every idle timeout exceeds the outage target with margin, and the continuity machinery — not a timeout — bounds the recovery. |

### 13.3 Annex INV — the invariants

The properties a conforming implementation must hold under any profile
(§11.2).

| id | Invariant |
|---|---|
| INV-1 | An update is applied only if every part of it arrived. |
| INV-2 | At every converged observation, the receiver's content equals the sender's emitted state for every acknowledged cell. |
| INV-3 | No input object is applied twice, and none after its deadline. |
| INV-4 | After any session end or park beyond grace, the sender's pressed set is empty. |
| INV-5 | Every queue stays within its cap. |
| INV-6 | No object exceeds `max_object_bytes`, and no update exceeds `max_parts × the carrier's fragment cap`. |
| INV-7 | The bytes sent in any one-second window are at most `pace_bps/8 × 1.25`. |
| INV-8 | The input echo is at most `2 × RTT + 250 ms` whenever the link delivers any object. The echo is measured the way the **sender** measures it (§5.2): from the sender's application of the input to the arrival of the acknowledgement that names it. |
| INV-9 | A session survives every outage and flap schedule, with no lost session. |
| INV-10 | Every drop is attributed to exactly one hop. |
| INV-11 | The receiver's loss accounting is made in the **update-id** space (§5.2, §5.1.1), so an intermediary's own object never reads as a loss and a clean link never looks lossy. |
| INV-12 | The chain epoch only moves forward (§5.1, §6.5.3): a stale acknowledgement is counted, never obeyed. |

### 13.4 Annex S — the acceptance stories

The stories the conformance corpus's scenarios cover. Each is a property a
user would notice, and each is checked by a committed scenario.

| id | Story |
|---|---|
| S-1 | Typing is echoed within the tier's budget. |
| S-2 | A scroll converges within the plan deadline. |
| S-3 | An outage is survived and the session resumes. |
| S-4 | A flapping link is survived without operator action. |
| S-5 | A repair plan is atomic and monotone. |
| S-6 | Input keeps its priority while a plan runs. |
| S-7 | Memory stays bounded under continuous motion. |
| S-8 | A recovery is fully attributed. |
| S-9 | A resume rebases rather than resets. |
| S-10 | No key is stuck after a session ends. |
| S-11 | Typing stays first under extreme loss. |
| S-12 | The carrier is selected by measurement. |
| S-13 | A single lane is a working degradation, not a failure. |
| S-14 | The baseline tier behaves as specified. |
| S-15 | A peer without the lane's support degrades explicitly. |
