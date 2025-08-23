import WebSocket
open WebSocket

/-- Placeholder client that would connect to a WebSocket endpoint.
Currently only demonstrates frame encode/decode roundtrip locally.
-/

def demoRoundtrip : IO Unit := do
  let payload := ByteArray.mk #[UInt8.ofNat 'H'.toNat, 'i'.toNat]
  let frame : Frame := { header := { opcode := .text, masked := true, payloadLen := payload.size }, maskingKey? := some { b0:=0x01, b1:=0x02, b2:=0x03, b3:=0x04}, payload }
  let encoded := encodeFrame .client frame
  match decodeFrame .server encoded with
  | some res => IO.println s!"Decoded frame payload size = {res.frame.payload.size}"
  | none => IO.println "Decode failed"

def main : IO Unit := demoRoundtrip
