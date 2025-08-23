import WebSocket
import WebSocket.Server.Types
open WebSocket

namespace WebSocket.Server.Events

open WebSocket.Server.Types

/-- Event subscription ID -/
abbrev SubscriptionId := Nat

/-- Event filter for selective subscription -/
inductive EventFilter
  | all
  | connected
  | disconnected
  | message (opcodeFilter : Option OpCode := none)
  | error
  | custom (predicate : ServerEvent → Bool)

/-- Event subscription -/
structure EventSubscription where
  id : SubscriptionId
  filter : EventFilter
  handler : EventHandler
  active : Bool := true

/-- Event manager state -/
structure EventManager where
  subscriptions : List EventSubscription := []
  nextId : SubscriptionId := 1

/-- Create a new event manager -/
def mkEventManager : EventManager := {}

/-- Check if event matches filter -/
def matchesFilter (filter : EventFilter) (event : ServerEvent) : Bool :=
  match filter with
  | .all => true
  | .connected => match event with | .connected _ _ => true | _ => false
  | .disconnected => match event with | .disconnected _ _ => true | _ => false
  | .message opcodeFilter =>
      match event with
      | .message _ opc _ =>
          match opcodeFilter with
          | none => true
          | some targetOpc => opc == targetOpc
      | _ => false
  | .error => match event with | .error _ _ => true | _ => false
  | .custom pred => pred event

/-- Subscribe to events with a filter -/
def subscribe (manager : EventManager) (filter : EventFilter) (handler : EventHandler) : EventManager × SubscriptionId :=
  let subId := manager.nextId
  let subscription : EventSubscription := {
    id := subId,
    filter := filter,
    handler := handler,
    active := true
  }
  let newManager := {
    subscriptions := subscription :: manager.subscriptions,
    nextId := manager.nextId + 1
  }
  (newManager, subId)

/-- Unsubscribe from events -/
def unsubscribe (manager : EventManager) (subId : SubscriptionId) : EventManager :=
  let newSubscriptions := manager.subscriptions.map (fun sub =>
    if sub.id == subId then { sub with active := false } else sub
  )
  { manager with subscriptions := newSubscriptions }

/-- Remove inactive subscriptions -/
def cleanup (manager : EventManager) : EventManager :=
  let activeSubscriptions := manager.subscriptions.filter (·.active)
  { manager with subscriptions := activeSubscriptions }

/-- Dispatch event to all matching subscribers -/
def dispatch (manager : EventManager) (event : ServerEvent) : IO Unit := do
  for subscription in manager.subscriptions do
    if subscription.active && matchesFilter subscription.filter event then
      try
        subscription.handler event
      catch e =>
        -- Log error but continue with other handlers
        IO.println s!"Error in event handler {subscription.id}: {e}"

/-- Enhanced server state with event management -/
structure EnhancedServerState where
  base : ServerState
  eventManager : EventManager

/-- Create enhanced server with event management -/
def mkEnhancedServer (config : ServerConfig := {}) : EnhancedServerState :=
  { base := mkServer config, eventManager := mkEventManager }

/-- Subscribe to specific connection events -/
def subscribeToConnection (manager : EventManager) (targetConnId : Nat) (handler : EventHandler) : EventManager × SubscriptionId :=
  subscribe manager (.custom (fun event =>
    match event with
    | .connected id _ | .disconnected id _ | .message id _ _ | .error id _ => id == targetConnId
  )) handler

end WebSocket.Server.Events
