/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import Lake
open Lake DSL System

/-!
TLS (OpenSSL) support — runtime detection via dlopen.

TLS is always available at build time. At runtime, the library tries to load
`libssl.so` / `libcrypto.so` dynamically — if OpenSSL is installed on the host
the TLS functions work; otherwise they return a descriptive error.

No build-time toggle, no rebuild needed. Just install OpenSSL to enable TLS:

    # Debian / Ubuntu
    sudo apt install libssl-dev

    # or point LD_LIBRARY_PATH to a custom OpenSSL prefix
    LD_LIBRARY_PATH=/path/to/openssl/lib ./your-server

For production use, prefer validated TLS enablement or a TLS-terminating reverse
proxy instead of running unencrypted WebSocket traffic directly.
-/

def commonLeancArgs : Array String := #["-fPIC"]

-- -ldl is needed for dlopen (runtime OpenSSL loading)
def commonLinkArgs : Array String := #["-ldl"]

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
