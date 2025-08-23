#!/usr/bin/env bash
# Run the advanced WebSocket echo server with optional port and maxConnections.
# Usage:
#   ./run-advanced-echo.sh                # default port 9001, maxConnections 50
#   ./run-advanced-echo.sh 8080           # custom port 8080
#   ./run-advanced-echo.sh 8080 200       # custom port + maxConnections
set -euo pipefail

PORT="${1:-9001}"
MAX_CONNS="${2:-50}"

# Build if needed
lake build advancedEchoServer >/dev/null

exec lake exe advancedEchoServer "$PORT" "$MAX_CONNS"