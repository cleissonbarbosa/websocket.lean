/-
Simple TLS WebSocket Server

Exemplo simplificado de servidor WebSocket com TLS usando a infraestrutura existente.

Pré-requisitos:
1. Certificados: ./scripts/make_test_certs.sh
2. TLS habilitado: enableTLS := true em lakefile.lean

Teste:
  wscat --connect wss://localhost:9443 --no-check
-/

import WebSocket
import WebSocket.Net
import WebSocket.Log
import WebSocket.Server.Types
import WebSocket.Server.Accept

open WebSocket WebSocket.Net
open WebSocket.Server.Types WebSocket.Server.Accept

def main : IO Unit := do
  WebSocket.info "🔒 Iniciando servidor WebSocket TLS simples..."

  let certFile := "WebSocket/Tests/certs/server.cert.pem"
  let keyFile := "WebSocket/Tests/certs/server.key.pem"

  -- Verificar certificados
  let certExists ← (do let _ ← IO.FS.readFile certFile; pure true) <|> pure false
  let keyExists ← (do let _ ← IO.FS.readFile keyFile; pure true) <|> pure false

  if !certExists || !keyExists then
    WebSocket.error "Certificados não encontrados! Execute: ./scripts/make_test_certs.sh"
    return

  -- Configurar servidor com TLS
  let config : ServerConfig := {
    port := 9443,
    maxConnections := 10,
    tlsCertFile? := some certFile,
    tlsKeyFile? := some keyFile
  }

  let server := mkServer config
  let server' ← start server

  match server'.tlsCtx? with
  | none =>
    WebSocket.error "TLS não foi inicializado. Verifique:"
    WebSocket.error "1. enableTLS := true em lakefile.lean"
    WebSocket.error "2. OpenSSL está instalado"
    WebSocket.error "3. Recompile com: lake clean && lake build"
    return
  | some ctx =>
    WebSocket.info s!"✅ Contexto TLS inicializado (ctx={ctx})"
    WebSocket.info s!"✅ Servidor escutando em wss://localhost:{config.port}"
    WebSocket.info ""
    WebSocket.info "Para testar:"
    WebSocket.info "  npm install -g wscat"
    WebSocket.info "  wscat --connect wss://localhost:9443 --no-check"
    WebSocket.info ""
    WebSocket.info "Ou com curl:"
    WebSocket.info "  curl --insecure -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" \\"
    WebSocket.info "       -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" \\"
    WebSocket.info "       -H \"Sec-WebSocket-Version: 13\" https://localhost:9443"
    WebSocket.info ""
    WebSocket.info "Aguardando conexões... (Ctrl+C para sair)"

    -- Loop simples - usa um contador para evitar problemas de terminação
    let mut loopServer := server'
    for _ in [0:100000] do  -- Loop por um número fixo grande de iterações
      let (nextServer, ev?) ← acceptConnection loopServer
      loopServer := nextServer
      match ev? with
      | some (.connected id _) =>
        WebSocket.info s!"✅ Nova conexão TLS estabelecida (ID: {id})"
        -- Em um servidor real, processaríamos mensagens aqui
      | some (.error _ msg) =>
        WebSocket.warn s!"Erro: {msg}"
      | _ =>
        IO.sleep 100
