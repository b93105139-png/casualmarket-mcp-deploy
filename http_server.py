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
