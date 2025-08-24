/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-! ### Levels -/
inductive LogLevel | trace | debug | info | warn | error deriving Repr, DecidableEq

instance : ToString LogLevel where
  toString
    | .trace => "TRACE"
    | .debug => "DEBUG"
    | .info  => "INFO"
    | .warn  => "WARN"
    | .error => "ERROR"

/-! ### Structured entry -/
structure LogEntry where
  level        : LogLevel
  timestampIso : String          -- wall-clock UTC ISO8601 (ms precision)
  module?      : Option String := none
  message      : String
  deriving Repr

/-! ### Logger interface -/
structure Logger where
  /-- Core logging function receiving a structured entry. -/
  log : LogEntry → IO Unit
  deriving Inhabited

/-! Global start time (monotonic). Using `initialize` ensures it runs exactly once. -/
initialize startTimeMs : Nat ← IO.monoMsNow

/-! ANSI color helpers (very small; avoid dependency). -/
namespace Internal
  def colored (code : String) (s : String) : IO String := do
    let env ← IO.getEnv "NO_COLOR"
    if env.isSome then
      pure s
    else
      pure s!"\x1b[{code}m{s}\x1b[0m"

  def levelTag (lvl : LogLevel) : IO String := do
    let base := toString lvl
    match lvl with
    | .trace => colored "90" base
    | .debug => colored "34" base
    | .info  => colored "32" base
    | .warn  => colored "33" base
    | .error => colored "31" base
end Internal

open Internal

/-! ### Default logger formatting
Format:
  [ +123ms ][LEVEL][Module] message
Module part omitted if absent.
-/
def defaultLogger : Logger :=
  { log := fun e => do
      let lvlTag ← levelTag e.level
      let modPart := match e.module? with
        | some m => s!"[{m}] "
        | none   => ""
        IO.println s!"{e.timestampIso} [{lvlTag}] {modPart}{e.message}" }

/-! Global mutable logger reference. -/
initialize currentLoggerRef : IO.Ref Logger ← IO.mkRef defaultLogger

/-- Replace the global logger. -/
def setLogger (l : Logger) : IO Unit := currentLoggerRef.set l

/-- Retrieve the current global logger. -/
def getLogger : IO Logger := currentLoggerRef.get

/-! ### Helper constructors & public API -/

@[extern "ws_now_iso8601"]
opaque ws_now_iso8601 : IO String

private def mkEntry (lvl : LogLevel) (msg : String) (mod? : Option String) : IO LogEntry := do
  let iso ← ws_now_iso8601
  pure { level := lvl, timestampIso := iso, module? := mod?, message := msg }

/-- Core logging helper (no module). -/
def log (lvl : LogLevel) (msg : String) : IO Unit := do
  let logger ← getLogger
  logger.log (← mkEntry lvl msg none)

/-- Log with explicit module name. -/
def logMod (lvl : LogLevel) (module : String) (msg : String) : IO Unit := do
  let logger ← getLogger
  logger.log (← mkEntry lvl msg module)

/-! Convenience level-specific helpers (without or with module). -/
def trace (msg : String) : IO Unit := log .trace msg
def debug (msg : String) : IO Unit := log .debug msg
def info  (msg : String) : IO Unit := log .info  msg
def warn  (msg : String) : IO Unit := log .warn  msg
def error (msg : String) : IO Unit := log .error msg

def traceMod (module msg : String) : IO Unit := logMod .trace module msg
def debugMod (module msg : String) : IO Unit := logMod .debug module msg
def infoMod  (module msg : String) : IO Unit := logMod .info  module msg
def warnMod  (module msg : String) : IO Unit := logMod .warn  module msg
def errorMod (module msg : String) : IO Unit := logMod .error module msg

/-! ### Customization Examples

To produce JSON logs:

```
def jsonLogger : Logger := {
  log := fun e => IO.println <| Id.run <|
    let modField := match e.module? with | some m => s!",\"module\":\"{m}\"" | none => ""
  s!"{{\"ts\":\"{e.timestampIso}\",\"level\":\"{e.level}\",\"msg\":{String.quote e.message}{modField}}}"
}
-- setLogger jsonLogger
```

Users wanting wall-clock time can wrap a custom logger that queries the system clock (via
FFI or an external process) and substitutes a different timestamp field.
-/

end WebSocket
