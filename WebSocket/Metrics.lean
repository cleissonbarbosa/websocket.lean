/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-- Basic metrics for WebSocket server operations -/
structure Metrics where
  /-- Total connections accepted -/
  connectionsTotal : IO.Ref Nat
  /-- Currently active connections -/
  connectionsActive : IO.Ref Nat
  /-- Total frames received -/
  framesReceived : IO.Ref Nat
  /-- Total messages received -/
  messagesReceived : IO.Ref Nat
  /-- Total bytes received -/
  bytesReceived : IO.Ref Nat
  /-- Total bytes sent -/
  bytesSent : IO.Ref Nat
  /-- Total protocol violations detected -/
  violationsTotal : IO.Ref Nat
  /-- Handshake failures -/
  handshakesFailed : IO.Ref Nat
  /-- Successful handshakes -/
  handshakesSuccessful : IO.Ref Nat

/-- Create a new metrics instance -/
def mkMetrics : IO Metrics := do
  pure {
    connectionsTotal := ← IO.mkRef 0,
    connectionsActive := ← IO.mkRef 0,
    framesReceived := ← IO.mkRef 0,
    messagesReceived := ← IO.mkRef 0,
    bytesReceived := ← IO.mkRef 0,
    bytesSent := ← IO.mkRef 0,
    violationsTotal := ← IO.mkRef 0,
    handshakesFailed := ← IO.mkRef 0,
    handshakesSuccessful := ← IO.mkRef 0
  }

initialize globalMetricsRef : Option (IO.Ref Metrics) ← do
  let metrics ← mkMetrics
  return some (← IO.mkRef metrics)

private def getMetrics : IO Metrics :=
  match globalMetricsRef with
  | some ref => ref.get
  | none => mkMetrics

/-- Increment a counter atomically -/
def Metrics.inc (_m : Metrics) (counter : IO.Ref Nat) : IO Unit :=
  counter.modify (· + 1)

/-- Get current value of a counter -/
def Metrics.get (_m : Metrics) (counter : IO.Ref Nat) : IO Nat := counter.get

/-- Record connection opened -/
def Metrics.connectionOpened : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.connectionsTotal
  metrics.inc metrics.connectionsActive

/-- Record connection closed -/
def Metrics.connectionClosed : IO Unit := do
  let metrics ← getMetrics
  metrics.connectionsActive.modify (fun n => if n > 0 then n - 1 else 0)

/-- Record frame received -/
def Metrics.frameReceived (size : Nat) : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.framesReceived
  metrics.bytesReceived.modify (· + size)

/-- Record message received -/
def Metrics.messageReceived : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.messagesReceived

/-- Record bytes sent -/
def Metrics.recordBytesSent (size : Nat) : IO Unit := do
  let metrics ← getMetrics
  metrics.bytesSent.modify (· + size)

/-- Record protocol violation -/
def Metrics.violation : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.violationsTotal

/-- Record handshake failure -/
def Metrics.handshakeFailed : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.handshakesFailed

/-- Record successful handshake -/
def Metrics.handshakeSuccessful : IO Unit := do
  let metrics ← getMetrics
  metrics.inc metrics.handshakesSuccessful

/-- Get all metrics as a structured report -/
def Metrics.report : IO String := do
  let metrics ← getMetrics
  let connTotal ← metrics.get metrics.connectionsTotal
  let connActive ← metrics.get metrics.connectionsActive
  let framesRecv ← metrics.get metrics.framesReceived
  let msgsRecv ← metrics.get metrics.messagesReceived
  let bytesRecv ← metrics.get metrics.bytesReceived
  let bytesSent ← metrics.get metrics.bytesSent
  let violations ← metrics.get metrics.violationsTotal
  let hsFailed ← metrics.get metrics.handshakesFailed
  let hsSuccess ← metrics.get metrics.handshakesSuccessful

  pure s!"WebSocket Metrics:
  Connections: {connActive} active, {connTotal} total
  Handshakes: {hsSuccess} successful, {hsFailed} failed
  Traffic: {msgsRecv} messages, {framesRecv} frames
  Bytes: {bytesRecv} received, {bytesSent} sent
  Violations: {violations} protocol violations"

/-- Reset all metrics to zero -/
def Metrics.reset : IO Unit := do
  let metrics ← getMetrics
  metrics.connectionsTotal.set 0
  metrics.connectionsActive.set 0
  metrics.framesReceived.set 0
  metrics.messagesReceived.set 0
  metrics.bytesReceived.set 0
  metrics.bytesSent.set 0
  metrics.violationsTotal.set 0
  metrics.handshakesFailed.set 0
  metrics.handshakesSuccessful.set 0

end WebSocket
