/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Net
import WebSocket.Log
open WebSocket WebSocket.Net

/-- Resultado detalhado da tentativa de aceitação/handshake para decidir quando logar erro. -/
structure AcceptResult where
  conn? : Option Conn
  invalidHandshake : Bool := false

/-- Leitura incremental do handshake HTTP para evitar fechar conexão antes do cliente enviar cabeçalhos. -/
def robustAccept (lh : ListenHandle) (maxWaitMs : Nat := 1000) : IO AcceptResult := do
  -- Tenta aceitar; se não houver conexão pendente (dependendo da implementação C, pode lançar), tratamos como nenhuma.
  let clientFd ← (try pure (some (← acceptImpl lh.fd)) catch _ => pure none)
  match clientFd with
  | none =>
      return { conn? := none }
  | some fd => do
      (try setNonblockingImpl fd catch _ => pure ())
      let deadlineIters := maxWaitMs / 5
      let readLoop (start : ByteArray) : IO ByteArray := do
        let mut acc := start
        let mut i : Nat := 0
        while i < deadlineIters do
          let s := String.fromUTF8! acc
            -- Verifica se já recebemos o terminador de cabeçalhos
          if (s.splitOn "\r\n\r\n").length > 1 then
            return acc
          IO.sleep 5
          let more ← recvImpl fd 4096
          if more.size > 0 then
            acc := acc ++ more
          i := i + 1
        return acc
      let first ← recvImpl fd 4096
      let firstStr := String.fromUTF8! first
      let bytes ← if (firstStr.splitOn "\r\n\r\n").length > 1 then pure first else readLoop first
      if bytes.size = 0 then
        closeImpl fd
        return { conn? := none }
      let reqStr := String.fromUTF8! bytes
      match WebSocket.upgradeRaw reqStr with
      | some resp =>
          let responseText := s!"HTTP/1.1 {resp.status} {resp.reason}\r\n" ++
            String.intercalate "\r\n" (resp.headers.map (fun (k,v) => s!"{k}: {v}")) ++ "\r\n\r\n"
          let _ ← sendImpl fd (ByteArray.mk responseText.toUTF8.data)
          let transport ← mkTcpTransport fd
          let conn : Conn := {
            transport := transport.toTransport,
            assembler := {},
            pingState := {}
          }
          return { conn? := some conn }
      | none =>
          closeImpl fd
          return { conn? := none, invalidHandshake := true }

partial def echoLoop (c : Conn) : IO Unit := do
  let bytes ← c.transport.recv
  if bytes.size = 0 then
    WebSocket.log .info "[conn] closed"
  else
    let (c', events) ← WebSocket.handleIncoming c bytes
    for (opc,payload) in events do
      if opc = .text then
        let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload := payload }
        c'.transport.send (encodeFrame f)
    echoLoop c'

partial def main : IO Unit := do
  let port := 9001
  let lh ← openServer port
  WebSocket.log .info s!"Listening on 0.0.0.0:{port} (robust example)"
  let rec acceptLoop (consecutiveSilent : Nat := 0) : IO Unit := do
    let res ← robustAccept lh
    match res.conn? with
    | some c =>
        WebSocket.log .info "Handshake complete"
        echoLoop c
        acceptLoop 0
    | none =>
        -- Só loga erro se realmente detectamos um handshake inválido.
        if res.invalidHandshake then
          WebSocket.log .error "Invalid WebSocket handshake received"
        else
          -- handshake ausente/timeout: evitamos spam; loga a cada ~5s (100 tentativas * 50ms)
          if consecutiveSilent % 100 = 0 then
            WebSocket.log .debug "Aguardando conexões..."
        IO.sleep 50
        acceptLoop (consecutiveSilent + 1)
  acceptLoop
