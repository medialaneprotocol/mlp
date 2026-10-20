# 11. Verification

The protocol's promises are only worth what they are checked against. This
section states the layers of verification and the invariants that must hold
at each of them.

## 11.1 The layers

| Layer | What | Where | When |
|---|---|---|---|
| L1 unit | the fragment codec, the assembly, the TLV registry, the estimator, the pacer, the scheduler, the convergence accounting, the input queue, the resume machine | the reference implementation's own tests | on every change |
| L2 harness | both ends as machines over a deterministic link model, with a scenario per tier and the invariants checked as it runs | [`mlp-harness`](https://github.com/medialaneprotocol/mlp-harness) | on every change |
| L3 conformance | the committed scenarios and decision traces, replayed by the reference implementation **and** by the browser implementation; the regeneration byte-compared | [`mlp-conformance`](https://github.com/medialaneprotocol/mlp-conformance) | on every change |
| L4 property | the tier budgets and the invariants as asserted properties, over randomized profiles, with a failing case shrunk to a counterexample | the harness's property suite | on every change |
| L5 network | a live stack over a shaped link, with a real client driving the real interface and the metrics asserted | the chaos harness | on demand and on a schedule |
| L6 field | real hardware on real hostile networks | the acceptance runbook | at a release |

## 11.2 The invariants

These are property-tested over randomized profiles and committed as named
corpus scenarios. A conforming implementation MUST hold all of them.

| id | Invariant |
|---|---|
| INV-1 | An update is applied only if every part of it arrived; a partial update is never applied. |
| INV-2 | At every `converged` observation, the receiver's content equals the sender's emitted state for every cell the receiver acknowledged. |
| INV-3 | No input object is applied twice, and none after its deadline — releases excepted, and asserted applied. |
| INV-4 | After any session end or park beyond the grace period, the sender's pressed set is empty: no stuck keys. |
| INV-5 | Every queue — the sender's, the intermediaries', the receiver's — stays within its cap under any profile. |
| INV-6 | No object exceeds `max_object_bytes`, and no update exceeds `max_parts × the carrier's fragment cap`. |
| INV-7 | The bytes sent in any one-second window are at most `pace_bps/8 × 1.25`; probes are accounted separately. |
| INV-8 | The input echo is at most `2 × RTT + 250 ms` whenever the link delivers any object. |
| INV-9 | A session survives every outage and flap schedule in `flap(5, 10 s, 10 s)` with no lost session and exactly one resumed lane per receiver. |
| INV-10 | Every drop is attributed to exactly one hop: the sum of the hop reports and the link loss equals the receiver-reported loss, within one object. |

## 11.3 The harness

The harness is the transport's verification layer: a deterministic,
sans-IO network model, a scenario language, the protocol's own machines
driven over that model, the invariants above checked as the run proceeds,
a trace a machine can diff, and a prediction the model answers with.

It is a *layer*, not a second implementation: the harness never decides
what an update means, never assembles an object and never paces a byte. It
drives the machines and watches what they decide.

Every invariant has a deliberately broken peer that violates it, and the
harness's gate runs those peers and requires them to fail: a harness that
cannot fail is a decoration.

## 11.4 The conformance gate

The gate validates the corpus's schema, the profile-to-tier identity, the
corpus's completeness, the digest stability (it regenerates the traces and
compares the bytes), and that both consumers resolve to the one canonical
corpus directory.

**The two consumers.** The reference implementation replays every committed
scenario through its simulator and writes the decision traces; the gate
regenerates them and compares the bytes. The browser implementation replays
the same corpus and requires its own machine to decide the way the published
trace says the protocol decides: the applied window's progression, the
acknowledgements the window reports, the chain epoch, and the validity of
every acknowledgement. A browser implementation that cannot read the corpus
fails its own gate — a comparison that read nothing is not a comparison.

**The gate checks its own teeth.** A mutation of the corpus must be
noticed: a tier profile whose numbers drifted from the canonical point, a
scenario that dropped one of the matrix's cases, and a trace whose digest
was tampered with. A gate that cannot fail is not a gate.

The traces are **generated, never written by hand.** When a protocol change
alters a decision, the traces are regenerated and the diff is part of the
change's review. A change that alters a decision belongs to the reference
implementation and to the corpus — never to an implementation that only
consumes them.

## 11.5 The network layer

The network layer is where a real implementation's assumptions meet a real
link. It requires a shaped link, a real client, and metric assertions; it
is on demand and on a schedule rather than on every change, because it is
slow and it needs privileges.

Its procedure, and the acceptance matrix it walks, are in the acceptance
runbook that ships with the reference implementation.
