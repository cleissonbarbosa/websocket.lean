/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Log
import WebSocket.Net
open WebSocket WebSocket.Net

namespace WebSocket.Server.Types

/-- WebSocket server configuration -/
structure ServerConfig where
  port : UInt32 := 8080
  maxConnections : Nat := 100
  pingInterval : Nat := 30
  maxMissedPongs : Nat := 3
  maxMessageSize : Nat := 1024 * 1024  -- 1MB default
  subprotocols : List String := []
  negotiateExtensions : Bool := false
  /-- Minimum log level (inclusive) for built-in logging calls. -/
  logLevelMin : LogLevel := .info
  /-- Whether to emit connection lifecycle logs. -/
  logConnections : Bool := true

/-- Server event types -/
inductive ServerEvent
  | connected (id : Nat) (addr : String)
  | disconnected (id : Nat) (reason : String)
  | message (id : Nat) (opcode : OpCode) (payload : ByteArray)
  | error (id : Nat) (error : String)
  deriving Repr

/-- Connection state -/
structure ConnectionState where
  id : Nat
  conn : TcpConn
  addr : String := "unknown"
  subprotocol : Option String := none
  active : Bool := true

/-- Server state -/
structure ServerState where
  config : ServerConfig
  listenHandle : Option ListenHandle := none
  connections : List ConnectionState := []
  nextConnId : Nat := 1

/-- Event handler type -/
abbrev EventHandler := ServerEvent → IO Unit

/-- Create a new server with configuration -/
def mkServer (config : ServerConfig := {}) : ServerState :=
  { config }

end WebSocket.Server.Types
