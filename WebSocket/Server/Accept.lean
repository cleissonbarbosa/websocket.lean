import WebSocket
import WebSocket.Log
import WebSocket.Net
import WebSocket.Server.Types
open WebSocket WebSocket.Net

namespace WebSocket.Server.Accept

open WebSocket.Server.Types

/-- Start listening on the configured port -/
def start (server : ServerState) : IO ServerState := do
  let lh ← openServer server.config.port
  if server.config.logConnections then
    WebSocket.log .info s!"Listening on port {server.config.port}"
  return { server with listenHandle := some lh }

/-- Accept a single connection and perform handshake -/
def acceptConnection (server : ServerState) : IO (ServerState × Option ServerEvent) := do
  match server.listenHandle with
  | none => return (server, some (.error 0 "Server not listening"))
  | some lh =>
    try
      let upgradeCfg : UpgradeConfig := {
        subprotocols := { supported := server.config.subprotocols, rejectOnNoMatch := false },
        extensions := { supportedExtensions := [] }
      }
      let res ← WebSocket.Net.acceptAndUpgradeWithConfig lh upgradeCfg
      match res with
      | some (tcpConn, subp?, _exts) =>
          let tcpConn' : TcpConn := { tcpConn with assembler := { maxMessageSize? := some server.config.maxMessageSize } }
          let connId := server.nextConnId
          let connState : ConnectionState := {
            id := connId,
            conn := tcpConn',
            addr := "127.0.0.1",
            subprotocol := subp?
          }
          let newServer := { server with connections := connState :: server.connections, nextConnId := connId + 1 }
          if server.config.logConnections then
            WebSocket.log .info s!"Accepted connection #{connId}"
          return (newServer, some (.connected connId "127.0.0.1"))
      | none => return (server, none)
    catch e => return (server, some (.error 0 s!"Accept error: {e}"))

end WebSocket.Server.Accept
