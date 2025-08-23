import Lake
open Lake DSL

package «websocket» where
  srcDir := "."

@[default_target] lean_lib WebSocket where
  roots := #[`WebSocket]
  precompileModules := true
  moreLinkArgs := #["c/ws_socket.o"]

script build_c_modules do
  let wd ← IO.currentDir
  let srcDir := wd / "c"
  let leanInc := (← getLeanSysroot) / "include"
  let cFile := "ws_socket.c"
  let src := srcDir / cFile
  let obj := srcDir / "ws_socket.o"
  -- naive: always rebuild (could check timestamps)
  let cmd := s!"cc -std=gnu11 -O3 -DNDEBUG -D_GNU_SOURCE -D_DEFAULT_SOURCE -DLEAN_FFI -I{leanInc} -I{srcDir} -c {src} -o {obj}"
  IO.println s!"[C] {cmd}"
  let _ ← IO.Process.run { cmd := "sh", args := #["-c", cmd] }
  pure 0

lean_exe echoServer where
  root := `WebSocket.Examples.EchoServer
  moreLinkArgs := #["c/ws_socket.o"]
lean_exe advancedEchoServer where
  root := `WebSocket.Examples.AdvancedEchoServer
  moreLinkArgs := #["c/ws_socket.o"]
lean_exe EnhancedEchoServer where
  root := `WebSocket.Examples.EnhancedEchoServer
  moreLinkArgs := #["c/ws_socket.o"]
lean_exe echoClient where
  root := `WebSocket.Examples.EchoClient
  moreLinkArgs := #["c/ws_socket.o"]
lean_exe tests where
  root := `WebSocket.Tests.Main
  moreLinkArgs := #["c/ws_socket.o"]
