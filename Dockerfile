# Multi-stage build: CasualMarket MCP + Caddy (Bearer auth reverse proxy)
# rev: 2026-04-20 inline-http-server
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv (dependency manager used by CasualMarket)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Clone CasualMarket source (pinned to main for reproducibility)
ARG CASUALMARKET_REF=main
RUN git clone --depth 1 --branch ${CASUALMARKET_REF} https://github.com/sacahan/CasualMarket.git /app/casualmarket

WORKDIR /app/casualmarket
RUN uv sync --frozen --no-dev

# ---------- runtime stage ----------
FROM python:3.12-slim

WORKDIR /app

# Install Caddy and curl (for healthcheck / start script)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg debian-keyring debian-archive-keyring apt-transport-https \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends caddy \
    && rm -rf /var/lib/apt/lists/*

# Copy prebuilt CasualMarket (venv + source) from builder stage
COPY --from=builder /app/casualmarket /app/casualmarket

# Copy Caddy config + start script from the deploy repo
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh

# Create the Streamable HTTP entrypoint INLINE.
# We embed this rather than COPY because the Zeabur builder silently drops
# additional COPY lines for files at repo root (confirmed via build logs:
# stage-1 counter 7/7 with only Caddyfile + start.sh copied). Writing the
# file via RUN heredoc forces it into the image layer unambiguously.
RUN cat > /app/http_server.py <<'PYEOF'
#!/usr/bin/env python3
"""Streamable HTTP transport entrypoint for CasualMarket MCP.

Uses FastMCP's built-in streamable HTTP runner so the server works with
Claude.ai's Custom Connectors flow (which requires the new transport rather
than legacy SSE).
"""

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

RUN chmod +x /app/start.sh && ls -la /app/ && head -5 /app/http_server.py

ENV PATH="/app/casualmarket/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LOG_LEVEL=INFO

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -f http://127.0.0.1:8080/health || exit 1

CMD ["/app/start.sh"]
