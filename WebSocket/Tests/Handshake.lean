import WebSocket
open WebSocket

namespace WebSocket.Tests.Handshake

def testHandshake : IO Unit := do
  let req : HandshakeRequest := {
    method := "GET", resource := "/chat",
    headers := [
      ("Host","example.com"), ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Key","dGhlIHNhbXBsZSBub25jZQ==")
    ] }
  match upgrade req with
  | some resp =>
      let expected := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      let got? := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Accept" then some v else none)
      match got? with
      | some v =>
          if v = expected then
            IO.println s!"Handshake status {resp.status} (accept OK)"
          else throw <| IO.userError s!"Accept mismatch expected {expected} got {v}"
      | none => throw <| IO.userError "Missing Sec-WebSocket-Accept"
  | none => throw <| IO.userError "Handshake failed"

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

def testSubprotocolNegotiation : IO Unit := do
  let req : HandshakeRequest := {
    method := "GET", resource := "/", headers := [
      ("Host","ex"),("Upgrade","websocket"),("Connection","Upgrade"),("Sec-WebSocket-Key","dGhlIHNhbXBsZSBub25jZQ=="),
      ("Sec-WebSocket-Protocol","chat, superchat")
    ] }
  match WebSocket.upgrade req with
  | some resp =>
      let chosen? := resp.headers.findSome? (fun (k,v) => if k = "Sec-WebSocket-Protocol" then some v else none)
      match chosen? with
      | some proto => if proto = "chat" then IO.println "Subprotocol negotiation passed" else throw <| IO.userError s!"Unexpected subprotocol {proto}"
      | none => throw <| IO.userError "Missing Sec-WebSocket-Protocol in response"
  | none => throw <| IO.userError "Upgrade failed in subprotocol test"

def testUpgradeErrors : IO Unit := do
  let base : HandshakeRequest := { method := "GET", resource := "/", headers := [] }
  if (WebSocket.upgradeE base).isOk then throw <| IO.userError "Expected missingHost" else pure ()
  let withHost := { base with headers := [("Host","x")] }
  if (WebSocket.upgradeE withHost).isOk then throw <| IO.userError "Expected missingUpgrade" else pure ()
  let withUp := { withHost with headers := withHost.headers ++ [("Upgrade","websocket")] }
  if (WebSocket.upgradeE withUp).isOk then throw <| IO.userError "Expected missingConnection" else pure ()
  let withConn := { withUp with headers := withUp.headers ++ [("Connection","close")] }
  if (WebSocket.upgradeE withConn).isOk then throw <| IO.userError "Expected connectionNotUpgrade" else pure ()

def run : IO Unit := do
  testHandshake; testUpgradeRaw; testSubprotocolNegotiation; testUpgradeErrors

end WebSocket.Tests.Handshake
