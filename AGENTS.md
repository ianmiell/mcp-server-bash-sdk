# AGENTS.md

## Project Overview

A pure-Bash implementation of an [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server SDK. It handles JSON-RPC 2.0 over stdio with no Node.js or Python runtime required — only `bash` and `jq`.

## Architecture

```
mcpserver_core.sh       — Protocol layer: JSON-RPC 2.0, MCP method dispatch, logging
moviemcpserver.sh       — Example server: business logic (tool_* functions)
movieserver_config.json — MCP server metadata (name, version, capabilities)
movieserver_tools.json  — Tool schema definitions (inputSchema per tool)
```

The core never changes when adding new servers. Only the config/tools JSON files and the `tool_*` functions differ between servers.

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

```bash
bash test_mcpserver_core.sh
```

Tests call `process_request` directly with raw JSON-RPC strings and use `assert_contains` to check responses. The test tool `tool_test_echo` is defined inline in the test file.

To test a running server manually:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./moviemcpserver.sh
```

## Requirements

- `bash`
- `jq` (`brew install jq` on macOS)

## Limitations

- No concurrency or streaming responses
- Single-line tool output only (newlines are collapsed to spaces)
- Not suited for high throughput
