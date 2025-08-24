import Lake
open Lake DSL System

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
  moreLeancArgs := #["-fPIC"]

lean_exe echoServer where
  root := `Examples.EchoServer
  moreLeancArgs := #["-fPIC"]
lean_exe advancedEchoServer where
  root := `Examples.AdvancedEchoServer
  moreLeancArgs := #["-fPIC"]
lean_exe enhancedEchoServer where
  root := `Examples.EnhancedEchoServer
  moreLeancArgs := #["-fPIC"]
lean_exe chatServer where
  root := `Examples.Chat.ChatServer
  moreLeancArgs := #["-fPIC"]
lean_exe echoClient where
  root := `Examples.EchoClient
  moreLeancArgs := #["-fPIC"]
@[test_driver]
lean_exe tests where
  root := `WebSocket.Tests.Main
  moreLeancArgs := #["-fPIC"]
