# casualmarket-mcp-deploy

Wraps [sacahan/CasualMarket](https://github.com/sacahan/CasualMarket) with a Caddy reverse proxy enforcing `Authorization: Bearer $BEARER_TOKEN`.

Deployed to Zeabur, bound to `market.jessefang.com`.

## Env vars

- `BEARER_TOKEN` (required)
- `LOG_LEVEL` (optional, default `INFO`)

## Endpoints

- `/health` — public liveness probe (no auth)
- `/sse` — MCP SSE endpoint (auth required)
- `/*` — everything else proxied to CasualMarket when auth valid

## Ports

- Container listens on `:8080` (Caddy). CasualMarket runs on `127.0.0.1:8000` internally.
