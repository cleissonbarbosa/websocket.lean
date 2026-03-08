# WebSocket Lean

[![CI](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml/badge.svg)](https://github.com/cleissonbarbosa/websocket.lean/actions/workflows/ci.yml) ![GitHub Release](https://img.shields.io/github/v/release/cleissonbarbosa/websocket.lean) ![Status](https://img.shields.io/badge/status-beta-yellow)

Lean 4 implementation of WebSocket protocol building blocks and server utilities.

The project is in beta and is aimed at development, experimentation, and incremental hardening. It already includes the core pieces needed to parse frames, perform the HTTP upgrade, assemble fragmented messages, run a server loop, and build example applications.

## What is in the repository

- Core protocol types and frame encoding/decoding.
- HTTP upgrade and handshake validation.
- Fragment reassembly and close frame helpers.
- Incremental connection loop with ping/pong handling.
- Async server utilities, event dispatching, backpressure, rate limiting, keepalive, and basic metrics.
- Example servers and a simple client.
- Test suite covering protocol, crypto, framing, fragmentation, handshake, UTF-8, FFI, integration, and rate limiting.

## Public entry points

The top-level import keeps a flat public namespace:

```lean
import WebSocket
```

For server-focused code, you can also import the aggregated server API:

```lean
import WebSocket.Server
import WebSocket.Server.Events
```

Important modules in this repository:

- `WebSocket` re-exports the core protocol and handshake modules.
- `WebSocket.Server` re-exports the higher-level server API.
- `WebSocket.Net` contains TCP and optional TLS transport helpers.
- `WebSocket.Client` contains a small client wrapper built on `connectClient`.

## Quick examples

Create and encode a text frame:

```lean
import WebSocket

open WebSocket

def bytes : ByteArray :=
  encodeFrame (makeTextFrame "hello")
```

Perform a raw HTTP upgrade:

```lean
import WebSocket

def maybeResponse :=
  WebSocket.upgradeRaw
    "GET /chat HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
```

Start an async server with an event handler:

```lean
import WebSocket
import WebSocket.Server
import WebSocket.Server.Events

open WebSocket WebSocket.Server

def runDemo : IO Unit := do
  let server ← mkAsyncServer { port := 9001 }
  let manager := mkEventManager
  let handler : EventHandler := fun event =>
    match event with
    | .message id .text payload =>
        IO.println s!"[{id}] {String.fromUTF8! payload}"
    | _ =>
        pure ()
  let (manager, _) := subscribe manager (.message none) handler
  runAsyncServer server (dispatch manager)
```

## Build and test

Requirements:

- Lean 4 toolchain from [lean-toolchain](lean-toolchain)
- Lake

Build the library and examples:

```bash
lake build
```

Run the test executable:

```bash
lake exe tests
```

The repository also includes a simple `Makefile` wrapper:

```bash
make build-lean
make perf
```

## Executables

The Lake configuration defines these executables:

- `echoServer`
- `advancedEchoServer`
- `enhancedEchoServer`
- `chatServer`
- `echoClient`
- `tlsEchoServer`
- `simpleTLSServer`
- `tests`

Most users should start with `enhancedEchoServer` or `chatServer` when exploring the server API.

## TLS status

TLS support uses runtime detection via `dlopen` — OpenSSL is loaded dynamically when needed. No build-time toggle or rebuild is required.

If OpenSSL (`libssl.so` + `libcrypto.so`) is installed on the host, TLS functions work automatically. Otherwise they return a descriptive error and everything else keeps working.

To enable TLS at runtime:

- Install OpenSSL: `sudo apt install libssl-dev` (Debian/Ubuntu) or equivalent.
- Or point `LD_LIBRARY_PATH` to a custom OpenSSL prefix: `LD_LIBRARY_PATH=/path/to/openssl/lib ./your-server`.
- Use `WebSocket.Net.tlsAvailableImpl` to check at runtime whether TLS is available.

No changes to `lakefile.lean` are needed. The same binary works with or without OpenSSL installed.

If TLS is not available at runtime, the TLS functions return an error.

For production deployments, a TLS-terminating reverse proxy is still the safer default unless you are explicitly validating the OpenSSL path and runtime behavior in your environment.

## Project status

Implemented and exercised in code:

- Frame parsing and encoding, including masking and control-frame validation.
- Fragmented message assembly.
- Handshake generation and validation.
- Subprotocol negotiation and extension parsing hooks.
- Incremental read loop with ping/pong support.
- Async server state, event subscriptions, graceful shutdown flow, and keepalive helpers.
- Rate limiting, backpressure helpers, and basic process metrics.
- Pure Lean SHA-1 and Base64 used during the handshake path.

Current limitations:

- The project is still beta.
- TLS is detected at runtime via dlopen (no rebuild needed).
- Native TLS support should be treated as experimental.
- Extension support is not comprehensive beyond parsing and validation hooks.
- More stress, interoperability, and long-run testing would still be useful.
- Formal verification work is still future work.

## Repository layout

- `WebSocket/` contains library code.
- `WebSocket/Tests/` contains the test suite.
- `Examples/` contains runnable examples.
- `scripts/` contains helper scripts for OpenSSL builds and test certificates.
- `vendor/openssl/` contains a vendored OpenSSL build used by the optional TLS path.

## Using as a dependency

In another Lean project, add the package with Lake:

```lean
require websocket from git "https://github.com/cleissonbarbosa/websocket.lean"
```

Then import the modules you need:

```lean
import WebSocket
import WebSocket.Server
```

## Examples to inspect

- `Examples/EchoServer.lean` is the simplest blocking prototype.
- `Examples/EnhancedEchoServer.lean` shows the async/event-driven server flow.
- `Examples/Chat/ChatServer.lean` shows a multi-client chat server.
- `Examples/EchoClient.lean` shows the client connection path.
- `Examples/TLSEchoServer.lean` and `Examples/SimpleTLSServer.lean` show the optional TLS path.

## Contributing

1. Make your changes.
2. Build the project.
3. Run `lake exe tests`.
4. Open a pull request with a concise description of behavior changes.

## License

[MIT](LICENSE)
