import WebSocket
import WebSocket.Net
import WebSocket.Server
import WebSocket.Server.Events
import WebSocket.Server.KeepAlive
import WebSocket.Server.Async
import WebSocket.Server.Messaging
open WebSocket WebSocket.Net WebSocket.Server WebSocket.Server.Async

/-!
 Enhanced Echo Server Example

 This example demonstrates the new server capabilities:
 * Event subscription system
 * Graceful close handling
 * Keep-alive ping integration
 * Async server loop
-/

namespace WebSocket.Examples

open WebSocket.Server.Async

/-- Helper: send text via AsyncServerState updating internal base. -/
def sendTextAsync (s : AsyncServerState) (connId : Nat) (text : String) : IO AsyncServerState := do
  let newBase ← WebSocket.Server.Messaging.sendText s.base connId text
  return { s with base := newBase }

/-- Helper: send binary via AsyncServerState updating internal base. -/
def sendBinaryAsync (s : AsyncServerState) (connId : Nat) (data : ByteArray) : IO AsyncServerState := do
  let newBase ← WebSocket.Server.Messaging.sendBinary s.base connId data
  return { s with base := newBase }

/-- Run the enhanced echo server using the async loop. -/
def main : IO Unit := do
  let config : ServerConfig := {
    port := 9001,
    maxConnections := 50,
    pingInterval := 15,
    maxMissedPongs := 2,
    maxMessageSize := 2 * 1024 * 1024
  }

  -- Create async server and start listening
  let asyncSrv0 ← mkAsyncServer config
  let startedBase ← WebSocket.Server.Accept.start asyncSrv0.base
  let asyncSrv := { asyncSrv0 with base := startedBase }

  -- Event manager setup
  let mut eventManager := mkEventManager

  -- Handlers for subscription (logging only)
  let connectionHandler : EventHandler := fun event => do
    match event with
    | .connected id addr => IO.println s!"🔗 Client {id} connected from {addr}"
    | .disconnected id reason => IO.println s!"❌ Client {id} disconnected: {reason}"
    | _ => pure ()

  let messageLogger : EventHandler := fun event => do
    match event with
    | .message id .text payload =>
        IO.println s!"💬 Text from {id}: {String.fromUTF8! payload}"
    | .message id .binary payload =>
        IO.println s!"📦 Binary from {id}: {payload.size} bytes"
    | .message id .ping _ => IO.println s!"🏓 Ping from {id}"
    | .message id .pong _ => IO.println s!"🏓 Pong from {id}"
    | _ => pure ()

  let errorHandler : EventHandler := fun event => do
    match event with
    | .error id msg => IO.println s!"⚠️  Error on connection {id}: {msg}"
    | _ => pure ()

  let (em1, _) := subscribe eventManager .connected connectionHandler
  let (em2, _) := subscribe em1 .disconnected connectionHandler
  let (em3, _) := subscribe em2 (.message none) messageLogger
  let (em4, _) := subscribe em3 .error errorHandler
  eventManager := em4

  -- A mutable ref to hold async server state for echo side-effects inside handler
  let srvRef ← IO.mkRef asyncSrv

  -- Unified handler: dispatch events then perform echo side-effects
  let enhancedHandler : EventHandler := fun ev => do
    dispatch eventManager ev
    match ev with
    | .message id .text payload => do
        let txt := String.fromUTF8! payload
        let s ← srvRef.get
        let s ← sendTextAsync s id s!"Echo: {txt}"
        srvRef.set s
    | .message id .binary payload => do
        let s ← srvRef.get
        let s ← sendBinaryAsync s id payload
        srvRef.set s
    | _ => pure ()

  IO.println s!"🚀 Enhanced Async WebSocket server starting on port {config.port}"
  IO.println "Features enabled:"
  IO.println "  ✓ Event subscription system"
  IO.println "  ✓ Keep-alive pings every 15s"
  IO.println "  ✓ Graceful close handling"
  IO.println "  ✓ Async processing loop"
  IO.println "  ✓ Auto-echo for text and binary messages"
  IO.println ""
  IO.println "Press Ctrl+C to stop gracefully... (Ctrl+C will terminate the process)"

  -- Run the async loop updating the shared state ref.
  runAsyncServerUpdating srvRef enhancedHandler

  IO.println "🛑 Server stopped"

end WebSocket.Examples

-- Expose a top-level `main` so Lake can build the executable.
def main : IO Unit := WebSocket.Examples.main
