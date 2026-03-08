/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-- Backpressure configuration (lightweight). -/
structure BackpressureConfig where
  maxInFlight : Nat := 1000
  highWatermark : Nat := 800
  lowWatermark : Nat := 200
  deriving Inhabited

/-- Internal per-connection backpressure state. -/
structure BpConn where
  inFlight : Nat := 0
  backpressured : Bool := false
  deriving Inhabited

/-- Global registry of backpressure states keyed by connection id. -/
initialize bpRegistry : IO.Ref (List (Nat × BpConn)) ← IO.mkRef ([] : List (Nat × BpConn))

private def findBp (l : List (Nat × BpConn)) (id : Nat) : Option BpConn :=
  match l.find? (fun (k,_) => k = id) with
  | some (_, v) => some v
  | none => none

private def upsertBp (l : List (Nat × BpConn)) (id : Nat) (v : BpConn) : List (Nat × BpConn) :=
  let rec go (ls : List (Nat × BpConn)) : List (Nat × BpConn) :=
    match ls with
    | [] => [(id, v)]
    | (k,old) :: rest => if k = id then (id, v) :: rest else (k,old) :: go rest
  go l

/-- Register a connection with default state. -/
def bpRegister (connId : Nat) : IO Unit := do
  let reg ← bpRegistry.get
  let present := (findBp reg connId).isSome
  if !present then
    bpRegistry.set ((connId, default) :: reg)
  else
    pure ()

/-- Unregister a connection. -/
def bpUnregister (connId : Nat) : IO Unit := do
  let reg ← bpRegistry.get
  bpRegistry.set (reg.filter (fun (k,_) => k ≠ connId))

/-- Mark a send attempt; returns whether it is allowed. -/
def bpBeforeSend (connId : Nat) (cfg : BackpressureConfig := {}) : IO Bool := do
  let reg ← bpRegistry.get
  let cur := (findBp reg connId).getD default
  let newInFlight := cur.inFlight + 1
  let bp := cur.backpressured || (newInFlight ≥ cfg.highWatermark)
  let new : BpConn := { inFlight := newInFlight, backpressured := bp }
  bpRegistry.set (upsertBp reg connId new)
  pure (newInFlight ≤ cfg.maxInFlight)

/-- Mark completion of a send attempt. -/
def bpAfterSend (connId : Nat) (cfg : BackpressureConfig := {}) : IO Unit := do
  let reg ← bpRegistry.get
  let cur := (findBp reg connId).getD default
  let dec := if cur.inFlight = 0 then 0 else cur.inFlight - 1
  let shouldRelease := cur.backpressured && dec ≤ cfg.lowWatermark
  let new : BpConn := { inFlight := dec, backpressured := if shouldRelease then false else cur.backpressured }
  bpRegistry.set (upsertBp reg connId new)

/-- Wait until all connections have zero in-flight sends, up to timeoutMs. -/
def bpWaitForDrain (timeoutMs : Nat := 5000) : IO Bool := do
  let start ← IO.monoNanosNow
  let timeoutNs := timeoutMs * 1000000
  let rec loop (attempts : Nat) : IO Bool := do
    let reg ← bpRegistry.get
    let anyBusy := reg.any (fun (_,st) => st.inFlight > 0)
    if !anyBusy then
      pure true
    else if attempts ≥ 1000 then
      pure false
    else
      let now ← IO.monoNanosNow
      if now - start ≥ timeoutNs then
        pure false
      else
        IO.sleep 10
        loop (attempts + 1)
  loop 0

end WebSocket
