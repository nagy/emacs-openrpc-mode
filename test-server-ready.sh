#!/usr/bin/env bash
# Simulates tauri-jsonrpc-husk: sends a "ready" notification, then
# the rpc.discover response, all as raw JSON lines.
set -e

while IFS= read -r line; do
  method=$(echo "$line" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  if [ "$method" = "rpc.discover" ]; then
    id=$(echo "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

    # First send a "ready" notification
    echo '{"jsonrpc":"2.0","method":"ready","params":{"status":"listening"}}'

    # Then send the rpc.discover response
    echo '{"jsonrpc":"2.0","result":{"info":{"description":"Test","title":"test","version":"0.1.0"},"methods":[{"description":"Returns schema.","name":"rpc.discover","params":[]},{"description":"Set title.","name":"window.set_title","params":[{"name":"title","required":true,"schema":{"type":"string"}}]},{"description":"Exit app.","name":"app.exit","params":[]}],"openrpc":"1.2.6"},"id":'"$id"'}'
  else
    id=$(echo "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    [ -n "$id" ] && echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":'"$id"'}' || echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}'
  fi
done
