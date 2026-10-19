# 10. Observability

A protocol that cannot be observed cannot be operated. This section states
the series an implementation exports and the questions they answer.

## 10.1 Naming

The protocol's own series are prefixed `mlp_`. A deployment's series carry
its own prefix — the prefix names the component, and the protocol's
vocabulary follows it.

Histograms use seconds and carry the `_seconds` suffix. Session and peer
identifiers are hashed and capped; a fleet view uses aggregates rather than
identifiers.

The receiver-origin series carry `{session, path, source="receiver"}`,
where `path ∈ {stream, dc-direct, dc-turn, quic, unknown}` is the carrier
the session last reported.

## 10.2 The series and the questions they answer

| Question | Answered by |
|---|---|
| Why is this session slow? | the per-receiver round-trip time on both legs, the attributed loss, the pace, the receiver's goodput |
| Is it the last mile, or is it us? | the link-attributed loss against the hops' reported drops, cross-referenced through the hop reports |
| How long did recovery take? | the session-recovery histogram, the park duration, the resume outcomes |
| Is anything queuing? | the media queue depth at each hop, the input queue depth, the receiver's backlog |
| Is the receiver converged? | `mlp_converged`, `mlp_pending_cells`, `mlp_stale_fraction`, and the receiver's own `converged` and `stale_cells` |
| What does the user see? | the lane-state gauge, and the receiver-state gauge — the values of the state machine of §6.7 |
| Is the fleet degrading? | the quality score aggregated per tenant, and the echo and cadence histograms |
| Which peers speak this version? | `mlp_protocol_version{version="1"}` — one series per peer, carrying the single version the build accepts and emits |

## 10.3 Object completeness at a hop

A hop's slot completes an object when every part has arrived. The
`UPDATE_BYTES` TLV is the update's own total; an object's payload is the
whole body, metadata included, so the two do not sum equal and a hop MUST
NOT compare them. The content's own validator owns that.

An object whose parts are complete is forwarded; a partial one is never
delivered.

## 10.4 The error vocabulary

`MediaError.code`:

| code | meaning |
|---|---|
| 1 | `BAD_MAGIC` — the transport message is not an MLP fragment |
| 2 | `UNSUPPORTED_VERSION` — the fragment's version is not this one |
| 3 | `BAD_CLASS` — the class is not defined |
| 4 | `BAD_FLAGS` — a reserved flag bit is set |
| 5 | `BAD_PRIORITY` — a media fragment used a reserved priority |
| 6 | `BAD_FRAGMENT` — the fragment's index, count, or length is invalid |
| 7 | `BAD_LENGTH` — the payload length is invalid for the carrier |
| 8 | `BAD_EXT` — the header extension does not parse |
| 9 | `META_MISMATCH` — contradictory duplicate information |
| 10 | `ASSEMBLY_TIMEOUT` — the object did not complete in time |
| 11 | `ASSEMBLY_EVICTED` — the object was evicted from the bounded table |
| 12 | `OBJECT_ID_WRAP` — the object id counter wrapped |
| 13 | `BODY_INVALID` — the class body failed validation |
| 14 | `RATE_LIMITED` — the peer exceeded a limit |
| 15 | `LANE_DISABLED` — the lane is disabled by policy |

The receiver's local drop reasons, which are never reported back, are:
`MultiFragmentOnDatagram`, `FragmentMismatch`, `Expired`, `Duplicate`,
`AckBadBitmap`, `AckBadCount`, `SupersededByPlan`, `InFlightCap`.

## 10.5 The other vocabularies

- **Lane states**: `STARTING`, `LIVE`, `DEGRADED`, `CONVERGING`, `STALE`,
  `PARKED`, `DISABLED`, `DECODE_BOUND`, `NO_FEEDBACK`, `MEDIA_UNSUPPORTED`.
  They form a priority order — a receiver's state is the most significant
  one that applies.
- **Close codes**: `normal`, `server_shutdown`, `policy`, `superseded`,
  `park`.
- **Unsupported reasons**: `protocol`, `disabled_by_policy`,
  `no_sender_capability`.
- **Carriers**: `unknown`, `stream`, `dc-direct`, `dc-turn`, `quic`.
- **Estimator modes**: `StartUp`, `Steady`, `Degraded`, `Floor`,
  `NoFeedback`.
- **Scheduler bands**: `P0`, `P1`, `P2`, `P3`.
- **Update kinds**: `delta`, `anchor`, `idle`, `pulse`, `repair`.
