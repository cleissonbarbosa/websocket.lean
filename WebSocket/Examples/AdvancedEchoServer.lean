import WebSocket
import WebSocket.Server
open WebSocket WebSocket.Server

/-- Enhanced echo server with high-level API -/
def main : IO Unit := do
  let config : ServerConfig := {
    port := 9001,
    maxConnections := 50,
    pingInterval := 30,
    subprotocols := ["echo", "chat"]
  }

  let server := mkServer config
  let server ← start server

  -- Event handler
  let handleEvent : EventHandler := fun event => do
    match event with
    | .connected id addr =>
        IO.println s!"Client {id} connected from {addr}"
    | .disconnected id reason =>
        IO.println s!"Client {id} disconnected: {reason}"
    | .message id opcode payload =>
        match opcode with
        | .text =>
            let message := String.fromUTF8! payload
            IO.println s!"Received text from {id}: {message}"
            -- Echo the message back
            let _ ← sendText server id s!"Echo: {message}"
            pure ()
        | .binary =>
            IO.println s!"Received binary from {id}: {payload.size} bytes"
            let _ ← sendBinary server id payload
            pure ()
        | .ping =>
            IO.println s!"Received ping from {id}"
        | .close =>
            IO.println s!"Received close from {id}"
        | _ =>
            IO.println s!"Received {opcode} from {id}"
    | .error id error =>
        IO.println s!"Error from client {id}: {error}"

  IO.println "Enhanced WebSocket server started. Press Ctrl+C to stop."

  -- For now, just handle one connection as a demonstration
  -- In a real server, you'd want proper concurrent connection handling
  let (server', eventOpt) ← acceptConnection server
  match eventOpt with
  | some event =>
    handleEvent event
    match event with
    | .connected connId _ =>
      -- Simple message processing loop for demonstration
      let mut currentServer := server'
      for _ in [0:10] do  -- Process up to 10 message exchanges
        let (newServer, events) ← processConnection currentServer connId
        currentServer := newServer
        for event in events do
          handleEvent event
        IO.sleep 1000  -- Wait 1 second between processing rounds
  | none => IO.println "Failed to accept connection"

  stop server'
  IO.println "Server stopped"
