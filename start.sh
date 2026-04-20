#!/bin/bash
set -e

if [ -z "$BEARER_TOKEN" ]; then
    echo "ERROR: BEARER_TOKEN environment variable not set"
    exit 1
fi

# Start CasualMarket with Streamable HTTP transport (MCP endpoint at /mcp)
# http_server.py lives at /app/; PYTHONPATH lets `from src.server import mcp`
# resolve against the CasualMarket checkout.
cd /app/casualmarket
PYTHONPATH=/app/casualmarket python /app/http_server.py &
CASUAL_PID=$!

# Wait for the MCP endpoint to respond. Any HTTP response (even 4xx) means
# the server is up; pure TCP refusal yields code=000.
for i in $(seq 1 60); do
    if ! kill -0 "$CASUAL_PID" 2>/dev/null; then
        echo "ERROR: CasualMarket process exited during startup"
        wait "$CASUAL_PID" || true
        exit 1
    fi
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8000/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d '{}' 2>/dev/null || echo "000")
    if [ "$code" != "000" ] && [ -n "$code" ]; then
        echo "CasualMarket ready after ${i}s (code=$code)"
        break
    fi
    echo "Waiting for CasualMarket... ($i/60)"
    sleep 1
done

trap "kill $CASUAL_PID 2>/dev/null; exit 0" SIGTERM SIGINT
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
