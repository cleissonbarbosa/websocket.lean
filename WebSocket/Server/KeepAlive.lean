/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Server.Types
import WebSocket.Server.Messaging
open WebSocket

namespace WebSocket.Server.KeepAlive

open WebSocket.Server.Types
open WebSocket.Server.Messaging

/-- Ping configuration -/
structure PingConfig where
  intervalMs : UInt64 := 30000
  maxMissedPongs : Nat := 3
  timeoutMs : UInt64 := 10000

/-- Send ping to a connection if interval has elapsed -/
def checkAndSendPing (server : ServerState) (connId : Nat) (config : PingConfig := {}) : IO ServerState := do
  let currentTimeMs := UInt64.ofNat ((← IO.monoNanosNow) / 1000000)
  match server.connections.find? (·.id = connId) with
  | none => return server
  | some connState =>
    if !connState.active then return server
    let elapsed := currentTimeMs.toNat - connState.lastActivityMs.toNat
    if elapsed < config.intervalMs.toNat then return server
    let pingPayload := ByteArray.mk #[
      UInt8.ofNat ((currentTimeMs.toNat >>> 24) &&& 0xFF),
      UInt8.ofNat ((currentTimeMs.toNat >>> 16) &&& 0xFF),
      UInt8.ofNat ((currentTimeMs.toNat >>> 8) &&& 0xFF),
      UInt8.ofNat (currentTimeMs.toNat &&& 0xFF)]
    let pingFrame : Frame := {
      header := { opcode := .ping, masked := false, payloadLen := pingPayload.size },
      payload := pingPayload
    }
    try
      let c : Conn := (connState.conn : Conn)
      c.transport.send (encodeFrame pingFrame)
      return server
    catch _ =>
      let newConns := server.connections.filter (·.id ≠ connId)
      return { server with connections := newConns }

/-- Handle incoming pong frame -/
def handlePong (server : ServerState) (connId : Nat) (_ : ByteArray) : IO ServerState := do
  let nowMs := UInt64.ofNat ((← IO.monoNanosNow) / 1000000)
  match server.connections.find? (·.id = connId) with
  | none => return server
  | some connState =>
    let updated := { connState with lastActivityMs := nowMs }
    let newConns := server.connections.map (fun c => if c.id = connId then updated else c)
    return { server with connections := newConns }

/-- Check for ping timeouts and close dead connections -/
def checkPingTimeouts (server : ServerState) (config : PingConfig := {}) : IO ServerState := do
  let currentTimeMs := UInt64.ofNat ((← IO.monoNanosNow) / 1000000)
  let timeoutThreshold := config.intervalMs.toNat * (config.maxMissedPongs + 1)
  let mut newConns : List ConnectionState := []
  for connState in server.connections do
    if connState.active && connState.lastActivityMs > 0 then
      let idle := currentTimeMs.toNat - connState.lastActivityMs.toNat
      if idle > timeoutThreshold then
        try
          let c : Conn := (connState.conn : Conn)
          c.transport.close
        catch _ => pure ()
        WebSocket.Metrics.connectionClosed
        WebSocket.bpUnregister connState.id
      else
        newConns := connState :: newConns
    else
      newConns := connState :: newConns
  return { server with connections := newConns }

/-- Process keep-alive for all connections -/
def processKeepAlive (server : ServerState) (config : PingConfig := {}) : IO ServerState := do
  let mut currentServer := server
  for connState in server.connections do
    if connState.active then
      currentServer ← checkAndSendPing currentServer connState.id config
  currentServer ← checkPingTimeouts currentServer config
  return currentServer

/-- Enhanced event handler that processes pong frames -/
def wrapEventHandlerWithPing (server : IO.Ref ServerState) (_ : PingConfig) (baseHandler : EventHandler) : EventHandler :=
  fun event => do
    match event with
    | .message connId .pong payload =>
      let currentServer ← server.get
      let newServer ← handlePong currentServer connId payload
      server.set newServer
      baseHandler event
    | _ => baseHandler event

end WebSocket.Server.KeepAlive
