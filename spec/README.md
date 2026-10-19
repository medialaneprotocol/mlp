# The Media Lane Protocol (MLP)

The specification of the **Media Lane Protocol**: a transport for real-time
interactive media over links that are slow, lossy, or both.

MLP carries three kinds of traffic at once — control, media and feedback —
and keeps them apart. It moves content it does not interpret, paces it
under a rate it measured, and always knows what each receiver may be
stale in.

## Reading it

Start with [00-index.md](00-index.md): it says what the document is, what
it deliberately does not cover, and the order to read the rest in.

| Section | What it settles |
|---|---|
| [1. Vocabulary and scope](01-vocabulary.md) | the words, the three roles, and what the protocol does not do |
| [2. Target envelope](02-target-envelope.md) | the five tiers the protocol is designed against |
| [3. Traffic classes and isolation](03-traffic-classes.md) | what runs where, and what may not starve what |
| [4. Framing](04-framing.md) | the carriers, the fragment header, the TLV registry, the object lifecycle |
| [5. Class bodies](05-class-bodies.md) | every message a peer may need to decode |
| [6. Reliability architecture](06-reliability.md) | the estimator, the pacer, the scheduler, the convergence predicate |
| [7. Session continuity](07-continuity.md) | parking, resume, the reconnect ladder |
| [8. The input path](08-input.md) | sequencing, deadlines, the pressed set |
| [9. The timeout framework](09-timeouts.md) | every timeout, as a function of the measured round-trip time |
| [10. Observability](10-observability.md) | the series an implementation exports |
| [11. Verification](11-verification.md) | the invariants, and how they are checked |
| [12. Deployment](12-deployment.md) | the switches, and what a deployment must not do |

The [annexes](13-annexes.md) carry the decision list, the normative
refinements, and the invariant list.

## The reference implementations

| | |
|---|---|
| [`mlp-core`](https://github.com/medialaneprotocol/mlp-core) | Rust, sans-IO: the normative implementation |
| [`mlp-ts`](https://github.com/medialaneprotocol/mlp-ts) | TypeScript: the browser-side mirror |
| [`mlp-proto`](https://github.com/medialaneprotocol/mlp-proto) | the class bodies' wire schemas |
| [`mlp-conformance`](https://github.com/medialaneprotocol/mlp-conformance) | the corpus and the gate that keeps it honest |

## Contributing to the specification

A change to this document is a change to a contract between
implementations that do not share an author, so it is reviewed like code:

1. Open an issue describing the problem, not the wording.
2. Propose the change with the observable behaviour it produces and the
   behaviour it replaces.
3. Update the reference implementation and the conformance corpus in the
   same change: a specification that no implementation follows is a wish.

A change that alters a decision the corpus records MUST regenerate the
traces, and the diff is part of the review.

## Conventions

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT** and **MAY**
are to be interpreted as in RFC 2119 and RFC 8174.

A rule written as a numbered algorithm is normative, and so is the order
of its steps.

## License

Apache-2.0. See [LICENSE](LICENSE).

The reference implementations are under PolyForm Noncommercial 1.0.0, so
that the specification — and therefore any implementation of it — stays
open.
