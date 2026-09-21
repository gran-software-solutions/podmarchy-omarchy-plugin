#!/bin/bash
# Smoke tests for podmarchy-api and podmarchy-player.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

STATE=$(mktemp -d)
RUNTIME=$(mktemp -d)
trap 'rm -rf "$STATE" "$RUNTIME"' EXIT

export XDG_STATE_HOME="$STATE"
export XDG_RUNTIME_DIR="$RUNTIME"

echo "== auth-status without credentials =="
./podmarchy-api auth-status | jq -e '.configured == false'

echo "== auth-set rejects a short key =="
if printf 'short\nsecret1234\n' | ./podmarchy-api auth-set >/dev/null 2>&1; then
  echo "FAIL: short key accepted" >&2
  exit 1
fi

echo "== auth-set accepts a valid key =="
printf 'ABCDEFGH\nSECRET1234\n' | ./podmarchy-api auth-set | jq -e '.ok == true'

echo "== auth-status with credentials =="
./podmarchy-api auth-status | jq -e '.configured == true'

echo "== credentials file is mode 600 =="
perm=$(stat -c '%a' "$STATE/omarchy/podmarchy/credentials.json")
[[ $perm == "600" ]] || { echo "FAIL: credentials are $perm" >&2; exit 1; }

echo "== player status creates idle status =="
./podmarchy-player status | jq -e '.running == false'
[[ -s "$RUNTIME/podmarchy/status.json" ]]

echo "== player rejects non-http url =="
if ./podmarchy-player play '{"url":"file:///etc/passwd"}' >/dev/null 2>&1; then
  echo "FAIL: file:// url accepted" >&2
  exit 1
fi

echo "== player rejects url with newline =="
if ./podmarchy-player play '{"url":"https://x/a\n--flag"}' >/dev/null 2>&1; then
  echo "FAIL: newline url accepted" >&2
  exit 1
fi

echo "== search/trending/episodes with mock Podcast Index =="
python3 tests/mock-server.py 9877 &
mock_pid=$!
trap 'kill $mock_pid 2>/dev/null || true; rm -rf "$STATE" "$RUNTIME"' EXIT
sleep 0.3

PODMARCHY_API_BASE=http://127.0.0.1:9877 ./podmarchy-api search test | jq -e '.feeds | length == 1'
PODMARCHY_API_BASE=http://127.0.0.1:9877 ./podmarchy-api trending en | jq -e '.feeds | length == 1'
PODMARCHY_API_BASE=http://127.0.0.1:9877 ./podmarchy-api episodes 123 | jq -e '.items | length == 1'

echo "All smoke tests passed."
