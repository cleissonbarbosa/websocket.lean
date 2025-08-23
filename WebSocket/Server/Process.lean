import WebSocket
import WebSocket.Net
import WebSocket.Server.Types
open WebSocket WebSocket.Net

namespace WebSocket.Server.Process

open WebSocket.Server.Types

/-- Process incoming messages from a connection -/
def processConnection (server : ServerState) (connId : Nat) : IO (ServerState × List ServerEvent) := do
  match server.connections.find? (·.id = connId) with
  | none => return (server, [.error connId "Connection not found"])
  | some connState =>
    if ¬ connState.active then
      return (server, [])
    try
      let baseConn : Conn := (connState.conn : Conn)
      let bytes ← baseConn.transport.recv
      if bytes.size = 0 then
        return (server, [])
      else
        let (newConn, events) ← WebSocket.handleIncoming baseConn bytes
        let updatedConnState := { connState with conn := { transport := connState.conn.transport, assembler := newConn.assembler, pingState := newConn.pingState } }
        let newConns := server.connections.map (fun c => if c.id = connId then updatedConnState else c)
        let newServer := { server with connections := newConns }
        let serverEvents := events.map (fun (opc, payload) => ServerEvent.message connId opc payload)
        return (newServer, serverEvents)
    catch e =>
      let newConns := server.connections.filter (·.id ≠ connId)
      let newServer := { server with connections := newConns }
      return (newServer, [.error connId s!"Connection error: {e}"])

end WebSocket.Server.Process
