#!/bin/bash
PORT="1234"
echo "Starting server on port ${PORT}"
set -x
socat -v TCP-LISTEN:"${PORT}",bind=127.0.0.1,reuseaddr,fork EXEC:'./moviemcpserver.sh',stderr
