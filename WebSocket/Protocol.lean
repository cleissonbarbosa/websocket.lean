/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Extensions
open WebSocket

namespace WebSocket.Protocol

/-- Subprotocol negotiation strategy -/
inductive SubprotocolStrategy
  | firstMatch      -- Select first client-requested protocol that server supports
  | priority (priorities : List String)  -- Select based on server priority order
  | custom (selector : List String → List String → Option String)  -- Custom selection function

/-- Subprotocol negotiation result -/
inductive NegotiationResult
  | selected (protocol : String)
  | none
  | error (reason : String)
  deriving Repr

/-- Negotiate subprotocol selection -/
def negotiateSubprotocol (clientProtocols : List String) (serverProtocols : List String) (strategy : SubprotocolStrategy := .firstMatch) : NegotiationResult :=
  if clientProtocols.isEmpty ∨ serverProtocols.isEmpty then
    .none
  else
    match strategy with
    | .firstMatch =>
        match clientProtocols.find? (serverProtocols.contains ·) with
        | some proto => .selected proto
        | none => .none
    | .priority priorities =>
        match priorities.find? (fun p => clientProtocols.contains p ∧ serverProtocols.contains p) with
        | some proto => .selected proto
        | none => .none
    | .custom selector =>
        match selector clientProtocols serverProtocols with
        | some proto => .selected proto
        | none => .none

/-- Extension negotiation placeholder -/
structure Extension where
  name : String
  parameters : List (String × String) := []
  deriving Repr

/-- Parse extension header -/
def parseExtensions (header : String) : List Extension :=
  -- Simplified parser - in production this should properly handle quoted strings and parameters
  header.splitOn "," |>.map (fun ext =>
    let trimmed := ext.trim
    let parts := trimmed.splitOn ";"
    match parts with
    | [] => { name := "" }
    | name :: params =>
        let parsedParams := params.map (fun p =>
          let kv := p.trim.splitOn "="
          match kv with
          | [k] => (k.trim, "")
          | [k, v] => (k.trim, v.trim)
          | _ => ("", "")
        )
        { name := name.trim, parameters := parsedParams }
  ) |>.filter (·.name ≠ "")

/-- Enhanced upgrade function with strategy support -/
def upgradeWithStrategy (req : HandshakeRequest) (supportedProtocols : List String := []) (strategy : SubprotocolStrategy := .firstMatch) : Except HandshakeError HandshakeResponse := do
  if req.method ≠ "GET" then throw .badMethod
  match header? req "Host" with | none => throw .missingHost | some _ => pure ()
  let some u := header? req "Upgrade" | throw .missingUpgrade
  if lower u ≠ "websocket" then throw .notWebSocket
  let some c := header? req "Connection" | throw .missingConnection
  if ¬ containsIgnoreCase c "upgrade" then throw .connectionNotUpgrade
  let some k := header? req "Sec-WebSocket-Key" | throw .missingKey
  let accept := acceptKey k

  -- Enhanced subprotocol negotiation
  let subProto? : Option String :=
    match header? req "Sec-WebSocket-Protocol" with
    | none => none
    | some raw =>
        let clientProtocols := raw.splitOn "," |>.map (·.trim) |>.filter (· ≠ "")
        match negotiateSubprotocol clientProtocols supportedProtocols strategy with
        | .selected proto => some proto
        | _ => none

  -- Basic extension negotiation: echo back any extensions that appear (no validation) - conservative improvement
  let extensionsHeader? := header? req "Sec-WebSocket-Extensions"
  let negotiatedExtensions : List ExtensionConfig :=
    match extensionsHeader? with
    | none => []
    | some raw => parseExtensions raw  -- reuse existing parser (simple pass-through)

  let baseHeaders := [
    ("Upgrade","websocket"), ("Connection","Upgrade"), ("Sec-WebSocket-Accept", accept)
  ]
  let withProto := match subProto? with
    | some sp => baseHeaders ++ [("Sec-WebSocket-Protocol", sp)]
    | none => baseHeaders
  let headers := if negotiatedExtensions.isEmpty then withProto else
    withProto ++ [("Sec-WebSocket-Extensions", formatExtensions negotiatedExtensions)]

  return { status := 101, reason := "Switching Protocols", headers }

/-- Close code validation and mapping -/
def isValidCloseCode (code : Nat) : Bool :=
  (code >= 1000 ∧ code <= 1011) ∨
  (code >= 3000 ∧ code <= 3999) ∨
  (code >= 4000 ∧ code <= 4999)

/-/ Re-export mapping defined in Assembler (single source of truth). -/
@[inline] def closeCodeForViolation : ProtocolViolation → CloseCode :=
  violationCloseCode

end WebSocket.Protocol
