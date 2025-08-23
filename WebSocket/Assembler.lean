import WebSocket.Core.Types
import WebSocket.Core.Frames
import WebSocket.Close
import WebSocket.UTF8

namespace WebSocket

/-- Fragmentation assembler state. -/
structure AssemblerState where
  buffering : Bool := false
  opcodeFirst? : Option OpCode := none
  acc : ByteArray := ByteArray.empty
  deriving Repr

/-- Output from frame processing -/
inductive AssemblerOutput
  | continue (st : AssemblerState)
  | message (opcode : OpCode) (data : ByteArray) (st : AssemblerState)
  | violation (v : ProtocolViolation)
  deriving Repr

/-- Build close frame -/
def buildCloseFrame (code : CloseCode) (reason : String := "") : Frame :=
  let codeBytes : ByteArray := ByteArray.mk #[UInt8.ofNat (code.toNat >>> 8), UInt8.ofNat (code.toNat &&& 0xFF)]
  let reasonBytes := ByteArray.mk reason.toUTF8.data
  let payload := if codeBytes.size + reasonBytes.size <= 125 then codeBytes ++ reasonBytes else codeBytes
  { header := { opcode := .close, masked := false, payloadLen := payload.size }, payload }

/-- Build close frame with enhanced validation for reason -/
def buildCloseFrameSafe (code : CloseCode) (reason : String := "") : Option Frame :=
  if reason.all (fun c => c.toNat >= 32 || c == '\t' || c == '\n' || c == '\r') then
    let codeBytes : ByteArray := ByteArray.mk #[UInt8.ofNat (code.toNat >>> 8), UInt8.ofNat (code.toNat &&& 0xFF)]
    let reasonBytes := ByteArray.mk reason.toUTF8.data
    if codeBytes.size + reasonBytes.size <= 125 then
      let payload := codeBytes ++ reasonBytes
      some { header := { opcode := .close, masked := false, payloadLen := payload.size }, payload }
    else none
  else none

/-- All protocol violations map to protocolError (placeholder) -/
def violationCloseCode : ProtocolViolation → CloseCode
  | _ => .protocolError

def closeFrameForViolation (v : ProtocolViolation) : Frame :=
  buildCloseFrame (violationCloseCode v) ""

/-- Process a frame through the assembler -/
def processFrame (st : AssemblerState) (f : Frame) : AssemblerOutput :=
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
    | .close =>
        match parseClosePayload f.payload with
        | some _ => .message f.header.opcode f.payload st
        | none => .violation .invalidClosePayload
    | .ping | .pong =>
        .message f.header.opcode f.payload st

end WebSocket
