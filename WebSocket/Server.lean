import WebSocket
import WebSocket.Net
open WebSocket WebSocket.Net

namespace WebSocket.Server

/-- WebSocket server configuration -/
structure ServerConfig where
  port : UInt32 := 8080
  maxConnections : Nat := 100
  pingInterval : Nat := 30
  maxMissedPongs : Nat := 3
  maxMessageSize : Nat := 1024 * 1024  -- 1MB default
  subprotocols : List String := []
  negotiateExtensions : Bool := false
  -- no automatic instances needed

/-- Server event types -/
inductive ServerEvent
  | connected (id : Nat) (addr : String)
  | disconnected (id : Nat) (reason : String)
  | message (id : Nat) (opcode : OpCode) (payload : ByteArray)
  | error (id : Nat) (error : String)
  deriving Repr

/-- Connection state -/
structure ConnectionState where
  id : Nat
  conn : TcpConn
  addr : String := "unknown"
  subprotocol : Option String := none
  active : Bool := true
  -- no automatic instances needed

/-- Server state -/
structure ServerState where
  config : ServerConfig
  listenHandle : Option ListenHandle := none
  connections : List ConnectionState := []
  nextConnId : Nat := 1
  -- no automatic instances needed

/-- Event handler type -/
abbrev EventHandler := ServerEvent → IO Unit

/-- Create a new server with configuration -/
def mkServer (config : ServerConfig := {}) : ServerState :=
  { config }

/-- Start listening on the configured port -/
def start (server : ServerState) : IO ServerState := do
  let lh ← openServer server.config.port
  IO.println s!"WebSocket server listening on port {server.config.port}"
  return { server with listenHandle := some lh }

/-- Accept a single connection and perform handshake -/
def acceptConnection (server : ServerState) : IO (ServerState × Option ServerEvent) := do
  match server.listenHandle with
  | none => return (server, some (.error 0 "Server not listening"))
  | some lh =>
    try
      let upgradeCfg : UpgradeConfig := {
        subprotocols := { supported := server.config.subprotocols, rejectOnNoMatch := false },
        extensions := { supportedExtensions := [] } -- placeholder
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
          return (newServer, some (.connected connId "127.0.0.1"))
      | none =>
          -- No pending connection or handshake failure; silent so caller can retry.
          return (server, none)
    catch e =>
      return (server, some (.error 0 s!"Accept error: {e}"))

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
        -- Non-blocking read yielded no data; keep connection open, no events.
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

/-- Send a message to a specific connection -/
def sendMessage (server : ServerState) (connId : Nat) (opcode : OpCode) (payload : ByteArray) : IO ServerState := do
  match server.connections.find? (·.id = connId) with
  | none =>
    IO.println s!"Connection {connId} not found"
    return server
  | some connState =>
    try
      let frame : Frame := { header := { opcode := opcode, masked := false, payloadLen := payload.size }, payload := payload }
      let c : Conn := (connState.conn : Conn)
      c.transport.send (encodeFrame frame)
      return server
    catch e =>
      IO.println s!"Failed to send to connection {connId}: {e}"
      let newConns := server.connections.filter (·.id ≠ connId)
      return { server with connections := newConns }

/-- Send a text message to a connection -/
def sendText (server : ServerState) (connId : Nat) (text : String) : IO ServerState := do
  let payload := ByteArray.mk text.toUTF8.data
  sendMessage server connId .text payload

/-- Send a binary message to a connection -/
def sendBinary (server : ServerState) (connId : Nat) (data : ByteArray) : IO ServerState := do
  sendMessage server connId .binary data

/-- Broadcast a message to all active connections -/
def broadcast (server : ServerState) (opcode : OpCode) (payload : ByteArray) : IO ServerState := do
  let mut newServer := server
  for connState in server.connections do
    if connState.active then
      newServer ← sendMessage newServer connState.id opcode payload
  return newServer

/-- Broadcast text to all connections -/
def broadcastText (server : ServerState) (text : String) : IO ServerState := do
  let payload := ByteArray.mk text.toUTF8.data
  broadcast server .text payload

/-- Stop the server and close all connections -/
def stop (server : ServerState) : IO Unit := do
  for connState in server.connections do
    try
      let c : Conn := (connState.conn : Conn)
      c.transport.close
    catch _ => pure ()
  IO.println "Server stopped"

/-- Simple server loop that handles one connection at a time -/
partial def runServer (server : ServerState) (handler : EventHandler) : IO Unit := do
  let (server', eventOpt) ← acceptConnection server
  match eventOpt with
  | some event =>
    handler event
    -- Process the connection if it was successfully established
    match event with
    | .connected connId _ =>
      let (server'', events) ← processConnection server' connId
      for event in events do
        handler event
      runServer server'' handler
    | _ => runServer server' handler
  | none => runServer server' handler

end WebSocket.Server
