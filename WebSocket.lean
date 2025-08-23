-- Root module re-exporting public API (refactored).
import WebSocket.Core.Types
import WebSocket.Core.Frames
import WebSocket.Handshake
import WebSocket.Subprotocols
import WebSocket.Extensions
import WebSocket.Upgrade
import WebSocket.Close
import WebSocket.Assembler
import WebSocket.Connection
import WebSocket.Random
import WebSocket.KeepAlive
import WebSocket.UTF8
import WebSocket.Crypto.Base64
import WebSocket.Crypto.SHA1
import WebSocket.HTTP

namespace WebSocket
-- All definitions already live in this namespace across files; nothing to re-export explicitly.
end WebSocket
