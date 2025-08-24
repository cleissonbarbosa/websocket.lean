/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
open WebSocket

namespace WebSocket.Tests.InvalidOpcode

/-- Craft a frame with invalid opcode 0x3 (reserved) to trigger .invalidOpcode violation. -/
def mkInvalidOpcodeBytes : ByteArray := Id.run do
  -- FIN=1, RSV=0, opcode=0x3 (not defined), no mask, payload len=0
  let mut b := ByteArray.empty
  b := b.push 0x83 -- 1000 0011: FIN + opcode=3
  b := b.push 0x00 -- no mask, length 0
  b

def run : IO Unit := do
  -- Build a dummy connection with a transport that captures sends
  let sentRef ← IO.mkRef ([] : List ByteArray)
  let dummyTransport : Transport := {
    recv := pure mkInvalidOpcodeBytes,
    send := fun ba => do
      sentRef.modify (fun acc => ba :: acc),
    closed := pure false,
    close := pure ()
  }
  let conn : Conn := { transport := dummyTransport, assembler := {}, pingState := {} }
  let (_conn', events) ← handleIncoming conn mkInvalidOpcodeBytes
  if events.length ≠ 0 then
    panic! "Expected no events for invalid opcode"
  let sent ← sentRef.get
  if sent.isEmpty then
    panic! "Expected a close frame to be sent on invalid opcode"
  IO.println "Invalid opcode violation test passed"

end WebSocket.Tests.InvalidOpcode
