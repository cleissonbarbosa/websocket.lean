import WebSocket.Handshake

namespace WebSocket

/-- WebSocket extension configuration -/
structure ExtensionConfig where
  name : String
  parameters : List (String × Option String) := []
  deriving Repr, DecidableEq

/-- Configuration for extension negotiation -/
structure ExtensionNegotiationConfig where
  /-- Available extensions server supports -/
  supportedExtensions : List ExtensionConfig := []
  /-- Custom negotiation function -/
  negotiator : Option (List ExtensionConfig → List ExtensionConfig → List ExtensionConfig) := none

/-- Parse Sec-WebSocket-Extensions header -/
def parseExtensions (headerValue : String) : List ExtensionConfig :=
  let extensions := headerValue.splitOn "," |>.map (fun s => s.trim) |>.filter (fun s => s.length > 0)
  extensions.filterMap (fun ext =>
    let parts := ext.splitOn ";" |>.map (fun s => s.trim)
    match parts with
    | [] => none
    | name :: paramStrs =>
      let params := paramStrs.filterMap (fun p =>
        let kv := p.splitOn "=" |>.map (fun s => s.trim)
        match kv with
        | [k] => some (k, none)
        | [k, v] => some (k, some v)
        | _ => none)
      some { name, parameters := params })

/-- Default extension negotiator (conservative: only accept what server explicitly supports) -/
def defaultExtensionNegotiator (serverSupported clientRequested : List ExtensionConfig) : List ExtensionConfig :=
  clientRequested.filter (fun req =>
    serverSupported.any (fun sup => sup.name = req.name))

/-- Negotiate extensions based on configuration -/
def negotiateExtensions (config : ExtensionNegotiationConfig) (clientExtensions : List ExtensionConfig) : List ExtensionConfig :=
  let negotiator := config.negotiator.getD defaultExtensionNegotiator
  negotiator config.supportedExtensions clientExtensions

/-- Format extensions for response header -/
def formatExtensions (extensions : List ExtensionConfig) : String :=
  String.intercalate ", " (extensions.map (fun ext =>
    let params := String.intercalate "; " (ext.parameters.map (fun (k, v?) =>
      match v? with
      | none => k
      | some v => s!"{k}={v}"))
    if params.length > 0 then s!"{ext.name}; {params}" else ext.name))

end WebSocket
