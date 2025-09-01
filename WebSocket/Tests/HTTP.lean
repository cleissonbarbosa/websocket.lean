/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.HTTP

namespace WebSocket.Tests.HTTP

def testParseEmpty : IO Unit := do
  match WebSocket.HTTP.parse "" with
  | .error _ => IO.println "HTTP empty parse test passed"
  | .ok _ => throw <| IO.userError "Expected error for empty request"

def testParseMalformedHeader : IO Unit := do
  let raw := "GET / HTTP/1.1\r\nHost example.com\r\n\r\n"
  match WebSocket.HTTP.parse raw with
  | .error _ => IO.println "HTTP malformed header test passed"
  | .ok _ => throw <| IO.userError "Expected error for malformed header"

def run : IO Unit := do
  testParseEmpty
  testParseMalformedHeader

end WebSocket.Tests.HTTP

