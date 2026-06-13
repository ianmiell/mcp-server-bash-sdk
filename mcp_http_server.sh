#!/bin/bash
# mcp_http_server.sh — Starts a socat-backed HTTP server that wraps moviemcpserver.sh.
# nginx (or any reverse proxy) should sit in front of this for TLS and auth.

PORT="${MCP_HTTP_PORT:-8888}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v socat &>/dev/null; then
    echo "Error: socat is required. Install it with: brew install socat" >&2
    exit 1
fi

echo "MCP HTTP server listening on 127.0.0.1:${PORT}"
echo "Endpoints: POST /mcp  GET /health"
if [[ -n "$MCP_AUTH_TOKEN" ]]; then
    echo "Auth: Bearer token required on /mcp"
else
    echo "Auth: disabled (set MCP_AUTH_TOKEN to enable)"
fi
exec socat \
    TCP-LISTEN:"${PORT}",bind=127.0.0.1,reuseaddr,fork \
    EXEC:"$SCRIPT_DIR/mcp_http_handler.sh",stderr
