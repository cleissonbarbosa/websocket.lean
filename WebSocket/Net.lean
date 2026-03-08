/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Handshake
import WebSocket.Random
import WebSocket.Net.InlineC
import WebSocket.Log
import WebSocket.Net.TLSInlineC
open WebSocket

namespace WebSocket.Net

/-- External C functions for basic TCP socket operations. -/

@[extern "ws_listen"]
opaque listenImpl (port : UInt32) : IO UInt32

@[extern "ws_accept"]
opaque acceptImpl (listenFd : UInt32) : IO UInt32

@[extern "ws_peer_addr"]
opaque peerAddrImpl (fd : UInt32) : IO String

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

-- TLS FFI
@[extern "ws_tls_init_ctx"] opaque tlsInitCtxImpl (certFile : @& String) (keyFile : @& String) : IO UInt64
@[extern "ws_tls_accept"] opaque tlsAcceptImpl (ctxPtr : UInt64) (fd : UInt32) : IO UInt64
@[extern "ws_tls_read"] opaque tlsReadImpl (sslPtr : UInt64) (maxBytes : UInt32) : IO ByteArray
@[extern "ws_tls_write"] opaque tlsWriteImpl (sslPtr : UInt64) (data : ByteArray) : IO UInt32
@[extern "ws_tls_close"] opaque tlsCloseImpl (sslPtr : UInt64) : IO Unit

structure AcceptedClient where
  fd : UInt32
  addr : String

/-- Stream abstraction (plain TCP or TLS) used during HTTP upgrade and transport layer. -/
structure Stream where
  recvSome : UInt32 → IO ByteArray
  sendAll : ByteArray → IO Unit
  close : IO Unit
  isTLS : Bool := false

private partial def sendAllWith (sendChunk : ByteArray → IO UInt32) (data : ByteArray)
    (offset : Nat := 0) (retries : Nat := 0) : IO Unit := do
  if offset >= data.size then
    pure ()
  else
    let sent ← sendChunk (data.extract offset data.size)
    if sent.toNat = 0 then
      if retries >= 1000 then
        throw <| IO.userError "send timeout"
      IO.sleep 10
      sendAllWith sendChunk data offset (retries + 1)
    else
      sendAllWith sendChunk data (offset + sent.toNat) 0

private def renderHttpResponse (resp : HandshakeResponse) : ByteArray :=
  ByteArray.mk <| (s!"HTTP/1.1 {resp.status} {resp.reason}\r\n" ++
    String.intercalate "\r\n" (resp.headers.map (fun (k,v) => s!"{k}: {v}")) ++
    "\r\n\r\n").toUTF8.data

private def hasHeaderTerminator (buf : ByteArray) : Bool :=
  ((String.fromUTF8! buf).splitOn "\r\n\r\n").length > 1

private inductive HttpReadError where
  | timeout
  | headersTooLarge

private partial def readHttpRequest (stream : Stream) (maxHeaderBytes : Nat) (attemptsLeft : Nat)
    (acc : ByteArray := ByteArray.empty) : IO (Except HttpReadError ByteArray) := do
  if acc.size > maxHeaderBytes then
    return .error .headersTooLarge
  if hasHeaderTerminator acc then
    return .ok acc
  if attemptsLeft = 0 then
    return .error .timeout
  let chunk ← stream.recvSome 1024
  if chunk.size = 0 then
    IO.sleep 10
    readHttpRequest stream maxHeaderBytes (attemptsLeft - 1) acc
  else
    readHttpRequest stream maxHeaderBytes (attemptsLeft - 1) (acc ++ chunk)

/-- Construct a plain TCP stream over a file descriptor. -/
def mkPlainStream (fd : UInt32) : Stream :=
  { recvSome := fun n => recvImpl fd n
  , sendAll := fun data => sendAllWith (sendImpl fd) data
  , close := closeImpl fd
  , isTLS := false
  }

/-- Construct a TLS stream over a file descriptor + SSL pointer. -/
def mkTlsStream (_fd : UInt32) (ssl : UInt64) : Stream :=
  { recvSome := fun n => tlsReadImpl ssl n
  , sendAll := fun data => sendAllWith (tlsWriteImpl ssl) data
  , close := tlsCloseImpl ssl
  , isTLS := true
  }

-- (Moved TcpTransport definitions earlier to be available here)


/-- Handle for a listening socket -/
structure ListenHandle where
  fd : UInt32

/-- Implementation of abstract Transport using TCP sockets -/
structure TcpTransport where
  fd : UInt32
  closed : IO.Ref Bool
  tls? : Option UInt64 := none  -- SSL* when present

/-- Helper to construct a transport with an internal closed flag. -/
def mkTcpTransport (fd : UInt32) : IO TcpTransport := do
  let r ← IO.mkRef false
  pure { fd, closed := r, tls? := none }

/-- Convert TcpTransport to abstract Transport. For now we treat an empty read as "no data"; EOF distinction TBD. -/
def TcpTransport.toTransport (t : TcpTransport) : Transport := {
  recv := do
    match t.tls? with
    | some ssl => tlsReadImpl ssl 65536
    | none => recvImpl t.fd 65536
  , send := fun data => do
      let isClosed ← t.closed.get
      if isClosed then pure () else
        match t.tls? with
        | some ssl => sendAllWith (tlsWriteImpl ssl) data
        | none => sendAllWith (sendImpl t.fd) data
  , closed := t.closed.get
  , close := do
      let was ← t.closed.get
      if was then pure () else
        (match t.tls? with | some ssl => (try tlsCloseImpl ssl catch _ => pure ()) | none => pure ())
        closeImpl t.fd; t.closed.set true
}



/-- Connection with TCP transport -/
structure TcpConn where
  transport : TcpTransport
  assembler : AssemblerState := {}
  pingState : PingState := {}
  buffer : ByteArray := ByteArray.empty

instance : Coe TcpConn Conn where
  coe tc := {
    transport := tc.transport.toTransport,
    assembler := tc.assembler,
    pingState := tc.pingState
  }

/-- Perform HTTP WebSocket upgrade over a generic `Stream`. Returns the resulting `TcpConn` plus selected subprotocol and negotiated extensions. -/
private def performHttpUpgrade (stream : Stream) (clientFd : UInt32) (cfg : UpgradeConfig)
  (handshakeTimeoutSeconds : Nat := 10) (maxHeaderBytes : Nat := 16384)
  : IO (Option (TcpConn × Option String × List ExtensionConfig)) := do
  let attempts := max 1 (handshakeTimeoutSeconds * 100)
  let requestBytes ← match ← readHttpRequest stream maxHeaderBytes attempts with
  | .error .timeout =>
      stream.sendAll (renderHttpResponse { status := 408, reason := "Request Timeout", headers := [] })
      return none
  | .error .headersTooLarge =>
      stream.sendAll (renderHttpResponse { status := 431, reason := "Request Header Fields Too Large", headers := [] })
      return none
  | .ok requestBytes =>
      pure requestBytes
  let requestString := String.fromUTF8! requestBytes
  match WebSocket.HTTP.parse requestString with
  | .error _ =>
      stream.sendAll (renderHttpResponse { status := 400, reason := "Bad Request", headers := [] })
      return none
  | .ok (rl, hs) =>
      let req : HandshakeRequest := { method := rl.method, resource := rl.resource, headers := hs }
      match upgradeWithFullConfig req cfg with
      | .error err =>
          let resp ← handshakeErrorResponse err
          stream.sendAll (renderHttpResponse resp)
          return none
      | .ok resp =>
          stream.sendAll (renderHttpResponse resp)
          let baseTransport ← mkTcpTransport clientFd
          let base : TcpConn := { transport := baseTransport }
          let selectedSubprotocol := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Protocol" then some v else none)
          let negotiatedExtensions := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Extensions" then some v else none)
            |>.map parseExtensions |>.getD []
          return some (base, selectedSubprotocol, negotiatedExtensions)



/-- Start listening on a port -/
def openServer (port : UInt32) : IO ListenHandle := do
  let fd ← listenImpl port
  pure { fd }

/-- Accept a client and resolve its peer address. -/
def acceptClient (lh : ListenHandle) : IO AcceptedClient := do
  let clientFd ← acceptImpl lh.fd
  (try setNonblockingImpl clientFd catch _ => pure ())
  let clientAddr ← (try peerAddrImpl clientFd catch _ => pure "unknown")
  pure { fd := clientFd, addr := clientAddr }

/-/ Accept connection and perform WebSocket handshake -/
def acceptAndUpgrade (lh : ListenHandle) : IO (Option TcpConn) :=
  try
    let client ← acceptClient lh
    match ← performHttpUpgrade (mkPlainStream client.fd) client.fd {} with
    | some (tcpConn, _, _) => pure (some tcpConn)
    | none =>
        closeImpl client.fd
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
    sendAllWith (sendImpl fd) (ByteArray.mk raw.toUTF8.data)
    let respBytes ← readHttpRequest (mkPlainStream fd) 16384 1000
    let respBytes := match respBytes with | .ok bytes => bytes | .error _ => ByteArray.empty
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

/-- Upgrade an already accepted TCP client with optional TLS and configurable handshake limits. -/
def acceptAndUpgradeClientWithConfig (clientFd : UInt32) (cfg : UpgradeConfig)
    (tlsCtx? : Option UInt64 := none) (handshakeTimeoutSeconds : Nat := 10)
    : IO (Option (TcpConn × Option String × List ExtensionConfig)) := do
  try
    let mut tlsPtr? : Option UInt64 := none
    match tlsCtx? with
    | some ctx =>
        try
          let ssl ← tlsAcceptImpl ctx clientFd
          tlsPtr? := some ssl
        catch _ =>
          WebSocket.log .error "TLS handshake failed (SSL_accept)"
          closeImpl clientFd
          return none
    | none => pure ()
    let stream : Stream := match tlsPtr? with
      | some ssl => mkTlsStream clientFd ssl
      | none => mkPlainStream clientFd
    match ← performHttpUpgrade stream clientFd cfg handshakeTimeoutSeconds with
    | some (tcpBase, subp, exts) =>
        let tcpFinal := match tlsPtr? with
          | some ssl => { tcpBase with transport := { tcpBase.transport with tls? := some ssl } }
          | none => tcpBase
        return some (tcpFinal, subp, exts)
    | none =>
        closeImpl clientFd
        return none
  catch _ =>
    return none

/-- Accept a connection and perform a configurable WebSocket upgrade (subprotocols/extensions). -/
def acceptAndUpgradeWithConfig (lh : ListenHandle) (cfg : UpgradeConfig) (tlsCtx? : Option UInt64 := none) : IO (Option (TcpConn × Option String × List ExtensionConfig)) := do
  try
    let client ← acceptClient lh
    acceptAndUpgradeClientWithConfig client.fd cfg tlsCtx?
  catch _ =>
    return none

/-- Incrementally read from a TcpConn, accumulate into a LoopState and process frames.
 Returns updated TcpConn plus list of events (opcode,payload).
-/
def stepTcp (tc : TcpConn) (ls? : Option WebSocket.LoopState := none) : IO (TcpConn × List (OpCode × ByteArray) × WebSocket.LoopState) := do
  let base : Conn := (tc : Conn)
  let ls : WebSocket.LoopState := ls?.getD { conn := base, buffer := tc.buffer }
  let (ls', events) ← WebSocket.stepIO ls
  -- propagate back updated assembler & ping state
  let newTcp : TcpConn := { tc with assembler := ls'.conn.assembler, pingState := ls'.conn.pingState, buffer := ls'.buffer }
  pure (newTcp, events, ls')

end WebSocket.Net
