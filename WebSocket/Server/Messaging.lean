/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Log
import WebSocket.Net
import WebSocket.RateLimit
import WebSocket.Backpressure
import WebSocket.Metrics
import WebSocket.Server.Types
open WebSocket WebSocket.Net

namespace WebSocket.Server.Messaging

open WebSocket.Server.Types

/-- Send a message to a specific connection -/
def sendMessage (server : ServerState) (connId : Nat) (opcode : OpCode) (payload : ByteArray)
    (callback? : Option (Except String Unit → IO Unit) := none) : IO ServerState := do

  match server.connections.find? (·.id = connId) with
  | none =>
    WebSocket.log .warn s!"Connection {connId} not found"
    -- Call callback with error if provided
    match callback? with
    | some callback => callback (Except.error "Connection not found")
    | none => pure ()
    return server
  | some connState =>
    -- Backpressure: check before send and update after
    try
      let frame : Frame := { header := { opcode := opcode, masked := false, payloadLen := payload.size }, payload := payload }
      let c : Conn := (connState.conn : Conn)
      let _ ← bpRegister connId
      let allowed ← bpBeforeSend connId {}
      if !allowed then
        bpAfterSend connId {}
        match callback? with
        | some cb => cb (Except.error "Backpressure: max in-flight reached")
        | none => pure ()
        return server
      c.transport.send (encodeFrame frame)
      bpAfterSend connId {}
      WebSocket.Metrics.recordBytesSent payload.size
      -- Call success callback if provided
      match callback? with
      | some callback => callback (Except.ok ())
      | none => pure ()
      return server
    catch e =>
      bpAfterSend connId {}
      WebSocket.log .error s!"Failed to send to connection {connId}: {e}"
      -- Call error callback if provided
      match callback? with
      | some callback => callback (Except.error s!"Send failed: {e}")
      | none => pure ()
      WebSocket.Metrics.connectionClosed
      WebSocket.bpUnregister connId
      let newConns := server.connections.filter (·.id ≠ connId)
      return { server with connections := newConns }

/-- Send a text message to a connection -/
def sendText (server : ServerState) (connId : Nat) (text : String) : IO ServerState := do
  sendMessage server connId .text (ByteArray.mk text.toUTF8.data)

/-- Send a binary message to a connection -/
def sendBinary (server : ServerState) (connId : Nat) (data : ByteArray) : IO ServerState := do
  sendMessage server connId .binary data

/-- Broadcast a message to all active connections -/
def broadcast (server : ServerState) (opcode : OpCode) (payload : ByteArray)
    (callback? : Option (Except String Unit → IO Unit) := none) : IO ServerState := do

  let mut newServer := server
  for connState in server.connections do
    if connState.active then
      newServer ← sendMessage newServer connState.id opcode payload callback?

  return newServer

/-- Broadcast text to all connections -/
def broadcastText (server : ServerState) (text : String) : IO ServerState := do
  broadcast server .text (ByteArray.mk text.toUTF8.data)


/-- Stop the server and close all connections -/
def stop (server : ServerState) : IO Unit := do
  -- Close all connections
  for connState in server.connections do
    try
      let c : Conn := (connState.conn : Conn)
      c.transport.close
    catch _ => pure ()
    WebSocket.bpUnregister connState.id

  WebSocket.log .info "Server stopped"

/-- Get rate limiter statistics -/
def getRateLimitStats (server : ServerState) : IO (Option (Nat × Nat)) := do
  match server.rateLimiter with
  | none => pure none
  | some limiter =>
    let stats ← limiter.getStats
    pure (some stats)

/-- Check rate limit status for a client -/
def getClientRateLimitStatus (server : ServerState) (clientId : String) : IO (Option (Nat × Bool)) := do
  match server.rateLimiter with
  | none => pure none
  | some limiter =>
    limiter.getClientStatus clientId

/-- Clean up expired rate limit entries -/
def cleanupRateLimits (server : ServerState) : IO Nat := do
  match server.rateLimiter with
  | none => pure 0
  | some limiter =>
    limiter.cleanup

/-- Reset rate limiting data -/
def resetRateLimits (server : ServerState) : IO Unit := do
  match server.rateLimiter with
  | none => pure ()
  | some limiter =>
    limiter.reset

end WebSocket.Server.Messaging
