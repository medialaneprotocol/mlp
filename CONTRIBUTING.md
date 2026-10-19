# Contributing to the specification

A change to this specification is a change to a contract between
implementations that do not share an author. It is therefore reviewed like
code, and it carries the same obligations.

## Before you propose

1. **Read the whole section** the change touches, and the sections it
   depends on. Most of the protocol's rules are stated once and referenced
   everywhere; a change that contradicts one of them is a change to all of
   them.
2. **Check the invariants** (annex INV) and the decisions (annex D). A
   change that breaks an invariant is not a change to the specification —
   it is a change to what the protocol promises.
3. **Look for the rule in the reference implementation.** The
   implementation is normative too, and where the two disagree, one of them
   is a bug. A proposal that says "the specification should say what the
   code does" is a legitimate proposal, but it must say which side is
   wrong and why.

## The shape of a proposal

Describe the **observable behaviour**, not the wording:

- what a peer does, in terms another implementation can check;
- what a peer may rely on;
- what changes for an existing implementation, and how it migrates.

A proposal that only rewrites a paragraph is a proposal to change how the
document reads, which is a different thing and is reviewed as one.

## What a change must include

- The specification, updated.
- The reference implementation, updated, if the change is observable.
- The conformance corpus, regenerated, if the change alters a decision the
  corpus records. The traces are **generated, never written by hand**:
  run the gate with `--update` and commit the result. The diff of the
  traces is part of the change's review, and it is the clearest evidence
  of what the change actually does.
- The cross-references, still resolving. Run the checker.

## Changing a version

The protocol accepts exactly one version. A change that is not backward
compatible is a new version, and it means:

- the version byte changes;
- every implementation changes with it;
- the deployment ships every artifact in one window (§12.1).

There is no transition window, no dual acceptor, and no downgrade. That is
a deliberate cost: a protocol with two versions in the field is a protocol
with two behaviours, and the ambiguity is paid for by every user of it.

## Style

- The protocol speaks about **senders**, **receivers** and
  **intermediaries** — not about hosts, viewers, gateways and relays. The
  roles are what the protocol defines; where they sit is the deployment's.
- The protocol's unit of media state is an **update**, and its repair unit
  is a **cell**. A word that belongs to a codec does not belong here.
- Requirements are written in capitals and are testable. A sentence that
  cannot be checked is a sentence that cannot be wrong, and therefore
  cannot be right either.
- Numbers are normative. If a number appears in prose, it is a claim
  about a number that appears in a table, and the two must agree.

## The checkers

| Checker | What it enforces |
|---|---|
| `scripts/check-references.mjs` | every cross-reference resolves to a section that exists |
| the conformance gate | the corpus's shape, and that the traces are reproducible |

Run both before opening a proposal.
