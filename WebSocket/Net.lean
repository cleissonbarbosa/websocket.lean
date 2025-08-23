import WebSocket

namespace WebSocket.Net

open WebSocket

def ListenerHandle := UInt32
def SocketFD := UInt32

@[extern "ws_listen"] opaque c_listen (port : @& Nat) : IO ListenerHandle
@[extern "ws_accept"] opaque c_accept (lh : @& ListenerHandle) : IO SocketFD
@[extern "ws_close"] opaque c_close (fd : @& SocketFD) : IO Unit
@[extern "ws_recv_bytes"] opaque c_recv (fd : @& SocketFD) (max : @& Nat) : IO ByteArray
@[extern "ws_send_bytes"] opaque c_send (fd : @& SocketFD) (ba : @& ByteArray) : IO Nat

def openServer (port : Nat) : IO ListenerHandle := c_listen port
def accept (lh : ListenerHandle) : IO SocketFD := c_accept lh
def close (fd : SocketFD) : IO Unit := c_close fd

def mkTransportFromFd (fd : SocketFD) : Transport :=
{ recv := c_recv fd 4096,
	send := fun ba => do
		let _ ← c_send fd ba
		pure (),
	closed := pure false,
	close := c_close fd }

private def readUpgrade (t : Transport) (fuel : Nat) (acc : ByteArray := ByteArray.empty) : IO (Option HandshakeResponse) := do
	if fuel = 0 then return none
	let chunk ← t.recv
	if chunk.size = 0 then return none
	let acc := acc ++ chunk
	let s := String.fromUTF8! acc
	if s.contains "\r\n\r\n" then
		return WebSocket.upgradeRaw s
	else
		readUpgrade t (fuel - 1) acc

def acceptAndUpgrade (lh : ListenerHandle) : IO (Option Conn) := do
	let fd ← accept lh
	let t := mkTransportFromFd fd
	match ← readUpgrade t 32 with
	| some resp =>
			let headerLines := resp.headers.map (fun (k, v) => s!"{k}: {v}\r\n")
			let responseStr := s!"HTTP/1.1 {resp.status} {resp.reason}\r\n" ++ String.join headerLines ++ "\r\n"
			t.send (ByteArray.mk responseStr.toUTF8.data)
			pure (some { transport := t, assembler := {}, pingState := {} })
	| none => pure none

def upgradeOnExisting (t : Transport) : IO (Option Conn) := do
	match ← readUpgrade t 16 with
	| some resp =>
			let headerLines := resp.headers.map (fun (k, v) => s!"{k}: {v}\r\n")
			let responseStr := s!"HTTP/1.1 {resp.status} {resp.reason}\r\n" ++ String.join headerLines ++ "\r\n"
			t.send (ByteArray.mk responseStr.toUTF8.data)
			pure (some { transport := t, assembler := {}, pingState := {} })
	| none => pure none

def sendText (c : Conn) (s : String) : IO Unit := do
	let payload := ByteArray.mk s.toUTF8.data
	let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload := payload }
	c.transport.send (encodeFrame f)

partial def recvLoop (c : Conn) : IO Unit := do
	let bytes ← c.transport.recv
	if bytes.size = 0 then
		pure ()
	else
		let (c', events) ← WebSocket.handleIncoming c bytes
		for (opc, payload) in events do
			if opc = .text then
				let f : Frame := { header := { opcode := .text, masked := false, payloadLen := payload.size }, payload := payload }
				c'.transport.send (encodeFrame f)
		recvLoop c'

end WebSocket.Net
