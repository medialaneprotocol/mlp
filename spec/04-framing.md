# 4. Framing

This section is the wire format: what a fragment is, what its header says,
what the header extension may carry, and how fragments become objects.

## 4.1 Carriers

| Carrier | One transport message contains | Payload cap | Used by |
|---|---|---|---|
| WebSocket | exactly **one** MLP fragment | `MAX_WS_FRAGMENT = 65 536` B | the stream path |
| gRPC | 1..N concatenated MLP fragments (self-delimiting) | `MAX_GRPC_COALESCE = 65 536` B | the stream path |
| WebRTC data channel | exactly one fragment per message | `TARGET_FRAGMENT_PAYLOAD = 1 150` B | the datagram path |
| QUIC | 1..N concatenated MLP fragments (self-delimiting) | `MAX_GRPC_COALESCE = 65 536` B | the stream path |

On every carrier the fragment byte layout is identical; only the message
boundary differs. A receiver accepts 1..N fragments per received message on
a stream carrier and exactly 1 on a datagram carrier.

A *stream* carrier preserves order and is reliable at the transport level,
so the protocol's own loss is rare and mostly a matter of the carrier
dropping. A *datagram* carrier may lose, duplicate, and reorder, which is
why the protocol's own accounting (§6.5) exists at all.

## 4.2 Fragment header

Little-endian throughout. Offsets are from the first byte of the fragment.

| off | size | field | type | semantics and validation |
|---|---|---|---|---|
| 0 | 4 | `magic` | `[u8;4]` | `4D 4C 50 00` (`"MLP\0"`). Any other prefix rejects the whole transport message with `BAD_MAGIC` — counted, never a close. |
| 4 | 1 | `version` | u8 | `1`. Any other value ⇒ `UNSUPPORTED_VERSION`: the object is dropped and the lane sends `MediaError{code=UNSUPPORTED_VERSION}` once per session. |
| 5 | 1 | `class` | u8 | `0=CONTROL`, `1=CURSOR`, `2=MEDIA`, `3=FEEDBACK`, `4=PATH`; `5..255` reserved ⇒ `BAD_CLASS` (drop). Input and session control never appear on the media lane. |
| 6 | 1 | `flags` | bits | bit0 `FIN` (last fragment of the object), bit1 `ANCHOR` (the object's content is absolute: it may be applied onto any held state), bit2 `RETRANSMIT` (the sender's own resend), bit3 `DUP` (a deliberate duplicate of an echo-critical object), bit4 `ECHO_REQUESTED` (the receiver must reply with `ECHO_OF_OBJECT_ID` and timestamps), bit5 `PROBE` (a probe object), bit6 `URGENT` (control: drain before queued media), bit7 reserved, **must be 0** ⇒ `BAD_FLAGS`. |
| 7 | 1 | `priority` | u8 | `0..7`, `0` highest. A fragment whose `class == MEDIA` may not use `0` or `1` (`BAD_PRIORITY`): those are reserved for control, pointer and feedback, so the media pacer can never starve the reserved rate. Within `class == MEDIA`, `6` is interactive media and `7` is background refresh. |
| 8 | 4 | `object_id` | u32 | monotone per (lane, direction, sender epoch) — **per sender**: a lane carries objects from several senders and each numbers its own. A wrap is rejected (`OBJECT_ID_WRAP`). `0` is reserved for "no object" in `ECHO_OF_OBJECT_ID`. The object id identifies an object for deduplication (§4.4) and nothing else: a receiver MUST NOT read a gap in the object-id sequence as loss (§5.1.1, §5.2). |
| 12 | 2 | `fragment_index` | u16 | `0..fragment_count-1` ⇒ else `BAD_FRAGMENT`. |
| 14 | 2 | `fragment_count` | u16 | `1..=MAX_FRAGMENT_COUNT (4096)` ⇒ else `BAD_FRAGMENT`. |
| 16 | 4 | `payload_len` | u32 | `0..=the carrier's payload cap` ⇒ else `BAD_LENGTH`. |
| 20 | 2 | `header_ext_len` | u16 | `0` or `2..=MAX_HEADER_EXT (256)`, and the remaining bytes must parse as whole TLVs ⇒ else `BAD_EXT`. |
| 22 | `header_ext_len` | `header_ext` | TLV | zero or more `u8 type, u8 len, len bytes value`. An unknown type is skipped. A TLV whose `len` runs past the extension ⇒ `BAD_EXT`. |
| 22+ext | `payload_len` | `payload` | bytes | the class-specific body (§5). |

`FRAGMENT_FIXED_HEADER = 22` bytes. The overhead per fragment on the
datagram carrier is `22 + 4..20 (TLVs) + the carrier's own headers ≈ 90`,
so ≈ 115 B of 1 150 (10 %), which is accepted.

**Unknown TLVs are preserved, not just skipped.** A hop that forwards a
fragment it does not interpret MUST carry the extension through unchanged,
so that a peer behind it still sees what it expects.

## 4.3 Header extension TLV registry

The registry is the protocol's own vocabulary. It names what the protocol
accounts for — an update's identity, its chain, its epoch — and it does not
name what an update's content means.

| type | name | len | value | class | semantics |
|---|---|---|---|---|---|
| `0x01` | `UPDATE_ID` | 8 | u64 | C3 | the update this fragment belongs to |
| `0x02` | `UPDATE_BASE` | 8 | u64 | C3 | the update this one continues; `0` = self-contained |
| `0x03` | `PART` | 4 | u16 index ‖ u16 count | C3 | this fragment's part within its update, so a hop can coalesce without decoding the body |
| `0x04` | `UPDATE_BYTES` | 4 | u32 | C3 | the update's total payload bytes |
| `0x05` | `CHAIN_EPOCH` | 4 | u32 | C3 | the chain epoch; changes when the sender breaks the chain |
| `0x06` | `REFLECTS_INPUT_SEQ` | 8 | u64 | C3 | the highest input sequence whose effect the update's content includes (N-1) |
| `0x07` | `SEND_EPOCH_MS` | 8 | u64 | C3,C4 | the sender's session-relative ms at first emission; preserved verbatim on `RETRANSMIT` and quoted verbatim in a probe's echo, which is what makes the round-trip time and the echo computable without wall clocks |
| `0x08` | `DEADLINE_EPOCH_MS` | 8 | u64 | C3,C4 | the absolute session-relative deadline; a receiver past it drops the object and counts `expired` |
| `0x09` | `ECHO_OF_OBJECT_ID` | 4 | u32 | C4 | the object being echoed or acknowledged |
| `0x0A` | `BUDGET_BYTES` | 4 | u32 | C4 | the sender's current per-update budget (receiver-visible diagnostics) |
| `0x0B` | `PACE_BPS` | 4 | u32 | C4 | the sender's current pace (diagnostics, and the receiver's input-queue sizing) |
| `0x0C` | `PATH_HINT` | 1 | u8 | C5 | the carrier the sender believes is active: `0=unknown, 1=stream, 2=dc-direct, 3=dc-turn, 4=quic` |
| `0x0D` | `INPUT_SEQ` | 8 | u64 | C1 | the input object's sequence |
| `0x0E` | `CELL_COUNT` | 4 | u32 | C3,C4 | the sender's repair-grid size, for the staleness arithmetic |
| `0x0F` | `COST_MS` | 2 | u16 | C4 | a hop's measured processing cost |
| `0x10`–`0xEF` | reserved | — | — | — | skipped by receivers, ignored, never an error |
| `0xF0`–`0xFF` | experimental | — | — | — | accepted, skipped, and counted `experimental_tlv_total` |

A receiver that finds contradictory duplicate information — the same TLV
type twice with different values, or a TLV that disagrees with the body it
mirrors — rejects the object with `META_MISMATCH`. It never "trusts one of
the two".

## 4.4 Object lifecycle and assembly (normative)

```
accept_fragment(message):
  1  validate the header: magic, version, class, flags, priority, ids,
     lengths                                  else reject(reason)   [§4.2]
  2  parse the extension; unknown types are skipped and preserved
                                                 else reject(BAD_EXT)
  3  carrier rule: a datagram carrier accepts exactly one fragment
                                                 else reject(BAD_FRAGMENT)
  4  deadline: if SEND_EPOCH_MS and DEADLINE_EPOCH_MS are present and the
     deadline has passed                    else drop(expired) + counter
  5  deduplicate by (object_id, fragment_index) within the window
                                                 else drop(duplicate)
  6  join the object's fragment set; a fragment whose fragment_count
     disagrees with the open object          else reject(BAD_FRAGMENT)
  7  the object is complete when every index has arrived and FIN was seen
     otherwise keep it open until
     ASSEMBLY_TIMEOUT = 3 × RTT + 500 ms      else reject(ASSEMBLY_TIMEOUT)
  8  validate the class body                  else reject(the class's reason)
```

**Object state is per lane and bounded:** `MAX_OPEN_OBJECTS = 4` and
`MAX_ASSEMBLY_BYTES = 1 MiB`. Exceeding either evicts the oldest incomplete
object with `ASSEMBLY_EVICTED`, counted.

**A hop forwards whole objects only.** It reassembles fragments into one
object and replays the original encoded bytes; a partial object is never
handed to a peer lane.

**A fragment set is applied atomically.** All fragments of an object or
none of it: the receiver either holds the object whole or does not hold it.

## 4.5 The update model

An update is the protocol's unit of media state, and it has two shapes:

- A **self-contained** update carries `update_base = 0`. It establishes the
  surface on its own and any receiver may apply it whatever it currently
  holds.
- A **chained** update carries `update_base > 0`: the id of the update it
  continues. A receiver applies it only onto exactly that state.

This is the whole loss-recovery contract, and it is the protocol's, not a
codec's: a receiver that does not hold the base refuses the update and says
so, and a sender that learns of the refusal knows precisely which surface
the receiver is missing.

A receiver's obligation is precise:

- if the update is chained and the receiver does not hold the named base,
  it refuses the update and reports the base it does hold;
- if the update is self-contained, it may apply it onto whatever it holds,
  and the sender's per-receiver accounting is what makes that safe.

The sender's obligation is equally precise: it MUST know, for every
receiver, which cells that receiver may be stale in. §6.5 is how.
