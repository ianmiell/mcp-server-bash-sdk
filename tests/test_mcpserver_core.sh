#!/bin/bash
# Simple test script for MCP Core Server functionality
# Tests both standard functionality and error conditions

# Always keep logs for easier debugging

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Define a test-specific log file
export MCP_LOG_FILE="$SCRIPT_DIR/test_mcpserver.log"
# Set up for movieserver
MCP_CONFIG_FILE="$PROJECT_DIR/movieserver_config.json"
MCP_TOOLS_LIST_FILE="$PROJECT_DIR/movieserver_tools.json"

# Source the core MCP server implementation
# Note: run_mcp_server is only a function defined in mcpserver_core.sh but not executed
# unless explicitly called

function tool_test_echo() {
    # Extract text directly using grep to avoid jq parsing issues with multi-line JSON
    log "tool_test_echo called with: $1"
    local args text
    args="$1"
    text=$(echo "$args" | jq -r '.text')
    if [[ -z "$text" ]]; then
        echo "null"
        return 1
    fi
    # Simple string output, no JSON formatting needed
    echo "Hello, $text"
    return 0
}

# Source the core server implementation
source "$PROJECT_DIR/mcpserver_core.sh"

# Define a simple test tool function

# Color codes for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test utilities
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Function to run a test and report the result
run_test() {
    local test_name test_function
    test_name="$1"
    test_function="$2"
    TEST_COUNT=$((TEST_COUNT+1))
    echo -e "${YELLOW}Running test: ${test_name}${NC}"
    # Run the test function
    if $test_function; then
        PASS_COUNT=$((PASS_COUNT+1))
        echo -e "${GREEN}✓ PASSED: ${test_name}${NC}"
        return 0
    else
        FAIL_COUNT=$((FAIL_COUNT+1))
        echo -e "${RED}✗ FAILED: ${test_name}${NC}"
        return 1
    fi
}

# Function to assert that a string contains another string
assert_contains() {
    local haystack needle message haystack_nospace needle_nospace
    haystack="$1"
    needle="$2"
    message="$3"
    # Remove all spaces from haystack and needle for comparison
    haystack_nospace=$(echo "$haystack" | tr -d ' ')
    needle_nospace=$(echo "$needle" | tr -d ' ')
    if [[ "$haystack_nospace" == *"$needle_nospace"* ]]; then
        return 0
    else
        echo -e "${RED}Assertion failed: $message${NC}"
        echo -e "${RED}Expected to find: $needle${NC}"
        echo -e "${RED}In: $haystack${NC}"
        return 1
    fi
}

# Test the initialize method
test_handle_initialize() {
    local id params response
    id="1"
    #params='{"clientInfo": {"name": "TestClient"}, "capabilities": {}, "protocolVersion": "0.1.0"}'
    params='{"clientInfo": {"name": "TestClient"}, "capabilities": {}, "protocolVersion": "0.1.0"}'
    response=$(handle_initialize "$id" "$params")
    assert_contains "$response" '"jsonrpc": "2.0"' "Response should be JSON-RPC 2.0" || return 1
    assert_contains "$response" '"protocolVersion"' "Response should include protocol version" || return 1
    assert_contains "$response" '"serverInfo"' "Response should include server info" || return 1
    return 0
}

# Test the tools/call method with our test_echo tool
test_handle_tools_call() {
    local id response params request
    id="2"
    # Format params exactly as seen in mcpserver.log - single line JSON in the right format
    # Debug output
    echo "Starting test_handle_tools_call"
    # Define the test tool function - following pattern from moviemcpserver.sh
    # Call the process_request function with proper JSON-RPC formatted request
    echo "Calling handle_tools_call with id=$id and params=$params" >&2
    params="{'name':'test_echo','arguments':{'text':'hello'}"
    # [2025-05-31 08:22:07] [REQUEST] {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"book_ticket","arguments":{"movieId":4,"showTime":"11:30","numTickets":1},"_meta":{"progressToken":"0b35d562-1d24-40b1-8d30-99849fb7b83f"}}}
#
    # Format the request exactly like in mcpserver.log - as a complete JSON-RPC message
    request="{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/call\",\"params\":{\"name\":\"test_echo\",\"arguments\":{\"text\":\"MCP!\"}}}"
    # //{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_movies","arguments":{},"_meta":{"progressToken":"1027fb9f-9836-42ca-b3fa-d972a9b92c03"}}}
    echo "JSON-RPC request: $request" >&2
    # Use process_request which will parse the JSON-RPC request and call handle_tools_call
    response=$(process_request "$request")
    echo "Response from JSON-RPC request: $response" >&2
    # Add debugging info for empty response
    if [[ -z "$response" ]]; then
        echo "WARNING: Empty response received!" >&2
        return 1
    fi
    # Verify response
    assert_contains "$response" '"jsonrpc": "2.0"' "Response should be JSON-RPC 2.0" || return 1
    assert_contains "$response" '"content"' "Response should include content" || return 1
    assert_contains "$response" 'MCP' "Response should include echoed text" || return 1
    return 0
}

# Test the tools/list method
test_handle_tools_list() {
    local id request response
    id="3"
    request="{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/list\"}"
    response=$(process_request "$request")
    assert_contains "$response" '"jsonrpc": "2.0"' "Response should be JSON-RPC 2.0" || return 1
    assert_contains "$response" '"id": 3' "Response should include correct id" || return 1
    assert_contains "$response" '"tools"' "Response should include tools array" || return 1
    return 0
}

# Test handling of notifications/initialized notification
test_handle_notification() {
    local request response
    request="{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
    response=$(process_request "$request")
    # For notifications, response should be empty
    if [[ -n "$response" ]]; then
        echo -e "${RED}Notification should not return a response${NC}"
        return 1
    fi
    return 0
}

# Test error: invalid JSON-RPC version
test_invalid_jsonrpc_version() {
    local id request response
    id="4"
    request="{\"jsonrpc\":\"1.0\",\"id\":$id,\"method\":\"initialize\"}"
    response=$(process_request "$request")
    assert_contains "$response" '"error"' "Response should include error" || return 1
    assert_contains "$response" '"code": -32600' "Error code should be -32600" || return 1
    assert_contains "$response" '"message": "Invalid Request' "Error message should mention invalid request" || return 1
    return 0
}

# Test error: method not found
test_method_not_found() {
    local id request response
    id="5"
    request="{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"non_existent_method\"}"
    response=$(process_request "$request")
    assert_contains "$response" '"error"' "Response should include error" || return 1
    assert_contains "$response" '"code": -32601' "Error code should be -32601" || return 1
    assert_contains "$response" '"message": "Method not found' "Error message should mention method not found" || return 1
    return 0
}

# Test error: invalid tool name
test_invalid_tool_name() {
    local id request response
    id="6"
    request="{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/call\",\"params\":{\"name\":\"invalid-tool-name!\",\"arguments\":{}}}"
    response=$(process_request "$request")
    assert_contains "$response" '"error"' "Response should include error" || return 1
    assert_contains "$response" '"code": -32600' "Error code should be -32600" || return 1
    assert_contains "$response" '"message": "Invalid tool name format' "Error message should mention invalid tool name" || return 1
    return 0
}

# Test error: tool execution error
test_tool_execution_error() {
    local id response request
    local id="7"
    # Our test_echo tool actually returns a result for empty text (null),
    # so we need to use a different tool that doesn't exist for this test
    request="{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/call\",\"params\":{\"name\":\"non_existent_tool\",\"arguments\":{}}}"
    response=$(process_request "$request")
    assert_contains "$response" '"error"' "Response should include error" || return 1
    # The error code should be -32601 for "Method not found"
    assert_contains "$response" '"code": -32601' "Error code should be -32601" || return 1
    assert_contains "$response" '"message": "Tool not found' "Error message should mention tool not found" || return 1
    return 0
}

# Function to display test logs
display_test_logs() {
    if [[ -f "$MCP_LOG_FILE" ]]; then
        echo -e "\n${YELLOW}===== Test Logs =====${NC}"
        echo -e "${YELLOW}Log file: $MCP_LOG_FILE${NC}"
        echo -e "${YELLOW}Last 10 log entries:${NC}"
        tail -10 "$MCP_LOG_FILE"
        echo -e "\n${YELLOW}For complete logs, check: $MCP_LOG_FILE${NC}"
    else
        echo -e "\n${YELLOW}No log file found at: $MCP_LOG_FILE${NC}"
    fi
}


# Main test execution
main() {
    echo -e "\n${YELLOW}===== Running Simplified MCP Core Server Tests =====${NC}\n"
    # Clear log file before running tests
    > "$MCP_LOG_FILE"
    # Run the simplified test suite
    run_test "Handle Initialize Test" test_handle_initialize
    run_test "Handle Tools Call Test" test_handle_tools_call
    run_test "Handle Tools List Test" test_handle_tools_list
    run_test "Handle Notification Test" test_handle_notification
    run_test "Invalid JSON-RPC Version Test" test_invalid_jsonrpc_version
    run_test "Method Not Found Test" test_method_not_found
    run_test "Invalid Tool Name Test" test_invalid_tool_name
    run_test "Tool Execution Error Test" test_tool_execution_error
    # Print summary
    echo -e "\n${YELLOW}===== Test Summary =====${NC}"
    echo -e "Total tests: ${TEST_COUNT}"
    echo -e "${GREEN}Tests passed: ${PASS_COUNT}${NC}"
    # Display test logs
    display_test_logs
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Tests failed: ${FAIL_COUNT}${NC}"
        exit 1
    else
        echo -e "All tests passed!"
        exit 0
    fi
}

# Run the tests
main
