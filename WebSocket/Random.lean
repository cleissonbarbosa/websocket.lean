import WebSocket.Core.Types

namespace WebSocket

/-- Simple deterministic pseudo-random generator (xorshift32) for masking keys. Not cryptographic. -/
structure RNG where state : UInt32

namespace RNG
  def next (r : RNG) : RNG × UInt32 :=
    let x0 := r.state
    let x1 := x0 ^^^ (x0 <<< 13)
    let x2 := x1 ^^^ (x1 >>> 17)
    let x3 := x2 ^^^ (x2 <<< 5)
    ({ state := x3 }, x3)
  def maskingKey (r : RNG) : RNG × MaskingKey :=
    let (r1, a) := r.next
    let (r2, b) := r1.next
    let (r3, c) := r2.next
    let (r4, d) := r3.next
    let mk (w : UInt32) : UInt8 := UInt8.ofNat (w.toNat &&& 0xFF)
    (r4, { b0 := mk a, b1 := mk b, b2 := mk c, b3 := mk d })
end RNG

def randomMaskingKey (seed : Nat) : MaskingKey :=
  let seed32 : UInt32 := UInt32.ofNat (seed &&& 0xFFFFFFFF)
  let (_, k) := RNG.maskingKey { state := seed32 }
  k

end WebSocket
