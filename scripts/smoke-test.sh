#!/usr/bin/env bash
# =============================================================================
# Smoke test for vLLM inference stack
# Verifies the API is up and can generate a response
# =============================================================================
set -euo pipefail

VLLM_URL="${VLLM_URL:-http://localhost:8000}"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  vLLM Inference Stack - Smoke Test"
echo "============================================"
echo ""

# 1. Health check
echo -n "[1/4] Health check... "
if curl -sf "${VLLM_URL}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} - Server not responding at ${VLLM_URL}/health"
    echo "     Is the stack running? Try: docker compose up -d"
    exit 1
fi

# 2. List models
echo -n "[2/4] Listing models... "
MODELS=$(curl -sf "${VLLM_URL}/v1/models" 2>/dev/null)
if [ $? -eq 0 ]; then
    MODEL_ID=$(echo "$MODELS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}PASS${NC} - Model: ${MODEL_ID}"
else
    echo -e "${RED}FAIL${NC} - Could not list models"
    exit 1
fi

# 3. Chat completion
echo -n "[3/4] Chat completion... "
RESPONSE=$(curl -sf "${VLLM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"${MODEL_ID}"'",
        "messages": [{"role": "user", "content": "Say hello in exactly 5 words."}],
        "max_tokens": 30,
        "temperature": 0.7
    }' 2>/dev/null)

if [ $? -eq 0 ]; then
    CONTENT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "")
    TOKENS=$(echo "$RESPONSE" | python3 -c "import sys,json; u=json.load(sys.stdin)['usage']; print(f'prompt={u[\"prompt_tokens\"]}, completion={u[\"completion_tokens\"]}')" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}PASS${NC}"
    echo "     Response: ${CONTENT}"
    echo "     Tokens: ${TOKENS}"
else
    echo -e "${RED}FAIL${NC} - Chat completion failed"
    exit 1
fi

# 4. Metrics endpoint
echo -n "[4/4] Metrics endpoint... "
METRICS=$(curl -sf "${VLLM_URL}/metrics" 2>/dev/null | head -5)
if [ $? -eq 0 ] && [ -n "$METRICS" ]; then
    echo -e "${GREEN}PASS${NC} - Prometheus metrics available"
else
    echo -e "${YELLOW}WARN${NC} - Metrics endpoint not responding"
fi

echo ""
echo "============================================"
echo -e "  ${GREEN}All checks passed!${NC}"
echo "============================================"
echo ""
echo "  API:        ${VLLM_URL}/v1"
echo "  Docs:       ${VLLM_URL}/docs"
echo "  Prometheus:  http://localhost:9090"
echo "  Grafana:     http://localhost:3000 (admin/admin)"
echo ""
