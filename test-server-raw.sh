#!/usr/bin/env bash
# A minimal JSON-RPC 2.0 stdio server that speaks raw JSON lines
# (no Content-Length headers). Used for testing jsonrpc-noenvelope.

set -e

while IFS= read -r line; do
  # Parse method from the line
  method=$(echo "$line" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  if [ "$method" = "rpc.discover" ]; then
    id=$(echo "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"openrpc":"1.2.6","info":{"title":"Test API","version":"1.0.0"},"methods":[{"name":"greet","summary":"Greets the user","params":[{"name":"name","description":"The name to greet"}],"result":{"name":"greeting","description":"A friendly greeting"}},{"name":"add","summary":"Adds two numbers","params":[{"name":"a","description":"First number"},{"name":"b","description":"Second number"}],"result":{"name":"sum"}},{"name":"ping","summary":"Health check","params":[],"result":{"name":"pong"}}]}}'
  else
    echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}'
  fi
done
