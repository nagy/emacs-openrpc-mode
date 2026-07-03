#!/usr/bin/env bash
# A minimal JSON-RPC 2.0 stdio server that speaks raw JSON lines
# (no Content-Length headers). Used for testing jsonrpc-noenvelope.
# Pass --ready to emit a "ready" notification before rpc.discover.

set -e

READY_MODE=
[ "${1:-}" = "--ready" ] && READY_MODE=1

while IFS= read -r line; do
  method=$(echo "$line" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  if [ "$method" = "rpc.discover" ]; then
    id=$(echo "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    [ -n "$READY_MODE" ] && echo '{"jsonrpc":"2.0","method":"ready","params":{"status":"listening"}}'
    echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"info":{"description":"Test","title":"test","version":"0.1.0"},"methods":[{"description":"Returns schema.","name":"rpc.discover","params":[]},{"description":"Set title.","name":"window.set_title","params":[{"name":"title","required":true,"schema":{"type":"string"}}]},{"description":"Exit app.","name":"app.exit","params":[]}],"openrpc":"1.2.6"}}'
  else
    id=$(echo "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    if [ -n "$id" ]; then
      echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":'"$id"'}'
    else
      echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}'
    fi
  fi
done
