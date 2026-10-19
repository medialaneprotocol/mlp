# 12. Deployment

The protocol is deployed by an application, not by itself. This section
states the constraints a deployment MUST satisfy, and the switches it MUST
provide.

## 12.1 One version, one window

There is exactly one accepted protocol version and one implementation. The
protocol has no transition window, no dual acceptor, and no downgrade: a
peer that speaks a different version is refused with a typed reason naming
the accepted one.

A deployment therefore ships every artifact of a release together. A
deployment that needs to roll back MUST roll back all of them, because a
mixed deployment is a refused session rather than a degraded one.

## 12.2 The switches

A deployment MUST provide a way to stop emitting media without stopping
the session, and a way to disable the lane without killing the session.
The protocol does not name the switches — that is the deployment's
vocabulary — but the *effects* are normative:

| Effect | Requirement |
|---|---|
| Stop emitting media | the control path and the input path keep working; the session survives; the receiver is told the stream is stopped rather than left waiting |
| Disable the lane | the session runs control-only; the receiver shows an explicit unsupported state, not a blank surface |
| Cap the estimated rate | the estimator's ceiling is configurable, so a metered link can be capped |
| Turn off the patch behaviour | a debugging switch: strict chaining, with anchors only on an epoch change |
| Set the park window | the resume time-to-live is configurable |
| Pause content production | only when no receiver is connected; never in response to a transport stall (§7.5) |
| Cap the floor rate | the minimum rate, below which the receiver is told the session is text-only |

Each switch MUST be validated at start-up with a typed error naming it, and
each MUST be observable: a switch that changes behaviour without changing
a series is a switch nobody can trust.

## 12.3 What a deployment MUST NOT do

- It MUST NOT put a media fragment larger than 16 KiB on the control lane
  (§3.2).
- It MUST NOT let any intermediate hop's idle timeout fall below the
  session's idle timeout (§9.2).
- It MUST NOT coalesce or drop input objects for capacity at any hop
  (§8.3).
- It MUST NOT apply an input object twice, or apply one after its deadline,
  except a release (§8.3).
- It MUST NOT deliver a partial update to a peer (§4.4).
- It MUST NOT compare the protocol's `UPDATE_BYTES` with a body it cannot
  decode (§10.3).
- It MUST NOT re-create a receiver's state on a reconnect (§7.6).

## 12.4 The rollback posture

A rollback uses the deployment's own release machinery. Because there is
one version and one window, a rollback is a same-window operation: rolling
back the sender without the receivers, or the reverse, produces a refused
session, which is explicit rather than silent.

A deployment that cannot roll back all of its artifacts together MUST
carry the compatibility the protocol forbids — and then it is not
deploying this protocol.
