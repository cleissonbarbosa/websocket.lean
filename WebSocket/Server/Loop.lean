import WebSocket
import WebSocket.Server.Types
import WebSocket.Server.Accept
import WebSocket.Server.Process
open WebSocket

namespace WebSocket.Server.Loop

open WebSocket.Server.Types
open WebSocket.Server.Accept
open WebSocket.Server.Process

/-- Simple (blocking, recursive) server loop that handles one connection at a time.
    Still single-threaded; meant as a prototype. -/
partial def runServer (server : ServerState) (handler : EventHandler) : IO Unit := do
  let (server', eventOpt) ← acceptConnection server
  match eventOpt with
  | some event =>
      handler event
      match event with
      | .connected connId _ =>
          let (server'', events) ← processConnection server' connId
          for e in events do
            handler e
          runServer server'' handler
      | _ => runServer server' handler
  | none => runServer server' handler

end WebSocket.Server.Loop
