/-!
Server runtime helpers: spawn async loop as a Task for non-blocking start.
-*/
import WebSocket.Server.Async
import WebSocket.Server.Accept
import WebSocket.Log

namespace WebSocket.Server.Runtime
open WebSocket.Server.Async
open WebSocket.Server.Types

structure RunningServer where
  stateRef : IO.Ref AsyncServerState
  task : Task Unit
  stop : IO Unit

/-- Start server on given config and event handler in background, returning handle. -/
def startBackground (cfg : ServerConfig) (handler : EventHandler) : IO RunningServer := do
  let async0 ← mkAsyncServer cfg
  let started ← WebSocket.Server.Accept.start async0.base
  let srvRef ← IO.mkRef { async0 with base := started }
  -- Spawn task
  let rec loop : IO Unit := WebSocket.Server.Async.runAsyncServerUpdating srvRef handler
  let t ← IO.asTask loop
  let stopAction : IO Unit := do
    let st ← srvRef.get
    WebSocket.Server.Async.stopAsyncServer st
  return { stateRef := srvRef, task := t, stop := stopAction }

end WebSocket.Server.Runtime
