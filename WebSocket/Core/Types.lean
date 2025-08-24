/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-- Basic opcodes per RFC 6455. -/
inductive OpCode
  | continuation | text | binary | close | ping | pong
  deriving Repr, DecidableEq

namespace OpCode
  def toNat : OpCode → UInt8
    | continuation => 0x0 | text => 0x1 | binary => 0x2
    | close => 0x8 | ping => 0x9 | pong => 0xA
  def isControl : OpCode → Bool
    | close | ping | pong => true
    | _ => false
  instance : ToString OpCode where
    toString
      | continuation => "continuation"
      | text => "text"
      | binary => "binary"
      | close => "close"
      | ping => "ping"
      | pong => "pong"
end OpCode

/-- Wire frame header. -/
structure FrameHeader where
  fin  : Bool := true
  rsv1 : Bool := false
  rsv2 : Bool := false
  rsv3 : Bool := false
  opcode : OpCode
  masked : Bool
  payloadLen : Nat
  deriving Repr, DecidableEq

/-- Masking key (client-to-server). -/
structure MaskingKey where
  b0 : UInt8
  b1 : UInt8
  b2 : UInt8
  b3 : UInt8
  deriving Repr, DecidableEq

structure Frame where
  header : FrameHeader
  maskingKey? : Option MaskingKey := none
  payload : ByteArray


inductive ProtocolViolation
  | controlFragmented
  | controlTooLong
  | unexpectedContinuation
  | reservedBitsSet
  | invalidOpcode
  | textInvalidUTF8
  | invalidClosePayload
  | oversizedMessage
  | fragmentSequenceError
  deriving Repr, DecidableEq

instance : ToString ProtocolViolation where
  toString
    | ProtocolViolation.controlFragmented => "control frame fragmented"
    | ProtocolViolation.controlTooLong => "control frame payload >125"
    | ProtocolViolation.unexpectedContinuation => "unexpected continuation frame"
    | ProtocolViolation.reservedBitsSet => "reserved RSV bits set"
    | ProtocolViolation.invalidOpcode => "invalid opcode"
    | ProtocolViolation.textInvalidUTF8 => "invalid UTF-8 in text message"
    | ProtocolViolation.invalidClosePayload => "invalid close frame payload"
    | ProtocolViolation.oversizedMessage => "message too large"
    | ProtocolViolation.fragmentSequenceError => "fragmentation sequence error"

instance : Repr ByteArray where reprPrec b _ := s!"#ByteArray({b.size} bytes)"
instance [Repr α] : Repr (Option α) where
  reprPrec
    | some v, _ => s!"(some {repr v})"
    | none, _ => "none"

instance : Repr Frame where
  reprPrec f _ := s!"Frame(opc={f.header.opcode}, len={f.payload.size}, masked={f.header.masked})"

-- Provide BEq instances needed by tests comparing ByteArrays and Frames.
instance : BEq ByteArray where
  beq a b := a.data == b.data

instance : BEq FrameHeader where
  beq a b := a.fin == b.fin && a.rsv1 == b.rsv1 && a.rsv2 == b.rsv2 &&
    a.rsv3 == b.rsv3 && a.opcode == b.opcode && a.masked == b.masked && a.payloadLen == b.payloadLen

instance : BEq Frame where
  beq a b := a.header == b.header && a.maskingKey? == b.maskingKey? && a.payload.data == b.payload.data

/-- Internal sanity list to ensure constructors are recognized by compiler (can be removed later). -/
def _protocolViolationConstructors : List ProtocolViolation := [
  ProtocolViolation.controlFragmented,
  ProtocolViolation.controlTooLong,
  ProtocolViolation.unexpectedContinuation,
  ProtocolViolation.reservedBitsSet,
  ProtocolViolation.invalidOpcode,
  ProtocolViolation.textInvalidUTF8,
  ProtocolViolation.invalidClosePayload,
  ProtocolViolation.oversizedMessage,
  ProtocolViolation.fragmentSequenceError
]

end WebSocket

-- Re-export constructors at top level for simpler qualification when importing WebSocket.Core.Types
notation "WS_ProtViolation_textInvalidUTF8" => WebSocket.ProtocolViolation.textInvalidUTF8
notation "WS_ProtViolation_unexpectedContinuation" => WebSocket.ProtocolViolation.unexpectedContinuation
