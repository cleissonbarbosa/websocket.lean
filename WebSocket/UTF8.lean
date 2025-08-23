namespace WebSocket

/-- Simple UTF-8 validator (no normalization). Returns true iff the byte sequence is valid UTF-8. -/
def validateUTF8 (ba : ByteArray) : Bool := Id.run do
  let size := ba.size
  let rec loop (i : Nat) : Bool :=
    if i ≥ size then true else
    let b := ba.get! i |>.toNat
    if b < 0x80 then loop (i+1) else
    if b &&& 0xE0 == 0xC0 then
      if i + 1 ≥ size then false else
      let b1 := ba.get! (i+1) |>.toNat
      if (b &&& 0x1E) == 0 || (b1 &&& 0xC0) != 0x80 then false else
      loop (i+2)
    else if b &&& 0xF0 == 0xE0 then
      if i + 2 ≥ size then false else
      let b1 := ba.get! (i+1) |>.toNat; let b2 := ba.get! (i+2) |>.toNat
      if (b1 &&& 0xC0) != 0x80 || (b2 &&& 0xC0) != 0x80 then false else
      let cp := ((b &&& 0x0F) <<< 12) ||| ((b1 &&& 0x3F) <<< 6) ||| (b2 &&& 0x3F)
      if cp < 0x800 || (0xD800 <= cp && cp <= 0xDFFF) then false else loop (i+3)
    else if b &&& 0xF8 == 0xF0 then
      if i + 3 ≥ size then false else
      let b1 := ba.get! (i+1) |>.toNat; let b2 := ba.get! (i+2) |>.toNat; let b3 := ba.get! (i+3) |>.toNat
      if (b1 &&& 0xC0) != 0x80 || (b2 &&& 0xC0) != 0x80 || (b3 &&& 0xC0) != 0x80 then false else
      let cp := ((b &&& 0x07) <<< 18) ||| ((b1 &&& 0x3F) <<< 12) ||| ((b2 &&& 0x3F) <<< 6) ||| (b3 &&& 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF then false else loop (i+4)
    else false
  loop 0

end WebSocket
