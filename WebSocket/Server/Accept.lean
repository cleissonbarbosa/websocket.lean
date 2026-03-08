/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Log
import WebSocket.Metrics
import WebSocket.Net
import WebSocket.Server.Types
open WebSocket WebSocket.Net

namespace WebSocket.Server.Accept

open WebSocket.Server.Types

/-- Start listening on the configured port -/
def start (server : ServerState) : IO ServerState := do
  let lh ← openServer server.config.port
  let mut tlsCtx? := server.tlsCtx?
  let rateLimiter ←
    if server.config.rateLimit.enabled then
      RateLimiter.create server.config.rateLimit
    else
      RateLimiter.create { enabled := false }
  match server.config.tlsCertFile?, server.config.tlsKeyFile? with
  | some cert, some key =>
      try
        let ctx ← tlsInitCtxImpl cert key
        tlsCtx? := some ctx
        WebSocket.log .info s!"TLS context initialized"
      catch e =>
        WebSocket.log .error s!"Failed to init TLS context: {e}"
  | _, _ => pure ()
  if server.config.logConnections then
    WebSocket.log .info s!"Listening on port {server.config.port}"
  return { server with listenHandle := some lh, tlsCtx?, rateLimiter := some rateLimiter }

/-- Accept a single connection and perform handshake with rate limiting -/
def acceptConnection (server : ServerState) : IO (ServerState × Option ServerEvent) := do
  match server.listenHandle with
  | none => return (server, some (.error 0 "Server not listening"))
  | some lh =>
    try
      let client? ← WebSocket.Net.tryAcceptClient lh
      let some client := client?
        | return (server, none)

      if server.connections.length >= server.config.maxConnections then
        WebSocket.log .warn s!"Connection limit reached ({server.config.maxConnections}); rejecting {client.addr}"
        closeImpl client.fd
        return (server, some (.error 0 "Max connections reached"))

      -- Check rate limiting before handshake using the real peer address.
      match server.rateLimiter with
      | some limiter =>
        let rateCheck ← limiter.shouldAllow client.addr
        match rateCheck with
        | .error msg =>
          WebSocket.log .warn s!"Rate limit exceeded for client {client.addr}: {msg}"
          closeImpl client.fd
          return (server, none)  -- Silently drop connection
        | .ok () =>
          pure ()
      | none =>
        pure ()

      let upgradeCfg : UpgradeConfig := {
        subprotocols := { supported := server.config.subprotocols, rejectOnNoMatch := false },
        extensions := { supportedExtensions := [] }
      }
      let res ← WebSocket.Net.acceptAndUpgradeClientWithConfig client.fd upgradeCfg server.tlsCtx? server.config.handshakeTimeout
      match res with
      | some (tcpConn, subp?, _exts) =>
          WebSocket.Metrics.handshakeSuccessful
          WebSocket.Metrics.connectionOpened
          let tcpConn' : TcpConn := {
            tcpConn with
              assembler := {
                tcpConn.assembler with
                  maxMessageSize? := some server.config.maxMessageSize
                  maxFragments? := some server.config.maxFragmentsPerMessage
              }
          }
          let connId := server.nextConnId
          let nowMs := UInt64.ofNat ((← IO.monoNanosNow) / 1000000)
          let connState : ConnectionState := {
            id := connId
            conn := tcpConn'
            addr := client.addr
            subprotocol := subp?
            lastActivityMs := nowMs
          }
          let serverWithConn := { server with connections := connState :: server.connections, nextConnId := connId + 1 }

          if server.config.logConnections then
            WebSocket.log .info s!"Accepted connection #{connId} from {client.addr}"
          return (serverWithConn, some (.connected connId client.addr))
      | none =>
          WebSocket.Metrics.handshakeFailed
          return (server, none)
    catch e =>
      return (server, some (.error 0 s!"Accept error: {e}"))

end WebSocket.Server.Accept
