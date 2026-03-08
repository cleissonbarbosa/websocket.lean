# WebSocket Lean

[![CI](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml/badge.svg)](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml) | ![GitHub Release](https://img.shields.io/github/v/release/cleissonbarbosa/websocket.lean) | ![Status](https://img.shields.io/badge/status-beta-yellow)

**Beta** Lean 4 native implementation of the WebSocket protocol (RFC 6455). Includes: frame encoding/decoding & validation, fragmented message assembly, HTTP handshake with security validation, keep‑alive (ping/pong) state, close frame construction & mapping from violations, backpressure mechanisms, rate limiting, graceful shutdown, and monitoring.

Primary goals: security, reliability, observability, and eventual production readiness with formal verification foundations.

> [!INFO]
> This library is currently in **beta** status.

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

> [!NOTE]
> Beta release with core WebSocket functionality implemented. Recommended for development and testing. For production use, deploy behind a TLS-terminating reverse proxy and thoroughly test your specific use case.

Implemented today:

- ✅ **Full framing** (7/16/64‑bit lengths, masking, violation detection, control frame validation).
- ✅ **Fragmented message assembly** with invalid sequence detection and configurable max size.
- ✅ **Hardened HTTP handshake** with security validation (CRLF injection prevention, version enforcement, header validation).
- ✅ **Close frame construction/parsing** and violation→close code mapping.
- ✅ **Keep‑alive infrastructure** (ping scheduler + pong tracking) integrated into async examples.
- ✅ **Incremental loop** (buffer + progressive decode) with auto‑pong for received pings.
- ✅ **Backpressure mechanisms** with configurable high/low watermarks and send queue management.
- ✅ **Rate limiting** for handshake attempts with configurable windows and block durations.
- ✅ **Graceful shutdown** with connection draining and timeout handling.
- ✅ **Comprehensive metrics** (connections, frames, violations, backpressure events).
- ✅ **TCP client** (`WebSocket.Net.connectClient`) validating `Sec-WebSocket-Accept`.
- ✅ **Pure Lean SHA‑1 & Base64** (clarity over speed) used during handshake.

Implemented hardening:

- 🔒 **Security hardening** (handshake validation, injection prevention, header sanitization)
- 📊 **Observability** (structured logging, metrics collection, monitoring integration)
- ⚡ **Performance controls** (backpressure, rate limiting, resource limits)
- 🔄 **Reliability** (graceful shutdown, connection draining, error recovery)
- 📈 **Scalability** (configurable limits, efficient resource usage)

Remaining for future enhancement:

- TLS/WSS native support (currently deploy behind TLS reverse proxy)
- Extension semantics beyond RSV validation
- Formal verification proofs for critical properties
- Advanced networking features (epoll integration)

## ✅ Features Implemented

Core WebSocket functionality has been completed:

- ✅ **Incremental loop** with buffering + auto‑pong (`stepIO` / `runLoop`).
- ✅ **Hardened handshake** with security validation, CRLF injection prevention, version enforcement.
- ✅ **Configurable handshake** (subprotocol + parsed extensions) via `UpgradeConfig`.
- ✅ **Backpressure system** with configurable high/low watermarks and send queue management.
- ✅ **Rate limiting** for handshake attempts with configurable windows and block durations.
- ✅ **Graceful shutdown** with connection draining, timeout handling, and resource cleanup.
- ✅ **Comprehensive metrics** (connections, frames, violations, backpressure events).
- ✅ **TCP client** (`connectClient`) with handshake validation.
- ✅ **Server events** + subscription system (`WebSocket.Server.Events`).
- ✅ **Keepalive infrastructure** / ping-pong state with timeout policies.
- ✅ **Close frames**: build/parse + violation mapping with proper error responses.
- ✅ **Security hardening**: header validation, injection prevention, resource limits.
- ✅ **Observability**: structured logging, metrics collection, monitoring integration.

## 🚀 Production Readiness

This WebSocket implementation has the following status:

### ✅ Implemented
- **Core Protocol**: Full RFC 6455 compliance for basic operations
- **Security**: Handshake validation, injection prevention, rate limiting
- **Reliability**: Backpressure, graceful shutdown, connection draining
- **Observability**: Basic metrics, structured logging

### ⚠️ Limitations
- **No Native TLS**: Requires reverse proxy for WSS support
- **Limited Testing**: Needs more stress and integration testing
- **Performance**: Not optimized for high-throughput scenarios
- **Formal Verification**: Proofs not yet completed

### Recommended Setup for Testing/Development

```bash
# Deploy behind TLS reverse proxy (nginx/haproxy)
# Configure appropriate limits based on your use case:

let serverConfig : ServerConfig := {
  port := 8080,
  maxConnections := 10000,
  rateLimit := {
    maxRequests := 100,     -- per time window
    timeWindowSeconds := 60,
    blockDurationSeconds := 300,
    enabled := true
  },
  handshakeTimeout := 10,
	idleTimeout := 300,
	maxMessageSize := 10 * 1024 * 1024,
	maxFragmentsPerMessage := 128,
	maxFrameSize := 1024 * 1024
}
```

Native TLS remains opt-in and is disabled by default in the current build configuration. For production, prefer TLS termination in a reverse proxy unless you are explicitly validating the OpenSSL path in your environment.

### Required for Production

- 🔜 TLS/WSS native support (deploy behind TLS reverse proxy for now)
- 🔜 Extension semantics beyond RSV validation
- 🔜 Formal verification proofs for critical security properties
- 🔜 Advanced networking features (epoll integration)
- 🔜 Performance optimizations (zero-copy, SIMD operations)

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

Feedback, issues and PRs welcome. Long-term aim: achieve production readiness with formal verification of core safety & correctness properties.

## Known Issues

See [AUDIT_REPORT.md](AUDIT_REPORT.md) for a detailed security and reliability audit.

## Disclaimer

This library is provided as-is for educational and development purposes. Use in production environments is at your own risk. The maintainers recommend thorough testing and security review before any production deployment.
