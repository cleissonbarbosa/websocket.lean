/-
Copyright (c) 2022 Cleisson Barbosa. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Cleisson Barbosa
-/

namespace WebSocket

/-- Rate limit configuration -/
structure RateLimitConfig where
  /-- Maximum requests per time window -/
  maxRequests : Nat := 100
  /-- Time window in seconds -/
  timeWindowSeconds : Nat := 60
  /-- Block duration in seconds when limit is exceeded -/
  blockDurationSeconds : Nat := 300
  /-- Whether to enable rate limiting -/
  enabled : Bool := true

/-- Rate limit entry for tracking client requests -/
structure RateLimitEntry where
  /-- Client identifier (IP address or similar) -/
  clientId : String
  /-- Request count in current window -/
  requestCount : Nat := 0
  /-- Window start timestamp -/
  windowStart : UInt64 := 0
  /-- Block expiration timestamp -/
  blockedUntil : UInt64 := 0

/-- Rate limiter state -/
structure RateLimiter where
  config : RateLimitConfig
  /-- List of rate limit entries (simple implementation) -/
  entries : IO.Ref (List (String × RateLimitEntry))

def mkDefaultRateLimiter : IO RateLimiter := do
  let entries ← IO.mkRef ([] : List (String × RateLimitEntry))
  pure { config := {}, entries }

namespace RateLimiter

private def nowSeconds : IO Nat := do
  pure ((← IO.monoNanosNow) / 1000000000)

private def findEntry (entries : List (String × RateLimitEntry)) (clientId : String) : Option RateLimitEntry :=
  entries.findSome? (fun (id, entry) => if id == clientId then some entry else none)

private def upsertEntry (entries : List (String × RateLimitEntry)) (clientId : String) (entry : RateLimitEntry) : List (String × RateLimitEntry) :=
  let rec go : List (String × RateLimitEntry) → List (String × RateLimitEntry)
    | [] => [(clientId, entry)]
    | (id, oldEntry) :: rest =>
        if id == clientId then (clientId, entry) :: rest else (id, oldEntry) :: go rest
  go entries

/-- Create a new rate limiter -/
def create (config : RateLimitConfig := {}) : IO RateLimiter := do
  let entriesRef ← IO.mkRef ([] : List (String × RateLimitEntry))
  pure { config := config, entries := entriesRef }

/-- Check if a client is currently blocked -/
def isBlocked (limiter : RateLimiter) (clientId : String) : IO Bool := do
  let entries ← limiter.entries.get
  let currentTimeU64 := UInt64.ofNat (← nowSeconds)

  match findEntry entries clientId with
  | none => pure false
  | some entry =>
    if entry.blockedUntil > 0 then
      pure (currentTimeU64 < entry.blockedUntil)
    else
      pure false

/-- Check if a request should be allowed -/
def shouldAllow (limiter : RateLimiter) (clientId : String) : IO (Except String Unit) := do
  if !limiter.config.enabled then
    pure (Except.ok ())
  else
    let blocked ← isBlocked limiter clientId
    if blocked then
      pure (Except.error "Rate limit exceeded - client temporarily blocked")
    else
      let entries ← limiter.entries.get
      let currentTimeSec ← nowSeconds

      match findEntry entries clientId with
      | none =>
        -- First request from this client
        let newEntry : RateLimitEntry := {
          clientId := clientId,
          requestCount := 1,
          windowStart := UInt64.ofNat currentTimeSec,
          blockedUntil := UInt64.ofNat 0
        }
        limiter.entries.set (upsertEntry entries clientId newEntry)
        pure (Except.ok ())

      | some entry =>
        let windowStartSec := entry.windowStart.toNat
        let timeDiff := currentTimeSec - windowStartSec

        if timeDiff >= limiter.config.timeWindowSeconds then
          -- New time window
          let newEntry : RateLimitEntry := {
            clientId := clientId,
            requestCount := 1,
            windowStart := UInt64.ofNat currentTimeSec,
            blockedUntil := UInt64.ofNat 0
          }
          limiter.entries.set (upsertEntry entries clientId newEntry)
          pure (Except.ok ())
        else
          -- Same time window
          let newCount := entry.requestCount + 1
          if newCount > limiter.config.maxRequests then
            -- Rate limit exceeded, block the client
            let blockUntilSec := currentTimeSec + limiter.config.blockDurationSeconds
            let blockedEntry : RateLimitEntry := {
              clientId := clientId,
              requestCount := newCount,
              windowStart := entry.windowStart,
              blockedUntil := UInt64.ofNat blockUntilSec
            }
            limiter.entries.set (upsertEntry entries clientId blockedEntry)
            pure (Except.error s!"Rate limit exceeded: {newCount}/{limiter.config.maxRequests} requests in {limiter.config.timeWindowSeconds}s window")
          else
            -- Update request count
            let updatedEntry : RateLimitEntry := {
              clientId := clientId,
              requestCount := newCount,
              windowStart := entry.windowStart,
              blockedUntil := entry.blockedUntil
            }
            limiter.entries.set (upsertEntry entries clientId updatedEntry)
            pure (Except.ok ())

/-- Record a successful request (for metrics) -/
def recordRequest (_limiter : RateLimiter) (_clientId : String) : IO Unit :=
  pure ()

/-- Get current status for a client -/
def getClientStatus (limiter : RateLimiter) (clientId : String) : IO (Option (Nat × Bool)) := do
  let entries ← limiter.entries.get
  match findEntry entries clientId with
  | none => pure none
  | some entry =>
      let blocked ← isBlocked limiter clientId
      pure (some (entry.requestCount, blocked))

/-- Get rate limiter statistics -/
def getStats (limiter : RateLimiter) : IO (Nat × Nat) := do
  let entries ← limiter.entries.get
  let now := UInt64.ofNat (← nowSeconds)
  let blocked := entries.foldl (fun acc (_, entry) => if entry.blockedUntil > now then acc + 1 else acc) 0
  pure (entries.length, blocked)

/-- Clean up expired entries -/
def cleanup (limiter : RateLimiter) : IO Nat := do
  let entries ← limiter.entries.get
  let now := UInt64.ofNat (← nowSeconds)
  let keepEntry := fun ((_, entry) : String × RateLimitEntry) =>
    entry.blockedUntil > now || now.toNat - entry.windowStart.toNat < limiter.config.timeWindowSeconds
  let kept := entries.filter keepEntry
  limiter.entries.set kept
  pure (entries.length - kept.length)

/-- Reset all rate limiting data -/
def reset (limiter : RateLimiter) : IO Unit := do
  limiter.entries.set []

end RateLimiter

/-- Global rate limiter instance -/
initialize globalRateLimiter : IO.Ref (Option RateLimiter) ← IO.mkRef none

/-- Initialize global rate limiter -/
def initializeGlobalRateLimiter (config : RateLimitConfig := {}) : IO Unit := do
  let limiter ← RateLimiter.create config
  globalRateLimiter.set (some limiter)

/-- Get global rate limiter (create if not exists) -/
def getGlobalRateLimiter : IO RateLimiter := do
  let limiterOpt ← globalRateLimiter.get
  match limiterOpt with
  | some limiter => pure limiter
  | none =>
    let limiter ← RateLimiter.create {}
    globalRateLimiter.set (some limiter)
    pure limiter

/-- Check rate limit for a client using global limiter -/
def checkRateLimit (clientId : String) : IO (Except String Unit) := do
  let limiter ← getGlobalRateLimiter
  limiter.shouldAllow clientId

/-- Record request in global limiter -/
def recordRateLimitRequest (clientId : String) : IO Unit := do
  let limiter ← getGlobalRateLimiter
  limiter.recordRequest clientId

/-- Get rate limit stats from global limiter -/
def getRateLimitStats : IO (Nat × Nat) := do
  let limiter ← getGlobalRateLimiter
  limiter.getStats

end WebSocket
