/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket.Crypto

private def alphabet : Array Char :=
  Array.mk <| ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toList)

def base64Encode (bs : ByteArray) : String := Id.run do
  let fullGroups := bs.size / 3
  let rem := bs.size % 3
  let mut out := ""
  for g in [:fullGroups] do
    let i := g*3
    let b0 := bs.get! i
    let b1 := bs.get! (i+1)
    let b2 := bs.get! (i+2)
    let n : Nat := (b0.toNat <<< 16) ||| (b1.toNat <<< 8) ||| b2.toNat
    out := out.push (alphabet[((n >>> 18) &&& 0x3F)]!)
    out := out.push (alphabet[((n >>> 12) &&& 0x3F)]!)
    out := out.push (alphabet[((n >>> 6) &&& 0x3F)]!)
    out := out.push (alphabet[(n &&& 0x3F)]!)
  if rem = 1 then
    let b0 := bs.get! (bs.size-1)
    let n := b0.toNat
    let c0 := alphabet[(n >>> 2) &&& 0x3F]!
    let c1 := alphabet[(n <<< 4) &&& 0x3F]!
    out := out.push c0 |>.push c1 |>.push '=' |>.push '='
  else if rem = 2 then
    let b0 := bs.get! (bs.size-2); let b1 := bs.get! (bs.size-1)
    let n := (b0.toNat <<< 8) ||| b1.toNat
    let c0 := alphabet[(n >>> 10) &&& 0x3F]!
    let c1 := alphabet[(n >>> 4) &&& 0x3F]!
    let c2 := alphabet[(n <<< 2) &&& 0x3F]!
    out := out.push c0 |>.push c1 |>.push c2 |>.push '='
  out

end WebSocket.Crypto
