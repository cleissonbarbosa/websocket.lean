/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket
import WebSocket.Extensions
open WebSocket

namespace WebSocket.Protocol

/-- Subprotocol negotiation strategy -/
inductive SubprotocolStrategy
  | firstMatch
  | priority (priorities : List String)
  | custom (selector : List String → List String → Option String)

/-- Subprotocol negotiation result -/
inductive NegotiationResult
  | selected (protocol : String)
  | none
  | error (reason : String)
  deriving Repr

/-- Negotiate subprotocol selection -/
def negotiateSubprotocol (clientProtocols : List String) (serverProtocols : List String) (strategy : SubprotocolStrategy := .firstMatch) : NegotiationResult :=
  if clientProtocols.isEmpty ∨ serverProtocols.isEmpty then
    .none
  else
    match strategy with
    | .firstMatch =>
        match clientProtocols.find? (serverProtocols.contains ·) with
        | some proto => .selected proto
        | .none => .none
    | .priority priorities =>
        match priorities.find? (fun p => clientProtocols.contains p ∧ serverProtocols.contains p) with
        | some proto => .selected proto
        | .none => .none
    | .custom selector =>
        match selector clientProtocols serverProtocols with
        | some proto => .selected proto
        | .none => .none

/-- Close code validation -/
def isValidCloseCode (code : Nat) : Bool :=
  (code >= 1000 ∧ code <= 1011) ∨
  (code >= 3000 ∧ code <= 3999) ∨
  (code >= 4000 ∧ code <= 4999)

end WebSocket.Protocol
