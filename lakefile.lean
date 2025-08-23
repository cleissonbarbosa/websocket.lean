import Lake
open Lake DSL

package «websocket» where
  srcDir := "."

-- No external dependencies yet (keep core only)

-- Later we could depend on a socket FFI library; placeholder.

@[default_target]
lean_lib WebSocket where
  roots := #[`WebSocket]

lean_exe echoServer where
  root := `WebSocket.Examples.EchoServer
lean_exe echoClient where
  root := `WebSocket.Examples.EchoClient
lean_exe tests where
  root := `WebSocket.Tests.Main
