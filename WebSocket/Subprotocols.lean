import WebSocket.Handshake

namespace WebSocket

/-- Configuration for subprotocol selection -/
structure SubprotocolConfig where
  /-- Available subprotocols in order of preference -/
  supported : List String := []
  /-- Whether to reject connections when no subprotocol match is found -/
  rejectOnNoMatch : Bool := false
  /-- Custom selection function (first match wins if none provided) -/
  selector : Option (List String → List String → Option String) := none

/-- Default subprotocol selector: pick first client protocol that server supports -/
def defaultSubprotocolSelector (serverSupported clientRequested : List String) : Option String :=
  clientRequested.findSome? (fun cp => if serverSupported.contains cp then some cp else none)

/-- Execute subprotocol selection using config -/
def selectSubprotocol (config : SubprotocolConfig) (clientProtocols : List String) : Option String :=
  let selector := config.selector.getD defaultSubprotocolSelector
  selector config.supported clientProtocols

end WebSocket
