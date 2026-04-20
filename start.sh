#!/bin/bash
set -e

if [ -z "$BEARER_TOKEN" ]; then
	echo "ERROR: BEARER_TOKEN environment variable not set"
	exit 1
fi

# Start CasualMarket in background (binds 0.0.0.0:8000, only reachable from localhost via Caddy)
cd /app/casualmarket
python -m src.sse_server &
CASUAL_PID=$!

# Wait for CasualMarket to be ready
for i in $(seq 1 60); do
	if curl -fs http://127.0.0.1:8000/health > /dev/null 2>&1; then
		echo "CasualMarket ready after ${i}s"
		break
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
