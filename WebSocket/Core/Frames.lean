import WebSocket.Core.Types

namespace WebSocket

namespace MaskingKey
  def xor (a b : UInt8) : UInt8 := UInt8.ofNat (Nat.land (Nat.xor a.toNat b.toNat) 0xFF)
  def applyByte (k : MaskingKey) (i : Nat) (b : UInt8) : UInt8 :=
    let key := match i % 4 with
      | 0 => k.b0 | 1 => k.b1 | 2 => k.b2 | _ => k.b3
    xor b key
  def apply (k : MaskingKey) (data : ByteArray) : ByteArray := Id.run do
    let mut out := ByteArray.empty
    for i in [:data.size] do out := out.push (k.applyByte i (data.get! i))
    out
  axiom apply_involutive (k : MaskingKey) (data : ByteArray) : k.apply (k.apply data) = data
end MaskingKey

def validateFrame (f : Frame) : Option ProtocolViolation :=
  let h := f.header
  if h.rsv1 || h.rsv2 || h.rsv3 then
    some .reservedBitsSet
  else if h.opcode.isControl then
    if ¬ h.fin then some .controlFragmented
    else if h.payloadLen > 125 then some .controlTooLong
    else none
  else none

def encodeFrame (f : Frame) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let b0 : UInt8 :=
      (if f.header.fin then 0x80 else 0) |||
      (if f.header.rsv1 then 0x40 else 0) |||
      (if f.header.rsv2 then 0x20 else 0) |||
      (if f.header.rsv3 then 0x10 else 0) |||
      f.header.opcode.toNat
  out := out.push b0
  let maskBit : UInt8 := if f.header.masked then 0x80 else 0
  let len := f.payload.size
  if len < 126 then
    out := out.push (maskBit ||| (UInt8.ofNat len))
  else if len < 65536 then
    out := out.push (maskBit ||| 126)
    out := out.push (UInt8.ofNat ((len >>> 8) &&& 0xFF))
    out := out.push (UInt8.ofNat (len &&& 0xFF))
  else
    out := out.push (maskBit ||| 127)
    for shift in [56,48,40,32,24,16,8,0] do
      out := out.push (UInt8.ofNat ((len >>> shift) &&& 0xFF))
  let maskedPayload := match f.maskingKey? with
    | some k => if f.header.masked then k.apply f.payload else f.payload
    | none => f.payload
  match f.maskingKey? with
  | some k => out := out.push k.b0; out := out.push k.b1; out := out.push k.b2; out := out.push k.b3
  | none => ()
  out ++ maskedPayload

structure ParseResult where
  frame : Frame
  rest : ByteArray

partial def decodeFrame (buf : ByteArray) : Option ParseResult := Id.run do
  if buf.size < 2 then return none
  let b0 := buf.get! 0; let b1 := buf.get! 1
  let fin := (b0 &&& 0x80) != 0
  let opcodeVal := b0 &&& 0x0F
  let opcode? := match opcodeVal.toNat with
  | 0 => some OpCode.continuation | 1 => some .text | 2 => some .binary
  | 8 => some .close | 9 => some .ping | 10 => some .pong | _ => none
  let some opcode := opcode? | return none
  let masked := (b1 &&& 0x80) != 0
  let len7 := (b1 &&& 0x7F).toNat
  let mut idx := 2
  let (payloadLen?, idx') :=
    if len7 < 126 then (some len7, idx)
    else if len7 = 126 then
      if buf.size < idx + 2 then (none, idx) else
      let hi := buf.get! idx; let lo := buf.get! (idx+1)
      (some ((hi.toNat <<< 8) + lo.toNat), idx + 2)
    else
      if buf.size < idx + 8 then (none, idx) else
      let acc : Nat :=
        (((buf.get! (idx)).toNat      ) <<< 56) +
        (((buf.get! (idx+1)).toNat) <<< 48) +
        (((buf.get! (idx+2)).toNat) <<< 40) +
        (((buf.get! (idx+3)).toNat) <<< 32) +
        (((buf.get! (idx+4)).toNat) <<< 24) +
        (((buf.get! (idx+5)).toNat) <<< 16) +
        (((buf.get! (idx+6)).toNat) <<< 8)  +
        ((buf.get! (idx+7)).toNat)
      (some acc, idx + 8)
  let some payloadLen := payloadLen? | return none
  idx := idx'
  let (maskingKey?, idx'') := if masked then
    if buf.size < idx + 4 then (none, idx) else
      (some { b0 := buf.get! idx, b1 := buf.get! (idx+1), b2 := buf.get! (idx+2), b3 := buf.get! (idx+3) }, idx + 4)
    else (none, idx)
  idx := idx''
  if buf.size < idx + payloadLen then return none
  let slice := buf.extract idx (idx + payloadLen)
  let payload := match maskingKey? with | some k => k.apply slice | none => slice
  let header : FrameHeader := { fin := fin, opcode := opcode, masked := masked, payloadLen := payloadLen }
  let frame : Frame := { header := header, maskingKey? := maskingKey?, payload := payload }
  let rest := buf.extract (idx + payloadLen) buf.size
  some { frame := frame, rest := rest }

end WebSocket
