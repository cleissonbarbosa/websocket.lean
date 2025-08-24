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

def run : IO Unit := do
  testMaskedRoundtrip; testExtendedLengths; testControlValidation; testCloseFrames; testViolationClose; testInvalidClosePayload

end WebSocket.Tests.Frames
