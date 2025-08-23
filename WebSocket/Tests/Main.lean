import WebSocket
open WebSocket

/-- Basic tests (manual; in real Lean project use a test harness or `lake exe`). -/

def testMasking : IO Unit := do
  let key : MaskingKey := { b0:=0x11, b1:=0x22, b2:=0x33, b3:=0x44 }
  let payload := ByteArray.mk #[0x00,0xFF,0x10,0x20,0x30,0x40]
  let masked := key.apply payload
  let unmasked := key.apply masked
  if unmasked != payload then
    throw <| IO.userError "Masking involution failed"
  else
    IO.println "Masking test passed"

def testEncodeDecode : IO Unit := do
  let payload := ByteArray.mk #[UInt8.ofNat (Char.toNat 'O'), UInt8.ofNat (Char.toNat 'K')]
  let frame : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload != payload then throw <| IO.userError "Payload mismatch" else
      IO.println "Encode/Decode test passed"
  | none => throw <| IO.userError "Decode failed"

-- Handshake test (logic only)
def testHandshake : IO Unit := do
  let req : HandshakeRequest := {
    method := "GET", resource := "/chat",
    headers := [
      ("Host","example.com"), ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Key","dGhlIHNhbXBsZSBub25jZQ==")
    ] }
  match upgrade req with
  | some resp =>
      -- RFC 6455 example expected accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
      let expected := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      let got? := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Accept" then some v else none)
      match got? with
      | some v =>
          if v = expected then
            IO.println s!"Handshake status {resp.status} (accept OK)"
          else throw <| IO.userError s!"Accept mismatch expected {expected} got {v}"
      | none => throw <| IO.userError "Missing Sec-WebSocket-Accept"
  | none => throw <| IO.userError "Handshake failed"

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
  if hex.toUpper != "A9993E364706816ABA3E25717850C26C9CD0D89D" then -- expected 40 hex chars
    throw <| IO.userError s!"SHA1 test vector failed got {hex}"
  else IO.println "SHA1 test vector passed"

/-! Additional tests below (placed before main so they are in scope). -/

def mkPayload (n : Nat) : ByteArray := Id.run do
  let mut b := ByteArray.empty
  for i in [:n] do
    b := b.push (UInt8.ofNat (i % 256))
  b

def testMaskedRoundtrip : IO Unit := do
  let payload := mkPayload 50
  let key : MaskingKey := { b0 := 0xAA, b1 := 0xBB, b2 := 0xCC, b3 := 0xDD }
  let frame : Frame := { header := { opcode := .binary, masked := true, payloadLen := payload.size }, maskingKey? := some key, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload != payload then throw <| IO.userError "Masked roundtrip payload mismatch"
      else IO.println "Masked roundtrip test passed"
  | none => throw <| IO.userError "Masked roundtrip decode failed"

def testOneLength (n : Nat) : IO Unit := do
  let payload := mkPayload n
  let frame : Frame := { header := { opcode := .binary, masked := false, payloadLen := n }, payload }
  let bytes := encodeFrame frame
  match decodeFrame bytes with
  | some r =>
      if r.frame.payload.size != n then throw <| IO.userError s!"Length mismatch {n}" else pure ()
  | none => throw <| IO.userError s!"Extended length decode failed {n}"

def testExtendedLengths : IO Unit := do
  -- trigger single-byte length (<126)
  testOneLength 125
  -- trigger 16-bit extended (==126 and near upper bound)
  testOneLength 126
  testOneLength 65535
  -- trigger 64-bit extended (>= 65536)
  testOneLength 65536
  IO.println "Extended length tests passed"

def testControlValidation : IO Unit := do
  let payload := mkPayload 5
  let ping : Frame := { header := { opcode := .ping, masked := false, payloadLen := payload.size }, payload }
  match WebSocket.validateFrame ping with
  | some v => throw <| IO.userError s!"Unexpected violation {v}"
  | none => pure ()
  let badHeader := { ping.header with fin := false }
  let badFrame : Frame := { ping with header := badHeader }
  match WebSocket.validateFrame badFrame with
  | some .controlFragmented => pure ()
  | _ => throw <| IO.userError "Expected controlFragmented"
  let bigPayload := mkPayload 126
  let bigPing : Frame := { header := { opcode := .ping, masked := false, payloadLen := bigPayload.size }, payload := bigPayload }
  match WebSocket.validateFrame bigPing with
  | some .controlTooLong => IO.println "Control validation test passed"
  | _ => throw <| IO.userError "Expected controlTooLong"

def testUpgradeRaw : IO Unit := do
  let raw := "GET /chat HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
  match WebSocket.upgradeRaw raw with
  | some resp =>
      let expected := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      let got? := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Accept" then some v else none)
      match got? with
      | some v => if v = expected then IO.println "upgradeRaw test passed" else throw <| IO.userError "upgradeRaw accept mismatch"
      | none => throw <| IO.userError "upgradeRaw missing accept"
  | none => throw <| IO.userError "upgradeRaw failed"

def testUpgradeErrors : IO Unit := do
  let base : HandshakeRequest := { method := "GET", resource := "/", headers := [] }
  if (WebSocket.upgradeE base).isOk then throw <| IO.userError "Expected missingHost" else pure ()
  let withHost := { base with headers := [("Host","x")] }
  if (WebSocket.upgradeE withHost).isOk then throw <| IO.userError "Expected missingUpgrade" else pure ()
  let withUp := { withHost with headers := withHost.headers ++ [("Upgrade","websocket")] }
  if (WebSocket.upgradeE withUp).isOk then throw <| IO.userError "Expected missingConnection" else pure ()
  let withConn := { withUp with headers := withUp.headers ++ [("Connection","close")] }
  if (WebSocket.upgradeE withConn).isOk then throw <| IO.userError "Expected connectionNotUpgrade" else pure ()

def testCloseFrames : IO Unit := do
  let f := WebSocket.buildCloseFrame .normalClosure "bye"
  let parsed := WebSocket.parseClosePayload f.payload
  match parsed with
  | some info =>
      if info.code ≠ some .normalClosure then throw <| IO.userError "Close code mismatch"
  | none => throw <| IO.userError "Failed to parse close payload"

def testFragmentation : IO Unit := do
  -- Simulate sending a text message split into 2 frames
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

def testPingScheduler : IO Unit := do
  let ps : WebSocket.PingState := { lastPing := 0, lastPong := 0, interval := 10 }
  if WebSocket.duePing 5 ps then throw <| IO.userError "Ping too early" else pure ()
  if ¬ WebSocket.duePing 10 ps then throw <| IO.userError "Ping should be due" else pure ()

def testViolationClose : IO Unit := do
  let f := WebSocket.closeFrameForViolation .controlTooLong
  if f.header.opcode ≠ .close then throw <| IO.userError "Expected close opcode"
  match WebSocket.parseClosePayload f.payload with
  | some info =>
      if info.code ≠ some .protocolError then throw <| IO.userError "Violation close code mismatch"
  | none => throw <| IO.userError "Failed to parse violation close frame"

def main : IO Unit := do
  testMasking; testEncodeDecode; testHandshake; testSHA1Vector
  testMaskedRoundtrip; testExtendedLengths; testControlValidation
  testUpgradeRaw; testUpgradeErrors; testCloseFrames; testFragmentation; testPingScheduler
  testViolationClose
  IO.println "All tests done"
