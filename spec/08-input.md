# 8. The input path (normative)

Input travels the other way: from the receiver to the sender. It is the
path where a lost or duplicated object is most dangerous, because a lost
key-release leaves a key held forever.

The protocol's rules here are about three things: **boundedness** (a queue
that cannot grow without limit), **liveness** (a release always arrives,
or the sender learns that it did not), and **honesty** (the receiver is
told the truth about what it holds).

## 8.1 The input object

```
input_object = { input_seq, deadline_epoch_ms, kind, flags, payload }
```

- `input_seq` is monotone within a receiver's epoch, and starts at
  nothing — the value is opaque to everyone but the receiver that produced
  it and the sender that consumes it.
- `deadline_epoch_ms` is an absolute session-relative deadline; `0` means
  "never expires".
- `kind` and `flags` are transport-level, so that every hop can coalesce
  or drop an input object without decoding the payload.
- `payload` is the input's own serialized content, unchanged by the
  transport.

The kinds are `pointer_move`, `pointer_button`, `key`, `wheel`,
`clipboard`, `release_all`, `pressed_set`. The flags are `RELEASE` (a
key or button up), `REPEAT`, and `CRITICAL` (never dropped).

A payload that is not wrapped in an envelope is forwarded unchanged: a
peer that does not implement the wrapper still interoperates.

## 8.2 The receiver's queue (bounded, deadline-aware)

| Policy | Rule |
|---|---|
| Capacity | 64 objects and 8 KiB in total. Exceeding it drops the lowest-priority oldest object and counts `input_dropped_total{reason="capacity"}`. |
| `pointer_move` | latest-wins: a new move replaces an unsent move. While the transport is down, only the latest position is kept. |
| `wheel` | accumulated by direction into one object carrying the summed delta, capped at ±8 notches. |
| `key`, `pointer_button` | never dropped while queued. A `RELEASE` object is `CRITICAL` and bypasses the capacity drop. |
| `clipboard` | dropped when not connected, and never replayed: a stale paste is worse than no paste. |
| Deadline | `deadline_epoch_ms = now + input_deadline_ms` (5 000 by default). An expired object is removed and counted `input_dropped_total{reason="deadline"}`. |
| Replay on resume | the queued objects are sent in `input_seq` order, skipping the expired ones, followed by one `pressed_set`. |
| Local echo | the pointer overlay only. The overlay's position is authoritative at T3 and T4. Keys are never echoed. |

## 8.3 The hop rules

1. **The session's owner** puts input objects at the head of the control
   lane. They are never coalesced and never dropped for capacity. The
   replay guard keys on `(receiver_epoch, input_seq)` with a 4096-entry
   window, and a frame that fails validation is rejected whole.

2. **An intermediary** forwards input objects inline on the control lane,
   ahead of the queued objects, subject to the session's rate limit (the
   control lane allows 4 096 messages per second for an input burst).
   The forwarding is counted.

3. **The sender** consumes input on a dedicated worker, bounded at 64
   objects. The reader loop never waits for the injection: the injection
   result is reported asynchronously, and the time it took is measured
   separately from the time it waited. When the worker is full, pointer
   moves coalesce and the `pressed_set` and release objects are kept.
   The sender's deadline rule is: `now > deadline_epoch_ms` ⇒ drop and
   count — **except** for `release_all`, `pressed_set`, and any object
   with the `RELEASE` flag, which are always applied.

4. **The pressed-set protocol.** The receiver sends a `pressed_set`
   carrying the keys and buttons it holds, at resume and every
   `input_pressed_heartbeat = clamp(5 s, 2 × RTT, 30 s)`. The sender
   keeps its own pressed set, and on every `pressed_set` it releases
   every key and button it believes pressed that the set does not
   contain — counted, and that count must stay near zero in steady state.
   On a park, after `key_release_grace = 2 s` without the receiver, the
   sender releases everything for that receiver. On a session end, it
   releases everything through one `release_all` path.

5. **Deduplication.** The sender rejects an `(epoch, input_seq)` it has
   already seen within the window. A reordered object is applied if it is
   newer than the last applied sequence, and dropped otherwise. This
   makes the path effectively FIFO without requiring the transport to
   preserve order.

## 8.4 Why the local echo is a pointer only

On a two-second round-trip link, a pointer that follows the mouse only
after a round trip makes the surface feel broken. The pointer's true
position is the sender's anyway — the sender composites its own pointer
into the content — so the overlay is indicative, and the next object
reconciles it.

To keep it honest: the overlay is dimmed while the receiver has pending
cells, and hidden when the receiver is not live.

There is no text or keystroke echo. An echoed character the sender never
received is a data-integrity lie, and the receiver's input path is exactly
where a lie would do the most damage.
