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
  /-- Optional maximum total message size (payload bytes across a fragmented sequence or single frame). -/
  maxMessageSize? : Option Nat := none
  deriving Repr

instance : Inhabited AssemblerState := ⟨{}⟩

/-- Helper smart constructor allowing an optional max message size constraint. -/
def mkAssemblerState (maxMessageSize? : Option Nat := none) : AssemblerState :=
  { maxMessageSize? }

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


/-- Map protocol violations to appropriate RFC close codes.
RFC 6455 guidance (informal mapping used here):
* protocol errors (malformed framing, sequencing, reserved bits, invalid opcodes, bad close payload) -> 1002 protocolError
* invalid UTF-8 in text -> 1007 invalidPayload
* message too large / configured size limit -> 1009 messageTooBig
We treat fragmentation sequence structural mistakes as protocol errors.
-/
def violationCloseCode : ProtocolViolation → CloseCode
  | .textInvalidUTF8      => .invalidPayload   -- 1007
  | .oversizedMessage     => .messageTooBig    -- 1009
  | .controlFragmented
  | .controlTooLong
  | .unexpectedContinuation
  | .reservedBitsSet
  | .invalidOpcode
  | .invalidClosePayload
  | .fragmentSequenceError => .protocolError   -- 1002

/-- Construct a close frame for a given violation (empty reason for now). -/
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
          -- size limit check (fragmented accumulation)
          match st.maxMessageSize? with
          | some lim =>
              if newAcc.size > lim then
                .violation .oversizedMessage
              else if f.header.fin then
                let finalData := newAcc
                if st.opcodeFirst? = some .text then
                  if validateUTF8 finalData then
                    .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty, maxMessageSize? := st.maxMessageSize? }
                  else
                    .violation .textInvalidUTF8
                else
                  .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty, maxMessageSize? := st.maxMessageSize? }
              else
                .continue { st with acc := newAcc }
          | none =>
              if f.header.fin then
                let finalData := newAcc
                if st.opcodeFirst? = some .text then
                  if validateUTF8 finalData then
                    .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty, maxMessageSize? := st.maxMessageSize? }
                  else
                    .violation .textInvalidUTF8
                else
                  .message (st.opcodeFirst?.getD .text) finalData { buffering := false, opcodeFirst? := none, acc := ByteArray.empty, maxMessageSize? := st.maxMessageSize? }
              else
                .continue { st with acc := newAcc }
        else
          .violation .unexpectedContinuation
    | .text | .binary =>
        if st.buffering then
          -- A new data frame starting while another fragmented message in progress
          .violation .fragmentSequenceError
        else if f.header.fin then
          if f.header.opcode = .text then
            if validateUTF8 f.payload then
              match st.maxMessageSize? with
              | some lim => if f.payload.size > lim then .violation .oversizedMessage else .message f.header.opcode f.payload st
              | none => .message f.header.opcode f.payload st
            else
              .violation .textInvalidUTF8
          else
            match st.maxMessageSize? with
            | some lim => if f.payload.size > lim then .violation .oversizedMessage else .message f.header.opcode f.payload st
            | none => .message f.header.opcode f.payload st
        else
          -- Start a fragmented sequence
          match st.maxMessageSize? with
          | some lim =>
              if f.payload.size > lim then
                .violation .oversizedMessage
              else
                .continue { buffering := true, opcodeFirst? := some f.header.opcode, acc := f.payload, maxMessageSize? := st.maxMessageSize? }
          | none =>
              .continue { buffering := true, opcodeFirst? := some f.header.opcode, acc := f.payload, maxMessageSize? := st.maxMessageSize? }
    | .close =>
        match parseClosePayload f.payload with
        | some _ => .message f.header.opcode f.payload st
        | none => .violation .invalidClosePayload
    | .ping | .pong =>
        .message f.header.opcode f.payload st

end WebSocket
