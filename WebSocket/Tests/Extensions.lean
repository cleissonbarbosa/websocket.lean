/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
open WebSocket

namespace WebSocket.Tests.Extensions

def testParseAndFormat : IO Unit := do
  let raw := "permessage-deflate; client_max_window_bits; server_max_window_bits=10, x-foo; a=1; b"
  let exts := parseExtensions raw
  if exts.length != 2 then
    throw <| IO.userError s!"Expected 2 extensions, got {exts.length}"
  let s := formatExtensions exts
  if (s.splitOn ", ").length != 2 then
    throw <| IO.userError "Formatting did not preserve list shape"
  IO.println "Extensions parse/format test passed"

def testNegotiation : IO Unit := do
  let serverSupported : List ExtensionConfig := [
    { name := "permessage-deflate" },
    { name := "x-foo", parameters := [("a", some "1")] }
  ]
  let clientRequested : List ExtensionConfig := [
    { name := "permessage-deflate", parameters := [("client_max_window_bits", none)] },
    { name := "x-bar" }
  ]
  let cfg : ExtensionNegotiationConfig := { supportedExtensions := serverSupported }
  let agreed := negotiateExtensions cfg clientRequested
  match agreed with
  | ext :: _ =>
      if ext.name != "permessage-deflate" then
        throw <| IO.userError "Negotiation failed to select supported extension"
      else
        pure ()
  | [] => throw <| IO.userError "Negotiation produced no extensions"
  IO.println "Extensions negotiation test passed"

def run : IO Unit := do
  testParseAndFormat
  testNegotiation

end WebSocket.Tests.Extensions

