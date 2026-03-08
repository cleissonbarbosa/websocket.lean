/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

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
  fragmentCount : Nat := 0
  /-- Optional maximum total message size (payload bytes across a fragmented sequence or single frame). -/
  maxMessageSize? : Option Nat := none
  /-- Optional maximum number of fragments allowed in a single message. -/
  maxFragments? : Option Nat := none
  deriving Repr

instance : Inhabited AssemblerState := ⟨{}⟩

/-- Helper smart constructor allowing optional max message size and fragment count constraints. -/
def mkAssemblerState (maxMessageSize? : Option Nat := none) (maxFragments? : Option Nat := none) : AssemblerState :=
  { maxMessageSize?, maxFragments? }

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
  | .tooManyFragments     => .policyViolation  -- 1008
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
  let nextFragmentCount := if f.header.opcode = .continuation then st.fragmentCount + 1 else 1
  let fragmentLimitExceeded :=
    match st.maxFragments? with
    | some lim => decide (nextFragmentCount > lim)
    | none => false
  let sizeExceeded (sz : Nat) :=
    match st.maxMessageSize? with
    | some lim => decide (sz > lim)
    | none => false
  let resetState : AssemblerState :=
    { buffering := false, opcodeFirst? := none, acc := ByteArray.empty,
      fragmentCount := 0, maxMessageSize? := st.maxMessageSize?, maxFragments? := st.maxFragments? }
  let finishMessage (opcode : OpCode) (data : ByteArray) : AssemblerOutput :=
    if opcode = .text && !validateUTF8 data then .violation .textInvalidUTF8
    else .message opcode data resetState
  match validateFrame f with
  | some v => .violation v
  | none =>
    match f.header.opcode with
    | .continuation =>
        if !st.buffering then .violation .unexpectedContinuation
        else if fragmentLimitExceeded then .violation .tooManyFragments
        else
          let newAcc := st.acc ++ f.payload
          if sizeExceeded newAcc.size then .violation .oversizedMessage
          else if f.header.fin then finishMessage (st.opcodeFirst?.getD .text) newAcc
          else .continue { st with acc := newAcc, fragmentCount := nextFragmentCount }
    | .text | .binary =>
        if st.buffering then .violation .fragmentSequenceError
        else if f.header.fin then
          if sizeExceeded f.payload.size then .violation .oversizedMessage
          else finishMessage f.header.opcode f.payload
        else if fragmentLimitExceeded then .violation .tooManyFragments
        else if sizeExceeded f.payload.size then .violation .oversizedMessage
        else .continue { buffering := true, opcodeFirst? := some f.header.opcode, acc := f.payload,
                         fragmentCount := 1, maxMessageSize? := st.maxMessageSize?, maxFragments? := st.maxFragments? }
    | .close =>
        match parseClosePayload f.payload with
        | some _ => .message f.header.opcode f.payload st
        | none => .violation .invalidClosePayload
    | .ping | .pong =>
        .message f.header.opcode f.payload st

end WebSocket
