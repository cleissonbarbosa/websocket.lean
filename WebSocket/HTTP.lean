namespace WebSocket.HTTP

/-- Errors that can arise while parsing a raw HTTP request string for the WebSocket handshake. -/
inductive ParseError
  | emptyRequest
  | invalidRequestLine
  | invalidMethod (m : String)
  | noHeaders
  | malformedHeader (line : String)
  deriving Repr, DecidableEq

structure RequestLine where
  method : String
  resource : String
  version : String
  deriving Repr, DecidableEq

/-- Very small, line‑based parser (no folding, no obs-fold). Expects CRLF line endings. -/
partial def splitCRLF (s : String) : List String :=
  if s.isEmpty then [] else s.splitOn "\r\n"

private def parseRequestLine (line : String) : Except ParseError RequestLine :=
  let parts := line.splitOn " "
  match parts with
  | [m,r,v] => if m = "GET" then .ok { method := m, resource := r, version := v } else .error (.invalidMethod m)
  | _ => .error .invalidRequestLine

private def parseHeader (line : String) : Except ParseError (String × String) :=
  match line.splitOn ":" with
  | k :: rest =>
      let value := (String.intercalate ":" rest).trim
      .ok (k.trim, value)
  | _ => .error (.malformedHeader line)

/-- Parse a raw HTTP request into (RequestLine, headers). Stops at first empty line. -/
 def parse (raw : String) : Except ParseError (RequestLine × List (String × String)) := do
  let lines := splitCRLF raw
  if lines.length = 0 then throw .emptyRequest
  let rl ← parseRequestLine lines.head!
  let body := lines.tail!
  let rec gather (acc : List (String × String)) : List String → Except ParseError (List (String × String))
    | [] => .ok acc.reverse
    | l :: ls =>
        if l.isEmpty then .ok acc.reverse else
        match parseHeader l with
        | .ok h => gather (h :: acc) ls
        | .error e => .error e
  let hs ← gather [] body
  if hs.isEmpty then .error .noHeaders else
  return (rl, hs)

end WebSocket.HTTP
