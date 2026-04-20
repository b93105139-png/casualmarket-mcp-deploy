# Multi-stage build: CasualMarket MCP + Caddy (Bearer auth reverse proxy)
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

# Copy prebuilt CasualMarket (venv + source)
COPY --from=builder /app/casualmarket /app/casualmarket

# Copy our config + Streamable HTTP entrypoint (placed at /app/ so the target
# directory is guaranteed to exist; start.sh sets PYTHONPATH so `from src.*`
# resolves into the CasualMarket checkout)
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh
COPY http_server.py /app/http_server.py
RUN chmod +x /app/start.sh

ENV PATH="/app/casualmarket/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LOG_LEVEL=INFO

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -f http://127.0.0.1:8080/health || exit 1

CMD ["/app/start.sh"]
