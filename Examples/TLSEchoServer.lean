/-
TLS Echo Server Example

Esta demonstração inicia um servidor WebSocket em modo TLS (quando a biblioteca
foi compilada com suporte TLS e quando você fornece um certificado e chave).

Pré‑requisitos:
 1. Gerar certificados de teste:
      ./scripts/make_test_certs.sh
    Isso cria:
      WebSocket/Tests/certs/server.cert.pem
      WebSocket/Tests/certs/server.key.pem
 2. Habilitar TLS no build (atualmente manual):
      - Edite `lakefile.lean` e defina `enableTLS : Bool := true`.
      - Opcional: construa OpenSSL localmente:
          ./scripts/build_openssl.sh
        e ajuste `localOpenSSL?` se necessário.
 3. Recompile:
      lake build tlsEchoServer

Execução:
  ./build/bin/tlsEchoServer
  Em seguida, teste o handshake:
  (exemplo usando `openssl s_client`)
    openssl s_client -connect localhost:9443 -quiet -servername localhost \\
      -no_ticket -ign_eof <<<'GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n'

Observação: O cliente ainda não implementa `wss://`; este exemplo mostra como
aceitar conexões TLS no servidor. Se TLS não estiver realmente habilitado no
build, o servidor inicia em modo claro e exibe aviso.
-/
import WebSocket
import WebSocket.Log
import WebSocket.Server.Types
import WebSocket.Server.Accept
import WebSocket.Server.Messaging
import WebSocket.Server.Process
open WebSocket WebSocket.Server.Types WebSocket.Server.Accept
open WebSocket.Server.Process

namespace Examples

def echoConn (base : ServerState) (connId : Nat) : IO ServerState := do
  /- Processa uma rodada de mensagens (se houver) e ecoa texto/binário. -/
  let (s', events) ← processConnection base connId
  let mut cur := s'
  for ev in events do
    match ev with
    | .message id .text payload =>
        cur ← WebSocket.Server.Messaging.sendText cur id (String.fromUTF8! payload)
    | .message id .binary payload =>
        cur ← WebSocket.Server.Messaging.sendBinary cur id payload
    | _ => pure ()
  pure cur

partial def loop (s : ServerState) : IO Unit := do
  let (s', ev?) ← acceptConnection s
  let mut s1 := s'
  match ev? with
  | some (.connected cid _) =>
      WebSocket.log .info s!"[tls-echo] connection {cid}"
      -- simples mini loop de echo para esta conexão (bloqueante). Em um servidor real faríamos multiplexing.
      for _ in [0:200] do
        s1 ← echoConn s1 cid
        IO.sleep 50
  | some (.error _ msg) => WebSocket.log .error s!"[tls-echo] erro: {msg}"
  | _ => IO.sleep 50
  loop s1

def main : IO Unit := do
  let cert := "WebSocket/Tests/certs/server.cert.pem"
  let key  := "WebSocket/Tests/certs/server.key.pem"
  let cfg : ServerConfig := {
    port := 9443,
    maxConnections := 32,
    tlsCertFile? := if (← (do try let _ ← IO.FS.readFile cert; pure true catch _ => pure false)) then some cert else none,
    tlsKeyFile?  := if (← (do try let _ ← IO.FS.readFile key; pure true catch _ => pure false)) then some key else none
  }
  let s0 := mkServer cfg
  let s1 ← start s0
  match s1.tlsCtx? with
  | some _ => WebSocket.log .info "[tls-echo] TLS ativo (contexto inicializado)"
  | none => WebSocket.log .warn "[tls-echo] TLS NÃO ATIVO (verifique build e certs) — operando sem criptografia"
  loop s1

end Examples

def main : IO Unit := Examples.main
