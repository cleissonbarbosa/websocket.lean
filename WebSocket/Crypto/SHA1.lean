namespace WebSocket.Crypto

@[inline] private def rotl (x : UInt32) (n : Nat) : UInt32 :=
  let s := n % 32
  if s = 0 then x else
  let v := x.toNat
  let mask32 := 0xFFFFFFFF
  let left := (v <<< s) &&& mask32
    let right := v >>> (32 - s)
  UInt32.ofNat ((left + right) &&& mask32)

private def sha1Pad (msg : ByteArray) : ByteArray := Id.run do
  let bitLen : UInt64 := (UInt64.ofNat msg.size) * 8
  let mut out := msg
  out := out.push 0x80
  while (out.size % 64) ≠ 56 do
    out := out.push 0x00
  for shift in [56,48,40,32,24,16,8,0] do
    let byte := UInt8.ofNat (UInt64.toNat ((bitLen >>> shift) &&& 0xFF))
    out := out.push byte
  out

private def toWord (b0 b1 b2 b3 : UInt8) : UInt32 :=
  (UInt32.ofNat b0.toNat <<< 24) ||| (UInt32.ofNat b1.toNat <<< 16) |||
  (UInt32.ofNat b2.toNat <<< 8) ||| (UInt32.ofNat b3.toNat)

def SHA1 (data : ByteArray) : ByteArray := Id.run do
  let padded := sha1Pad data
  let mut h0 : UInt32 := 0x67452301
  let mut h1 : UInt32 := 0xEFCDAB89
  let mut h2 : UInt32 := 0x98BADCFE
  let mut h3 : UInt32 := 0x10325476
  let mut h4 : UInt32 := 0xC3D2E1F0
  let chunks := padded.size / 64
  for c in [:chunks] do
    let base := c*64
    let mut w : Array UInt32 := Array.mkEmpty 80
    for i in [:16] do
      let j := base + i*4
      w := w.push (toWord (padded.get! j) (padded.get! (j+1)) (padded.get! (j+2)) (padded.get! (j+3)))
    for i in [16:80] do
      let x := w[(i-3)]! ^^^ w[(i-8)]! ^^^ w[(i-14)]! ^^^ w[(i-16)]!
      w := w.push (rotl x 1)
    let mut a := h0; let mut b := h1; let mut c' := h2; let mut d := h3; let mut e := h4
    for i in [:80] do
      let (f,k) :=
        if i < 20 then (((b &&& c') ||| ((~~~ b) &&& d)), 0x5A827999)
        else if i < 40 then (b ^^^ c' ^^^ d, 0x6ED9EBA1)
        else if i < 60 then (((b &&& c') ||| (b &&& d) ||| (c' &&& d)), 0x8F1BBCDC)
        else (b ^^^ c' ^^^ d, 0xCA62C1D6)
      let temp := (rotl a 5) + f + e + k + w[i]!
      e := d; d := c'; c' := rotl b 30; b := a; a := temp
    h0 := h0 + a; h1 := h1 + b; h2 := h2 + c'; h3 := h3 + d; h4 := h4 + e
  let words := #[h0,h1,h2,h3,h4]
  let mut out := ByteArray.empty
  let mut idx := 0
  while _h : idx < words.size do
    let word := words[idx]!
    let wn := word.toNat
    out := out.push (UInt8.ofNat ((wn >>> 24) &&& 0xFF))
    out := out.push (UInt8.ofNat ((wn >>> 16) &&& 0xFF))
    out := out.push (UInt8.ofNat ((wn >>> 8) &&& 0xFF))
    out := out.push (UInt8.ofNat (wn &&& 0xFF))
    idx := idx + 1
  out

end WebSocket.Crypto
