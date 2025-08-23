import WebSocket.Core.Types
import WebSocket.Core.Frames
import WebSocket.Crypto.Base64
import WebSocket.Crypto.SHA1
import WebSocket.HTTP
import WebSocket.UTF8

namespace WebSocket
open WebSocket

-- Handshake (simplified)
structure HandshakeRequest where
  method : String
  resource : String
  headers : List (String × String)
  deriving Repr
structure HandshakeResponse where
  status : Nat
  reason : String
  headers : List (String × String)
  deriving Repr
inductive HandshakeError
  | badMethod
  | missingHost
  | missingUpgrade
  | notWebSocket
  | missingConnection
  | connectionNotUpgrade
  | missingKey
  deriving Repr, DecidableEq
def lower (s : String) : String := s.map (·.toLower)
def header? (r : HandshakeRequest) (name : String) : Option String :=
  let target := lower name; r.headers.findSome? (fun (k,v) => if lower k = target then some v else none)
def containsIgnoreCase (h n : String) : Bool :=
  let lh := lower h
  let ln := lower n
  (lh.splitOn ln).length > 1
def acceptKey (clientKey : String) : String :=
  let guid := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  let bytes := ByteArray.mk ((clientKey ++ guid).toUTF8.data.map (fun c => UInt8.ofNat c.toNat))
  let digest := WebSocket.Crypto.SHA1 bytes
  WebSocket.Crypto.base64Encode digest
def upgradeE (req : HandshakeRequest) : Except HandshakeError HandshakeResponse := do
  if req.method ≠ "GET" then throw .badMethod
  match header? req "Host" with | none => throw .missingHost | some _ => pure ()
  let some u := header? req "Upgrade" | throw .missingUpgrade
  if lower u ≠ "websocket" then throw .notWebSocket
  let some c := header? req "Connection" | throw .missingConnection
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  let accept := acceptKey k
  -- Subprotocol negotiation: pick first token (if any) from Sec-WebSocket-Protocol
  let subProto? : Option String :=
    match header? req "Sec-WebSocket-Protocol" with
    | none => none
    | some raw =>
        let tokens := raw.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
        tokens.head?
  let baseHeaders := [
    ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Accept", accept)
  ]
  let headers := match subProto? with | some sp => baseHeaders ++ [("Sec-WebSocket-Protocol", sp)] | none => baseHeaders
  return { status := 101, reason := "Switching Protocols", headers }

def upgrade (req : HandshakeRequest) : Option HandshakeResponse :=
  match upgradeE req with | .ok r => some r | .error _ => none

/-- Convenience: parse raw HTTP request text and attempt WebSocket upgrade. -/
def upgradeRaw (raw : String) : Option HandshakeResponse :=
  match WebSocket.HTTP.parse raw with
  | .error _ => none
  | .ok (rl, hs) =>
      let req : HandshakeRequest := { method := rl.method, resource := rl.resource, headers := hs }
      upgrade req

/-- Close codes per RFC 6455 (subset). -/
inductive CloseCode
  | normalClosure | goingAway | protocolError | unsupportedData | noStatusRcvd
  | abnormalClosure | invalidPayload | policyViolation | messageTooBig
  | mandatoryExt | internalError | tlsHandshake
  deriving Repr, DecidableEq

namespace CloseCode
  def toNat : CloseCode → Nat
    | normalClosure => 1000 | goingAway => 1001 | protocolError => 1002 | unsupportedData => 1003
    | noStatusRcvd => 1005 | abnormalClosure => 1006 | invalidPayload => 1007 | policyViolation => 1008
    | messageTooBig => 1009 | mandatoryExt => 1010 | internalError => 1011 | tlsHandshake => 1015
  def ofNat? (n : Nat) : Option CloseCode :=
    match n with
    | 1000 => some .normalClosure | 1001 => some .goingAway | 1002 => some .protocolError
    | 1003 => some .unsupportedData | 1005 => some .noStatusRcvd | 1006 => some .abnormalClosure
    | 1007 => some .invalidPayload | 1008 => some .policyViolation | 1009 => some .messageTooBig
    | 1010 => some .mandatoryExt | 1011 => some .internalError | 1015 => some .tlsHandshake
    | _ => none
end CloseCode

structure CloseInfo where
  code : Option CloseCode -- Some indicates code present (must be at least 2 bytes)
  reason : String := ""
  deriving Repr

def parseClosePayload (payload : ByteArray) : Option CloseInfo :=
  if payload.size = 0 then some { code := none }
  else if payload.size = 1 then none -- invalid (must be 0 or ≥2 if code present)
  else
    let c := ((payload.get! 0).toNat <<< 8) + (payload.get! 1).toNat
    match CloseCode.ofNat? c with
    | none => some { code := none, reason := "" }
    | some cc =>
      -- Remaining bytes interpreted as UTF-8 (not validated yet)
      let rest := payload.extract 2 payload.size
  let utf8BA : ByteArray := rest
  let reason := (String.fromUTF8? utf8BA).getD ""
  some { code := some cc, reason }

def buildCloseFrame (code : CloseCode) (reason : String := "") : Frame :=
  let codeBytes : ByteArray := ByteArray.mk #[UInt8.ofNat (code.toNat >>> 8), UInt8.ofNat (code.toNat &&& 0xFF)]
  let payload := codeBytes ++ ByteArray.mk reason.toUTF8.data
  { header := { opcode := .close, masked := false, payloadLen := payload.size }, payload }

-- All current protocol violations map to protocolError (could specialize later)
def violationCloseCode : ProtocolViolation → CloseCode
  | _ => .protocolError

def closeFrameForViolation (v : ProtocolViolation) : Frame :=
  buildCloseFrame (violationCloseCode v) ""

/-! Simple deterministic pseudo-random generator (xorshift32) for masking keys. Not cryptographic. -/
structure RNG where state : UInt32

namespace RNG
  def next (r : RNG) : RNG × UInt32 :=
    let x0 := r.state
    let x1 := x0 ^^^ (x0 <<< 13)
    let x2 := x1 ^^^ (x1 >>> 17)
    let x3 := x2 ^^^ (x2 <<< 5)
    ({ state := x3 }, x3)
  def maskingKey (r : RNG) : RNG × MaskingKey :=
    let (r1, a) := r.next
    let (r2, b) := r1.next
    let (r3, c) := r2.next
    let (r4, d) := r3.next
    let mk (w : UInt32) : UInt8 := UInt8.ofNat (w.toNat &&& 0xFF)
    (r4, { b0 := mk a, b1 := mk b, b2 := mk c, b3 := mk d })
end RNG

def randomMaskingKey (seed : Nat) : MaskingKey :=
  let seed32 : UInt32 := UInt32.ofNat (seed &&& 0xFFFFFFFF)
  let (_, k) := RNG.maskingKey { state := seed32 }
  k

/-- Fragmentation assembler state. -/
structure AssemblerState where
  buffering : Bool := false
  opcodeFirst? : Option OpCode := none
  acc : ByteArray := ByteArray.empty
  deriving Repr

inductive AssemblerOutput
  | continue (st : AssemblerState)
  | message (opcode : OpCode) (data : ByteArray) (st : AssemblerState)
  | violation (v : ProtocolViolation)
  deriving Repr

def processFrame (st : AssemblerState) (f : Frame) : AssemblerOutput :=
  -- Validate control frames first
  match validateFrame f with
  | some v => .violation v
  | none =>
    match f.header.opcode with
    | .continuation =>
        if st.buffering then
          let newAcc := st.acc ++ f.payload
          if f.header.fin then
            let finalData := newAcc
            if st.opcodeFirst? = some .text then
              if validateUTF8 finalData then
                .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty }
              else
                .violation .textInvalidUTF8
            else
              .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty }
          else
            .continue { st with acc := newAcc }
        else
          .violation .unexpectedContinuation
    | .text | .binary =>
        if f.header.fin then
          if f.header.opcode = .text then
            if validateUTF8 f.payload then
              .message f.header.opcode f.payload st
            else
              .violation .textInvalidUTF8
          else
            .message f.header.opcode f.payload st
        else
          .continue { buffering := true, opcodeFirst? := some f.header.opcode, acc := f.payload }
    | .close | .ping | .pong =>
        .message f.header.opcode f.payload st

/-- Simple ping scheduler state. -/
structure PingState where
  lastPing : Nat := 0
  lastPong : Nat := 0
  interval : Nat := 30 -- seconds (logical time units)
  deriving Repr

def duePing (t : Nat) (ps : PingState) : Bool := t - ps.lastPing ≥ ps.interval

def registerPing (t : Nat) (ps : PingState) : PingState := { ps with lastPing := t }
def registerPong (t : Nat) (ps : PingState) : PingState := { ps with lastPong := t }

/-- Abstract transport interface (stub). -/
structure Transport where
  recv : IO ByteArray
  send : ByteArray → IO Unit

structure Conn where
  transport : Transport
  assembler : AssemblerState
  pingState : PingState

def makeTextFrame (s : String) : Frame :=
  let payload := ByteArray.mk s.toUTF8.data
  { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload }

def makePongFrame (payload : ByteArray) : Frame :=
  { header := { opcode := .pong, masked := false, payloadLen := payload.size }, payload }

def autoPong (frames : List (OpCode × ByteArray)) : List Frame :=
  frames.foldl (fun acc (opc,pl) => if opc = .ping then acc ++ [makePongFrame pl] else acc) []

def handleIncoming (c : Conn) (bytes : ByteArray) : IO (Conn × List (OpCode × ByteArray)) := do
  -- Naive: decode single frame only
  match decodeFrame bytes with
  | none => pure (c, [])
  | some res =>
    match processFrame c.assembler res.frame with
    | .violation _ => pure (c, [])
    | .continue st' => pure ({ c with assembler := st' }, [])
    | .message opc data st' =>
        let frames := [(opc, data)]
        -- Automatic pong reply if ping
        if opc = .ping then
          let pong := makePongFrame data
          c.transport.send (encodeFrame pong)
          pure ({ c with assembler := st' }, frames ++ [(.pong, data)])
        else
        pure ({ c with assembler := st' }, frames)
end WebSocket
