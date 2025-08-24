import WebSocket
import WebSocket.Log
import WebSocket.Server
import WebSocket.Server.Events
import WebSocket.Server.Async
import WebSocket.Server.Messaging
import WebSocket.Server.KeepAlive

open WebSocket
open WebSocket.Server
open WebSocket.Server.Events
open WebSocket.Server.Async
open WebSocket.Server.Messaging

/-!
# Chat Server Example

Fully working multi-client chat example built on the Async server + EventManager.

Features:
* Broadcast text messages.
* `/nick NewName` to change nickname.
* Join / leave status messages.
* `/who` lists currently connected users (nicknames).
* `/me action` sends an action / emote line.
* Message length limit (2000 chars) with feedback.
* Structured logging via module `Chat`.

Simplifications:
* No persistence.
* Single global room (no channels).
* Failed sends simply drop the connection at lower layers.

Testing: open multiple WebSocket clients (e.g. `wscat -c ws://localhost:9101`) then use `/nick`.
-/

namespace Examples.Chat

structure ChatUser where
  id : Nat
  nickname : String := "anon"
  deriving Repr

structure ChatState where
  users : List ChatUser := []


/-- Ensure user exists (create with default nickname if missing). -/
private def ensureUser (st : ChatState) (id : Nat) : ChatState :=
  if st.users.any (·.id = id) then st else { st with users := { id, nickname := s!"user{id}" } :: st.users }

/-- Set or replace nickname. -/
private def setNick (st : ChatState) (id : Nat) (nick : String) : ChatState :=
  let newUsers := st.users.filter (·.id ≠ id)
  { st with users := { id, nickname := nick } :: newUsers }

private def findNick? (st : ChatState) (id : Nat) : Option String :=
  (st.users.find? (·.id = id)) |>.map (·.nickname)

private def userList (st : ChatState) : String :=
  st.users.map (·.nickname) |>.reverse |>.intersperse ", " |>.foldl (· ++ ·) ""

/-- Broadcast helper (text). -/
private def bcast (asyncRef : IO.Ref AsyncServerState) (st : ChatState) (msg : String) : IO ChatState := do
  let srv ← asyncRef.get
  let newBase ← broadcastText srv.base msg
  let srv' := { srv with base := newBase }
  asyncRef.set srv'
  pure st

/-- Send only to one client. -/
private def sendTo (asyncRef : IO.Ref AsyncServerState) (st : ChatState) (id : Nat) (msg : String) : IO ChatState := do
  let srv ← asyncRef.get
  let newBase ← sendText srv.base id msg
  let srv' := { srv with base := newBase }
  asyncRef.set srv'
  pure st

/-- Handle a textual command. Returns (newState, consumed?) where consumed indicates whether to suppress broadcast. -/
private def handleCommand (asyncRef : IO.Ref AsyncServerState) (st : ChatState) (id : Nat) (raw : String) : IO (ChatState × Bool) := do
  if raw.startsWith "/nick " then
    let nick := raw.drop 6 |>.trim
    if nick.isEmpty then
      let st ← sendTo asyncRef st id "Usage: /nick <new-name>"
      return (st, true)
    else
      let old := (findNick? st id).getD s!"user{id}"
      let st := setNick st id nick
      let st ← bcast asyncRef st s!"* {old} is now {nick} *"
      return (st, true)
  else if raw.startsWith "/who" then
    let st ← sendTo asyncRef st id s!"Users: {userList st}"
    return (st, true)
  else if raw.startsWith "/me " then
    let action := raw.drop 4
    let nick := (findNick? st id).getD s!"user{id}"
    let st ← bcast asyncRef st s!"* {nick} {action} *"
    return (st, true)
  else
    pure (st, false)

/-- Process a user text message. -/
private def handleUserMessage (asyncRef : IO.Ref AsyncServerState) (st : ChatState) (id : Nat) (txt : String) : IO ChatState := do
  -- Basic validation
  if txt.length > 2000 then
    let st ← sendTo asyncRef st id "Message too long (limit 2000)."
    return st
  -- Command?
  let (st, consumed) ← handleCommand asyncRef st id txt
  if consumed then
    return st
  let nick := (findNick? st id).getD s!"user{id}"
  let st ← bcast asyncRef st s!"[{nick}] {txt}"
  pure st

/-- Main event handler. -/
private def makeHandler (asyncRef : IO.Ref AsyncServerState) (stateRef : IO.Ref ChatState) : EventHandler :=
  fun ev => do
  match ev with
  | .connected id addr => do
    WebSocket.logMod .info "Chat" s!"Connection {id} from {addr}"
    stateRef.modify fun st => ensureUser st id
    let st ← stateRef.get
    let nick := (findNick? st id).getD s!"user{id}"
    let st ← bcast asyncRef st s!"* {nick} joined *"
    stateRef.set st
  | .disconnected id reason => do
    WebSocket.logMod .info "Chat" s!"{id} left: {reason}"
    let st ← stateRef.get
    let nick := (findNick? st id).getD s!"user{id}"
    let st := { st with users := st.users.filter (·.id ≠ id) }
    let st ← bcast asyncRef st s!"* {nick} left *"
    stateRef.set st
  | .message id .text payload => do
    let txt := (String.fromUTF8? payload).getD "<invalid utf8>"
    let st ← stateRef.get
    let st ← handleUserMessage asyncRef st id txt
    stateRef.set st
  | .message id .binary payload =>
    WebSocket.logMod .info "Chat" s!"Ignoring binary from {id} ({payload.size} bytes)"
  | .message id .ping _ =>
    WebSocket.logMod .debug "Chat" s!"Ping from {id}"
  | .message id .pong _ =>
    WebSocket.logMod .debug "Chat" s!"Pong from {id}"
  | .message id .close _ =>
    WebSocket.logMod .info "Chat" s!"Close frame received from {id}"
  | .message id .continuation _ =>
    WebSocket.logMod .debug "Chat" s!"Ignoring continuation frame from {id}"
  | .error id err =>
    WebSocket.logMod .error "Chat" s!"Error {id}: {err}"

/-- Chat server entrypoint. -/
def main : IO Unit := do
  let config : ServerConfig := {
    port := 9101,
    maxConnections := 200,
    pingInterval := 20,
    maxMissedPongs := 2,
    maxMessageSize := 512 * 1024,
    subprotocols := ["chat"]
  }
  -- Estado base async
  let async0 ← mkAsyncServer config
  let startedBase ← WebSocket.Server.Accept.start async0.base
  let asyncStarted := { async0 with base := startedBase }
  -- Nosso ChatState
  let asyncRef ← IO.mkRef asyncStarted
  let stateRef ← IO.mkRef ({ : ChatState })
  WebSocket.logMod .info "Chat" s!"Chat server started on port {config.port}. Commands: /nick /who /me"
  -- Executa loop assíncrono infinito atualizando asyncRef e usando handler de chat.
  runAsyncServerUpdating asyncRef (makeHandler asyncRef stateRef)

end Examples.Chat

-- Exe root
def main : IO Unit := Examples.Chat.main
