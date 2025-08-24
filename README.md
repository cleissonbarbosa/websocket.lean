# WebSocket Lean

[![CI](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml/badge.svg)](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml) | ![GitHub Release](https://img.shields.io/github/v/release/cleissonbarbosa/websocket.lean) | ![Status](https://img.shields.io/badge/status-experimental-orange)

Experimental (not production‑ready) Lean 4 native implementation of the WebSocket protocol (RFC 6455). Includes: frame encoding/decoding & validation, fragmented message assembly, HTTP handshake with subprotocol & extension negotiation, keep‑alive (ping/pong) state, close frame construction & mapping from violations, and an incremental event‑oriented loop.

Primary goals: clarity, auditability and a path toward partial formal verification — not raw performance (yet).

## ✨ Recent Modularization

The original monolithic `WebSocket.lean` file was split into focused Lean source files. All symbols still live in the single namespace `WebSocket`, so existing user code that did `import WebSocket` keeps working.

Why a flat namespace? Every file contributes to `namespace WebSocket`, so users keep a single ergonomic import (`import WebSocket`) and existing code does not churn. If semantic versioning later demands namespacing (e.g. `WebSocket.V1`), compatibility aliases can be layered without breaking existing usage.

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

## Project Status

> [!WARNING]
> Do not use in production. Still missing: TLS/WSS, robust backpressure, real extension semantics (permessage‑deflate is only a stub), full formal proofs, and performance passes.

Implemented today:

- Full framing (7/16/64‑bit lengths, masking, violation detection, control frame validation).
- Fragmented message assembly with invalid sequence detection and configurable max size (`oversizedMessage`).
- HTTP handshake with configurable `UpgradeConfig` (subprotocol selection + preliminary extension negotiation: parse only, no compression yet).
- Close frame construction/parsing and violation→close code mapping.
- Keep‑alive infrastructure (ping scheduler + pong tracking) ready; integrated into async examples.
- Incremental loop (buffer + progressive decode) with auto‑pong for received pings.
- Experimental TCP client (`WebSocket.Net.connectClient`) validating `Sec-WebSocket-Accept`.
- Pure Lean SHA‑1 & Base64 (clarity over speed) used during handshake.

Key limitations:

- No TLS (`wss://`).
- No effective extension semantics (RSV bits only sanity‑checked).
- No formal proofs yet for frame roundtrip / size safety (targets listed below).
- Minimal networking shim: no epoll, no advanced multiplexing/backpressure.
- No adaptive memory limits or deep fragmentation attack mitigation beyond basic checks.

## ✅ / 🔜 Condensed Roadmap

Current status vs planned items:

- ✅ Incremental loop with buffering + auto‑pong (`stepIO` / `runLoop`).
- ✅ Configurable handshake (subprotocol + parsed extensions) via `UpgradeConfig`.
- ✅ Initial client (`connectClient`).
- ✅ Server events + subscription system (`WebSocket.Server.Events`).
- ✅ Keepalive infra / ping-pong state (base integration; timeout policies may evolve).
- ✅ Close frames: build/parse + violation mapping.
- 🔜 TLS (external bindings / wrapper).
- 🔜 Extension semantics (real permessage‑deflate + contextual RSV enforcement).
- 🔜 Formal properties: masking involution, frame roundtrip, length bounds & overflow freedom.
- 🔜 Fuzz/property harness (random fragmentation, masking patterns, large sizes).
- 🔜 Performance: zero‑copy slices, reusable buffers, optimized SHA‑1 / Base64.
- 🔜 Server lifecycle: full graceful shutdown (drain + broadcast) & backpressure strategy.

## 🧩 Planned Formal Verification Tasks

1. Masking involution proof (eliminate temporary axiom in `Core/Frames`).
2. Encode/decode roundtrip theorem for valid frames (+ payload length bounds).
3. Assembler invariant: well‑formed fragmentation sequences never spuriously violate.
4. (Optional) SHA‑1 refinement / correspondence with spec.

## 🛠️ Quick API Ergonomics

Create a text frame:

```lean
let f := WebSocket.makeTextFrame "hello"
let bytes := WebSocket.encodeFrame f
```

Incremental processing loop:

```lean
import WebSocket
open WebSocket

def loop (ls : LoopState) : IO Unit := do
	let (ls', events) ← stepIO ls
	for (opc,payload) in events do
		match opc with
		| .text => IO.println (String.fromUTF8! payload)
		| .ping => IO.println "PING (auto-pong sent)"
		| _ => pure ()
	loop ls'
```

Manual raw HTTP upgrade:

```lean
match WebSocket.upgradeRaw rawRequestString with
| some resp => -- write 101 response
| none => -- failed
```

Configurable upgrade:

```lean
let cfg : UpgradeConfig := { subprotocols := { supported := ["chat.v1"], rejectOnNoMatch := false } }
-- Used with acceptAndUpgradeWithConfig
```

Experimental client:

```lean
match ← WebSocket.Net.connectClient "localhost" 9001 "/" ["chat.v1"] with
| some conn => -- use in incremental loop
| none => IO.println "Connection failed"
```

## 🧱 Design Notes

- Flat namespace keeps ergonomics: every file contributes to `namespace WebSocket`.
- Separation makes each protocol concern auditable & testable in isolation (e.g. close parsing vs fragmentation assembly vs handshake purity).
- Future: if breaking API versioning is needed, introduce `WebSocket.V1.*` wrappers while keeping current flat modules as internal.

## 🧪 Testing

Run the full suite:

```bash
lake test
```

Add new tests in `WebSocket/Tests/`—they can import only the modules they exercise (but `import WebSocket` still works as a shortcut).

## 🔄 Build

Requires Lean 4 toolchain (see `lean-toolchain`).

```bash
lake build
```

Produced executables (after build):

- `echoServer`, `advancedEchoServer`, `enhancedEchoServer` – echo server variants (blocking → async + events + keepalive).
- `chatServer` – multi‑client broadcast/chat with nicknames.
- `echoClient` – experimental TCP/WebSocket client.
- `tests` – test driver.

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

NOTE: Historical single‑connection blocking prototype. Prefer async examples (`enhancedEchoServer`).

## Example: Enhanced Async Echo Server

See `Examples/EnhancedEchoServer.lean` for the full version (keep‑alive + events + echo + multiple connections). Use it as a template for custom apps.

## Example: Multi‑Client Chat (Broadcast + Commands)

Full chat (nicknames, broadcast, simple commands) in `Examples/Chat/ChatServer.lean` (binary: `chatServer`).

External minimal project using this library with a simple front-end: https://github.com/cleissonbarbosa/example-chat-lean4

## Contributing

1. Fork the repository.
2. Make your changes.
3. Run `lake test` to ensure everything works.
4. Open a PR with a clear description & any compatibility notes.

## License

[MIT](LICENSE)

---

Feedback, issues and PRs welcome. Medium‑term aim: layer in formal verification of core safety & correctness properties.
