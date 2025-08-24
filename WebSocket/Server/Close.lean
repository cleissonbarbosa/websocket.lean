/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Server.Types
open WebSocket

namespace WebSocket.Server.Close

open WebSocket.Server.Types

/-- Close handshake state for graceful disconnection -/
structure CloseState where
  /-- Whether we initiated the close -/
  initiated : Bool := false
  /-- Close code sent/received -/
  code : Option CloseCode := none
  /-- Close reason sent/received -/
  reason : String := ""
  /-- Timestamp when close was initiated (for timeout) -/
  startTime : Option UInt64 := none
  /-- Whether we're draining remaining messages before final close -/
  draining : Bool := false

/-- Close handshake configuration -/
structure CloseConfig where
  /-- Timeout for close handshake in milliseconds -/
  timeoutMs : UInt64 := 3000
  /-- Maximum messages to drain during close -/
  maxDrainMessages : Nat := 10
  /-- Whether to send close frame if not already sent -/
  sendCloseFrame : Bool := true

/-- Initiate graceful close handshake -/
def initiateClose (server : ServerState) (connId : Nat) (code : CloseCode := .normalClosure) (reason : String := "") (config : CloseConfig := {}) : IO ServerState := do
  match server.connections.find? (·.id = connId) with
  | none => return server
  | some connState =>
    if config.sendCloseFrame then
      -- Send close frame
      let closeFrame := buildCloseFrame code reason
      let c : Conn := (connState.conn : Conn)
      try
        c.transport.send (encodeFrame closeFrame)
      catch _ => pure ()

    -- Update connection with close state
    let timestamp ← IO.monoNanosNow
    -- Record (future) close state; currently not stored in `ConnectionState` structure.
    let _closeState : CloseState := {
      initiated := true,
      code := some code,
      reason := reason,
      startTime := some (UInt64.ofNat (timestamp / 1000000)), -- Convert to ms
      draining := true
    }

    -- Add close state to connection (would need to extend ConnectionState)
    -- For now, mark as inactive to stop normal processing
    let updatedConn := { connState with active := false }
    let newConns := server.connections.map (fun c => if c.id = connId then updatedConn else c)
    return { server with connections := newConns }

/-- Handle incoming close frame during handshake -/
def handleIncomingClose (server : ServerState) (connId : Nat) (payload : ByteArray) (config : CloseConfig := {}) : IO ServerState := do
  match server.connections.find? (·.id = connId) with
  | none => return server
  | some connState =>
  -- Parse payload (currently ignored in simplified close echo)
  let _ := parseClosePayload payload

    -- If we haven't sent a close frame yet, send one back
    if config.sendCloseFrame then
      -- Echo normal closure regardless (simplified); could inspect parsed info if needed
      let closeFrame := buildCloseFrame .normalClosure ""
      let c : Conn := (connState.conn : Conn)
      try
        c.transport.send (encodeFrame closeFrame)
      catch _ => pure ()

    -- Close the connection immediately after responding
    try
      let c : Conn := (connState.conn : Conn)
      c.transport.close
    catch _ => pure ()

    let newConns := server.connections.filter (·.id ≠ connId)
    return { server with connections := newConns }

/-- Check for close timeouts and finalize connections -/
def processCloseTimeouts (server : ServerState) (_ : CloseConfig := {}) : IO ServerState := do
  let currentTime ← IO.monoNanosNow
  let _ := UInt64.ofNat (currentTime / 1000000)  -- currentTimeMs for future use

  let mut newConns : List ConnectionState := []
  for connState in server.connections do
    -- This would check actual close state if we extended ConnectionState
    -- For now, just close inactive connections after timeout
    if ¬ connState.active then
      -- Simulate timeout check - in real implementation would check closeState.startTime
      try
        let c : Conn := (connState.conn : Conn)
        c.transport.close
      catch _ => pure ()
      -- Don't add to newConns (remove it)
    else
      newConns := connState :: newConns

  return { server with connections := newConns }

end WebSocket.Server.Close
