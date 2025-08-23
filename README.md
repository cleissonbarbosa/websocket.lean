# WebSocket Lean (Experimental)

Experimental native Lean 4 implementation (self‑contained, pure Lean) of the WebSocket protocol (RFC 6455) core logic.

## ✨ Recent Refactor (Modularization)
The original monolithic `WebSocket.lean` file was split into focused Lean source files. All symbols still live in the single namespace `WebSocket`, so existing user code that did `import WebSocket` keeps working.

Module files (all under `WebSocket/` unless noted):

| File | Responsibility |
|------|----------------|
| `Core/Types.lean` | Core protocol types: `OpCode`, `FrameHeader`, `Frame`, `ProtocolViolation`, masking key, etc. |
| `Core/Frames.lean` | Encode/decode logic + validation (`encodeFrame`, `decodeFrame`, `validateFrame`). |
| `Handshake.lean` | Handshake request/response models, header utilities, `acceptKey`. |
| `Upgrade.lean` | High-level upgrade functions (`upgradeE`, `upgrade`, `upgradeWithConfig`, `upgradeWithFullConfig`, `upgradeRaw`). |
| `Subprotocols.lean` | Subprotocol negotiation (`SubprotocolConfig`, `selectSubprotocol`). |
| `Extensions.lean` | Parsing + negotiation scaffolding for `Sec-WebSocket-Extensions`. |
| `Close.lean` | Close codes + `parseClosePayload`. |
| `Assembler.lean` | Fragmentation reassembly and close-frame builders (`processFrame`, `buildCloseFrame*`). |
| `Connection.lean` | Minimal transport abstraction + frame handling loop (`Transport`, `Conn`, `runLoop`, `handleIncoming`). |
| `KeepAlive.lean` | Ping/pong strategy + state (`PingState`, `KeepAliveStrategy`). |
| `Random.lean` | Simple deterministic RNG for masking fuzz (`RNG`, `randomMaskingKey`). |
| `UTF8.lean` | UTF‑8 validation used for text frames & close reasons. |
| `Crypto/Base64.lean` | Base64 implementation used in handshake. |
| `Crypto/SHA1.lean` | SHA‑1 implementation used in handshake. |
| `HTTP.lean` | Minimal HTTP request parser for upgrade. |
| `Net.lean` (WIP) | FFI socket shim integration (accept + upgrade helpers). |

Why a flat namespace? Keeping every module inside `namespace WebSocket` avoids breaking existing imports and simplifies referencing (no `WebSocket.Handshake.HandshakeRequest`, just `WebSocket.HandshakeRequest`). If future API versioning or hierarchical visibility is desired, we can introduce nested namespaces with compatibility aliases.

### Quick Import Examples
```lean
import WebSocket
open WebSocket

-- Build a close frame
def demoClose : Frame := buildCloseFrame CloseCode.normalClosure "bye"

-- Perform a basic upgrade from raw HTTP
def maybeResp := upgradeRaw "GET /chat HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
```

## Status

> [!WARNING]
> This is **not** production-ready. There is still **no real TCP / TLS layer**; the project currently focuses on correct framing, handshake logic, and internal state handling. Cryptographic pieces needed for the opening handshake (SHA‑1 + Base64) are implemented in pure Lean for experimentation (not performance‑tuned).

Implemented pieces (now organized across modules):
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
* Subprotocol negotiation (`Subprotocols.lean`) with configurable selection function.
* Extension parsing + conservative negotiation scaffolding (`Extensions.lean`).
* Automatic pong generation upon receiving ping frames (within `handleIncoming`).
* Additional protocol violations surfaced: `unexpectedContinuation`, `textInvalidUTF8`.
* Comprehensive test suite: masking, encode/decode (masked & extended lengths), handshake RFC example, SHA‑1 vector, control frame validation, raw HTTP upgrade, upgrade error paths, close frame parsing, fragmentation sequence, ping scheduler, violation→close mapping, UTF‑8 invalid cases, subprotocol negotiation, unexpected continuation, auto‑pong.

Remaining / Next TODO (updated after modular split):
* Networking:
	- (IN PROGRESS) Native TCP socket FFI shim (`c/ws_socket.c`) + `WebSocket.Net` accept & handshake helpers.
	- Integrate incremental loop with real socket transport (current shim returns raw bytes; still missing continuous event pump with backpressure / partial frame accumulation at transport layer).
	- TLS / WSS support (likely via external library binding; out of pure Lean scope initially).
* Protocol completeness:
	- Harden close reason validation (UTF‑8 + allowed codepoints) — text frame UTF‑8 already enforced.
	- Advanced subprotocol selection policies (server ordering, rejection rules already partially configurable via `SubprotocolConfig`).
	- Extension negotiation beyond structural parsing (e.g. permessage-deflate parameters, compression toggles).
	- Keepalive: integrate timing + missed pong tracking (`PingState` base exists) with loop scheduling.
	- Additional violation detection (fragment sequencing invariants, size thresholds, reserved bit semantics for negotiated extensions).
	- Close handshake helper (bidirectional close, timeout & draining).
* Formal verification / proofs:
	- Replace masking involution axiom with a proof (now isolated in `Core/Frames.lean`).
	- Frame encode/decode roundtrip theorem (valid frames / size bounds) referencing `validateFrame`.
	- Length correctness & overflow absence.
	- (Optional) SHA‑1 spec refinement argument.
* Testing:
	- Property / fuzz tests for parser & roundtrip (random lengths, fragmentation patterns, masking) — scaffolding RNG present.
	- Negative tests (malformed headers, invalid opcodes, partial frames, wrong extended length sizes).
	- Deterministic seeds list for reproducible fuzz sessions.
* API surface:
	- High-level `Server` / `Client` combinators (current `Connection.lean` is low-level, single-connection oriented).
	- Structured error & close event propagation events.
	- Resource cleanup / graceful shutdown orchestration.
* Performance / ergonomics:
	- Optimize SHA‑1 and Base64 (current versions are clarity-oriented).
	- Streaming decode (incremental) rather than whole-buffer decode.
	- ByteArray builder utilities / zero‑copy slices.
* Documentation:
	- Protocol state machine outline (opening → open → closing → closed).
	- Fragmentation invariants & assembler guarantees (conditions for `.continue` vs `.violation`).
	- Extending violation types + mapping to close codes (`violationCloseCode`).
	- Subprotocol & extension negotiation customization cookbook.
	- Keepalive behavior specification & liveness considerations.

## 🧱 Design Notes
* Flat namespace keeps ergonomics: every file contributes to `namespace WebSocket`.
* Separation makes each protocol concern auditable & testable in isolation (e.g. close parsing vs fragmentation assembly vs handshake purity).
* Future: if breaking API versioning is needed, introduce `WebSocket.V1.*` wrappers while keeping current flat modules as internal.

## 🧪 Testing
Run the full suite:
```bash
lake exe tests
```
Add new tests in `WebSocket/Tests/`—they can import only the modules they exercise (but `import WebSocket` still works as a shortcut).

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

## Example: Minimal echo server prototype (in-progress networking)
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
PRs welcome: socket backends, UTF‑8 & validation layers, proofs, fuzzing harness, high-level API, better keepalive runtime, extension negotiation strategies, and documentation improvements.

## License
MIT
