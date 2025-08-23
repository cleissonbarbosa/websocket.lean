import WebSocket
import WebSocket.Server
open WebSocket WebSocket.Server

/-- Minimal advanced echo prototype (single connection, sequential loop). -/

def main : IO Unit := do
  -- CLI arg parsing disabled (IO.getArgs unavailable); using defaults
  let port := 9001
  let maxConns := 50
  let config : ServerConfig := {
    port := UInt32.ofNat port,
    maxConnections := maxConns,
    pingInterval := 30,
    subprotocols := ["echo", "chat"]
  }

  let server := mkServer config
  let server ← start server

  -- Simple printer (no echo logic) — echo performed in processing loop where we can update server state.
  let handleEvent : EventHandler := fun ev =>
    match ev with
    | .connected id addr => IO.println s!"Client {id} connected from {addr}"
    | .disconnected id reason => IO.println s!"Client {id} disconnected: {reason}"
    | .message id opc payload =>
        match opc with
        | .text => IO.println s!"[print] text from {id}: {(String.fromUTF8! payload)}"
        | .binary => IO.println s!"[print] binary from {id}: {payload.size} bytes"
        | .ping => IO.println s!"[print] ping from {id}"
        | .pong => IO.println s!"[print] pong from {id}"
        | .close => IO.println s!"[print] close from {id}"
        | .continuation => IO.println s!"[print] continuation (ignored) from {id}"
    | .error id err => IO.println s!"Error from client {id}: {err}"

  IO.println s!"Enhanced WebSocket server started on port {port}. Press Ctrl+C to stop."

  -- For now, just handle one connection as a demonstration
  -- In a real server, you'd want proper concurrent connection handling
  let (server', eventOpt) ← acceptConnection server
  match eventOpt with
  | some event =>
      handleEvent event
      match event with
      | .connected connId _ =>
          let mut cur := server'
          for _ in [0:10] do
            let (cur', events) ← processConnection cur connId
            cur := cur'
            for ev in events do
              match ev with
              | .message cid .text payload =>
                  handleEvent ev
                  let msg := String.fromUTF8! payload
                  cur ← sendText cur cid s!"Echo: {msg}"
              | .message cid .binary payload =>
                  handleEvent ev
                  cur ← sendBinary cur cid payload
              | _ => handleEvent ev
            IO.sleep 500
      | _ => pure ()
  | none => IO.println "Failed to accept connection"

  match eventOpt with
  | some _ => stop server'
  | none => pure ()
  IO.println "Server stopped"
