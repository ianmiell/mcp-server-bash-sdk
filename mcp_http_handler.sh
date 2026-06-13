#!/bin/bash
# mcp_http_handler.sh — Handles a single HTTP connection for the MCP server.
# Spawned per connection by socat. Reads one HTTP request, pipes the JSON-RPC
# body to moviemcpserver.sh, and writes an HTTP response back.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read request line (e.g. "POST /mcp HTTP/1.1")
read -r request_line
method="${request_line%% *}"
rest="${request_line#* }"
path="${rest%% *}"
path="${path%$'\r'}"

# Read headers until blank line; capture Content-Length and Authorization
content_length=0
auth_header=""
while IFS= read -r header; do
    header="${header%$'\r'}"
    [[ -z "$header" ]] && break
    header_lower="$(echo "$header" | tr '[:upper:]' '[:lower:]')"
    if [[ "$header_lower" =~ ^content-length:[[:space:]]*([0-9]+) ]]; then
        content_length="${BASH_REMATCH[1]}"
    elif [[ "$header_lower" =~ ^authorization:[[:space:]]* ]]; then
        # Preserve original casing of token value
        auth_header="${header#*: }"
    fi
done

# Read exactly content_length bytes of body
body=""
if [[ $content_length -gt 0 ]]; then
    body=$(head -c "$content_length")
fi

http_response() {
    local status="$1" content_type="$2" body="$3"
    local len=${#body}
    printf "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
        "$status" "$content_type" "$len" "$body"
}

# Bearer token auth — enabled when MCP_AUTH_TOKEN is set; /health is always exempt
if [[ -n "$MCP_AUTH_TOKEN" && "$path" != "/health" ]]; then
    if [[ "$auth_header" != "Bearer $MCP_AUTH_TOKEN" ]]; then
        http_response "401 Unauthorized" "application/json" \
            '{"error":"Unauthorized","message":"Valid Bearer token required in Authorization header"}'
        exit 0
    fi
fi

case "$method $path" in
    "POST /mcp")
        if [[ -z "$body" ]]; then
            http_response "400 Bad Request" "application/json" \
                '{"jsonrpc":"2.0","error":{"code":-32700,"message":"Empty request body"},"id":null}'
            exit 0
        fi
        # Pipe single JSON-RPC message to server; stdin close after printf causes clean EOF exit
        response=$(printf '%s\n' "$body" | "$SCRIPT_DIR/moviemcpserver.sh" 2>/dev/null)
        http_response "200 OK" "application/json" "$response"
        ;;
    "GET /health")
        http_response "200 OK" "text/plain" "OK"
        ;;
    *)
        http_response "404 Not Found" "text/plain" "Not Found"
        ;;
esac
