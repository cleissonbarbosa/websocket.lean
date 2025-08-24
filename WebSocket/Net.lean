import WebSocket
import WebSocket.Handshake
import WebSocket.Random
import WebSocket.Net.InlineC
open WebSocket

namespace WebSocket.Net

/-- External C functions for basic TCP socket operations. -/

@[extern "ws_listen"]
opaque listenImpl (port : UInt32) : IO UInt32

@[extern "ws_accept"]
opaque acceptImpl (listenFd : UInt32) : IO UInt32

@[extern "ws_close"]
opaque closeImpl (fd : UInt32) : IO Unit

@[extern "ws_recv_bytes"]
opaque recvImpl (fd : UInt32) (maxBytes : UInt32) : IO ByteArray

@[extern "ws_send_bytes"]
opaque sendImpl (fd : UInt32) (data : ByteArray) : IO UInt32

@[extern "ws_set_nonblocking"]
opaque setNonblockingImpl (fd : UInt32) : IO Unit

@[extern "ws_connect"]
opaque connectImpl (host : @& String) (port : UInt32) : IO UInt32

/-- Handle for a listening socket -/
structure ListenHandle where
  fd : UInt32

/-- Implementation of abstract Transport using TCP sockets -/
structure TcpTransport where
  fd : UInt32
  closed : IO.Ref Bool

/-- Helper to construct a transport with an internal closed flag. -/
def mkTcpTransport (fd : UInt32) : IO TcpTransport := do
  let r ← IO.mkRef false
  pure { fd, closed := r }

/-- Convert TcpTransport to abstract Transport. For now we treat an empty read as "no data"; EOF distinction TBD. -/
def TcpTransport.toTransport (t : TcpTransport) : Transport := {
  recv := do
    let chunk ← recvImpl t.fd 65536
    pure chunk,
  send := fun data => do
    let isClosed ← t.closed.get
    if isClosed then pure () else
    let _ ← sendImpl t.fd data; pure (),
  closed := t.closed.get,
  close := do
    let was ← t.closed.get
    if was then pure () else
      closeImpl t.fd
      t.closed.set true
}

/-- Connection with TCP transport -/
structure TcpConn where
  transport : TcpTransport
  assembler : AssemblerState := {}
  pingState : PingState := {}

instance : Coe TcpConn Conn where
  coe tc := {
    transport := tc.transport.toTransport,
    assembler := tc.assembler,
    pingState := tc.pingState
  }

/-- Start listening on a port -/
def openServer (port : UInt32) : IO ListenHandle := do
  let fd ← listenImpl port
  pure { fd }

/-/ Accept connection and perform WebSocket handshake -/
def acceptAndUpgrade (lh : ListenHandle) : IO (Option TcpConn) :=
  try
    let clientFd ← acceptImpl lh.fd
    (try setNonblockingImpl clientFd catch _ => pure ())
    let requestBytes ← recvImpl clientFd 4096
    let requestString := String.fromUTF8! requestBytes
    match WebSocket.upgradeRaw requestString with
    | some response =>
        let responseText := s!"HTTP/1.1 {response.status} {response.reason}\r\n" ++
          String.intercalate "\r\n" (response.headers.map (fun (k,v) => s!"{k}: {v}")) ++
          "\r\n\r\n"
        let responseBytes := ByteArray.mk responseText.toUTF8.data
        let _ ← sendImpl clientFd responseBytes
        let transport ← mkTcpTransport clientFd
        pure (some { transport, assembler := {}, pingState := {} })
    | none =>
        closeImpl clientFd
        pure none
  catch _ => pure none

/-/ Connect to WebSocket server (client-side) -/
def connectClient (host : String) (port : UInt32) (resource : String := "/") (subprotocols : List String := []) : IO (Option TcpConn) :=
  try
    let fd ← connectImpl host port
    let key ← secureWebSocketKey
    let baseHeaders := [
      ("Host", host), ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Key", key), ("Sec-WebSocket-Version","13")
    ]
    let protoHeader := if subprotocols.isEmpty then [] else [("Sec-WebSocket-Protocol", String.intercalate ", " subprotocols)]
    let requestLines := [s!"GET {resource} HTTP/1.1"] ++ (baseHeaders ++ protoHeader).map (fun (k,v) => s!"{k}: {v}") ++ ["",""]
    let raw := String.intercalate "\r\n" requestLines
    let _ ← sendImpl fd (ByteArray.mk raw.toUTF8.data)
    let respBytes ← recvImpl fd 4096
    let respStr := String.fromUTF8! respBytes
    if respStr.startsWith "HTTP/1.1 101" then
      let lines := respStr.splitOn "\r\n"
      let headers := lines.tail!.takeWhile (· ≠ "")
      let accept? := headers.findSome? (fun l =>
        match l.splitOn ":" with
        | k::rest => if lower k.trim = "sec-websocket-accept" then some ((String.intercalate ":" rest).trim) else none
        | _ => none)
      match accept? with
      | some acceptVal =>
          let expected := acceptKey key
          if acceptVal = expected then
            let transport ← mkTcpTransport fd
            pure (some { transport, assembler := {}, pingState := {} })
          else (do closeImpl fd; pure none)
      | none => (do closeImpl fd; pure none)
    else (do closeImpl fd; pure none)
  catch _ => pure none

/-- Accept a connection and perform a configurable WebSocket upgrade (subprotocols/extensions). -/
def acceptAndUpgradeWithConfig (lh : ListenHandle) (cfg : UpgradeConfig) : IO (Option (TcpConn × Option String × List ExtensionConfig)) := do
  try
    let clientFd ← acceptImpl lh.fd
    (try setNonblockingImpl clientFd catch _ => pure ())
    let requestBytes ← recvImpl clientFd 4096
    let requestString := String.fromUTF8! requestBytes
    match WebSocket.HTTP.parse requestString with
    | .error _ => closeImpl clientFd; return none
    | .ok (rl, hs) =>
        let req : HandshakeRequest := { method := rl.method, resource := rl.resource, headers := hs }
        match upgradeWithFullConfig req cfg with
        | .error _ => closeImpl clientFd; return none
        | .ok resp =>
            let responseText := s!"HTTP/1.1 {resp.status} {resp.reason}\r\n" ++
              String.intercalate "\r\n" (resp.headers.map (fun (k,v) => s!"{k}: {v}")) ++
              "\r\n\r\n"
            let _ ← sendImpl clientFd (ByteArray.mk responseText.toUTF8.data)
            let transport ← mkTcpTransport clientFd
            let selectedSubprotocol := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Protocol" then some v else none)
            let negotiatedExtensions := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Extensions" then some v else none)
              |>.map parseExtensions |>.getD []
            return some ({ transport, assembler := {}, pingState := {} }, selectedSubprotocol, negotiatedExtensions)
  catch _ =>
    return none

/-- Incrementally read from a TcpConn, accumulate into a LoopState and process frames.
 Returns updated TcpConn plus list of events (opcode,payload).
-/
def stepTcp (tc : TcpConn) (ls? : Option WebSocket.LoopState := none) : IO (TcpConn × List (OpCode × ByteArray) × WebSocket.LoopState) := do
  let base : Conn := (tc : Conn)
  let ls : WebSocket.LoopState := ls?.getD { conn := base }
  let (ls', events) ← WebSocket.stepIO ls
  -- propagate back updated assembler & ping state
  let newTcp : TcpConn := { tc with assembler := ls'.conn.assembler, pingState := ls'.conn.pingState }
  pure (newTcp, events, ls')

end WebSocket.Net
