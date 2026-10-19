# 1. Vocabulary and scope

## 1.1 The words

- **Lane** — an independent transport path between two peers: the *control
  lane* and the *media lane*.
- **Object** — one protocol-level unit on a lane: a control object, a media
  update, an acknowledgement.
- **Fragment** — one transport-message-sized piece of an object. MLP's unit of
  framing.
- **Update** — the unit of media state. A *self-contained* update carries its
  whole surface; a *chained* update continues the surface the update named
  by its base established.
- **Cell** — one cell of the repair grid: the unit the protocol accounts for.
  The grid is declared by the sender; what a cell contains is a codec's
  business.
- **Sender** — the peer that produces updates.
- **Receiver** — the peer that applies them.
- **Intermediary** — a peer that forwards objects between a sender and a
  receiver without interpreting them.
- **Tier** — T0…T4 of the target envelope (§2).
- **Parked** — a session whose live transport died but whose state is
  deliberately retained (§7).
- **Plan** — a sender-side, budget-truncated schedule of anchor updates that
  covers the cells a receiver may be stale in (§6.6).
- **Carrier** — the transport a lane's fragments travel over: a *stream*
  carrier, a *datagram* carrier (§4.1).

## 1.2 The roles

MLP names three roles, and it names them by what they do rather than by
where they sit in a deployment:

| Role | Does | Never |
|---|---|---|
| **sender** | produces updates, estimates the link, paces its output, accounts for what each receiver holds | interpret a receiver's state |
| **receiver** | applies updates, acknowledges what it applied, reports the link it measures | decide what the sender should send next |
| **intermediary** | forwards whole objects, reports what it dropped | decode an object's content |

A deployment may place these roles anywhere — a server, a browser, an
edge — and may run several of them in one process. The protocol does not care.

## 1.3 The separation that makes the protocol extensible

MLP carries bytes it does not interpret. The `MEDIA` class is defined by
nothing but its length: whatever a codec produces is what travels, and the
protocol moves it, accounts for it, and paces it.

This is the reason the protocol has one wire format rather than a codec
registry, one negotiation rather than a dial, and one chain rather than a
per-codec chain. A new codec is a new body behind the same transport; it
costs the protocol nothing.

The corollary is equally important: **the protocol cannot promise anything
about content**. It guarantees that a receiver either holds an update whole
or does not hold it at all, that a sender always knows which cells a
receiver may be stale in, and that both are operating under a rate the link
measured. What those bytes depict is the codec's promise, and the protocol
does not make it.

## 1.4 What this protocol does not do

- It does not define an update's content (§1.3).
- It does not define who may open a session, or how a session is
  authenticated. A deployment's own identity system supplies that, and the
  protocol's objects are carried inside whatever the deployment has already
  authenticated.
- It does not define a deployment's topology, its endpoints, or its
  supervision.
- It does not define a codec's wire format, its limits, or its
  application rules.

## 1.5 The unit of media state

MLP's own unit is an **update**. The wire carries its identity in the
header (§4.3) and its content in the body, and the protocol's accounting —
the convergence predicate of §6.5, the acknowledgement window of §5.2 — is
expressed in updates.

An implementation that carries a different kind of content maps it onto
updates. The mapping is the codec's, and the protocol's requirements hold
over the mapping: a receiver either applies an update whole or refuses it,
and a sender always knows which cells a receiver may be stale in.
