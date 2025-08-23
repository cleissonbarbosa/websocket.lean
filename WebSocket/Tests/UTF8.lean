import WebSocket
open WebSocket

namespace WebSocket.Tests.UTF8

def testInvalidUTF8TextFrame : IO Unit := do
  let badBytes := ByteArray.mk #[0xC0,0xAF] -- overlong '/'
  let fBad : Frame := { header := { opcode := .text, masked := false, payloadLen := badBytes.size }, payload := badBytes }
  match WebSocket.processFrame {} fBad with
  | .violation .textInvalidUTF8 => IO.println "UTF-8 invalid test passed"
  | _ => throw <| IO.userError "Expected textInvalidUTF8"

def run : IO Unit := do
  testInvalidUTF8TextFrame

end WebSocket.Tests.UTF8
