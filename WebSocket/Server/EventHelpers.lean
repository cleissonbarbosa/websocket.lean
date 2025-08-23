import WebSocket.Server.Events
import WebSocket.Server.Types
open WebSocket.Server.Events
open WebSocket.Server.Types

-- Convenience functions for common subscription patterns

/-- Subscribe to all connection events -/
def subscribeToConnections (manager : EventManager) (handler : WebSocket.Server.Types.EventHandler) : EventManager × SubscriptionId :=
  subscribe manager (.custom (fun event =>
    match event with
    | .connected _ _ | .disconnected _ _ => true
    | _ => false
  )) handler

/-- Subscribe to text messages only -/
def subscribeToTextMessages (manager : EventManager) (handler : WebSocket.Server.Types.EventHandler) : EventManager × SubscriptionId :=
  subscribe manager (.message (some .text)) handler

/-- Subscribe to binary messages only -/
def subscribeToBinaryMessages (manager : EventManager) (handler : WebSocket.Server.Types.EventHandler) : EventManager × SubscriptionId :=
  subscribe manager (.message (some .binary)) handler

/-- Subscribe to errors -/
def subscribeToErrors (manager : EventManager) (handler : WebSocket.Server.Types.EventHandler) : EventManager × SubscriptionId :=
  subscribe manager .error handler
