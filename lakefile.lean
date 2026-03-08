/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import Lake
open Lake DSL System

/-!
Manual TLS (OpenSSL) build support.

TLS is disabled by default. To enable it, edit this file and set:

- `enableTLS := true`
- `localOpenSSL? := some "vendor/openssl"` if you want to link against a local build

If TLS is disabled, stub C functions are compiled instead (see
`WebSocket/Net/TLSInlineC.lean`) so the rest of the code continues to build.

You can build a local OpenSSL via `scripts/build_openssl.sh`, which installs into
`vendor/openssl` by default unless `OPENSSL_PREFIX` is overridden.

For production use, prefer validated TLS enablement or a TLS-terminating reverse
proxy instead of running unencrypted WebSocket traffic directly.
-/
-- NOTE: Lake configuration runs in a pure context; to avoid fragile unsafe IO here
-- we keep a simple manual toggle. Set to true to attempt TLS (OpenSSL) linkage.
-- For environment driven builds, you can patch this file in automation or inject
-- -DWEBSOCKET_TLS plus link args manually (see README TLS section).
-- WARNING: TLS is disabled by default for compatibility. Enable for production!
-- Set to true to enable TLS support with OpenSSL
def enableTLS : Bool := false

-- Optional path prefix to a locally built OpenSSL (containing lib/libssl.a etc.).
-- Leave as none to rely on system libraries when TLS is enabled.
-- Using system OpenSSL by default (set to `some "vendor/openssl"` to use local build)
def localOpenSSL? : Option String := none

def commonLeancArgs : Array String :=
  #["-fPIC"] ++ (if enableTLS then #["-DWEBSOCKET_TLS"] else #[])

def commonLinkArgs : Array String :=
  if enableTLS then
    match localOpenSSL? with
    | some root =>
        -- Static link against locally built libs (order matters for some linkers)
        #[(s!"{root}/lib/libssl.a"), (s!"{root}/lib/libcrypto.a"), "-ldl", "-lpthread", "-lz"]
    | none =>
      -- Prefer standard linker flags for system OpenSSL.
      #["-lssl", "-lcrypto", "-ldl", "-lpthread", "-lz"]
  else #[]

require alloy from git "https://github.com/tydeu/lean4-alloy" @ "master"

package «websocket» where
  srcDir := "."
  -- Library semantic version (kept in sync with VERSION file & release workflow)
  version := v!"0.1.3"

-- Alloy facets for embedded C
module_data alloy.c.o.export : FilePath
module_data alloy.c.o.noexport : FilePath

@[default_target] lean_lib WebSocket where
  roots := #[`WebSocket]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `module.alloy.c.o.export]
    else
      #[Module.oNoExportFacet, `module.alloy.c.o.noexport]
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs

lean_exe echoServer where
  root := `Examples.EchoServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe advancedEchoServer where
  root := `Examples.AdvancedEchoServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe enhancedEchoServer where
  root := `Examples.EnhancedEchoServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe chatServer where
  root := `Examples.Chat.ChatServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe echoClient where
  root := `Examples.EchoClient
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe tlsEchoServer where
  root := `Examples.TLSEchoServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
lean_exe simpleTLSServer where
  root := `Examples.SimpleTLSServer
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
@[test_driver]
lean_exe tests where
  root := `WebSocket.Tests.Main
  moreLeancArgs := commonLeancArgs
  moreLinkArgs := commonLinkArgs
