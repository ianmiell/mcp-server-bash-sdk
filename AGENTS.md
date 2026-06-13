# AGENTS.md

## Project Overview

A pure-Bash implementation of an [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server SDK. It handles JSON-RPC 2.0 over stdio with no Node.js or Python runtime required — only `bash` and `jq`.

## Architecture

```
mcpserver_core.sh        — Protocol layer: JSON-RPC 2.0, MCP method dispatch, logging
moviemcpserver.sh        — Example stdio server: business logic (tool_* functions)
movieserver_config.json  — MCP server metadata (name, version, capabilities)
movieserver_tools.json   — Tool schema definitions (inputSchema per tool)

mcp_http_handler.sh      — Per-connection HTTP handler (spawned by socat)
mcp_http_server.sh       — Starts a socat TCP listener on 127.0.0.1:8888 (default)
nginx_mcp.conf           — nginx reverse proxy config (port 8080 → 8888)
tcp_mcp_server.sh        — Raw TCP wrapper via socat (no HTTP layer)

tests/
  test_mcpserver_core.sh   — Unit tests for mcpserver_core.sh protocol logic
  test_mcp_http_server.sh  — Unit + integration tests for the HTTP layer
```

The core never changes when adding new servers. Only the config/tools JSON files and the `tool_*` functions differ between servers.

### HTTP transport

`mcp_http_handler.sh` is spawned once per TCP connection by socat. It reads a single HTTP request, pipes the JSON-RPC body to `moviemcpserver.sh` via stdin (EOF on pipe close causes a clean exit), and wraps the response in an HTTP reply. nginx sits in front for TLS and routing.

## Key Conventions

### Tool functions
- Must be named `tool_<name>` where `<name>` matches a tool in `*_tools.json`
- Accept a single argument `$1` containing a JSON object of parameters
- Extract parameters with `jq -r '.param_name'`
- Success: `echo <result>; return 0`
- Validation/logic error: `echo <error message>; return 1`
- Output is automatically wrapped in MCP content response by the core

### Creating a new server
1. Create `<name>server.sh` — set `MCP_CONFIG_FILE`, `MCP_TOOLS_LIST_FILE`, `MCP_LOG_FILE`, then `source mcpserver_core.sh`, define `tool_*` functions, call `run_mcp_server "$@"`
2. Create `<name>server_tools.json` — JSON Schema for each tool's `inputSchema`
3. Create `<name>server_config.json` — `protocolVersion`, `serverInfo`, `capabilities`
4. `chmod +x <name>server.sh`

## Testing

All tests live in `tests/`. Run them from the repo root:

```bash
bash tests/test_mcpserver_core.sh    # JSON-RPC protocol unit tests
bash tests/test_mcp_http_server.sh   # HTTP handler unit + socat integration tests
```

`test_mcpserver_core.sh` calls `process_request` directly with raw JSON-RPC strings.  
`test_mcp_http_server.sh` pipes raw HTTP to the handler for unit tests, then starts a real socat server and uses curl for integration tests. Requires `curl` and `nc`; integration tests are skipped if either is absent.

To test a running server manually:

```bash
# stdio
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./moviemcpserver.sh

# HTTP (start mcp_http_server.sh first)
curl -s -X POST http://localhost:8888/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Requirements

- `bash`
- `jq` (`brew install jq` on macOS)

## Limitations

- No concurrency or streaming responses
- Single-line tool output only (newlines are collapsed to spaces)
- Not suited for high throughput
