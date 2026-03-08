/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

import WebSocket.Tests.Basic
import WebSocket.Tests.Crypto
import WebSocket.Tests.Handshake
import WebSocket.Tests.HandshakeKeyValidation
import WebSocket.Tests.Frames
import WebSocket.Tests.Fragmentation
import WebSocket.Tests.KeepAlive
import WebSocket.Tests.UTF8
import WebSocket.Tests.InvalidOpcode
import WebSocket.Tests.Integration
import WebSocket.Tests.FFI
import WebSocket.RateLimit

namespace WebSocket.Tests.RateLimit

def run : IO Unit := do
  let limiter ← WebSocket.RateLimiter.create { maxRequests := 2, timeWindowSeconds := 60, blockDurationSeconds := 60, enabled := true }
  match ← limiter.shouldAllow "client-a" with
  | .ok () => pure ()
  | .error _ => throw <| IO.userError "Expected first request to pass"
  match ← limiter.shouldAllow "client-a" with
  | .ok () => pure ()
  | .error _ => throw <| IO.userError "Expected second request to pass"
  match ← limiter.shouldAllow "client-a" with
  | .error _ => IO.println "Rate limiter counting test passed"
  | .ok () => throw <| IO.userError "Expected third request to be rate-limited"

end WebSocket.Tests.RateLimit

def main : IO Unit := do
  WebSocket.Tests.Basic.run
  WebSocket.Tests.Crypto.run
  WebSocket.Tests.Handshake.run
  WebSocket.Tests.HandshakeKeyValidation.run
  WebSocket.Tests.Frames.run
  WebSocket.Tests.Fragmentation.run
  WebSocket.Tests.KeepAlive.run
  WebSocket.Tests.UTF8.run
  WebSocket.Tests.InvalidOpcode.run
  WebSocket.Tests.Integration.run
  WebSocket.Tests.FFI.run
  WebSocket.Tests.RateLimit.run
  IO.println "All tests done"
