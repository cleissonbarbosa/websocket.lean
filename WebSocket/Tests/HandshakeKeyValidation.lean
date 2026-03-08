import WebSocket
open WebSocket

namespace WebSocket.Tests.HandshakeKeyValidation

def testValidKey : IO Unit := do
  -- Chave do exemplo da RFC (deve ter 16 bytes decodificados)
  let key := "dGhlIHNhbXBsZSBub25jZQ=="
  match validateClientKey key with
  | .ok _ => pure ()
  | .error _ => throw <| IO.userError "Expected valid key, got error"

def testBadBase64 : IO Unit := do
  let key := "@@@@@@=="  -- caracteres inválidos
  match validateClientKey key with
  | .error HandshakeError.badKeyBase64 => pure ()
  | _ => throw <| IO.userError "Expected badKeyBase64"

def testBadLength : IO Unit := do
  -- "c2hvcnQ=" decodifica para "short" (5 bytes)
  let key := "c2hvcnQ="
  match validateClientKey key with
  | .error HandshakeError.badKeyLength => pure ()
  | _ => throw <| IO.userError "Expected badKeyLength"

def run : IO Unit := do
  testValidKey; testBadBase64; testBadLength
  IO.println "Handshake key validation tests passed"

end WebSocket.Tests.HandshakeKeyValidation
