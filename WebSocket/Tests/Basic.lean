import WebSocket
import WebSocket.Tests.Util
open WebSocket Tests

namespace WebSocket.Tests.Basic

def testMasking : IO Unit := do
  let key : MaskingKey := { b0:=0x11, b1:=0x22, b2:=0x33, b3:=0x44 }
  let payload := ByteArray.mk #[0x00,0xFF,0x10,0x20,0x30,0x40]
  let masked := key.apply payload
  let unmasked := key.apply masked
  if unmasked != payload then
    throw <| IO.userError "Masking involution failed"
  else
    IO.println "Masking test passed"

def testEncodeDecode : IO Unit := do
  let payload := ByteArray.mk #[UInt8.ofNat (Char.toNat 'O'), UInt8.ofNat (Char.toNat 'K')]
  let frame : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload != payload then throw <| IO.userError "Payload mismatch" else
      IO.println "Encode/Decode test passed"
  | none => throw <| IO.userError "Decode failed"

def run : IO Unit := do
  testMasking; testEncodeDecode

  -- Test violation -> close code mapping
  let mappingExpect : List (ProtocolViolation × CloseCode) := [
    (ProtocolViolation.textInvalidUTF8, CloseCode.invalidPayload),
    (ProtocolViolation.oversizedMessage, CloseCode.messageTooBig),
    (ProtocolViolation.controlTooLong, CloseCode.protocolError),
    (ProtocolViolation.reservedBitsSet, CloseCode.protocolError)
  ]
  for (v, cc) in mappingExpect do
    if violationCloseCode v ≠ cc then
      panic! s!"Mapping mismatch for {v}: expected code {(CloseCode.toNat cc)}, got {(CloseCode.toNat (violationCloseCode v))}"
  IO.println "Violation→CloseCode mapping test passed"
  -- (Placeholder) Networking smoke: ensure TcpTransport .toTransport compiles & step function linkable.
  -- Full integration tests would require spawning a socket; omitted here for determinism.

end WebSocket.Tests.Basic
