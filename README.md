# WebSocket Lean (Experimental)

Experimental native Lean 4 implementation (self‑contained, pure Lean) of the WebSocket protocol (RFC 6455) core logic.

## Status

> [!WARNING]
> This is **not** production-ready. There is still **no real TCP / TLS layer**; the project currently focuses on correct framing, handshake logic, and internal state handling. Cryptographic pieces needed for the opening handshake (SHA‑1 + Base64) are implemented in pure Lean for experimentation (not performance‑tuned).

Implemented pieces:
* Frame data structures + encode/decode (base, 16‑bit, 64‑bit extended lengths).
* Masking logic (runtime tested; formal involution proof still pending).
* Real opening handshake logic: header validation + correct `Sec-WebSocket-Accept` (pure Lean SHA‑1 + Base64).
* Minimal HTTP request parser + convenience `upgradeRaw`.
* Control frame validation (FIN requirement, payload ≤125) and close frame construction / parsing with a subset of RFC close codes.
* Fragmentation assembler for continuation frames (reassembles text/binary messages, enforces control frame rules early).
* Protocol violation classification (initial subset) and mapping to close frames.
* Ping scheduler state (interval tracking) + basic tests.
* Deterministic pseudo‑random masking key generator (xorshift32) for fuzz / property tests.
* UTF‑8 validation for text frames (rejects overlongs, surrogates, invalid sequences) both single and fragmented message reassembly.
* Subprotocol negotiation scaffolding: selects first requested token from `Sec-WebSocket-Protocol` if present.
* Automatic pong generation upon receiving ping frames (within `handleIncoming`).
* Additional protocol violations surfaced: `unexpectedContinuation`, `textInvalidUTF8`.
* Comprehensive test suite: masking, encode/decode (masked & extended lengths), handshake RFC example, SHA‑1 vector, control frame validation, raw HTTP upgrade, upgrade error paths, close frame parsing, fragmentation sequence, ping scheduler, violation→close mapping, UTF‑8 invalid cases, subprotocol negotiation, unexpected continuation, auto‑pong.

Remaining / Next TODO:
* Networking:
	- (IN PROGRESS) Native TCP socket FFI shim (`c/ws_socket.c`) + `WebSocket.Net` accept & handshake helpers.
	- Integrate incremental loop with real socket transport (current shim returns raw bytes; still missing continuous event pump with backpressure / partial frame accumulation at transport layer).
	- TLS / WSS support (likely via external library binding; out of pure Lean scope initially).
* Protocol completeness:
	- UTF‑8 validation for close reasons (current implementation validates text messages; close payload reason still permissive) + possibly stricter error mapping.
	- Subprotocol selection strategy (priority / server preference) beyond "first token"; ability to reject when unsupported.
	- Extension negotiation hooks (e.g. permessage-deflate placeholder).
	- Configurable keepalive strategy (timers, missed pong detection) beyond automatic pong reply.
	- More protocol violation variants (reserved bits misuse already flagged; explicit invalid opcode signaling, continuation sequencing edge cases, oversized control frames already covered).
	- Close handshake flow helper (send/await close then shutdown).
* Formal verification / proofs:
	- Replace masking involution axiom with a proof.
	- Frame encode/decode roundtrip theorem (for valid frames under size bounds).
	- Length field correctness & absence of truncation/overflow.
	- (Optional) Justification / spec refinement relation for SHA‑1 implementation.
* Testing:
	- Property / fuzz tests for parser & roundtrip (random lengths, fragmentation patterns, masking) — scaffolding RNG present.
	- Negative tests (malformed headers, invalid opcodes, partial frames, wrong extended length sizes).
	- Deterministic seeds list for reproducible fuzz sessions.
* API surface:
	- High-level `Server` / `Client` modules with callback-based message handling.
	- Structured error & close event propagation.
	- Graceful shutdown and resource cleanup specification.
* Performance / ergonomics:
	- Optimize SHA‑1 and Base64 (current versions are clarity-oriented).
	- Streaming decode (incremental) rather than whole-buffer decode.
	- ByteArray builder utilities / zero‑copy slices.
* Documentation:
	- Add protocol state machine outline.
	- Document fragmentation invariants & assembler guarantees.
	- Developer guide for extending violations & close mappings.
	- Clarify current subprotocol negotiation strategy and how to extend it.

## Roadmap ( condensed )
1. Socket + incremental I/O layer; streaming decoder.
2. UTF‑8 & additional protocol validations (reserved bits, opcode range, continuation sequencing).
3. High‑level server/client API with clean close handshake management.
4. Formal proofs (masking involution → roundtrip → length safety) & property-based fuzz harness.
5. Subprotocol / extension negotiation stubs.
6. Automatic pong + keepalive strategy and liveness reasoning sketch.
7. Performance passes (buffer reuse, optimized crypto) once semantics solid.

## Building
Requires Lean 4 toolchain (see `lean-toolchain`).

```
lake build
```

Run tests:
```
lake exe tests
```

Minimal echo server prototype (in-progress networking):
```lean
import WebSocket
import WebSocket.Net
open WebSocket WebSocket.Net

def echoLoop (c : Conn) : IO Unit := do
	let bytes ← c.transport.recv
	if bytes.size = 0 then
		IO.println "[conn] closed"
	else
		let (c', events) ← WebSocket.handleIncoming c bytes
		for (opc,payload) in events do
			if opc = .text then
				let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload := payload }
				c'.transport.send (encodeFrame f)
		echoLoop c'

def main : IO Unit := do
	let lh ← openServer 9001
	IO.println "Listening on 0.0.0.0:9001"
	let rec acceptLoop : IO Unit := do
		match ← acceptAndUpgrade lh with
		| some c =>
				IO.println "Handshake complete"
				(echoLoop c) -- runs until close
				acceptLoop
		| none => IO.println "Handshake failed / timeout"; acceptLoop
	acceptLoop
```
NOTE: This is a blocking, single-connection-at-a-time demonstration; no concurrency, fragmentation buffering done only inside `handleIncoming` for individual frames. Production design should spawn lightweight tasks per connection and use an incremental buffer reader.

## Usage (future planned API)
```lean
import WebSocket
open WebSocket

-- Hypothetical high-level server, not yet implemented:
#check Role.client
```

## Contributing
PRs welcome: socket backends, UTF‑8 & validation layers, proofs, fuzzing harness, high-level API.

## License
MIT
