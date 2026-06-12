#!/bin/zsh
# Captures real Cohere Chat V2 responses as test fixtures (issue #4).
#
# Usage:
#   COHERE_API_KEY=$(security find-generic-password -s cohere-api-key -w) ./scripts/capture-fixtures.sh
#
# The key is read from the environment only; it is never written to any output.
# Trial tier allows 20 calls/min per endpoint — calls are spaced to stay under it.
set -euo pipefail

: "${COHERE_API_KEY:?Set COHERE_API_KEY (e.g. from Keychain; see README)}"
BASE_URL="${COHERE_BASE_URL:-https://api.cohere.com}"
MODEL="${COHERE_MODEL:-command-a-plus-05-2026}"
OUT="$(dirname "$0")/../Tests/CohereAPITests/Fixtures"
PAUSE=5

call() { # name, extra curl args...
  local name=$1; shift
  echo "capturing: $name"
  curl -sS "$BASE_URL/v2/chat" \
    -H "Authorization: Bearer $COHERE_API_KEY" \
    -H "Content-Type: application/json" \
    "$@" > "$OUT/$name"
  sleep $PAUSE
}

# 1. Basic chat, non-streamed
call chat-basic.json -d '{
  "model": "'"$MODEL"'",
  "messages": [{"role": "user", "content": "In one short sentence, what is retrieval-augmented generation?"}]
}'

# 2. Basic chat, streamed (raw SSE)
call chat-stream-basic.sse -d '{
  "model": "'"$MODEL"'",
  "stream": true,
  "messages": [{"role": "user", "content": "Count from 1 to 5, one number per word."}]
}'

# 3. Document-grounded request with citations (raw SSE)
call chat-stream-citations.sse -d '{
  "model": "'"$MODEL"'",
  "stream": true,
  "documents": [
    {"id": "doc-pump-manual", "data": {"title": "Pump P-301 Service Manual", "text": "Pump P-301 requires bearing lubrication every 500 operating hours. Use grade NLGI 2 lithium grease only. Overgreasing causes seal failure."}},
    {"id": "doc-safety-bulletin", "data": {"title": "Safety Bulletin 2026-04", "text": "Before servicing P-301, isolate power at breaker panel B and apply lockout-tagout. Verify zero rotation before removing the coupling guard."}}
  ],
  "messages": [{"role": "user", "content": "How often does P-301 need bearing lubrication, and what must I do before servicing it?"}]
}'

# 4. Tool-call round trip, streamed (raw SSE)
call chat-stream-tools.sse -d '{
  "model": "'"$MODEL"'",
  "stream": true,
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_equipment_status",
      "description": "Returns the current operational status of a piece of field equipment",
      "parameters": {
        "type": "object",
        "properties": {"equipment_id": {"type": "string", "description": "Equipment identifier, e.g. P-301"}},
        "required": ["equipment_id"]
      }
    }
  }],
  "messages": [{"role": "user", "content": "Is pump P-301 currently running?"}]
}'

# 5. Response headers (rate-limit documentation; no body kept)
echo "capturing: response-headers.txt"
curl -sS -o /dev/null -D - "$BASE_URL/v2/chat" \
  -H "Authorization: Bearer $COHERE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "'"$MODEL"'", "messages": [{"role": "user", "content": "hi"}]}' \
  | grep -ivE "set-cookie|authorization" > "$OUT/response-headers.txt"

echo "done. Review fixtures for stray sensitive content before committing."
