# The Media Lane Protocol (MLP v1)

Status: normative. This document is the specification of the Media Lane
Protocol: the target network envelope, the traffic classes and their
isolation rules, the MLP v1 wire format, the reliability architecture
(bandwidth estimation, pacing, per-receiver convergence accounting and repair
plans), session continuity, the input path, the timeout framework, and the
observability contract.

The protocol has one operation-facing name, **MLP v1**, and one wire magic,
**`MLP\0`** (`4D 4C 50 00`). There is exactly one media implementation and one
catalog format version: a peer that does not speak them is refused with a
typed reason. There is no transition window and no second version anywhere.

## What this document is

A protocol is a contract between implementations that do not share an
author. This one therefore says what the bytes are, what a receiver must do
with them, and what a sender may assume — and nothing else. It does not
describe a product, a deployment, a vendor, or a particular application.

Concretely, the document does **not** say:

- what an update's bytes *mean* — that is a codec's business (§1.4);
- who captures what, or how content is produced;
- how a session is authenticated, or who may open one;
- what a deployment's endpoints, certificates, or process supervision look like.

It **does** say:

- the byte layout of every fragment, and the validation order;
- the objects, their lifecycle, and their assembly;
- the traffic classes, their isolation, and the priority discipline;
- the estimator, the pacer, the scheduler, and the convergence predicate;
- the continuity rules: parking, resume, and the reconnect ladder;
- the input path: sequencing, deadlines, and the pressed set;
- the timeout framework, which is entirely relative to a measured round-trip
  time;
- the invariants an implementation must preserve.

## The reference implementations

| | |
|---|---|
| [`mlp-core`](https://github.com/medialaneprotocol/mlp-core) | Rust, sans-IO: the normative implementation of the byte format and every policy |
| [`mlp-ts`](https://github.com/medialaneprotocol/mlp-ts) | TypeScript: the browser-side mirror |
| [`mlp-proto`](https://github.com/medialaneprotocol/mlp-proto) | the class bodies' wire schemas |
| [`mlp-conformance`](https://github.com/medialaneprotocol/mlp-conformance) | the corpus and the gate that keeps it honest |

When this document and the reference implementation disagree, that is a bug
in one of them. Both are normative; neither is a substitute for the other.

## Reading order

| Section | What it settles |
|---|---|
| [1. Vocabulary and scope](01-vocabulary.md) | the words, and what the protocol deliberately does not do |
| [2. Target envelope](02-target-envelope.md) | the tiers the protocol is designed against |
| [3. Traffic classes and isolation](03-traffic-classes.md) | what runs where, and what may not starve what |
| [4. Framing](04-framing.md) | the carriers, the fragment header, the TLV registry, the object lifecycle |
| [5. Class bodies](05-class-bodies.md) | every message a peer may need to decode |
| [6. Reliability architecture](06-reliability.md) | the estimator, the pacer, the scheduler, the convergence predicate |
| [7. Session continuity](07-continuity.md) | parking, resume, the reconnect ladder |
| [8. Input path](08-input.md) | sequencing, deadlines, the pressed set |
| [9. Timeout framework](09-timeouts.md) | every timeout, as a function of the measured round-trip time |
| [10. Observability](10-observability.md) | the series an implementation exports |
| [11. Verification](11-verification.md) | the invariants, and how they are checked |
| [12. Deployment](12-deployment.md) | the kill switches and the rollout posture |

## Conventions

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT** and **MAY**
are to be interpreted as in RFC 2119 and RFC 8174.

A rule written as an algorithm in a numbered list is normative: the order of
the steps is part of the rule, and a receiver that reorders them is not
conformant.

Numbers are decimal unless a base is stated. Byte offsets are from the first
byte of the fragment that carries them.

The word *must* in the sense of a requirement on an implementation is written
in capitals; the word in ordinary prose is not a requirement.
