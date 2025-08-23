import WebSocket.Tests.Basic
import WebSocket.Tests.Crypto
import WebSocket.Tests.Handshake
import WebSocket.Tests.Frames
import WebSocket.Tests.Fragmentation
import WebSocket.Tests.KeepAlive
import WebSocket.Tests.UTF8
import WebSocket.Tests.InvalidOpcode
import WebSocket.Tests.Integration

def main : IO Unit := do
  WebSocket.Tests.Basic.run
  WebSocket.Tests.Crypto.run
  WebSocket.Tests.Handshake.run
  WebSocket.Tests.Frames.run
  WebSocket.Tests.Fragmentation.run
  WebSocket.Tests.KeepAlive.run
  WebSocket.Tests.UTF8.run
  WebSocket.Tests.InvalidOpcode.run
  WebSocket.Tests.Integration.run
  IO.println "All tests done"
