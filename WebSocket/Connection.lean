import WebSocket.Core.Types
import WebSocket.Core.Frames
import WebSocket.Assembler
import WebSocket.KeepAlive

namespace WebSocket

/-- Abstract transport interface (stub). -/
structure Transport where
  recv : IO ByteArray
  send : ByteArray → IO Unit
  closed : IO Bool := pure false
  close : IO Unit := pure ()

/-- WebSocket connection state -/
structure Conn where
  transport : Transport
  assembler : AssemblerState
  pingState : PingState

/-- Create text frame -/
def makeTextFrame (s : String) : Frame :=
  let payload := ByteArray.mk s.toUTF8.data
  { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload }

/-- Create pong frame -/
def makePongFrame (payload : ByteArray) : Frame :=
  { header := { opcode := .pong, masked := false, payloadLen := payload.size }, payload }

/-- Auto-generate pong responses for pings -/
def autoPong (frames : List (OpCode × ByteArray)) : List Frame :=
  frames.foldl (fun acc (opc,pl) => if opc = .ping then acc ++ [makePongFrame pl] else acc) []

/-- Handle incoming data (single-frame naive) -/
def handleIncoming (c : Conn) (bytes : ByteArray) : IO (Conn × List (OpCode × ByteArray)) := do
  match decodeFrame bytes with
  | none => pure (c, [])
  | some res =>
    match processFrame c.assembler res.frame with
    | .violation _ => pure (c, [])
    | .continue st' => pure ({ c with assembler := st' }, [])
    | .message opc data st' =>
        let frames := [(opc, data)]
        if opc = .ping then
          let pong := makePongFrame data
          c.transport.send (encodeFrame pong)
          pure ({ c with assembler := st' }, frames ++ [(.pong, data)])
        else
          pure ({ c with assembler := st' }, frames)

/-- Incremental connection loop state (buffering undecoded bytes). -/
structure LoopState where
  conn : Conn
  buffer : ByteArray := ByteArray.empty

/-- Attempt to decode as many frames as possible from current buffer. -/
def drainBuffer (ls : LoopState) : (LoopState × List (OpCode × ByteArray)) :=
  let rec loop (fuel : Nat) (buf : ByteArray) (acc : List (OpCode × ByteArray)) (c : Conn) : (ByteArray × Conn × List (OpCode × ByteArray)) :=
    match fuel with
    | 0 => (buf, c, acc.reverse)
    | Nat.succ fuel' =>
        match decodeFrame buf with
        | none => (buf, c, acc.reverse)
        | some r =>
            match processFrame c.assembler r.frame with
            | .violation _ => (r.rest, c, acc.reverse)
            | .continue st' => loop fuel' r.rest acc ({ c with assembler := st' })
            | .message opc data st' => loop fuel' r.rest ((opc,data)::acc) ({ c with assembler := st' })
  let fuel := ls.buffer.size.succ
  let (rest, c', events) := loop fuel ls.buffer [] ls.conn
  ({ ls with conn := c', buffer := rest }, events)

/-- Perform one I/O read then drain buffer. -/
def stepIO (ls : LoopState) : IO (LoopState × List (OpCode × ByteArray)) := do
  let bytes ← ls.conn.transport.recv
  if bytes.size = 0 then
    pure (ls, [])
  else
    let ls' := { ls with buffer := ls.buffer ++ bytes }
    let (ls'', evs) := drainBuffer ls'
    for (opc,pl) in evs do
      if opc = .ping then
        ls''.conn.transport.send (encodeFrame (makePongFrame pl))
    pure (ls'', evs)

partial def runLoop (ls : LoopState) (maxSteps : Nat := 1000) : IO LoopState := do
  if maxSteps = 0 then return ls else
  let closed ← ls.conn.transport.closed
  if closed then return ls else
  let (ls', _) ← stepIO ls
  runLoop ls' (maxSteps - 1)

end WebSocket
