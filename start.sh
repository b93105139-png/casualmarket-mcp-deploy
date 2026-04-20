#!/bin/bash
set -e

if [ -z "$BEARER_TOKEN" ]; then
    echo "ERROR: BEARER_TOKEN environment variable not set"
    exit 1
fi

# Write the Streamable HTTP entrypoint at container start. We do this here
# rather than via Dockerfile COPY because Zeabur's builder caches the runtime
# stage's COPY instructions aggressively — new COPY lines get silently
# dropped across rebuilds. start.sh itself IS being copied, so it's the one
# reliable place to materialise new files.
cat > /app/http_server.py <<'PYEOF'
#!/usr/bin/env python3
"""Streamable HTTP transport entrypoint for CasualMarket MCP."""

import asyncio

from src.server import mcp
from src.utils.logging import get_logger, setup_logging

setup_logging()
logger = get_logger(__name__)


async def main() -> None:
    logger.info("Starting CasualMarket MCP Server with Streamable HTTP")
    logger.info("Endpoint: http://0.0.0.0:8000/mcp")
    await mcp.run_http_async(host="0.0.0.0", port=8000, log_level="info")


def run() -> None:
    asyncio.run(main())


if __name__ == "__main__":
    run()
PYEOF

echo "Generated /app/http_server.py:"
ls -la /app/http_server.py

# Start CasualMarket with Streamable HTTP transport (MCP endpoint at /mcp)
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
