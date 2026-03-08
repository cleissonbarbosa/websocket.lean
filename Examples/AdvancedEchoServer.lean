/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Server
import WebSocket.Log
open WebSocket WebSocket.Server

/-- Minimal advanced echo prototype (single connection, sequential loop). -/

def main : IO Unit := do
  /- Since IO.getArgs is unavailable in this environment, read configuration
     from environment variables set by the wrapper script:
       WS_PORT       (default 9001)
       WS_MAX_CONNS  (default 50)
  -/
  let defaultPort : Nat := 9001
  let defaultMax : Nat := 50
  let parseNat? : String → Option Nat := fun s => s.toNat?
  let envPort? ← IO.getEnv "WS_PORT"
  let envMax?  ← IO.getEnv "WS_MAX_CONNS"
  let port := match envPort? with | some v => (parseNat? v).getD defaultPort | none => defaultPort
  let maxConns := match envMax? with | some v => (parseNat? v).getD defaultMax | none => defaultMax
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
    | .connected id addr => WebSocket.log .info s!"Client {id} connected from {addr}"
    | .disconnected id reason => WebSocket.log .info s!"Client {id} disconnected: {reason}"
    | .message id opc payload =>
        match opc with
        | .text => WebSocket.log .info s!"[print] text from {id}: {(String.fromUTF8! payload)}"
        | .binary => WebSocket.log .info s!"[print] binary from {id}: {payload.size} bytes"
        | .ping => WebSocket.log .info s!"[print] ping from {id}"
        | .pong => WebSocket.log .info s!"[print] pong from {id}"
        | .close => WebSocket.log .info s!"[print] close from {id}"
        | .continuation => WebSocket.log .info s!"[print] continuation (ignored) from {id}"
    | .error id err => WebSocket.log .error s!"Error from client {id}: {err}"

  WebSocket.log .info s!"Enhanced WebSocket server started on port {port} (maxConnections={maxConns}). Press Ctrl+C to stop."

  /- Simple loop:
     1. Repeatedly call acceptConnection until a client connects.
     2. Then poll that connection for messages, echoing text & binary.
     3. After a fixed number of idle iterations, exit.
  -/
  let rec waitForClient (s : ServerState) (tries : Nat := 200) : IO (ServerState × Option Nat) := do
    if tries = 0 then return (s, none) else
    let (s', ev?) ← acceptConnection s
    match ev? with
    | some (.connected cid _) => return (s', some cid)
    | some ev =>
        handleEvent ev
        IO.sleep 50
        waitForClient s' (tries - 1)
    | none =>
        IO.sleep 50
        waitForClient s' (tries - 1)

  let (server', connId?) ← waitForClient server
  match connId? with
  | none =>
      WebSocket.log .error "No client connected (timeout). Stopping server."
      stop server'
  | some cid =>
      WebSocket.log .info s!"Client {cid} connected; entering echo loop"
      let mut cur := server'
      for _ in [0:400] do
        let (cur', events) ← processConnection cur cid
        cur := cur'
        for ev in events do
          match ev with
          | .message id .text payload =>
              handleEvent ev
              let msg := String.fromUTF8! payload
              cur ← sendText cur id s!"Echo: {msg}"
          | .message id .binary payload =>
              handleEvent ev
              cur ← sendBinary cur id payload
          | _ => handleEvent ev
        IO.sleep 50
      WebSocket.log .info "Loop complete; stopping server"
      stop cur
  WebSocket.log .info "Server stopped"
