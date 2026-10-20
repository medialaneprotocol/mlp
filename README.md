# The Media Lane Protocol

The specification of the **Media Lane Protocol (MLP)**: a transport for
real-time interactive media over links that are slow, lossy, or both.

MLP carries three kinds of traffic at once — control, media and feedback —
and keeps them apart. It moves content it does not interpret, paces it
under a rate it measured, and always knows what each receiver may be
stale in.

- **[The specification](spec/README.md)** — the normative document.
- **[`mlp-core`](https://github.com/medialaneprotocol/mlp-core)** — the
  Rust reference implementation.
- **[`mlp-ts`](https://github.com/medialaneprotocol/mlp-ts)** — the
  browser-side reference implementation.
- **[`mlp-proto`](https://github.com/medialaneprotocol/mlp-proto)** — the
  class bodies' wire schemas.
- **[`mlp-conformance`](https://github.com/medialaneprotocol/mlp-conformance)**
  — the corpus and the gate that keeps it honest.

## The one-paragraph version

A lane carries objects. Objects are fragmented, paced, coalesced and
reassembled by rules that depend on nothing but the link's measured
round-trip time. A sender knows, for every receiver, exactly which parts
of the surface that receiver may be missing, and repairs exactly those.
A receiver either holds an object whole or refuses it, and says which
base it does hold. Nothing in the protocol interprets the content.

## Status

The protocol is **v1** and is stable. There is exactly one accepted
version: a peer that speaks another one is refused with a typed reason,
and there is no transition window and no fallback. See
[§12.1](spec/12-deployment.md).

The repository is in development. One moving version, `v0.1.0`, naming the
current commit: there is exactly one tag, and a change moves it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). A specification change is a
contract change, so it carries the same obligations as a code change:
the reference implementation and the conformance corpus move with it.

## Checking the specification

```bash
node scripts/check-references.mjs --impl ../mlp-core --impl ../mlp-ts
```

Every cross-reference must resolve to a section that exists. A reference
that points at nothing sends a reader looking for a rule that was never
written.

## License

Apache-2.0 — see [LICENSE](LICENSE).

The reference implementations are under PolyForm Noncommercial 1.0.0, so
that the *specification* — and therefore any implementation of it — stays
open.
