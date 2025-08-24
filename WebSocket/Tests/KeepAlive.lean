/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
open WebSocket

namespace WebSocket.Tests.KeepAlive

def testPingScheduler : IO Unit := do
  let ps : WebSocket.PingState := { lastPing := 0, lastPong := 0, interval := 10, strategy := .pingPong 10 3 }
  if WebSocket.duePing 5 ps then throw <| IO.userError "Ping too early" else pure ()
  if ¬ WebSocket.duePing 10 ps then throw <| IO.userError "Ping should be due" else pure ()

def testAutoPong : IO Unit := do
  let payload := ByteArray.mk "hi".toUTF8.data
  let pingFrame : Frame := { header := { opcode := .ping, masked := false, payloadLen := payload.size }, payload := payload }
  let bytes := encodeFrame pingFrame
  let dummyTransport : Transport := { recv := pure ByteArray.empty, send := fun _ => pure () }
  let conn : Conn := { transport := dummyTransport, assembler := {}, pingState := {} }
  let (_, events) ← WebSocket.handleIncoming conn bytes
  if events.any (fun (opc,_) => opc = .pong) then
    IO.println "AutoPong test (logical) passed"
  else
    throw <| IO.userError "Expected pong event in returned list"

def testKeepAliveEnhanced : IO Unit := do
  let ps : WebSocket.PingState := { lastPing := 0, lastPong := 0, interval := 10, maxMissedPongs := 2, missedPongs := 0, strategy := .pingPong 10 2 }
  if WebSocket.connectionDead ps then throw <| IO.userError "Connection should not be dead initially"
  let ps1 := WebSocket.registerPing 10 ps
  if ps1.missedPongs ≠ 1 then throw <| IO.userError "Should have 1 missed pong after ping"
  let ps2 := WebSocket.registerPing 20 ps1
  if ps2.missedPongs ≠ 2 then throw <| IO.userError "Should have 2 missed pongs"
  let ps3 := WebSocket.registerPing 30 ps2
  if ¬ WebSocket.connectionDead ps3 then throw <| IO.userError "Connection should be considered dead"
  let ps4 := WebSocket.registerPong 35 ps2
  if ps4.missedPongs ≠ 0 then throw <| IO.userError "Pong should reset missed count"
  IO.println "Enhanced keepalive test passed"

def run : IO Unit := do
  testPingScheduler; testAutoPong; testKeepAliveEnhanced

end WebSocket.Tests.KeepAlive
