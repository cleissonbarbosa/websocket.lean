import WebSocket
import WebSocket.Tests.Util
open WebSocket Tests

namespace WebSocket.Tests.Fragmentation

def testFragmentation : IO Unit := do
  let part1Payload := ByteArray.mk "Hel".toUTF8.data
  let part2Payload := ByteArray.mk "lo".toUTF8.data
  let f1 : Frame := { header := { opcode := .text, masked := false, payloadLen := part1Payload.size, fin := false }, payload := part1Payload }
  let f2 : Frame := { header := { opcode := .continuation, masked := false, payloadLen := part2Payload.size, fin := true }, payload := part2Payload }
  let st0 : WebSocket.AssemblerState := {}
  match WebSocket.processFrame st0 f1 with
  | .continue st1 =>
      match WebSocket.processFrame st1 f2 with
      | .message opc data _ =>
          if opc ≠ .text || data != part1Payload ++ part2Payload then throw <| IO.userError "Fragment reassembly failed"
      | _ => throw <| IO.userError "Second frame did not produce message"
  | _ => throw <| IO.userError "First frame not buffered"

def testOversizedMessage : IO Unit := do
  let st : WebSocket.AssemblerState := { maxMessageSize? := some 5 }
  let payload := ByteArray.mk "123456".toUTF8.data
  let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size, fin := true }, payload := payload }
  match WebSocket.processFrame st f with
  | .violation .oversizedMessage => IO.println "Oversized message test passed"
  | _ => throw <| IO.userError "Expected oversizedMessage"

def testFragmentSequenceError : IO Unit := do
  let part1 := ByteArray.mk "Hello".toUTF8.data
  let f1 : Frame := { header := { opcode := .text, masked := false, payloadLen := part1.size, fin := false }, payload := part1 }
  let st0 : WebSocket.AssemblerState := {}
  let st1 := match WebSocket.processFrame st0 f1 with
    | .continue st' => st'
    | _ => panic! "Expected continue"
  let f2 : Frame := { header := { opcode := .binary, masked := false, payloadLen := 1, fin := true }, payload := ByteArray.mk #[0x00] }
  match WebSocket.processFrame st1 f2 with
  | .violation .fragmentSequenceError => IO.println "Fragment sequence error test passed"
  | _ => throw <| IO.userError "Expected fragmentSequenceError"

def testUnexpectedContinuation : IO Unit := do
  let contPayload := ByteArray.mk "more".toUTF8.data
  let contFrame : Frame := { header := { opcode := .continuation, masked := false, payloadLen := contPayload.size, fin := true }, payload := contPayload }
  match WebSocket.processFrame {} contFrame with
  | .violation .unexpectedContinuation => IO.println "Unexpected continuation test passed"
  | _ => throw <| IO.userError "Expected unexpectedContinuation"

def run : IO Unit := do
  testFragmentation; testOversizedMessage; testFragmentSequenceError; testUnexpectedContinuation

end WebSocket.Tests.Fragmentation
