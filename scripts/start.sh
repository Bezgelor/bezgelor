#!/bin/bash
# Start all servers with the web portal (interactive)
set -e

# Auto-detect server IP if not set (use first non-localhost IPv4 address)
if [ -z "$WORLD_PUBLIC_ADDRESS" ]; then
  WORLD_PUBLIC_ADDRESS=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
  export WORLD_PUBLIC_ADDRESS
fi

exec mix bezgelor.start
