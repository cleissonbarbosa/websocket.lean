import WebSocket.Core.Types
import WebSocket.UTF8

namespace WebSocket

/-- Close codes per RFC 6455 (subset). -/
inductive CloseCode
  | normalClosure | goingAway | protocolError | unsupportedData | noStatusRcvd
  | abnormalClosure | invalidPayload | policyViolation | messageTooBig
  | mandatoryExt | internalError | tlsHandshake
  deriving Repr, DecidableEq

namespace CloseCode
  def toNat : CloseCode → Nat
    | normalClosure => 1000 | goingAway => 1001 | protocolError => 1002 | unsupportedData => 1003
    | noStatusRcvd => 1005 | abnormalClosure => 1006 | invalidPayload => 1007 | policyViolation => 1008
    | messageTooBig => 1009 | mandatoryExt => 1010 | internalError => 1011 | tlsHandshake => 1015
  def ofNat? (n : Nat) : Option CloseCode :=
    match n with
    | 1000 => some .normalClosure | 1001 => some .goingAway | 1002 => some .protocolError
    | 1003 => some .unsupportedData | 1005 => some .noStatusRcvd | 1006 => some .abnormalClosure
    | 1007 => some .invalidPayload | 1008 => some .policyViolation | 1009 => some .messageTooBig
    | 1010 => some .mandatoryExt | 1011 => some .internalError | 1015 => some .tlsHandshake
    | _ => none
end CloseCode

/-- Information extracted from a close frame -/
structure CloseInfo where
  code : Option CloseCode -- Some indicates code present (must be at least 2 bytes)
  reason : String := ""
  deriving Repr

/-- Parse close frame payload with enhanced UTF-8 validation -/
def parseClosePayload (payload : ByteArray) : Option CloseInfo :=
  if payload.size = 0 then some { code := none }
  else if payload.size = 1 then none -- invalid
  else
    let c := ((payload.get! 0).toNat <<< 8) + (payload.get! 1).toNat
    match CloseCode.ofNat? c with
    | none =>
      if c >= 3000 && c <= 4999 then
        let rest := payload.extract 2 payload.size
        if validateUTF8 rest then
          match String.fromUTF8? rest with
          | some reason => some { code := none, reason }
          | none => none
        else none
      else none
    | some cc =>
      let rest := payload.extract 2 payload.size
      if validateUTF8 rest then
        match String.fromUTF8? rest with
        | some reason =>
          if reason.all (fun c => c.toNat >= 32 || c == '\t' || c == '\n' || c == '\r') then
            some { code := some cc, reason }
          else none
        | none => none
      else none

end WebSocket
