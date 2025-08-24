/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Log
import WebSocket.Net
import WebSocket.Server.Types
open WebSocket WebSocket.Net

namespace WebSocket.Server.Messaging

open WebSocket.Server.Types

/-- Send a message to a specific connection -/
def sendMessage (server : ServerState) (connId : Nat) (opcode : OpCode) (payload : ByteArray) : IO ServerState := do
  match server.connections.find? (·.id = connId) with
  | none =>
    WebSocket.log .warn s!"Connection {connId} not found"
    return server
  | some connState =>
    try
      let frame : Frame := { header := { opcode := opcode, masked := false, payloadLen := payload.size }, payload := payload }
      let c : Conn := (connState.conn : Conn)
      c.transport.send (encodeFrame frame)
      return server
    catch e =>
      WebSocket.log .error s!"Failed to send to connection {connId}: {e}"
      let newConns := server.connections.filter (·.id ≠ connId)
      return { server with connections := newConns }

/-- Send a text message to a connection -/
def sendText (server : ServerState) (connId : Nat) (text : String) : IO ServerState := do
  sendMessage server connId .text (ByteArray.mk text.toUTF8.data)

/-- Send a binary message to a connection -/
def sendBinary (server : ServerState) (connId : Nat) (data : ByteArray) : IO ServerState := do
  sendMessage server connId .binary data

/-- Broadcast a message to all active connections -/
def broadcast (server : ServerState) (opcode : OpCode) (payload : ByteArray) : IO ServerState := do
  let mut newServer := server
  for connState in server.connections do
    if connState.active then
      newServer ← sendMessage newServer connState.id opcode payload
  return newServer

/-- Broadcast text to all connections -/
def broadcastText (server : ServerState) (text : String) : IO ServerState := do
  broadcast server .text (ByteArray.mk text.toUTF8.data)

/-- Stop the server and close all connections -/
def stop (server : ServerState) : IO Unit := do
  for connState in server.connections do
    try
      let c : Conn := (connState.conn : Conn)
      c.transport.close
    catch _ => pure ()
  WebSocket.log .info "Server stopped"

end WebSocket.Server.Messaging
