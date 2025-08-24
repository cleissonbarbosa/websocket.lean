/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
open WebSocket

namespace WebSocket.Tests.Crypto

def testSHA1Vector : IO Unit := do
  -- SHA1("abc") = A9993E364706816ABA3E25717850C26C9CD0D89D
  let bytes := ByteArray.mk ("abc".toUTF8.data.map (fun c => UInt8.ofNat c.toNat))
  let digest := WebSocket.Crypto.SHA1 bytes
  let toHexChar (n : Nat) : Char :=
    let v := n % 16
    Char.ofNat (if v < 10 then 48 + v else 55 + v)
  let hex := String.join <| (List.range digest.size).map (fun i =>
    let b := (digest.get! i).toNat
    let hi := toHexChar (b >>> 4)
    let lo := toHexChar (b &&& 0xF)
    String.mk [hi, lo])
  if hex.toUpper != "A9993E364706816ABA3E25717850C26C9CD0D89D" then
    throw <| IO.userError s!"SHA1 test vector failed got {hex}"
  else IO.println "SHA1 test vector passed"

def run : IO Unit := do
  testSHA1Vector

end WebSocket.Tests.Crypto
