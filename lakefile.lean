import Lake
open Lake DSL System

package «websocket» where
  srcDir := "."
  -- Library semantic version (kept in sync with VERSION file & release workflow)
  version := v!"0.1.0"

def detectHost : IO (String × String) := do
  let osRaw ← IO.Process.run {cmd := "uname", args := #["-s"]}
  let archRaw ← IO.Process.run {cmd := "uname", args := #["-m"]}
  let os :=
    if osRaw.trim == "Darwin" then "macos"
    else if osRaw.trim == "Linux" then "linux" else osRaw.trim.toLower
  let arch :=
    match archRaw.trim with
    | "x86_64" | "amd64" => "x86_64"
    | "aarch64" | "arm64" => "arm64"
    | other => other
  pure (os, arch)

-- The legacy direct link args replaced by proper Lake target objects.
def wsLinkArgs : Array String := #[] -- kept for backward compatibility (unused now)

/-! Lake integration for the C helper code.

We model the C source as an `input_file`, compile it to an object (`target`),
and also package it as a static library via `extern_lib` (useful if multiple
executables link it or for downstream packaging). Lean targets then depend on
the object via `moreLinkObjs`. -/

input_file ws_socket.c where
  path := "c/ws_socket.c"
  text := true

target ws_socket.o pkg : FilePath := do
  let srcJob ← ws_socket.c.fetch
  let oFile := pkg.buildDir / "c" / "ws_socket.o"
  let flags := #[
    "-std=gnu11", "-O2", "-fPIC", "-DNDEBUG", "-D_GNU_SOURCE", "-D_DEFAULT_SOURCE", "-DLEAN_FFI",
    "-I", (← getLeanIncludeDir).toString, "-I", (pkg.dir / "c").toString
  ]
  buildO oFile srcJob flags

extern_lib libwssocket pkg := do
  let o ← ws_socket.o.fetch
  let name := nameToStaticLib "wssocket"
  buildStaticLib (pkg.staticLibDir / name) #[o]

@[default_target] lean_lib WebSocket where
  roots := #[`WebSocket]
  precompileModules := true
  moreLinkObjs := #[ws_socket.o]


script build_c_modules do
  let (os,arch) ← detectHost
  let prebuilt := s!"prebuilt/{os}-{arch}/ws_socket.o"
  let prebuiltExists ← (System.FilePath.mk prebuilt).pathExists
  let targetObj := System.FilePath.mk "c/ws_socket.o"
  if prebuiltExists then
    IO.println s!"[prebuilt] Using {prebuilt} -> {targetObj}"
    -- Copy (overwrite) so linker argument stays constant
    IO.FS.createDirAll (System.FilePath.mk "c")
    let bytes ← IO.FS.readBinFile prebuilt
    IO.FS.writeBinFile targetObj bytes
    pure 0
  else
    IO.println s!"[build] No prebuilt object for {os}-{arch}; compiling C fallback"
    let wd ← IO.currentDir
    let srcDir := wd / "c"
    let leanInc := (← getLeanSysroot) / "include"
    let cFile := "ws_socket.c"
    let src := srcDir / cFile
    IO.FS.createDirAll srcDir
    let obj := targetObj
    let cmd := s!"cc -std=gnu11 -O2 -fPIC -DNDEBUG -D_GNU_SOURCE -D_DEFAULT_SOURCE -DLEAN_FFI -I{leanInc} -I{srcDir} -c {src} -o {obj}"
    IO.println s!"[C] {cmd}"
    -- Run compiler directly (avoid bashisms like `set -o pipefail` for dash / POSIX sh on CI).
    try
      let _ ← IO.Process.run { cmd := "sh", args := #["-c", cmd] }
      pure 0
    catch e =>
      IO.eprintln s!"[error] C compilation failed: {e}"
      pure 1

/-!
Convenience alias: `lake script run build_c`
Performs the same steps as `build_c_modules` (try prebuilt, else compile).
Invoke with `lake script run build_c` (Lake subcommand requires `run`).
-/
script build_c do
  let (os,arch) ← detectHost
  let prebuilt := s!"prebuilt/{os}-{arch}/ws_socket.o"
  let prebuiltExists ← (System.FilePath.mk prebuilt).pathExists
  let targetObj := System.FilePath.mk "c/ws_socket.o"
  if prebuiltExists then
    IO.println s!"[prebuilt] Using {prebuilt} -> {targetObj}"
    IO.FS.createDirAll (System.FilePath.mk "c")
    let bytes ← IO.FS.readBinFile prebuilt
    IO.FS.writeBinFile targetObj bytes
    pure 0
  else
    IO.println s!"[build] No prebuilt object for {os}-{arch}; compiling C fallback"
    let wd ← IO.currentDir
    let srcDir := wd / "c"
    let leanInc := (← getLeanSysroot) / "include"
    let cFile := "ws_socket.c"
    let src := srcDir / cFile
    IO.FS.createDirAll srcDir
    let obj := targetObj
    let cmd := s!"cc -std=gnu11 -O2 -fPIC -DNDEBUG -D_GNU_SOURCE -D_DEFAULT_SOURCE -DLEAN_FFI -I{leanInc} -I{srcDir} -c {src} -o {obj}"
    IO.println s!"[C] {cmd}"
    try
      let _ ← IO.Process.run { cmd := "sh", args := #["-c", cmd] }
      pure 0
    catch e => IO.eprintln s!"[error] C compilation failed: {e}"; pure 1

/-! Script to only fetch/copy a prebuilt object (no compilation). Returns 0 if available, 1 if not. -/
script use_prebuilt do
  let (os,arch) ← detectHost
  let prebuilt := System.FilePath.mk s!"prebuilt/{os}-{arch}/ws_socket.o"
  if ← prebuilt.pathExists then
    IO.println s!"[prebuilt] Found {prebuilt}"
    IO.FS.createDirAll (System.FilePath.mk "c")
    let bytes ← IO.FS.readBinFile prebuilt
    IO.FS.writeBinFile (System.FilePath.mk "c/ws_socket.o") bytes
    pure 0
  else
    IO.eprintln s!"[prebuilt] Not found: {prebuilt}"
    pure 1

lean_exe echoServer where
  root := `Examples.EchoServer
  moreLinkObjs := #[ws_socket.o]
lean_exe advancedEchoServer where
  root := `Examples.AdvancedEchoServer
  moreLinkObjs := #[ws_socket.o]
lean_exe enhancedEchoServer where
  root := `Examples.EnhancedEchoServer
  moreLinkObjs := #[ws_socket.o]
lean_exe chatServer where
  root := `Examples.Chat.ChatServer
  moreLinkObjs := #[ws_socket.o]
lean_exe echoClient where
  root := `Examples.EchoClient
  moreLinkObjs := #[ws_socket.o]
lean_exe tests where
  root := `WebSocket.Tests.Main
  moreLinkObjs := #[ws_socket.o]
