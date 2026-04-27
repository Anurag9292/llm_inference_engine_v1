#!/usr/bin/env bash
# =============================================================================
# Simple benchmark for vLLM inference stack
# Sends N concurrent requests and measures latency/throughput
# =============================================================================
set -euo pipefail

VLLM_URL="${VLLM_URL:-http://localhost:8000}"
NUM_REQUESTS="${1:-10}"
MAX_TOKENS="${2:-100}"
CONCURRENT="${3:-3}"
GREEN='\033[0;32m'
NC='\033[0m'

echo "============================================"
echo "  vLLM Inference Stack - Benchmark"
echo "============================================"
echo "  Requests:    ${NUM_REQUESTS}"
echo "  Max tokens:  ${MAX_TOKENS}"
echo "  Concurrency: ${CONCURRENT}"
echo "  Endpoint:    ${VLLM_URL}"
echo "============================================"
echo ""

# Get model name
MODEL_ID=$(curl -sf "${VLLM_URL}/v1/models" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
if [ -z "$MODEL_ID" ]; then
    echo "ERROR: Cannot reach vLLM server at ${VLLM_URL}"
    exit 1
fi
echo "Model: ${MODEL_ID}"
echo ""

PROMPTS=(
    "Explain the concept of recursion in programming with a simple example."
    "What are the main differences between TCP and UDP protocols?"
    "Write a Python function that finds the longest common subsequence of two strings."
    "Describe the CAP theorem in distributed systems."
    "What is the difference between a stack and a queue? Give real-world examples."
    "Explain how garbage collection works in modern programming languages."
    "What are microservices and when should you use them?"
    "Describe the observer design pattern with a practical example."
    "What is the difference between concurrency and parallelism?"
    "Explain how a hash table works and what makes a good hash function."
)

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

START_TIME=$(date +%s%N)

# Launch requests with controlled concurrency
for i in $(seq 1 "${NUM_REQUESTS}"); do
    # Wait if we've hit concurrency limit
    while [ "$(jobs -r | wc -l)" -ge "${CONCURRENT}" ]; do
        sleep 0.1
    done

    PROMPT_IDX=$(( (i - 1) % ${#PROMPTS[@]} ))
    (
        REQ_START=$(date +%s%N)
        RESPONSE=$(curl -sf "${VLLM_URL}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"${MODEL_ID}"'",
                "messages": [{"role": "user", "content": "'"${PROMPTS[$PROMPT_IDX]}"'"}],
                "max_tokens": '"${MAX_TOKENS}"',
                "temperature": 0.7
            }' 2>/dev/null)
        REQ_END=$(date +%s%N)

        LATENCY_MS=$(( (REQ_END - REQ_START) / 1000000 ))
        TOKENS=$(echo "$RESPONSE" | python3 -c "import sys,json; u=json.load(sys.stdin)['usage']; print(u['completion_tokens'])" 2>/dev/null || echo "0")

        echo "${LATENCY_MS},${TOKENS}" > "${TMPDIR}/req_${i}.csv"
        echo "  Request ${i}/${NUM_REQUESTS}: ${LATENCY_MS}ms, ${TOKENS} tokens generated"
    ) &
done

# Wait for all requests to finish
wait

END_TIME=$(date +%s%N)
TOTAL_TIME_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo ""
echo "============================================"
echo "  Results"
echo "============================================"

# Aggregate results
python3 -c "
import os, glob

latencies = []
total_tokens = 0

for f in glob.glob('${TMPDIR}/req_*.csv'):
    with open(f) as fh:
        parts = fh.read().strip().split(',')
        latencies.append(int(parts[0]))
        total_tokens += int(parts[1])

latencies.sort()
n = len(latencies)
total_time_s = ${TOTAL_TIME_MS} / 1000.0

if n == 0:
    print('  No successful requests!')
else:
    print(f'  Successful requests: {n}/${NUM_REQUESTS}')
    print(f'  Total wall time:     {total_time_s:.1f}s')
    print(f'  Total tokens:        {total_tokens}')
    print(f'')
    print(f'  Latency (per request):')
    print(f'    Min:    {latencies[0]}ms')
    print(f'    Median: {latencies[n//2]}ms')
    print(f'    p90:    {latencies[int(n*0.9)]}ms')
    print(f'    p99:    {latencies[int(n*0.99)]}ms')
    print(f'    Max:    {latencies[-1]}ms')
    print(f'    Avg:    {sum(latencies)/n:.0f}ms')
    print(f'')
    print(f'  Throughput:')
    print(f'    Requests/s:  {n/total_time_s:.2f}')
    print(f'    Tokens/s:    {total_tokens/total_time_s:.2f}')
" 2>/dev/null

echo "============================================"
echo ""
