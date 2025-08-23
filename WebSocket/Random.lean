import WebSocket.Core.Types
import WebSocket.Crypto.Base64
open IO

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

@[extern "ws_random_bytes"]
private opaque randomBytesImpl (n : UInt32) : IO ByteArray

/-- Cryptographically secure random masking key (falls back to deterministic if randomness fails). -/
def randomMaskingKeyIO : IO MaskingKey := do
  try
    let bs ← randomBytesImpl 4
    if bs.size = 4 then
      pure { b0 := bs.get! 0, b1 := bs.get! 1, b2 := bs.get! 2, b3 := bs.get! 3 }
    else
      pure { b0 := 0, b1 := 0, b2 := 0, b3 := 0 }
  catch _ =>
    -- fallback deterministic
    let (_, k) := RNG.maskingKey { state := 0x12345678 }
    pure k

/-- Deterministic (legacy) masking key kept for compatibility / tests needing determinism. -/
def randomMaskingKey (seed : Nat) : MaskingKey :=
  let seed32 : UInt32 := UInt32.ofNat (seed &&& 0xFFFFFFFF)
  let (_, k) := RNG.maskingKey { state := seed32 }
  k

/-- Secure random base64 string of length 24 (16 raw bytes) for Sec-WebSocket-Key. -/
def secureWebSocketKey : IO String := do
  try
    let bs ← randomBytesImpl 16
    pure (WebSocket.Crypto.base64Encode bs)
  catch _ =>
    -- fallback: deterministic 16 bytes
    let arr : Array UInt8 := (List.range 16 |>.map (fun i => UInt8.ofNat i)).toArray
    let seed := ByteArray.mk arr
    pure (WebSocket.Crypto.base64Encode seed)

end WebSocket
