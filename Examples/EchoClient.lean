/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Log
open WebSocket

/-- Placeholder client that would connect to a WebSocket endpoint.
Currently only demonstrates frame encode/decode roundtrip locally.
-/

def demoRoundtrip : IO Unit := do
  -- Build a small text payload and mask it (simulating a client-to-server frame).
  let payload := ByteArray.mk #[UInt8.ofNat 'H'.toNat, UInt8.ofNat 'i'.toNat]
  let key : MaskingKey := { b0:=0x01, b1:=0x02, b2:=0x03, b3:=0x04 }
  let frame : Frame := { header := { opcode := .text, masked := true, payloadLen := payload.size }, maskingKey? := some key, payload }
  let encoded := encodeFrame frame
  match decodeFrame encoded with
  | some res =>
      let decoded := res.frame.payload
      let asString := (String.fromUTF8? decoded).getD "<invalid utf8>"
      WebSocket.log .info s!"Decoded frame: opcode={res.frame.header.opcode}, len={decoded.size}, text=\"{asString}\""
  | none => WebSocket.log .error "Decode failed"

def main : IO Unit := demoRoundtrip
