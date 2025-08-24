/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Server.Types
import WebSocket.Server.Accept
import WebSocket.Server.Process
import WebSocket.Server.Close
open WebSocket

namespace WebSocket.Server.Async

open WebSocket.Server.Types
open WebSocket.Server.Accept
open WebSocket.Server.Process
open WebSocket.Server.Close

/-- Connection task state for async processing -/
structure ConnectionTask where
  connId : Nat
  active : Bool := true
  lastActivity : UInt64 := 0

/-- Async server state with task management -/
structure AsyncServerState where
  base : ServerState
  tasks : List ConnectionTask := []
  shouldStop : IO.Ref Bool

/-- Create async server -/
def mkAsyncServer (config : ServerConfig := {}) : IO AsyncServerState := do
  let stopRef ← IO.mkRef false
  return {
    base := mkServer config,
    tasks := [],
    shouldStop := stopRef
  }

/-- Process a single connection non-blockingly -/
def processConnectionAsync (server : AsyncServerState) (connId : Nat) : IO (AsyncServerState × List ServerEvent) := do
  let (newBase, events) ← processConnection server.base connId
  return ({ server with base := newBase }, events)

/-- Accept connections with timeout -/
def acceptWithTimeout (server : AsyncServerState) (_ : UInt32 := 100) : IO (AsyncServerState × Option ServerEvent) := do
  -- In a real implementation, this would use select/poll/epoll with timeout
  -- For now, simulate with a quick accept attempt
  let (newBase, eventOpt) ← acceptConnection server.base
  return ({ server with base := newBase }, eventOpt)

/-- Process all active connections -/
def processAllConnections (server : AsyncServerState) (handler : EventHandler) : IO AsyncServerState := do
  let mut currentServer := server
  let mut activeTasks : List ConnectionTask := []

  for task in server.tasks do
    if task.active then
      let (newServer, events) ← processConnectionAsync currentServer task.connId
      currentServer := newServer

      -- Handle events
      for event in events do
        handler event

      -- Update task activity
      let timestamp ← IO.monoNanosNow
      let updatedTask := { task with lastActivity := UInt64.ofNat timestamp }
      activeTasks := updatedTask :: activeTasks
    else
      activeTasks := task :: activeTasks

  return { currentServer with tasks := activeTasks }

/-- Main async server loop -/
partial def runAsyncServer (server : AsyncServerState) (handler : EventHandler) : IO Unit := do
  let shouldStop ← server.shouldStop.get
  if shouldStop then
    return ()

  -- Accept new connections with timeout
  let (server1, eventOpt) ← acceptWithTimeout server 50
  let mut currentServer := server1

  match eventOpt with
  | some event =>
    handler event
    match event with
    | .connected connId _ =>
      -- Add new connection task
      let timestamp ← IO.monoNanosNow
      let newTask : ConnectionTask := { connId, active := true, lastActivity := UInt64.ofNat timestamp }
      currentServer := { currentServer with tasks := newTask :: currentServer.tasks }
    | _ => pure ()
  | none => pure ()

  -- Process all existing connections
  currentServer ← processAllConnections currentServer handler

  -- Process close timeouts
  let newBase ← processCloseTimeouts currentServer.base
  currentServer := { currentServer with base := newBase }

  -- Small delay to prevent busy waiting
  IO.sleep 10  -- 10ms

  -- Continue loop
  runAsyncServer currentServer handler

/-- Stop the async server gracefully -/
def stopAsyncServer (server : AsyncServerState) : IO Unit := do
  server.shouldStop.set true
  -- Initiate close for all connections
  for task in server.tasks do
    if task.active then
      let _ ← initiateClose server.base task.connId
      pure ()

/-- Variant of the async loop that keeps an IO.Ref with the latest server state updated.
    This allows external handlers (that capture the ref) to observe newly accepted connections
    when performing side-effect actions like echoing messages. -/
partial def runAsyncServerUpdating (srvRef : IO.Ref AsyncServerState) (handler : EventHandler) : IO Unit := do
  let server ← srvRef.get
  let shouldStop ← server.shouldStop.get
  if shouldStop then
    return ()
  -- Accept new connections
  let (server1, eventOpt) ← acceptWithTimeout server 50
  let mut currentServer := server1
  match eventOpt with
  | some event =>
      handler event
      match event with
      | .connected connId _ =>
          let timestamp ← IO.monoNanosNow
          let newTask : ConnectionTask := { connId, active := true, lastActivity := UInt64.ofNat timestamp }
          currentServer := { currentServer with tasks := newTask :: currentServer.tasks }
      | _ => pure ()
  | none => pure ()
  -- Process connections
  currentServer ← processAllConnections currentServer handler
  -- Close timeouts
  let newBase ← processCloseTimeouts currentServer.base
  currentServer := { currentServer with base := newBase }
  -- Persist updated state
  srvRef.set currentServer
  IO.sleep 10
  runAsyncServerUpdating srvRef handler

end WebSocket.Server.Async
