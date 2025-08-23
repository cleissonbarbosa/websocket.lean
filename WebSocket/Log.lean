/-!
Simple pluggable logging abstraction to remove hardcoded IO.println calls.
Users can set a global logger ref or pass loggers explicitly (future work).
-/
namespace WebSocket

inductive LogLevel | trace | debug | info | warn | error deriving Repr, DecidableEq

instance : ToString LogLevel where
  toString
    | .trace => "TRACE"
    | .debug => "DEBUG"
    | .info  => "INFO"
    | .warn  => "WARN"
    | .error => "ERROR"

structure Logger where
  log : LogLevel → String → IO Unit := fun lvl msg => IO.println s!"[{lvl}] {msg}"

/-- Current default logger (can be threaded manually by users if they need custom behavior). -/
def defaultLogger : Logger := {}

/-- Placeholder setter (no-op). Future: maintain a global registry or require explicit passing. -/
def setLogger (_ : Logger) : IO Unit := pure ()

/-- Log using default logger. (Until a global mutable design is reintroduced.) -/
def log (lvl : LogLevel) (msg : String) : IO Unit := defaultLogger.log lvl msg

end WebSocket
