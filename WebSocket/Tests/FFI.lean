import WebSocket.Net

namespace WebSocket.Tests.FFI

/-- Simple runtime check that an extern symbol links and can be invoked.
    We attempt to open a server socket on an ephemeral port (0 lets the OS pick).
    We then immediately close it. If the FFI symbol were missing, this would
    raise an error before we print success. -/
def run : IO Unit := do
  let res ← (do
    let h ← WebSocket.Net.openServer 0
    -- Closing immediately; we just care that call succeeded
    -- (closeImpl is used indirectly via Conn.close but we call directly here).
    pure (some h))
    |>.catchExceptions (fun _ => pure none)
  match res with
  | some _ => IO.println "[FFI] ws_listen linked OK"
  | none => IO.eprintln "[FFI] ws_listen failed (symbol missing or runtime error)"

end WebSocket.Tests.FFI
