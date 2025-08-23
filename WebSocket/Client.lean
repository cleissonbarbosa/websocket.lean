import WebSocket
import WebSocket.Net
import WebSocket.Random
open WebSocket WebSocket.Net

namespace WebSocket.Client

/-- WebSocket client configuration -/
structure ClientConfig where
  host : String := "localhost"
  port : UInt32 := 8080
  resource : String := "/"
  subprotocols : List String := []
  headers : List (String × String) := []
  pingInterval : Nat := 30
  maxMissedPongs : Nat := 3
  deriving Repr

/-- Client event types -/
inductive ClientEvent
  | connected
  | disconnected (reason : String)
  | message (opcode : OpCode) (payload : ByteArray)
  | error (error : String)
  | pong (payload : ByteArray)
  deriving Repr

/-- Client state -/
structure ClientState where
  config : ClientConfig
  conn : Option TcpConn := none
  connected : Bool := false
  deriving Repr

/-- Event handler type -/
abbrev EventHandler := ClientEvent → IO Unit

/-- Create a new client with configuration -/
def mkClient (config : ClientConfig) : ClientState :=
  { config }

/-- Connect to WebSocket server -/
def connect (client : ClientState) : IO (ClientState × Option ClientEvent) := do
  try
    match ← connectClient client.config.host client.config.port client.config.resource with
    | some tcpConn =>
        let newClient := {
          client with
          conn := some tcpConn,
          connected := true
        }
        return (newClient, some .connected)
    | none =>
        return (client, some (.error "Failed to connect to server"))
  catch e =>
    return (client, some (.error s!"Connection error: {e}"))

/-- Process incoming messages -/
def processMessages (client : ClientState) : IO (ClientState × List ClientEvent) := do
  match client.conn with
  | none => return (client, [.error "Not connected"])
  | some tcpConn =>
    if ¬ client.connected then
      return (client, [])
    try
      let bytes ← tcpConn.transport.recv
      if bytes.size = 0 then
        -- Connection closed
        let newClient := {
          client with
          conn := none,
          connected := false
        }
        return (newClient, [.disconnected "Connection closed"])
      else
        let (newConn, events) ← WebSocket.handleIncoming tcpConn bytes
        let newTcpConn : TcpConn := {
          transport := newConn.transport,
          assembler := newConn.assembler,
          pingState := newConn.pingState
        }
        let newClient := { client with conn := some newTcpConn }
        let clientEvents := events.map (fun (opc, payload) =>
          if opc = .pong then ClientEvent.pong payload
          else ClientEvent.message opc payload)
        return (newClient, clientEvents)
    catch e =>
      let newClient := {
        client with
        conn := none,
        connected := false
      }
      return (newClient, [.error s!"Processing error: {e}"])

/-- Send a message -/
def sendMessage (client : ClientState) (opcode : OpCode) (payload : ByteArray) : IO ClientState := do
  match client.conn with
  | none =>
    IO.println "Not connected"
    return client
  | some tcpConn =>
    try
      let mk ← randomMaskingKeyIO
      let frame : Frame := {
        header := { opcode := opcode, masked := true, payloadLen := payload.size },
        maskingKey? := some mk,
        payload := payload
      }
  let t := tcpConn.transport.toTransport
  t.send (encodeFrame frame)
      return client
    catch e =>
      IO.println s!"Failed to send message: {e}"
      return { client with conn := none, connected := false }

/-- Send a text message -/
def sendText (client : ClientState) (text : String) : IO ClientState := do
  let payload := ByteArray.mk text.toUTF8.data
  sendMessage client .text payload

/-- Send a binary message -/
def sendBinary (client : ClientState) (data : ByteArray) : IO ClientState := do
  sendMessage client .binary data

/-- Send a ping -/
def sendPing (client : ClientState) (payload : ByteArray := ByteArray.empty) : IO ClientState := do
  sendMessage client .ping payload

/-- Close the connection -/
def close (client : ClientState) (code : CloseCode := .normalClosure) (reason : String := "") : IO ClientState := do
  match client.conn with
  | none => return client
  | some tcpConn =>
    try
      let closeFrame := buildCloseFrame code reason
  let t := tcpConn.transport.toTransport
  t.send (encodeFrame closeFrame)
  t.close
      return { client with conn := none, connected := false }
    catch _ =>
      return { client with conn := none, connected := false }

/-- Simple client loop -/
partial def runClient (client : ClientState) (handler : EventHandler) : IO Unit := do
  let (client', events) ← processMessages client
  for event in events do
    handler event
  -- Add delay to prevent busy waiting
  IO.sleep 10  -- 10ms
  if client'.connected then
    runClient client' handler
  else
    handler (.disconnected "Client stopped")

end WebSocket.Client
