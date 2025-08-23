# WebSocket Lean (Experimental)

Experimental native Lean 4 implementation (self‑contained, pure Lean) of the WebSocket protocol (RFC 6455) core logic.

## ✨ Recent Refactor (Modularization)
The original monolithic `WebSocket.lean` file was split into focused Lean source files. All symbols still live in the single namespace `WebSocket`, so existing user code that did `import WebSocket` keeps working.

Why a flat namespace? Keeping every module inside `namespace WebSocket` avoids breaking existing imports and simplifies referencing (no `WebSocket.Handshake.HandshakeRequest`, just `WebSocket.HandshakeRequest`). If future API versioning or hierarchical visibility is desired, we can introduce nested namespaces with compatibility aliases.

### Quick Import Examples
```lean
import WebSocket
import WebSocket.Server
import WebSocket.Server.Events
open WebSocket WebSocket.Server

-- Build a close frame
def demoClose : Frame := buildCloseFrame CloseCode.normalClosure "bye"

-- Perform a basic upgrade from raw HTTP
def maybeResp := upgradeRaw "GET /chat HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"

-- Async server + event system (simplified):
def runDemo : IO Unit := do
	let srv ← mkAsyncServer { port := 9001 }
	let em0 := mkEventManager
	-- Subscribe to every text message
	let handler : EventHandler := fun ev =>
		match ev with
		| .message id .text payload => IO.println s!"[text:{id}] {String.fromUTF8! payload}"
		| _ => pure ()
	let (em1, _) := subscribe em0 (.message none) handler
	runAsyncServer srv (dispatch em1)
```

## Status

> [!WARNING]
> This is **not** production-ready. There is still **no real TCP / TLS layer**; the project currently focuses on correct framing, handshake logic, and internal state handling. Cryptographic pieces needed for the opening handshake (SHA‑1 + Base64) are implemented in pure Lean for experimentation (not performance‑tuned).

✨ **NEW FEATURES (v0.2.0):**
- **Event subscription system**: Subscribe to specific events with filters (`EventManager`, `subscribe`, `dispatch`)
- **Graceful close handshake**: Proper WebSocket close protocol with timeout handling (`initiateClose`, `processCloseTimeouts`)
- **Async server loop**: Non-blocking server with task management (`AsyncServerState`, `runAsyncServer`, `runAsyncServerUpdating`)
- **Keep-alive integration**: Automated ping/pong with configurable intervals and timeout detection
- **Comprehensive integration tests**: Full test suite for new functionality

Implemented pieces (now organized across modules):
* Frame data structures + encode/decode (base, 16‑bit, 64‑bit extended lengths).
* Masking logic (runtime tested; formal involution proof still pending).
* Real opening handshake logic: header validation + correct `Sec-WebSocket-Accept` (pure Lean SHA‑1 + Base64).
* Minimal HTTP request parser + convenience `upgradeRaw`.
* Control frame validation (FIN requirement, payload ≤125) and close frame construction / parsing with a subset of RFC close codes.
* Fragmentation assembler for continuation frames (reassembles text/binary messages, enforces control frame rules early).
* Protocol violation classification (subset) and concrete mapping to RFC close codes (UTF‑8 → 1007, size limit → 1009, structural → 1002) with automatic close frame emission.
* Ping scheduler state (interval tracking) + basic tests.
* Deterministic pseudo‑random masking key generator (xorshift32) for fuzz / property tests.
* UTF‑8 validation for text frames (rejects overlongs, surrogates, invalid sequences) both single and fragmented message reassembly.
* Subprotocol negotiation (`Subprotocols.lean`) with configurable selection function.
* Extension parsing + conservative negotiation scaffolding (`Extensions.lean`).
* Automatic pong generation upon receiving ping frames (within `handleIncoming`).
* Enhanced frame decoder (`decodeFrameEnhanced`) integrated into connection loop (detects reserved bits & invalid opcodes early).
* Additional protocol violations surfaced: `unexpectedContinuation`, `textInvalidUTF8`, `fragmentSequenceError`, `oversizedMessage`.
* Comprehensive test suite: masking, encode/decode (masked & extended lengths), handshake RFC example, SHA‑1 vector, control frame validation, raw HTTP upgrade, upgrade error paths, close frame parsing, fragmentation sequence, ping scheduler, violation→close mapping, UTF‑8 invalid cases, subprotocol negotiation, unexpected continuation, auto‑pong, invalid opcode, size limit & fragmentation errors, keepalive logic.

Remaining / Next TODO (updated after modular split):
* Networking:
	- (IN PROGRESS) Native TCP socket FFI shim (`c/ws_socket.c`) + `WebSocket.Net` accept & handshake helpers. (basic listen/accept + upgrade implemented)
	- Integrate incremental loop with real socket transport (current shim returns raw bytes; still missing continuous event pump with backpressure / partial frame accumulation at transport layer).
	- TLS / WSS support (likely via external library binding; out of pure Lean scope initially).
* Protocol completeness:
	- Harden close reason validation (UTF‑8 + allowed codepoints) — text frame UTF‑8 already enforced; close reason filtering partially present (printable + control subset) but needs full RFC constraints.
	- Advanced subprotocol selection policies (server ordering, rejection rules already partially configurable via `SubprotocolConfig`).
	- Extension negotiation beyond structural parsing (e.g. permessage-deflate parameters, compression toggles).
	- Keepalive: integrate timing + missed pong tracking (`PingState` base exists) with loop scheduling (strategy + missed pong counter implemented; not yet wired into loop timing logic).
	- Additional violation detection: reserved bits (DONE), invalid opcodes (DONE), unexpected continuation (DONE), text invalid UTF‑8 (DONE), close payload validation (DONE), fragmentation sequencing (DONE: `fragmentSequenceError`), size thresholds (DONE: `oversizedMessage` with configurable max message size), remaining: reserved bit semantics for negotiated extensions.
	- Close handshake helper (bidirectional close, timeout & draining).
* Formal verification / proofs:
	- Replace masking involution axiom with a proof (now isolated in `Core/Frames.lean`).
	- Frame encode/decode roundtrip theorem (valid frames / size bounds) referencing `validateFrame`.
	- Length correctness & overflow absence.
	- (Optional) SHA‑1 spec refinement argument.
* Testing:
	- Property / fuzz tests for parser & roundtrip (random lengths, fragmentation patterns, masking) — scaffolding RNG present.
	- Negative tests (malformed headers, invalid opcodes, partial frames, wrong extended length sizes) — some covered, expand further.
	- Deterministic seeds list for reproducible fuzz sessions.
	- (NEW) Added tests for `oversizedMessage` and `fragmentSequenceError`.
* API surface:
	- High-level `Server` / `Client` combinators (current `Connection.lean` is low-level, single-connection oriented).
	- Structured error & close event propagation events.
	- Resource cleanup / graceful shutdown orchestration.
* Performance / ergonomics:
	- Optimize SHA‑1 and Base64 (current versions are clarity-oriented).
	- Streaming decode (incremental) rather than whole-buffer decode (infra parcial: draining buffer + decoder aprimorado; falta integração completa no servidor e multiplexação).
	- ByteArray builder utilities / zero‑copy slices.
* Documentation:
	- Protocol state machine outline (opening → open → closing → closed).
	- Fragmentation invariants & assembler guarantees (conditions for `.continue` vs `.violation`).
	- Extending violation types + mapping to close codes (`violationCloseCode`).
	- Subprotocol & extension negotiation customization cookbook.
	- Keepalive behavior specification & liveness considerations (partially implemented behavior needs narrative/spec).

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

## Roadmap (condensed / updated)
1. ✅ **COMPLETED**: Integrate incremental buffered loop into server (multi-connection, non-blocking); concurrency & graceful shutdown primitives.
2. ✅ **COMPLETED**: Close handshake orchestration (bidirectional: respond + drain + timeout) and structured disconnect events w/ code & reason.
3. ✅ **COMPLETED**: Keepalive runtime: timed ping emission + missed pong policy using existing `PingState`.
4. ✅ **COMPLETED**: Event subscription/dispatch system with filtering for easy integration.
5. ✅ **COMPLETED**: Integration tests covering server functionality and new features.
6. **NEXT**: Client implementation (connect + HTTP upgrade + validate response headers & negotiated subprotocol/extensions).
7. **NEXT**: Extension semantics (permessage-deflate stub, RSV bit enforcement) and documentation of extension safety.
8. **NEXT**: Formal proofs: masking involution → frame roundtrip → length safety; property-based fuzz harness (fragmentation, masking, random sizes).
9. **NEXT**: Performance passes: buffer reuse, zero-copy slices, optimized SHA‑1/Base64.

## Building
Requires Lean 4 toolchain (see `lean-toolchain`).

```
lake build
```

Run tests:
```
lake exe tests
```

## Example: Minimal Echo Server (Blocking Prototype)
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
	let cfg : UpgradeConfig := { subprotocols := { supported := ["chat.v1"], rejectOnNoMatch := false } }
	let rec acceptLoop : IO Unit := do
		match ← acceptAndUpgradeWithConfig lh cfg with
		| some (tcpConn, subp?, _) =>
				IO.println s!"Handshake complete (subprotocol?={subp?})"
				(echoLoop (tcpConn : Conn))
				acceptLoop
		| none => IO.println "Handshake failed / timeout"; acceptLoop
	acceptLoop
```
NOTE: This is a blocking, single-connection-at-a-time demonstration kept for historical context. Prefer the async example below.

## Example: Enhanced Async Echo Server (current approach)

See `WebSocket/Examples/EnhancedEchoServer.lean` for the full version (keep-alive + events + echo). A reduced core excerpt:

```lean
import WebSocket
import WebSocket.Server
import WebSocket.Server.Events
open WebSocket WebSocket.Server

def main : IO Unit := do
	let cfg : ServerConfig := { port := 9001, pingInterval := 15, maxMissedPongs := 2 }
	-- Create & start base inside async wrapper
	let async0 ← mkAsyncServer cfg
	let started ← WebSocket.Server.Accept.start async0.base
	let async := { async0 with base := started }

	-- Event manager + echo side-effects via IO.Ref updated by runAsyncServerUpdating
	let em0 := mkEventManager
	let (em1, _) := subscribe em0 (.message none) (fun ev => match ev with
		| .message id .text payload => IO.println s!"[recv {id}] {String.fromUTF8! payload}"
		| _ => pure ())

	let ref ← IO.mkRef async
	let handler : EventHandler := fun ev => do
		dispatch em1 ev
		match ev with
		| .message id .text payload => do
				let s ← ref.get
				let sBase ← WebSocket.Server.Messaging.sendText s.base id s!"Echo: {String.fromUTF8! payload}"
				ref.set { s with base := sBase }
		| _ => pure ()
	runAsyncServerUpdating ref handler
```

`runAsyncServerUpdating` mantém o `AsyncServerState` sincronizado com novas conexões, permitindo que handlers façam side‑effects (envio de frames) sem “perder” a conexão recém aceita.

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
