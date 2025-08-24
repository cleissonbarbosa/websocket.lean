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
  | subprotocolRejected
  deriving Repr, DecidableEq

/-- Utility: lowercase a string -/
def lower (s : String) : String := s.map (·.toLower)

/-- Fetch header value (case-insensitive) -/
def header? (r : HandshakeRequest) (name : String) : Option String :=
  let target := lower name; r.headers.findSome? (fun (k,v) => if lower k = target then some v else none)

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

end WebSocket
