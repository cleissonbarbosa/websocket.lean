/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket.Server.Types
import WebSocket.Server.Accept
import WebSocket.Server.Process
import WebSocket.Server.Messaging
import WebSocket.Server.Loop
import WebSocket.Server.Close
import WebSocket.Server.Async
import WebSocket.Server.KeepAlive
import WebSocket.Server.Events

/-!
 High-level (prototype) server API. This file now only re-exports the reorganized
 server submodules (Types, Lifecycle, Messaging, Loop) to keep `import WebSocket.Server`
 working while allowing finer-grained maintenance.
-/

namespace WebSocket.Server
  -- Re-export commonly used symbols at this aggregation level for ergonomics.
  export WebSocket.Server.Types (ServerConfig ServerEvent ConnectionState ServerState EventHandler mkServer)
  export WebSocket.Server.Accept (start acceptConnection)
  export WebSocket.Server.Process (processConnection)
  export WebSocket.Server.Messaging (sendMessage sendText sendBinary broadcast broadcastText stop)
  export WebSocket.Server.Loop (runServer)
  export WebSocket.Server.Close (CloseState CloseConfig initiateClose handleIncomingClose processCloseTimeouts)
  export WebSocket.Server.Async (AsyncServerState mkAsyncServer runAsyncServer runAsyncServerUpdating stopAsyncServer processConnectionAsync)
  export WebSocket.Server.KeepAlive (PingConfig processKeepAlive checkAndSendPing handlePong wrapEventHandlerWithPing)
  export WebSocket.Server.Events (EventManager EventFilter EventSubscription mkEventManager subscribe unsubscribe dispatch)
end WebSocket.Server
