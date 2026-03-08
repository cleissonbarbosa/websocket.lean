/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Client
import WebSocket.Log
open WebSocket WebSocket.Client

def main : IO Unit := do
  let config : ClientConfig := {
    host := "localhost",
    port := 9001,
    resource := "/"
  }
  let client := mkClient config
  let (client', event?) ← connect client
  match event? with
  | some .connected =>
    WebSocket.log .info "Connected to server"
    let client'' ← sendText client' "Hello, WebSocket!"
    let (_, events) ← processMessages client''
    for ev in events do
      match ev with
      | .message _ payload => WebSocket.log .info s!"Received: {String.fromUTF8! payload}"
      | .disconnected _ reason => WebSocket.log .info s!"Disconnected: {reason}"
      | .error err => WebSocket.log .error s!"Error: {err}"
      | _ => pure ()
  | some (.error err) =>
    WebSocket.log .error s!"Connection failed: {err}"
  | _ =>
    WebSocket.log .error "Unexpected event"
