import WebSocket.Handshake
import WebSocket.Subprotocols
import WebSocket.Extensions
import WebSocket.HTTP

namespace WebSocket

/-- Complete configuration for WebSocket upgrades -/
structure UpgradeConfig where
  subprotocols : SubprotocolConfig := {}
  extensions : ExtensionNegotiationConfig := {}

/-- Basic handshake upgrade with error handling -/
def upgradeE (req : HandshakeRequest) : Except HandshakeError HandshakeResponse := do
  if req.method ≠ "GET" then throw .badMethod
  match header? req "Host" with | none => throw .missingHost | some _ => pure ()
  let some u := header? req "Upgrade" | throw .missingUpgrade
  if lower u ≠ "websocket" then throw .notWebSocket
  let some c := header? req "Connection" | throw .missingConnection
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  let accept := acceptKey k
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

/-- Enhanced upgrade with subprotocol configuration -/
def upgradeWithConfig (req : HandshakeRequest) (config : SubprotocolConfig) : Except HandshakeError HandshakeResponse := do
  if req.method ≠ "GET" then throw .badMethod
  match header? req "Host" with | none => throw .missingHost | some _ => pure ()
  let some u := header? req "Upgrade" | throw .missingUpgrade
  if lower u ≠ "websocket" then throw .notWebSocket
  let some c := header? req "Connection" | throw .missingConnection
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  let accept := acceptKey k
  let clientTokens := match header? req "Sec-WebSocket-Protocol" with
    | none => []
    | some raw => raw.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
  if config.supported.length > 0 && config.rejectOnNoMatch then
    let selected := selectSubprotocol config clientTokens
    if selected.isNone then throw .subprotocolRejected
  let subProto? := if config.supported.length > 0 then selectSubprotocol config clientTokens else clientTokens.head?
  let baseHeaders := [
    ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Accept", accept)
  ]
  let headers := match subProto? with
    | some sp => baseHeaders ++ [("Sec-WebSocket-Protocol", sp)]
    | none => baseHeaders
  return { status := 101, reason := "Switching Protocols", headers }

/-- Safe upgrade with subprotocol configuration -/
def upgradeWithConfigSafe (req : HandshakeRequest) (config : SubprotocolConfig) : Option HandshakeResponse :=
  match upgradeWithConfig req config with | .ok r => some r | .error _ => none

/-- Enhanced upgrade with full configuration support -/
def upgradeWithFullConfig (req : HandshakeRequest) (config : UpgradeConfig) : Except HandshakeError HandshakeResponse := do
  if req.method ≠ "GET" then throw .badMethod
  match header? req "Host" with | none => throw .missingHost | some _ => pure ()
  let some u := header? req "Upgrade" | throw .missingUpgrade
  if lower u ≠ "websocket" then throw .notWebSocket
  let some c := header? req "Connection" | throw .missingConnection
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  let accept := acceptKey k
  let clientTokens := match header? req "Sec-WebSocket-Protocol" with
    | none => []
    | some raw => raw.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
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

/-- Convenience: parse raw HTTP request text and attempt WebSocket upgrade (basic). -/
def upgradeRaw (raw : String) : Option HandshakeResponse :=
  match WebSocket.HTTP.parse raw with
  | .error _ => none
  | .ok (rl, hs) =>
      let req : HandshakeRequest := { method := rl.method, resource := rl.resource, headers := hs }
      upgrade req

end WebSocket
