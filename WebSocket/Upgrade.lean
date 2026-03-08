/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket.Handshake
import WebSocket.Subprotocols
import WebSocket.Extensions
import WebSocket.HTTP
import WebSocket.Log

namespace WebSocket

/-- Generate appropriate HTTP error response for handshake failure -/
def handshakeErrorResponse (error : HandshakeError) : IO HandshakeResponse := do
  match error with
  | .badMethod =>
      WebSocket.log .warn "Handshake failed: bad method (not GET)"
      pure <| HandshakeResponse.mk 405 "Method Not Allowed" [("Allow", "GET")]
  | .missingHost =>
      WebSocket.log .warn "Handshake failed: missing Host header"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .missingUpgrade =>
      WebSocket.log .warn "Handshake failed: missing Upgrade header"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .notWebSocket =>
      WebSocket.log .warn "Handshake failed: Upgrade header not 'websocket'"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .missingConnection =>
      WebSocket.log .warn "Handshake failed: missing Connection header"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .connectionNotUpgrade =>
      WebSocket.log .warn "Handshake failed: Connection header doesn't contain 'upgrade'"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .missingKey =>
      WebSocket.log .warn "Handshake failed: missing Sec-WebSocket-Key header"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .badVersion =>
      WebSocket.log .warn "Handshake failed: Sec-WebSocket-Version not 13"
      pure <| HandshakeResponse.mk 426 "Upgrade Required" [("Sec-WebSocket-Version", "13")]
  | .badKeyLength =>
      WebSocket.log .warn "Handshake failed: Sec-WebSocket-Key not 16 bytes after base64 decode"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .badKeyBase64 =>
      WebSocket.log .warn "Handshake failed: Sec-WebSocket-Key invalid base64"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .subprotocolRejected =>
      WebSocket.log .warn "Handshake failed: requested subprotocol not supported"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .headerInjectionAttempted =>
      WebSocket.log .warn "Handshake failed: header injection attempt detected"
      pure <| HandshakeResponse.mk 400 "Bad Request" []
  | .multipleHeadersForbidden =>
      WebSocket.log .warn "Handshake failed: multiple headers for single-value field"
      pure <| HandshakeResponse.mk 400 "Bad Request" []

/-- Complete configuration for WebSocket upgrades -/
structure UpgradeConfig where
  subprotocols : SubprotocolConfig := {}
  extensions : ExtensionNegotiationConfig := {}

/-- Basic handshake upgrade with comprehensive error handling and security validation -/
def upgradeE (req : HandshakeRequest) : Except HandshakeError HandshakeResponse := do
  -- Method validation
  if req.method ≠ "GET" then throw .badMethod

  -- Required headers with security validation
  match header? req "Host" with
  | none => throw .missingHost
  | some host => validateHeaderValue host

  -- Validate single occurrence of critical headers
  validateSingleHeader req "Host"
  validateSingleHeader req "Upgrade"
  validateSingleHeader req "Connection"
  validateSingleHeader req "Sec-WebSocket-Key"
  validateSingleHeader req "Sec-WebSocket-Version"

  -- Upgrade header validation
  let some u := header? req "Upgrade" | throw .missingUpgrade
  validateHeaderValue u
  if lower u ≠ "websocket" then throw .notWebSocket

  -- Connection header validation
  let some c := header? req "Connection" | throw .missingConnection
  validateHeaderValue c
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade

  -- Version validation (RFC 6455 requires version 13)
  validateVersion req

  -- Key validation with security checks
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  validateHeaderValue k
  let () ← validateClientKey k
  let accept := acceptKey k

  -- Subprotocol handling (optional)
  let subProto? : Option String :=
    match header? req "Sec-WebSocket-Protocol" with
    | none => none
    | some raw =>
        let tokens := raw.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
        tokens.head?

  let baseHeaders := [
    ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Accept", accept)
  ]
  let headers := match subProto? with | some sp => baseHeaders ++ [("Sec-WebSocket-Protocol", sp)] | none => baseHeaders
  return { status := 101, reason := "Switching Protocols", headers }

/-- Simple upgrade (Option-based) -/
def upgrade (req : HandshakeRequest) : Option HandshakeResponse :=
  match upgradeE req with | .ok r => some r | .error _ => none

/-- Upgrade with proper error response generation -/
def upgradeWithErrorResponse (req : HandshakeRequest) : IO HandshakeResponse := do
  match upgradeE req with
  | .ok response => pure response
  | .error err => handshakeErrorResponse err


/-- Enhanced upgrade with full configuration support and security validation -/
def upgradeWithFullConfig (req : HandshakeRequest) (config : UpgradeConfig) : Except HandshakeError HandshakeResponse := do
  -- Method validation
  if req.method ≠ "GET" then throw .badMethod

  -- Required headers with security validation
  match header? req "Host" with
  | none => throw .missingHost
  | some host => validateHeaderValue host

  -- Validate single occurrence of critical headers
  validateSingleHeader req "Host"
  validateSingleHeader req "Upgrade"
  validateSingleHeader req "Connection"
  validateSingleHeader req "Sec-WebSocket-Key"
  validateSingleHeader req "Sec-WebSocket-Version"

  -- Upgrade header validation
  let some u := header? req "Upgrade" | throw .missingUpgrade
  validateHeaderValue u
  if lower u ≠ "websocket" then throw .notWebSocket

  -- Connection header validation
  let some c := header? req "Connection" | throw .missingConnection
  validateHeaderValue c
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade

  -- Version validation (RFC 6455 requires version 13)
  validateVersion req

  -- Key validation with security checks
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  validateHeaderValue k
  let () ← validateClientKey k
  let accept := acceptKey k
  let clientTokens := match header? req "Sec-WebSocket-Protocol" with
    | none => []
    | some raw =>
        raw.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
  if config.subprotocols.supported.length > 0 && config.subprotocols.rejectOnNoMatch then
    let selected := selectSubprotocol config.subprotocols clientTokens
    if selected.isNone then throw .subprotocolRejected
  let subProto? := if config.subprotocols.supported.length > 0 then selectSubprotocol config.subprotocols clientTokens else clientTokens.head?
  let clientExtensions := match header? req "Sec-WebSocket-Extensions" with
    | none => []
    | some raw => parseExtensions raw
  let negotiatedExtensions := negotiateExtensions config.extensions clientExtensions
  let baseHeaders := [
    ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Accept", accept)
  ]
  let headersWithSubprotocol := match subProto? with
    | some sp => baseHeaders ++ [("Sec-WebSocket-Protocol", sp)]
    | none => baseHeaders
  let headers := if negotiatedExtensions.length > 0 then
    headersWithSubprotocol ++ [("Sec-WebSocket-Extensions", formatExtensions negotiatedExtensions)]
  else headersWithSubprotocol
  return { status := 101, reason := "Switching Protocols", headers }

/-- Full config upgrade with proper error response generation -/
def upgradeWithFullConfigAndErrorResponse (req : HandshakeRequest) (config : UpgradeConfig) : IO HandshakeResponse := do
  match upgradeWithFullConfig req config with
  | .ok response => pure response
  | .error err => handshakeErrorResponse err

/-- Convenience: parse raw HTTP request text and attempt WebSocket upgrade (basic). -/
def upgradeRaw (raw : String) : Option HandshakeResponse :=
  match WebSocket.HTTP.parse raw with
  | .error _ => none
  | .ok (rl, hs) =>
      let req : HandshakeRequest := { method := rl.method, resource := rl.resource, headers := hs }
      upgrade req

end WebSocket
