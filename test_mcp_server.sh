printf '%s\n' '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_movies"},"id":1}' | nc localhost 1234 | jq '.result.content[0].text' | jq -r .
