import WebSocket
import WebSocket.Server
import WebSocket.Server.Types
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

/-- Run all integration tests -/
def run : IO Unit := do
  IO.println "Running integration tests..."
  testServerCreation
  testEventCreation
  testServerState
  IO.println "All integration tests passed"

end WebSocket.Tests.Integration
