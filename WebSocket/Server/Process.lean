/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Net
import WebSocket.Metrics
import WebSocket.Backpressure
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
      let nowMs := UInt64.ofNat ((← IO.monoNanosNow) / 1000000)
      if server.config.idleTimeout > 0 && connState.lastActivityMs > 0 then
        let idleForMs := nowMs.toNat - connState.lastActivityMs.toNat
        if idleForMs >= server.config.idleTimeout * 1000 then
          let c : Conn := (connState.conn : Conn)
          try
            c.transport.close
          catch _ => pure ()
          WebSocket.Metrics.connectionClosed
          WebSocket.bpUnregister connId
          let newConns := server.connections.filter (·.id ≠ connId)
          return ({ server with connections := newConns }, [.disconnected connId "idle timeout"])
      let baseConn : Conn := (connState.conn : Conn)
      let bytes ← baseConn.transport.recv
      if bytes.size = 0 then
        try
          baseConn.transport.close
        catch _ => pure ()
        WebSocket.Metrics.connectionClosed
        WebSocket.bpUnregister connId
        let newConns := server.connections.filter (·.id ≠ connId)
        return ({ server with connections := newConns }, [.disconnected connId "peer closed connection"])
      else
        WebSocket.Metrics.frameReceived bytes.size
        let (newConn, events, _) ← WebSocket.Net.stepTcp connState.conn (some { conn := baseConn, buffer := connState.conn.buffer })
        let updatedConnState := { connState with conn := newConn, lastActivityMs := nowMs }
        let newConns := server.connections.map (fun c => if c.id = connId then updatedConnState else c)
        let newServer := { server with connections := newConns }
        for (opc, _payload) in events do
          if opc = .text || opc = .binary then
            WebSocket.Metrics.messageReceived
          if opc = .close then
            WebSocket.Metrics.connectionClosed
        if events.any (fun (opc, _) => opc = .close) then
          try
            baseConn.transport.close
          catch _ => pure ()
          WebSocket.bpUnregister connId
          let remaining := newServer.connections.filter (·.id ≠ connId)
          let serverEvents := events.map (fun (opc, payload) => ServerEvent.message connId opc payload) ++ [.disconnected connId "close frame received"]
          return ({ newServer with connections := remaining }, serverEvents)
        let serverEvents := events.map (fun (opc, payload) => ServerEvent.message connId opc payload)
        return (newServer, serverEvents)
    catch e =>
      WebSocket.Metrics.connectionClosed
      WebSocket.bpUnregister connId
      try
        let c : Conn := (connState.conn : Conn)
        c.transport.close
      catch _ => pure ()
      let newConns := server.connections.filter (·.id ≠ connId)
      let newServer := { server with connections := newConns }
      return (newServer, [.error connId s!"Connection error: {e}"])

end WebSocket.Server.Process
