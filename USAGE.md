# Guia de Uso das Novas Funcionalidades do WebSocket Server

Este guia demonstra como utilizar as novas funcionalidades implementadas no servidor WebSocket.

## 1. Servidor Assíncrono com Gerenciamento de Tarefas

```lean
import WebSocket.Server.Async

-- Criar servidor assíncrono
let asyncServer ← mkAsyncServer { port := 9001, maxConnections := 100 }

-- Handler de eventos
let eventHandler : EventHandler := fun event => do
  match event with
  | .connected id addr => IO.println s!"Cliente {id} conectou de {addr}"
  | .message id .text payload => 
      let text := String.fromUTF8! payload
      IO.println s!"Mensagem de texto: {text}"
  | _ => pure ()

-- Executar servidor assíncrono
runAsyncServer asyncServer eventHandler
```

## 2. Sistema de Subscrição a Eventos

```lean
import WebSocket.Server.Events

-- Criar gerenciador de eventos
let mut eventManager := mkEventManager

-- Handler específico para mensagens de texto
let textHandler : EventHandler := fun event => do
  IO.println "Recebida mensagem de texto!"

-- Handler específico para conexões
let connectionHandler : EventHandler := fun event => do
  match event with
  | .connected id addr => IO.println s!"Nova conexão: {id} de {addr}"
  | .disconnected id reason => IO.println s!"Desconectado {id}: {reason}"
  | _ => pure ()

-- Subscrever a eventos específicos
let (em1, textSubId) := subscribe eventManager (.message (some .text)) textHandler
let (em2, connSubId) := subscribe em1 (.custom (fun event =>
  match event with
  | .connected _ _ | .disconnected _ _ => true
  | _ => false
)) connectionHandler

eventManager := em2

-- Despachar eventos
dispatch eventManager (ServerEvent.connected 1 "192.168.1.100")
dispatch eventManager (ServerEvent.message 1 .text (ByteArray.mk "Hello".toUTF8.data))

-- Cancelar subscrição
eventManager := unsubscribe eventManager textSubId
```

## 3. Close Handshake Gracioso

```lean
import WebSocket.Server.Close

-- Configuração de close
let closeConfig : CloseConfig := {
  timeoutMs := 5000,      -- 5 segundos de timeout
  maxDrainMessages := 20,  -- Máximo 20 mensagens para drenar
  sendCloseFrame := true   -- Enviar frame de close automaticamente
}

-- Iniciar close gracioso
let newServer ← initiateClose server connId .normalClosure "Servidor desligando" closeConfig

-- Processar timeouts de close
let serverWithTimeouts ← processCloseTimeouts newServer closeConfig

-- Handler para close frames recebidos
let handleClose : EventHandler := fun event => do
  match event with
  | .message connId .close payload =>
      let newServer ← handleIncomingClose currentServer connId payload closeConfig
      serverRef.set newServer
  | _ => pure ()
```

## 4. Keep-Alive com Ping/Pong

```lean
import WebSocket.Server.KeepAlive

-- Configuração de ping
let pingConfig : PingConfig := {
  intervalMs := 30000,     -- Ping a cada 30 segundos
  maxMissedPongs := 3,     -- Máximo 3 pongs perdidos
  timeoutMs := 10000       -- 10 segundos de timeout para pong
}

-- Processar keep-alive para todas as conexões
let serverWithPing ← processKeepAlive server pingConfig

-- Wrapper de event handler que processa pongs automaticamente
let serverRef ← IO.mkRef server
let wrappedHandler := wrapEventHandlerWithPing serverRef pingConfig baseHandler

-- Usar o handler wrapped no servidor
runServer server wrappedHandler
```

## 5. Exemplo Completo: Servidor de Chat Avançado

```lean
import WebSocket.Server
import WebSocket.Server.Async
import WebSocket.Server.Events
import WebSocket.Server.KeepAlive
import WebSocket.Server.Close

def main : IO Unit := do
  -- Configuração do servidor
  let config : ServerConfig := {
    port := 8080,
    maxConnections := 200,
    maxMessageSize := 1024 * 1024,  -- 1MB
    subprotocols := ["chat.v1", "chat.v2"]
  }
  
  -- Criar servidor assíncrono
  let asyncServer ← mkAsyncServer config
  let serverRef ← IO.mkRef asyncServer.base
  
  -- Sistema de eventos
  let mut eventManager := mkEventManager
  
  -- Handler de chat (broadcast de mensagens)
  let chatHandler : EventHandler := fun event => do
    match event with
    | .message connId .text payload =>
        let text := String.fromUTF8! payload
        let server ← serverRef.get
        -- Broadcast para todos menos o remetente
        let newServer ← broadcast server .text payload
        serverRef.set newServer
        IO.println s!"Broadcast de {connId}: {text}"
    | _ => pure ()
  
  -- Handler de conexões
  let connectionHandler : EventHandler := fun event => do
    match event with
    | .connected id addr => 
        IO.println s!"✅ Cliente {id} entrou no chat ({addr})"
    | .disconnected id reason =>
        IO.println s!"❌ Cliente {id} saiu do chat: {reason}"
    | _ => pure ()
  
  -- Subscrever aos eventos
  let (em1, _) := subscribe eventManager (.message (some .text)) chatHandler
  let (em2, _) := subscribe em1 (.custom (fun event =>
    match event with
    | .connected _ _ | .disconnected _ _ => true
    | _ => false
  )) connectionHandler
  eventManager := em2
  
  -- Configurar keep-alive
  let pingConfig : PingConfig := { intervalMs := 15000 }
  
  -- Handler combinado
  let combinedHandler : EventHandler := fun event => do
    dispatch eventManager event
  
  let finalHandler := wrapEventHandlerWithPing serverRef pingConfig combinedHandler
  
  IO.println "🚀 Servidor de chat iniciado na porta 8080"
  IO.println "Funcionalidades:"
  IO.println "  ✓ Chat em tempo real com broadcast"
  IO.println "  ✓ Keep-alive automático (15s)"
  IO.println "  ✓ Close handshake gracioso"
  IO.println "  ✓ Processamento assíncrono"
  IO.println "  ✓ Sistema de eventos por subscrição"
  
  try
    runAsyncServer asyncServer finalHandler
  catch e =>
    IO.println s!"Erro no servidor: {e}"
  finally
    stopAsyncServer asyncServer
    IO.println "Servidor finalizado graciosamente"
```

## Filtros de Evento Disponíveis

- `.all` - Todos os eventos
- `.connected` - Apenas eventos de conexão
- `.disconnected` - Apenas eventos de desconexão
- `.message (some .text)` - Apenas mensagens de texto
- `.message (some .binary)` - Apenas mensagens binárias
- `.message none` - Todas as mensagens
- `.error` - Apenas eventos de erro
- `.custom predicate` - Filtro personalizado com predicado

## Próximos Passos

- Implementação de cliente WebSocket
- Extensões (permessage-deflate)
- Provas formais de correção
- Otimizações de performance
- Suporte a TLS/WSS