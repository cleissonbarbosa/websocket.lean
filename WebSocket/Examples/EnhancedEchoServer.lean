import WebSocket
import WebSocket.Net
import WebSocket.Server
import WebSocket.Server.Events
import WebSocket.Server.KeepAlive
import WebSocket.Server.Async
open WebSocket WebSocket.Net WebSocket.Server

/-!
 Enhanced Echo Server Example

 This example demonstrates the new server capabilities:
 * Event subscription system
 * Graceful close handling
 * Keep-alive ping integration
 * Async server loop
-/

def main : IO Unit := do
  -- Create async server with custom config
  let config : ServerConfig := {
    port := 9001,
    maxConnections := 50,
    pingInterval := 15,  -- 15 second ping interval
    maxMissedPongs := 2,
    maxMessageSize := 2 * 1024 * 1024  -- 2MB
  }

  let asyncServer ← mkAsyncServer config

  -- Set up event management
  let mut eventManager := mkEventManager

  -- Connection handler
  let connectionHandler : EventHandler := fun event => do
    match event with
    | .connected id addr =>
        IO.println s"🔗 Client {id} connected from {addr}"
    | .disconnected id reason =>
        IO.println s"❌ Client {id} disconnected: {reason}"
    | _ => pure ()

  -- Message handler with echo functionality
  let serverRef ← IO.mkRef asyncServer.base
  let messageHandler : EventHandler := fun event => do
    match event with
    | .message id .text payload =>
        let text := String.fromUTF8! payload
        IO.println s"💬 Text from {id}: {text}"
        -- Echo the message back
        let server ← serverRef.get
        let newServer ← sendText server id s"Echo: {text}"
        serverRef.set newServer
    | .message id .binary payload =>
        IO.println s"📦 Binary from {id}: {payload.size} bytes"
        -- Echo binary data back
        let server ← serverRef.get
        let newServer ← sendBinary server id payload
        serverRef.set newServer
    | .message id .ping payload =>
        IO.println s"🏓 Ping from {id}"
        -- Pong is handled automatically by the protocol layer
    | .message id .pong payload =>
        IO.println s"🏓 Pong from {id}"
    | _ => pure ()

  -- Error handler
  let errorHandler : EventHandler := fun event => do
    match event with
    | .error id msg =>
        IO.println s"⚠️  Error on connection {id}: {msg}"
    | _ => pure ()

  -- Subscribe to different event types
  let (em1, _) := subscribeToConnections eventManager connectionHandler
  let (em2, _) := subscribe em1 (.message none) messageHandler
  let (em3, _) := subscribeToErrors em2 errorHandler
  eventManager := em3

  -- Enhanced event handler that dispatches to subscribers
  let enhancedHandler : EventHandler := fun event => do
    dispatch eventManager event

  -- Set up keep-alive with ping wrapping
  let pingConfig : KeepAlive.PingConfig := {
    intervalMs := 15000,  -- 15 seconds
    maxMissedPongs := 3,
    timeoutMs := 5000     -- 5 second ping timeout
  }

  let wrappedHandler := wrapEventHandlerWithPing serverRef pingConfig enhancedHandler

  IO.println s"🚀 Enhanced WebSocket server starting on port {config.port}"
  IO.println "Features enabled:"
  IO.println "  ✓ Event subscription system"
  IO.println "  ✓ Keep-alive pings every 15s"
  IO.println "  ✓ Graceful close handling"
  IO.println "  ✓ Async connection processing"
  IO.println "  ✓ Auto-echo for text and binary messages"
  IO.println ""
  IO.println "Press Ctrl+C to stop gracefully..."

  -- Install signal handler for graceful shutdown
  try
    runAsyncServer asyncServer wrappedHandler
  catch e =>
    IO.println s"Server error: {e}"
  finally
    IO.println "🛑 Server shutting down..."
    stopAsyncServer asyncServer
