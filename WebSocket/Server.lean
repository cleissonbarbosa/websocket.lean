import WebSocket.Server.Types
import WebSocket.Server.Accept
import WebSocket.Server.Process
import WebSocket.Server.Messaging
import WebSocket.Server.Loop

/-!
 High-level (prototype) server API. This file now only re-exports the reorganized
 server submodules (Types, Lifecycle, Messaging, Loop) to keep `import WebSocket.Server`
 working while allowing finer-grained maintenance.

 The actual implementations were split into:
 * `Server/Types.lean`       : configuration, state, events, helpers
 * `Server/Accept.lean`      : accept + handshake logic
 * `Server/Process.lean`     : per-connection processing (read + frame handling)
 * `Server/Messaging.lean`   : send / broadcast helpers
 * `Server/Loop.lean`        : naive recursive loop (blocking prototype)

 Future additions (planned):
 * Connection cleanup + close handshake orchestration
 * Concurrent task spawning per connection
 * KeepAlive ping integration using `PingState`
-/

namespace WebSocket.Server
  -- Re-export commonly used symbols at this aggregation level for ergonomics.
  export WebSocket.Server.Types (ServerConfig ServerEvent ConnectionState ServerState EventHandler mkServer)
  export WebSocket.Server.Accept (start acceptConnection)
  export WebSocket.Server.Process (processConnection)
  export WebSocket.Server.Messaging (sendMessage sendText sendBinary broadcast broadcastText stop)
  export WebSocket.Server.Loop (runServer)
end WebSocket.Server
