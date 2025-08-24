/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-- Keepalive strategy configuration -/
inductive KeepAliveStrategy
  | disabled
  | pingOnly (interval : Nat)
  | pingPong (interval : Nat) (maxMissed : Nat)
  deriving Repr

/-- Enhanced ping scheduler state with configurable strategy -/
structure PingState where
  lastPing : Nat := 0
  lastPong : Nat := 0
  interval : Nat := 30
  maxMissedPongs : Nat := 3
  missedPongs : Nat := 0
  strategy : KeepAliveStrategy := .pingPong 30 3
  deriving Repr

def duePing (t : Nat) (ps : PingState) : Bool :=
  match ps.strategy with
  | .disabled => false
  | .pingOnly interval => t - ps.lastPing ≥ interval
  | .pingPong interval _ => t - ps.lastPing ≥ interval

def registerPing (t : Nat) (ps : PingState) : PingState :=
  match ps.strategy with
  | .disabled => ps
  | .pingOnly _ => { ps with lastPing := t }
  | .pingPong _ _ => { ps with lastPing := t, missedPongs := ps.missedPongs + 1 }

def registerPong (t : Nat) (ps : PingState) : PingState :=
  match ps.strategy with
  | .disabled => ps
  | .pingOnly _ => { ps with lastPong := t }
  | .pingPong _ _ => { ps with lastPong := t, missedPongs := 0 }

def connectionDead (ps : PingState) : Bool :=
  match ps.strategy with
  | .disabled | .pingOnly _ => false
  | .pingPong _ maxMissed => ps.missedPongs > maxMissed

def mkPingState (strategy : KeepAliveStrategy) : PingState :=
  match strategy with
  | .disabled => { strategy := .disabled, interval := 0 }
  | .pingOnly interval => { strategy := .pingOnly interval, interval := interval }
  | .pingPong interval maxMissed => { strategy := .pingPong interval maxMissed, interval := interval, maxMissedPongs := maxMissed }

end WebSocket
