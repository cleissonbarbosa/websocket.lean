import WebSocket

namespace WebSocket.Tests

/-- Common helpers for test modules. -/
def mkPayload (n : Nat) : ByteArray := Id.run do
  let mut b := ByteArray.empty
  for i in [:n] do
    b := b.push (UInt8.ofNat (i % 256))
  b

end WebSocket.Tests
