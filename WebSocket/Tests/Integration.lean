/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Server
import WebSocket.Server.Types
import WebSocket.Server.Async
import WebSocket.Tests.Util
open WebSocket WebSocket.Server WebSocket.Tests

namespace WebSocket.Tests.Integration

open WebSocket.Server.Types

/-- Test basic server creation and configuration -/
def testServerCreation : IO Unit := do
  let config : ServerConfig := {
    port := 9999,
    maxConnections := 10,
    maxMessageSize := 1024
  }
  let server := mkServer config

  if server.config.port != 9999 then
    throw $ IO.userError "Server port not set correctly"
  if server.config.maxConnections != 10 then
    throw $ IO.userError "Server maxConnections not set correctly"

  IO.println "Server creation test passed"

/-- Test basic event creation -/
def testEventCreation : IO Unit := do
  let connectEvent := ServerEvent.connected 1 "127.0.0.1"
  let _messageEvent := ServerEvent.message 1 .text (mkPayload 10)
  let _errorEvent := ServerEvent.error 1 "test error"

  match connectEvent with
  | .connected id addr =>
    if id != 1 || addr != "127.0.0.1" then
      throw $ IO.userError "Connect event creation failed"
  | _ => throw $ IO.userError "Wrong event type"

  IO.println "Event creation test passed"

/-- Test server state management -/
def testServerState : IO Unit := do
  let server := mkServer { port := 8080 }

  if server.connections.length != 0 then
    throw $ IO.userError "New server should have no connections"

  if server.nextConnId != 1 then
    throw $ IO.userError "New server should start with connId 1"

  IO.println "Server state test passed"

/-- Test that a non-blocking accept with no pending client is treated as idle, not as an error. -/
def testIdleAccept : IO Unit := do
  let server ← start (mkServer { port := 0, logConnections := false })
  let (server', ev?) ← acceptConnection server
  stop server'
  match ev? with
  | none =>
      IO.println "Idle accept test passed"
  | some (.error _ msg) =>
      throw <| IO.userError s!"Expected no error when no client is pending, got: {msg}"
  | some ev =>
      throw <| IO.userError s!"Expected no event when no client is pending, got: {repr ev}"

/-- Test that stale async tasks are dropped instead of emitting repeated connection-not-found errors. -/
def testAsyncDropsStaleTasks : IO Unit := do
  let stopRef ← IO.mkRef false
  let asyncServer : WebSocket.Server.Async.AsyncServerState := {
    base := mkServer { port := 0 }
    tasks := [{ connId := 1, active := true, lastActivity := 0 }]
    shouldStop := stopRef
  }
  let eventsRef ← IO.mkRef ([] : List ServerEvent)
  let handler : EventHandler := fun ev => eventsRef.modify (fun events => ev :: events)
  let updated ← WebSocket.Server.Async.processAllConnections asyncServer handler
  let events ← eventsRef.get
  if !updated.tasks.isEmpty then
    throw <| IO.userError "Expected stale async task list to be emptied"
  if !events.isEmpty then
    throw <| IO.userError "Expected no events when processing stale async tasks"
  IO.println "Async stale task cleanup test passed"

/-- Run all integration tests -/
def run : IO Unit := do
  IO.println "Running integration tests..."
  testServerCreation
  testEventCreation
  testServerState
  testIdleAccept
  testAsyncDropsStaleTasks
  IO.println "All integration tests passed"

end WebSocket.Tests.Integration
