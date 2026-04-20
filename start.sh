#!/bin/bash
set -e

if [ -z "$BEARER_TOKEN" ]; then
	echo "ERROR: BEARER_TOKEN environment variable not set"
	exit 1
fi

# Start CasualMarket with Streamable HTTP transport (MCP endpoint at /mcp)
cd /app/casualmarket
python -m src.http_server &
CASUAL_PID=$!

# Wait for the MCP endpoint to respond (accept any non-connection-refused reply)
for i in $(seq 1 60); do
	if curl -fs -o /dev/null -X POST http://127.0.0.1:8000/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d '{}' 2>/dev/null || [ $? -ne 7 ]; then
		code=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8000/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d '{}' 2>/dev/null || echo "000")
		if [ "$code" != "000" ] && [ "$code" != "" ]; then
			echo "CasualMarket ready after ${i}s (code=$code)"
			break
		fi
	fi
	if ! kill -0 "$CASUAL_PID" 2>/dev/null; then
		echo "ERROR: CasualMarket process exited during startup"
		exit 1
	fi
	echo "Waiting for CasualMarket... ($i/60)"
	sleep 1
done

# Trap signals to shut down cleanly
trap "kill $CASUAL_PID 2>/dev/null; exit 0" SIGTERM SIGINT

# Start Caddy in foreground
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
