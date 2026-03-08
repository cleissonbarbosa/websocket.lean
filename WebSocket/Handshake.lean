/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket.Core.Types
import WebSocket.Core.Frames
import WebSocket.Crypto.Base64
import WebSocket.Crypto.SHA1
import WebSocket.HTTP
import WebSocket.UTF8

namespace WebSocket

/-- WebSocket handshake request representation -/
structure HandshakeRequest where
  method : String
  resource : String
  headers : List (String × String)
  deriving Repr

/-- WebSocket handshake response representation -/
structure HandshakeResponse where
  status : Nat
  reason : String
  headers : List (String × String)
  deriving Repr

/-- Possible handshake errors -/
inductive HandshakeError
  | badMethod
  | missingHost
  | missingUpgrade
  | notWebSocket
  | missingConnection
  | connectionNotUpgrade
  | missingKey
  | badVersion        -- Sec-WebSocket-Version ausente ou diferente de 13
  | badKeyLength      -- Sec-WebSocket-Key não representa 16 bytes após Base64
  | badKeyBase64      -- Sec-WebSocket-Key Base64 inválido
  | subprotocolRejected
  | headerInjectionAttempted -- CRLF or other injection attempts in headers
  | multipleHeadersForbidden -- Multiple values for single header when not allowed
  deriving Repr, DecidableEq

/-- Utility: lowercase a string -/
def lower (s : String) : String := s.map (·.toLower)

/-- Fetch header value (case-insensitive) -/
def header? (r : HandshakeRequest) (name : String) : Option String :=
  let target := lower name; r.headers.findSome? (fun (k,v) => if lower k = target then some v else none)

/-- Fetch all header values for a given name (case-insensitive) -/
def headers (r : HandshakeRequest) (name : String) : List String :=
  let target := lower name
  r.headers.filterMap (fun (k,v) => if lower k = target then some v else none)

/-- Validate header value for CRLF injection attempts -/
def validateHeaderValue (value : String) : Except HandshakeError Unit := do
  if value.contains '\r' || value.contains '\n' then
    throw .headerInjectionAttempted
  if value.length > 4096 then -- Reasonable header length limit
    throw .headerInjectionAttempted
  pure ()

/-- Validate that a header appears exactly once (security measure) -/
def validateSingleHeader (r : HandshakeRequest) (name : String) : Except HandshakeError Unit := do
  let values := headers r name
  if values.length > 1 then
    throw .multipleHeadersForbidden
  pure ()

/-- Validate Sec-WebSocket-Version header -/
def validateVersion (r : HandshakeRequest) : Except HandshakeError Unit := do
  match header? r "Sec-WebSocket-Version" with
  | none => throw .badVersion
  | some version =>
      validateHeaderValue version
      if version.trim ≠ "13" then throw .badVersion
      pure ()

/-- Case-insensitive containment (naive) -/
def containsIgnoreCase (h n : String) : Bool :=
  let lh := lower h; let ln := lower n
  (lh.splitOn ln).length > 1

/-- Compute Sec-WebSocket-Accept -/
def acceptKey (clientKey : String) : String :=
  let guid := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  let bytes := ByteArray.mk ((clientKey ++ guid).toUTF8.data.map (fun c => UInt8.ofNat c.toNat))
  let digest := WebSocket.Crypto.SHA1 bytes
  WebSocket.Crypto.base64Encode digest

/-- Retorna índice de caractere base64 ou none. -/
private def b64Index? (c : Char) : Option Nat :=
  let alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".data
  let rec go (l : List Char) (idx : Nat) : Option Nat :=
    match l with
    | [] => none
    | h::t => if h = c then some idx else go t (idx+1)
  go alphabet 0

/-- Decodifica Base64 mínima para validação do Sec-WebSocket-Key.
    Não suporta whitespace; falha em padding irregular. -/
def base64Decode? (s : String) : Option ByteArray :=
  if s.length % 4 ≠ 0 then none else
  let chars := s.data
  let rec loop : List Char → Option ByteArray
    | a::b::c::d::rest =>
        let pad2 := c = '='; let pad3 := d = '='
        match b64Index? a with
        | none => none
        | some v0 =>
          match b64Index? b with
          | none => none
          | some v1 =>
            let v2? := if pad2 then some 0 else b64Index? c
            let v3? := if pad3 then some 0 else b64Index? d
            match v2? with
            | none => none
            | some v2 =>
              match v3? with
              | none => none
              | some v3 =>
                if pad2 && ¬ pad3 then none else
                match loop rest with
                | none => none
                | some tail =>
                  let n := (v0 <<< 18) ||| (v1 <<< 12) ||| (v2 <<< 6) ||| v3
                  let b0 := ByteArray.empty.push (UInt8.ofNat ((n >>> 16) &&& 0xFF))
                  let b1 := if pad2 then b0 else b0.push (UInt8.ofNat ((n >>> 8) &&& 0xFF))
                  let b2 := if pad3 then b1 else b1.push (UInt8.ofNat (n &&& 0xFF))
                  some (b2 ++ tail)
    | [] => some ByteArray.empty
    | _ => none -- tamanho já múltiplo de 4, então não deveria cair aqui
  loop chars

/-- Valida se a chave do cliente é Base64 de exatamente 16 bytes (nonce) conforme RFC 6455. -/
def validateClientKey (k : String) : Except HandshakeError Unit := do
  match base64Decode? k with
  | none => throw .badKeyBase64
  | some bytes => if bytes.size ≠ 16 then throw .badKeyLength else pure ()

end WebSocket
