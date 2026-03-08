/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Tests.Util
open WebSocket Tests

namespace WebSocket.Tests.Frames

def testMaskedRoundtrip : IO Unit := do
  let payload := mkPayload 50
  let key : MaskingKey := { b0 := 0xAA, b1 := 0xBB, b2 := 0xCC, b3 := 0xDD }
  let frame : Frame := { header := { opcode := .binary, masked := true, payloadLen := payload.size }, maskingKey? := some key, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload != payload then throw <| IO.userError "Masked roundtrip payload mismatch"
      else IO.println "Masked roundtrip test passed"
  | none => throw <| IO.userError "Masked roundtrip decode failed"

private def testOneLength (n : Nat) : IO Unit := do
  let payload := mkPayload n
  let frame : Frame := { header := { opcode := .binary, masked := false, payloadLen := n }, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload.size != n then throw <| IO.userError s!"Length mismatch {n}" else pure ()
  | none => throw <| IO.userError s!"Extended length decode failed {n}"

def testExtendedLengths : IO Unit := do
  testOneLength 125; testOneLength 126; testOneLength 65535; testOneLength 65536
  IO.println "Extended length tests passed"

def testControlValidation : IO Unit := do
  let payload := mkPayload 5
  let ping : Frame := { header := { opcode := .ping, masked := false, payloadLen := payload.size }, payload }
  match WebSocket.validateFrame ping with
  | some v => throw <| IO.userError s!"Unexpected violation {v}"
  | none => pure ()
  let badHeader := { ping.header with fin := false }
  let badFrame : Frame := { ping with header := badHeader }
  match WebSocket.validateFrame badFrame with
  | some .controlFragmented => pure ()
  | _ => throw <| IO.userError "Expected controlFragmented"
  let bigPayload := mkPayload 126
  let bigPing : Frame := { header := { opcode := .ping, masked := false, payloadLen := bigPayload.size }, payload := bigPayload }
  match WebSocket.validateFrame bigPing with
  | some .controlTooLong => IO.println "Control validation test passed"
  | _ => throw <| IO.userError "Expected controlTooLong"
  let rsvHeader := { ping.header with rsv1 := true }
  let rsvFrame : Frame := { ping with header := rsvHeader }
  match WebSocket.validateFrame rsvFrame with
  | some .reservedBitsSet => IO.println "Reserved bits validation passed"
  | other => throw <| IO.userError s!"Expected reservedBitsSet got {other}"

def testCloseFrames : IO Unit := do
  let f := WebSocket.buildCloseFrame .normalClosure "bye"
  let parsed := WebSocket.parseClosePayload f.payload
  match parsed with
  | some info =>
      if info.code ≠ some .normalClosure then throw <| IO.userError "Close code mismatch"
  | none => throw <| IO.userError "Failed to parse close payload"

def testViolationClose : IO Unit := do
  let f := WebSocket.closeFrameForViolation .controlTooLong
  if f.header.opcode ≠ .close then throw <| IO.userError "Expected close opcode"
  match WebSocket.parseClosePayload f.payload with
  | some info =>
      if info.code ≠ some .protocolError then throw <| IO.userError "Violation close code mismatch"
  | none => throw <| IO.userError "Failed to parse violation close frame"

def testInvalidClosePayload : IO Unit := do
  let invalidUTF8 := ByteArray.mk #[0x03, 0xE8, 0xFF, 0xFE]
  match WebSocket.parseClosePayload invalidUTF8 with
  | none => IO.println "Invalid close payload test passed"
  | some _ => throw <| IO.userError "Expected none for invalid UTF-8 in close reason"

private def mkChunkedTransport (chunks : List ByteArray) : IO Transport := do
  let ref ← IO.mkRef chunks
  pure {
    recv := do
      let current ← ref.get
      match current with
      | [] => pure ByteArray.empty
      | chunk :: rest =>
          ref.set rest
          pure chunk
    send := fun _ => pure ()
  }

def testStepIOMultipleFrames : IO Unit := do
  let frame1 := encodeFrame (WebSocket.makeTextFrame "one")
  let frame2 := encodeFrame (WebSocket.makeTextFrame "two")
  let transport ← mkChunkedTransport [frame1 ++ frame2]
  let conn : Conn := { transport := transport, assembler := {}, pingState := {} }
  let (state, events) ← WebSocket.stepIO { conn := conn }
  if state.buffer.size ≠ 0 then
    throw <| IO.userError "Expected empty buffer after decoding complete frames"
  match events with
  | [(.text, p1), (.text, p2)] =>
      if String.fromUTF8! p1 ≠ "one" || String.fromUTF8! p2 ≠ "two" then
        throw <| IO.userError "Unexpected payload order for multiple frames"
      IO.println "Multiple frames single-read test passed"
  | _ => throw <| IO.userError "Expected two text events from a single read"

def testStepIOPartialFrameAcrossReads : IO Unit := do
  let frame := encodeFrame (WebSocket.makeTextFrame "partial")
  let split := frame.size / 2
  let head := frame.extract 0 split
  let tail := frame.extract split frame.size
  let transport ← mkChunkedTransport [head, tail]
  let conn : Conn := { transport := transport, assembler := {}, pingState := {} }
  let (state1, events1) ← WebSocket.stepIO { conn := conn }
  if !events1.isEmpty then
    throw <| IO.userError "Expected no event for incomplete frame"
  if state1.buffer.size = 0 then
    throw <| IO.userError "Expected partial bytes to remain buffered"
  let (state2, events2) ← WebSocket.stepIO state1
  if state2.buffer.size ≠ 0 then
    throw <| IO.userError "Expected buffer to drain after receiving remaining bytes"
  match events2 with
  | [(.text, payload)] =>
      if String.fromUTF8! payload ≠ "partial" then
        throw <| IO.userError "Unexpected payload after reassembling partial frame"
      IO.println "Partial frame multi-read test passed"
  | _ => throw <| IO.userError "Expected one text event after completing partial frame"

def run : IO Unit := do
  testMaskedRoundtrip
  testExtendedLengths
  testControlValidation
  testCloseFrames
  testViolationClose
  testInvalidClosePayload
  testStepIOMultipleFrames
  testStepIOPartialFrameAcrossReads

end WebSocket.Tests.Frames
