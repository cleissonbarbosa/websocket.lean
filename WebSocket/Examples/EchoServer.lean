import WebSocket
import WebSocket.Net
open WebSocket WebSocket.Net

def echoLoop (c : Conn) : IO Unit := do
  let bytes ← c.transport.recv
  if bytes.size = 0 then
    IO.println "[conn] closed"
  else
    let (c', events) ← WebSocket.handleIncoming c bytes
    for (opc,payload) in events do
      if opc = .text then
        let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload := payload }
        c'.transport.send (encodeFrame f)
    echoLoop c'

def main : IO Unit := do
  let lh ← openServer 9001
  IO.println "Listening on 0.0.0.0:9001"
  let rec acceptLoop : IO Unit := do
    match ← acceptAndUpgrade lh with
    | some c =>
        IO.println "Handshake complete"
        (echoLoop c)
        acceptLoop
    | none =>
        IO.println "Handshake failed / timeout"
        acceptLoop
  acceptLoop
