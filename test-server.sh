#!/usr/bin/env bash
# A minimal JSON-RPC 2.0 stdio server that responds to rpc.discover
# Used for testing openrpc-mode.el

# Read Content-Length header (strip \r)
read -r header || exit 1
header="${header%%$'\r'*}"
# Extract length
length="${header#Content-Length: }"
# Read blank line (strip \r)
read -r blank
# Read JSON body
body=$(dd bs=1 count="$length" 2>/dev/null)

# Parse method from the request body
method=$(echo "$body" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ "$method" = "rpc.discover" ]; then
  # Extract request id
  id=$(echo "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

  response='{
  "jsonrpc": "2.0",
  "id": '"$id"',
  "result": {
    "openrpc": "1.2.6",
    "info": {
      "title": "Test API",
      "version": "1.0.0"
    },
    "methods": [
      {
        "name": "greet",
        "summary": "Greets the user",
        "description": "Takes a name and returns a greeting string",
        "params": [
          {"name": "name", "description": "The name to greet", "schema": {"type": "string"}}
        ],
        "result": {
          "name": "greeting",
          "description": "A friendly greeting",
          "schema": {"type": "string"}
        }
      },
      {
        "name": "add",
        "summary": "Adds two numbers",
        "params": [
          {"name": "a", "description": "First number", "schema": {"type": "integer"}},
          {"name": "b", "description": "Second number", "schema": {"type": "integer"}}
        ],
        "result": {
          "name": "sum",
          "schema": {"$ref": "#/components/schemas/Integer"}
        }
      },
      {
        "name": "ping",
        "summary": "Health check",
        "params": [],
        "result": {
          "name": "pong",
          "description": "Always returns '\''pong'\''"
        }
      }
    ]
  }
}'
  response_len=${#response}
  printf "Content-Length: %d\r\n\r\n%s" "$response_len" "$response"
else
  # Unknown method
  id=$(echo "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
  error_response='{
  "jsonrpc": "2.0",
  "id": '"$id"',
  "error": {"code": -32601, "message": "Method not found"}
}'
  error_len=${#error_response}
  printf "Content-Length: %d\r\n\r\n%s" "$error_len" "$error_response"
fi
