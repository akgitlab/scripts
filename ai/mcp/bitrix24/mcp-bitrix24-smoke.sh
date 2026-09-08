#!/usr/bin/env bash
# Smoke-test для mcp-bitrix24 (Bitrix24 CRM: контакты/сделки, read+write stage).
# Транспорт SSE (mcp 1.4.1 не умеет streamable-http): GET /sse держит поток,
# JSON-RPC уходит POST в session endpoint, ответы читаются из потока.
# Порядок: systemd -> SSE endpoint -> MCP handshake + tools/list ->
# tools/call (list_deals, реальный поход в Bitrix24) -> прямой вызов вебхука в обход MCP.
# Коды возврата: 0 = OK, ненулевое = количество проваленных слоёв.

set -u
BASE="${MCP_BASE:-http://127.0.0.1:8003}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mcp/servers/bitrix24}"
SECRETS="${SECRETS:-${INSTALL_DIR}/secrets/secrets.env}"
EXPECTED_TOOLS="${EXPECTED_TOOLS:-6}"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# tmp-файлы с гарантией очистки
SSE_OUT=$(mktemp)
CURL_PID=""
cleanup() { [[ -n "$CURL_PID" ]] && kill "$CURL_PID" 2>/dev/null; rm -f "$SSE_OUT"; }
trap cleanup EXIT

echo "=== mcp-bitrix24 smoke test ==="
echo "MCP base:     $BASE"
echo "Install dir:  $INSTALL_DIR"
echo "Secrets:      $SECRETS"
echo

# --- Слой 1: systemd -------------------------------------------------------
echo "[1/5] systemd"
MAIN_PID=$(systemctl show mcp-bitrix24 -p MainPID --value 2>/dev/null)
ACTIVE=$(systemctl is-active mcp-bitrix24 2>/dev/null)
NREST=$(systemctl show mcp-bitrix24 -p NRestarts --value 2>/dev/null)
echo "  MainPID=$MAIN_PID  ActiveState=$ACTIVE  NRestarts=$NREST"
if [[ "$ACTIVE" == "active" && -n "$MAIN_PID" && "$MAIN_PID" -gt 0 ]] && sudo kill -0 "$MAIN_PID" 2>/dev/null; then
  ok "service active (PID $MAIN_PID)"
else
  bad "service not active or PID dead"
fi
if [[ "$NREST" -le 3 ]] 2>/dev/null; then
  ok "restarts: $NREST"
else
  bad "service restart loop? NRestarts=$NREST"
fi
echo

# --- Слой 2: SSE endpoint (аналог /health) --------------------------------
echo "[2/5] SSE endpoint ${BASE}/sse"
curl -sN -m 15 "${BASE}/sse" > "$SSE_OUT" 2>/dev/null &
CURL_PID=$!

ENDPOINT=""
for _ in $(seq 1 20); do
  ENDPOINT=$(grep -m1 '^data:' "$SSE_OUT" 2>/dev/null | sed 's/^data: //' | tr -d '\r\n')
  [[ -n "$ENDPOINT" ]] && break
  sleep 0.3
done
if [[ -n "$ENDPOINT" ]]; then
  ok "SSE stream opened, session endpoint: $ENDPOINT"
else
  bad "no endpoint event in SSE stream"
fi
echo

# --- Слой 3: MCP handshake + tools/list -----------------------------------
echo "[3/5] MCP handshake (SSE)"
post_msg() { # $1 = JSON -> HTTP code
  curl -sS -o /dev/null -w '%{http_code}' -m 10 -X POST "${BASE}${ENDPOINT}" \
    -H 'Content-Type: application/json' -d "$1" 2>/dev/null
}
wait_reply() { # $1 = маркер '"id":N', $2 = max сек
  for _ in $(seq 1 $(( $2 * 2 ))); do
    grep -q "\"id\":$1" "$SSE_OUT" 2>/dev/null && return 0
    sleep 0.5
  done
  return 1
}

if [[ -n "$ENDPOINT" ]]; then
  RC=$(post_msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}')
  if [[ "$RC" == "202" || "$RC" == "200" ]] && wait_reply 1 10; then
    ok "initialize -> HTTP $RC"
  else
    bad "initialize failed (HTTP $RC)"
  fi

  post_msg '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null

  RC=$(post_msg '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
  TOOL_COUNT=0
  if wait_reply 2 10; then
    TOOL_COUNT=$(grep -m1 '"id":2' "$SSE_OUT" | sed 's/^data: //' | grep -oE '"name":"[^"]+"' | sort -u | wc -l)
  fi
  if [[ "$TOOL_COUNT" -ge "$EXPECTED_TOOLS" ]]; then
    ok "tools/list -> $TOOL_COUNT tools"
    grep -m1 '"id":2' "$SSE_OUT" | sed 's/^data: //' | grep -oE '"name":"[^"]+"' | sort -u | sed 's/^/    /'
  else
    bad "tools/list: $TOOL_COUNT tools (expected >= $EXPECTED_TOOLS)"
  fi
else
  bad "handshake skipped (no session endpoint)"
fi
echo

# --- Слой 4: tools/call list_deals — реальный поход в Bitrix24 -------------
echo "[4/5] tools/call list_deals (webhook E2E)"
if [[ -n "$ENDPOINT" ]]; then
  RC=$(post_msg '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_deals","arguments":{"limit":3}}}')
  if wait_reply 3 15; then
    grep -m1 '"id":3' "$SSE_OUT" | sed 's/^data: //' > /tmp/_b24_deals.json
    python3 - /tmp/_b24_deals.json <<'PY' > /tmp/_b24_deals.out 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
def find(node, key, want_type):
    if isinstance(node, dict):
        if key in node and isinstance(node[key], want_type): return node[key]
        for v in node.values():
            r = find(v, key, want_type)
            if r is not None: return r
    if isinstance(node, list):
        for v in node:
            r = find(v, key, want_type)
            if r is not None: return r
    return None
content = find(d, 'content', list)
is_err = find(d, 'isError', bool)
if is_err or not content:
    print('TOOL ERROR:', content[0].get('text', '')[:200] if content else d)
    raise SystemExit(2)
text = content[0]['text']
obj = json.loads(text)
if isinstance(obj, dict) and ('error' in obj or 'error_description' in obj):
    raise SystemExit(f"API error: {obj}")
if isinstance(obj, dict):  # апстрим: {'total': N, 'filters': {...}, 'deals': [...]}
    total = obj.get('total')
    deals = obj.get('deals', [])
else:
    total = len(obj)
    deals = obj
print(f'Got {len(deals)} deals (total={total}):')
for it in deals[:3]:
    if not isinstance(it, dict):
        continue
    did = it.get('id') or it.get('ID')
    title = it.get('title') or it.get('TITLE')
    stage = it.get('stage_id') or it.get('STAGE_ID')
    print(f'  - id={did} title={str(title)[:60]!r} stage={stage}')
raw = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
print(f'REPLACEMENT_CHARS: {raw.count(chr(0xFFFD))}')
PY
    PRC=$?
    cat /tmp/_b24_deals.out
    if [[ $PRC -eq 0 ]]; then
      ok "list_deals -> webhook E2E ok"
    else
      bad "list_deals failed (см. /var/log/mcp/mcp-bitrix24.log)"
    fi
    if grep -q '^Got ' /tmp/_b24_deals.out && grep -q '^REPLACEMENT_CHARS: 0' /tmp/_b24_deals.out; then
      ok "cyrillic clean (0 replacement chars)"
    else
      bad "cyrillic dirty: $(grep '^REPLACEMENT_CHARS' /tmp/_b24_deals.out)"
    fi
  else
    bad "no reply on tools/call (HTTP $RC)"
  fi
else
  bad "tools/call skipped (no session endpoint)"
fi
echo

# --- Слой 5: вебхук напрямую в обход MCP -----------------------------------
echo "[5/5] Bitrix24 webhook direct (bypass MCP)"
if [[ -r "$SECRETS" ]]; then
  WEBHOOK_URL=$(grep -m1 '^BITRIX_WEBHOOK_URL=' "$SECRETS" | cut -d= -f2-)
  if [[ -n "$WEBHOOK_URL" ]]; then
    DIRECT=$(curl -sS -m 10 -X POST "${WEBHOOK_URL}crm.deal.list" \
      -H 'Content-Type: application/json' \
      -d '{"select":["ID","TITLE"],"params":{"start":-1}}' 2>&1)
    if echo "$DIRECT" | grep -q '"result"'; then
      N=$(echo "$DIRECT" | grep -oE '"ID":"?[0-9]+' | wc -l)
      ok "webhook direct: crm.deal.list -> $N deals total"
    elif echo "$DIRECT" | grep -q 'error'; then
      bad "webhook API error: $(echo "$DIRECT" | head -c 200)"
    else
      bad "webhook unexpected response: $(echo "$DIRECT" | head -c 200)"
    fi
  else
    bad "BITRIX_WEBHOOK_URL not found in $SECRETS"
  fi
else
  bad "secrets not readable: $SECRETS"
fi
echo

echo "=== ИТОГ: $PASS passed, $FAIL failed ==="
exit $FAIL
