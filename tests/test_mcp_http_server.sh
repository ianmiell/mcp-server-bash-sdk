#!/bin/bash
# test_mcp_http_server.sh — Tests for mcp_http_handler.sh and mcp_http_server.sh
# Unit tests pipe raw HTTP directly to the handler (no socat needed).
# Integration tests start the socat server and hit it with curl.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_PORT="${MCP_TEST_PORT:-9999}"
SERVER_PID=""

# ── Colours and counters ─────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
    local test_name="$1" test_function="$2"
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${YELLOW}Running test: ${test_name}${NC}"
    if $test_function; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "${GREEN}✓ PASSED: ${test_name}${NC}"
        return 0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo -e "${RED}✗ FAILED: ${test_name}${NC}"
        return 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    local h n
    h=$(echo "$haystack" | tr -d ' \r\n')
    n=$(echo "$needle"   | tr -d ' \r\n')
    if [[ "$h" == *"$n"* ]]; then
        return 0
    fi
    echo -e "${RED}Assertion failed: $message${NC}"
    echo -e "${RED}Expected to find: $needle${NC}"
    echo -e "${RED}In: $haystack${NC}"
    return 1
}

assert_not_contains() {
    local haystack="$1" needle="$2" message="$3"
    local h n
    h=$(echo "$haystack" | tr -d ' \r\n')
    n=$(echo "$needle"   | tr -d ' \r\n')
    if [[ "$h" != *"$n"* ]]; then
        return 0
    fi
    echo -e "${RED}Assertion failed: $message${NC}"
    echo -e "${RED}Expected NOT to find: $needle${NC}"
    echo -e "${RED}In: $haystack${NC}"
    return 1
}

# ── HTTP request builder ─────────────────────────────────────────────────────
# send_handler_request method path [body] [bearer_token]
# Content-Length is calculated automatically. MCP_AUTH_TOKEN is inherited from
# the calling environment, so wrap calls in MCP_AUTH_TOKEN=... $(...) to test auth.
send_handler_request() {
    local method="$1" path="$2" body="${3:-}" token="${4:-}"
    {
        printf '%s %s HTTP/1.1\r\nHost: localhost\r\n' "$method" "$path"
        [[ -n "$token" ]] && printf 'Authorization: Bearer %s\r\n' "$token"
        if [[ -n "$body" ]]; then
            local len
            len=$(printf '%s' "$body" | wc -c | tr -d ' ')
            printf 'Content-Type: application/json\r\nContent-Length: %d\r\n\r\n%s' "$len" "$body"
        else
            printf '\r\n'
        fi
    } | "$PROJECT_DIR/mcp_http_handler.sh"
}

# ── Unit tests: HTTP handler ─────────────────────────────────────────────────

test_health_check() {
    local response
    response=$(send_handler_request "GET" "/health" "")
    assert_contains "$response" "HTTP/1.1 200" "Health check should return 200" || return 1
    assert_contains "$response" "OK"           "Health check body should be OK" || return 1
}

test_tools_list() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    assert_contains "$response" "HTTP/1.1 200"    "tools/list should return HTTP 200"    || return 1
    assert_contains "$response" '"jsonrpc":"2.0"' "Response should be JSON-RPC 2.0"      || return 1
    assert_contains "$response" '"tools"'         "Response body should include tools"   || return 1
}

test_tools_call_get_movies() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_movies","arguments":{}}}')
    assert_contains "$response" "HTTP/1.1 200" "get_movies should return 200"           || return 1
    assert_contains "$response" '"content"'    "Response should include content field"  || return 1
    assert_contains "$response" "Avengers"     "Response should include movie data"     || return 1
}

test_book_ticket_valid() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"book_ticket","arguments":{"movieId":1,"showTime":"10:00","numTickets":2}}}')
    assert_contains "$response" "HTTP/1.1 200" "Booking should return 200"             || return 1
    assert_contains "$response" '"content"'    "Response should include content"        || return 1
    assert_contains "$response" "bookingId"    "Response should include booking ID"     || return 1
}

test_validate_age_allowed() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"validate_age","arguments":{"age":20,"movieRating":"A"}}}')
    assert_contains "$response" "HTTP/1.1 200"          "Age check should return 200"           || return 1
    assert_contains "$response" "validation successful" "Adult should pass A-rating check"      || return 1
}

test_validate_age_denied() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"validate_age","arguments":{"age":15,"movieRating":"A"}}}')
    assert_contains "$response" "HTTP/1.1 200" "Age denial should still be HTTP 200"    || return 1
    assert_contains "$response" "18"           "Response should cite minimum age of 18" || return 1
}

test_empty_body_returns_400() {
    local response
    response=$(send_handler_request "POST" "/mcp" "")
    assert_contains "$response" "HTTP/1.1 400" "Empty body should return 400" || return 1
    assert_contains "$response" '"error"'      "400 body should be a JSON error" || return 1
}

test_get_mcp_returns_404() {
    local response
    response=$(send_handler_request "GET" "/mcp" "")
    assert_contains "$response" "HTTP/1.1 404" "GET /mcp should return 404 (POST only)" || return 1
}

test_unknown_path_returns_404() {
    local response
    response=$(send_handler_request "POST" "/unknown" \
        '{"jsonrpc":"2.0","id":6,"method":"tools/list"}')
    assert_contains "$response" "HTTP/1.1 404" "Unknown path should return 404" || return 1
}

test_invalid_tool_name_returns_jsonrpc_error() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"invalid-tool!","arguments":{}}}')
    assert_contains "$response" "HTTP/1.1 200" "Invalid tool name should be HTTP 200 with RPC error" || return 1
    assert_contains "$response" '"error"'      "Response body should contain JSON-RPC error"         || return 1
    assert_contains "$response" "-32600"       "Error code should be -32600 (invalid request)"       || return 1
}

test_missing_required_param_returns_jsonrpc_error() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"book_ticket","arguments":{}}}')
    assert_contains "$response" "HTTP/1.1 200" "Missing param should be HTTP 200 with RPC error" || return 1
    assert_contains "$response" '"error"'      "Response body should contain JSON-RPC error"     || return 1
}

test_unknown_method_returns_jsonrpc_error() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}')
    assert_contains "$response" "HTTP/1.1 200" "Unknown tool should be HTTP 200 with RPC error" || return 1
    assert_contains "$response" '"error"'      "Response body should contain JSON-RPC error"    || return 1
    assert_contains "$response" "-32601"       "Error code should be -32601 (not found)"        || return 1
}

test_response_has_content_length_header() {
    local response
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":10,"method":"tools/list"}')
    assert_contains "$response" "Content-Length:" "Response must include Content-Length header" || return 1
}

test_response_content_length_matches_body() {
    local response headers body declared_len actual_len
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":11,"method":"tools/list"}')
    # Split at the blank line between headers and body
    headers=$(echo "$response" | awk 'BEGIN{RS="\r\n\r\n"} NR==1')
    body=$(echo    "$response" | awk 'BEGIN{RS="\r\n\r\n"} NR==2')
    declared_len=$(echo "$headers" | grep -i 'content-length' | grep -o '[0-9]*')
    actual_len=$(printf '%s' "$body" | wc -c | tr -d ' ')
    if [[ "$declared_len" -eq "$actual_len" ]]; then
        return 0
    fi
    echo -e "${RED}Content-Length mismatch: declared=$declared_len actual=$actual_len${NC}"
    return 1
}

# ── Auth unit tests ──────────────────────────────────────────────────────────
# These tests set MCP_AUTH_TOKEN in the environment of the handler subprocess.

AUTH_TEST_TOKEN="test-secret-token-123"

test_auth_correct_token_allowed() {
    local response
    response=$(MCP_AUTH_TOKEN="$AUTH_TEST_TOKEN" \
        send_handler_request "POST" "/mcp" \
            '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$AUTH_TEST_TOKEN")
    assert_contains "$response" "HTTP/1.1 200" "Correct token should return 200" || return 1
    assert_contains "$response" '"tools"'      "Correct token should get tools"   || return 1
}

test_auth_wrong_token_rejected() {
    local response
    response=$(MCP_AUTH_TOKEN="$AUTH_TEST_TOKEN" \
        send_handler_request "POST" "/mcp" \
            '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "wrong-token")
    assert_contains "$response" "HTTP/1.1 401" "Wrong token should return 401"             || return 1
    assert_contains "$response" '"error"'      "401 body should contain error field"       || return 1
}

test_auth_missing_token_rejected() {
    local response
    response=$(MCP_AUTH_TOKEN="$AUTH_TEST_TOKEN" \
        send_handler_request "POST" "/mcp" \
            '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    assert_contains "$response" "HTTP/1.1 401" "Missing token should return 401" || return 1
}

test_auth_health_exempt() {
    local response
    # /health must be reachable without a token even when auth is enabled
    response=$(MCP_AUTH_TOKEN="$AUTH_TEST_TOKEN" \
        send_handler_request "GET" "/health")
    assert_contains "$response" "HTTP/1.1 200" "/health should not require auth" || return 1
    assert_contains "$response" "OK"           "/health body should be OK"       || return 1
}

test_auth_disabled_when_token_unset() {
    local response
    # With no MCP_AUTH_TOKEN set, requests without a token should pass
    response=$(send_handler_request "POST" "/mcp" \
        '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    assert_contains "$response" "HTTP/1.1 200" "Unauthenticated request should pass when auth is disabled" || return 1
}

# ── Integration tests: socat server ─────────────────────────────────────────

wait_for_port() {
    local port="$1" retries=30
    while ! nc -z 127.0.0.1 "$port" 2>/dev/null; do
        sleep 0.1
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            echo -e "${RED}Timed out waiting for port $port${NC}" >&2
            return 1
        fi
    done
}

start_test_server() {
    local token="${1:-}"
    MCP_HTTP_PORT="$TEST_PORT" MCP_AUTH_TOKEN="$token" \
        "$PROJECT_DIR/mcp_http_server.sh" >/dev/null 2>&1 &
    SERVER_PID=$!
    if ! wait_for_port "$TEST_PORT"; then
        echo -e "${RED}Failed to start test server on port $TEST_PORT${NC}" >&2
        return 1
    fi
}

stop_test_server() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
        SERVER_PID=""
    fi
}

curl_post() {
    local body="$1" token="${2:-}"
    local auth_arg=()
    [[ -n "$token" ]] && auth_arg=(-H "Authorization: Bearer $token")
    curl -s --max-time 5 \
        -X POST "http://127.0.0.1:${TEST_PORT}/mcp" \
        -H "Content-Type: application/json" \
        "${auth_arg[@]}" \
        -d "$body"
}

test_integration_health() {
    local response
    response=$(curl -s --max-time 5 "http://127.0.0.1:${TEST_PORT}/health")
    assert_contains "$response" "OK" "Integration health check should return OK" || return 1
}

test_integration_tools_list() {
    local response
    response=$(curl_post '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    assert_contains "$response" '"tools"'         "Integration tools/list should return tools list" || return 1
    assert_contains "$response" '"jsonrpc":"2.0"' "Integration response should be JSON-RPC 2.0"    || return 1
}

test_integration_get_movies() {
    local response
    response=$(curl_post '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_movies","arguments":{}}}')
    assert_contains "$response" "Avengers"  "Integration get_movies should return movie list" || return 1
    assert_contains "$response" '"content"' "Integration response should include content"     || return 1
}

test_integration_book_ticket() {
    local response
    response=$(curl_post '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"book_ticket","arguments":{"movieId":2,"showTime":"14:00","numTickets":1}}}')
    assert_contains "$response" "bookingId" "Integration booking should return booking ID" || return 1
}

test_integration_auth_correct_token() {
    local response
    response=$(curl_post '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$AUTH_TEST_TOKEN")
    assert_contains "$response" '"tools"' "Integration: correct token should get tools" || return 1
}

test_integration_auth_wrong_token() {
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -X POST "http://127.0.0.1:${TEST_PORT}/mcp" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer wrong-token" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    [[ "$status" == "401" ]] || { echo -e "${RED}Expected 401, got $status${NC}"; return 1; }
}

test_integration_auth_no_token() {
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -X POST "http://127.0.0.1:${TEST_PORT}/mcp" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
    [[ "$status" == "401" ]] || { echo -e "${RED}Expected 401, got $status${NC}"; return 1; }
}

test_integration_auth_health_exempt() {
    local response
    response=$(curl -s --max-time 5 "http://127.0.0.1:${TEST_PORT}/health")
    assert_contains "$response" "OK" "Integration: /health must not require a token" || return 1
}

test_integration_concurrent_requests() {
    local tmp1 tmp2 tmp3
    tmp1=$(mktemp) tmp2=$(mktemp) tmp3=$(mktemp)

    curl_post '{"jsonrpc":"2.0","id":10,"method":"tools/list"}' > "$tmp1" &
    local p1=$!
    curl_post '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"get_movies","arguments":{}}}' > "$tmp2" &
    local p2=$!
    curl_post '{"jsonrpc":"2.0","id":12,"method":"tools/list"}' > "$tmp3" &
    local p3=$!
    wait "$p1" "$p2" "$p3"

    local r1 r2 r3
    r1=$(cat "$tmp1"); r2=$(cat "$tmp2"); r3=$(cat "$tmp3")
    rm -f "$tmp1" "$tmp2" "$tmp3"

    assert_contains "$r1" '"tools"'   "Concurrent request 1 should succeed" || return 1
    assert_contains "$r2" "Avengers"  "Concurrent request 2 should succeed" || return 1
    assert_contains "$r3" '"tools"'   "Concurrent request 3 should succeed" || return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo -e "\n${YELLOW}===== MCP HTTP Handler Unit Tests =====${NC}\n"

    run_test "GET /health returns 200"                    test_health_check
    run_test "POST /mcp tools/list returns tools"         test_tools_list
    run_test "POST /mcp tools/call get_movies"            test_tools_call_get_movies
    run_test "POST /mcp tools/call book_ticket (valid)"   test_book_ticket_valid
    run_test "POST /mcp validate_age (allowed)"           test_validate_age_allowed
    run_test "POST /mcp validate_age (underage)"          test_validate_age_denied
    run_test "POST /mcp empty body returns 400"           test_empty_body_returns_400
    run_test "GET /mcp returns 404"                       test_get_mcp_returns_404
    run_test "POST /unknown returns 404"                  test_unknown_path_returns_404
    run_test "Invalid tool name returns JSON-RPC error"   test_invalid_tool_name_returns_jsonrpc_error
    run_test "Missing required param returns JSON-RPC error" test_missing_required_param_returns_jsonrpc_error
    run_test "Unknown tool returns JSON-RPC -32601 error" test_unknown_method_returns_jsonrpc_error
    run_test "Response includes Content-Length header"    test_response_has_content_length_header
    run_test "Content-Length matches actual body size"    test_response_content_length_matches_body

    echo -e "\n${YELLOW}===== Auth Unit Tests =====${NC}\n"

    run_test "Auth: correct token is allowed"             test_auth_correct_token_allowed
    run_test "Auth: wrong token is rejected (401)"        test_auth_wrong_token_rejected
    run_test "Auth: missing token is rejected (401)"      test_auth_missing_token_rejected
    run_test "Auth: /health exempt from auth"             test_auth_health_exempt
    run_test "Auth: disabled when MCP_AUTH_TOKEN unset"   test_auth_disabled_when_token_unset

    echo -e "\n${YELLOW}===== MCP HTTP Integration Tests (socat, no auth) =====${NC}\n"

    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}curl not found — skipping integration tests${NC}"
    elif ! command -v nc &>/dev/null; then
        echo -e "${YELLOW}nc not found — skipping integration tests${NC}"
    elif ! start_test_server; then
        echo -e "${RED}Could not start socat server — skipping integration tests${NC}"
    else
        run_test "Integration: health check"          test_integration_health
        run_test "Integration: tools/list"            test_integration_tools_list
        run_test "Integration: get_movies"            test_integration_get_movies
        run_test "Integration: book_ticket"           test_integration_book_ticket
        run_test "Integration: 3 concurrent requests" test_integration_concurrent_requests
        stop_test_server
    fi

    echo -e "\n${YELLOW}===== MCP HTTP Integration Tests (socat, with auth) =====${NC}\n"

    if ! command -v curl &>/dev/null || ! command -v nc &>/dev/null; then
        echo -e "${YELLOW}curl or nc not found — skipping auth integration tests${NC}"
    elif ! start_test_server "$AUTH_TEST_TOKEN"; then
        echo -e "${RED}Could not start auth test server — skipping${NC}"
    else
        run_test "Integration auth: correct token allowed"   test_integration_auth_correct_token
        run_test "Integration auth: wrong token → 401"       test_integration_auth_wrong_token
        run_test "Integration auth: no token → 401"          test_integration_auth_no_token
        run_test "Integration auth: /health exempt"          test_integration_auth_health_exempt
        stop_test_server
    fi

    echo -e "\n${YELLOW}===== Test Summary =====${NC}"
    echo    "Total:  ${TEST_COUNT}"
    echo -e "${GREEN}Passed: ${PASS_COUNT}${NC}"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"
        exit 1
    else
        echo "All tests passed!"
        exit 0
    fi
}

trap stop_test_server EXIT
main
