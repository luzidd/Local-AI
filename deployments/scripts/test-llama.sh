#!/usr/bin/env bash
# Test llama.cpp server with simple inference request

set -euo pipefail

API_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:11435}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check health endpoint
log_info "Checking server health..."
if ! health_response=$(curl -s -f "$API_URL/health" 2>&1); then
    log_error "Server not responding at $API_URL"
    log_error "Is the server running? Try: ./deploy-llama.sh deploy"
    exit 1
fi

echo "$health_response" | jq . 2>/dev/null || echo "$health_response"
echo ""

# List available models
log_info "Listing available models..."
models_response=$(curl -s "$API_URL/v1/models")
echo "$models_response" | jq . 2>/dev/null || echo "$models_response"
echo ""

# Simple test completion
log_info "Testing completion (this may take 10-30 seconds for first inference)..."
echo ""

# Note: Sampling parameters (temperature, top_k, top_p, etc.) can be adjusted per request.
# See deployments/podman/kube/TUNING-GUIDE.md#sampling-configuration for presets.
cat << 'EOF' | tee /tmp/llama-test-request.json
{
  "model": "gemma4-26b-q6-128k",
  "messages": [
    {
      "role": "user",
      "content": "Explain what a mixture of experts (MoE) model is in one sentence."
    }
  ],
  "temperature": 0.7,
  "max_tokens": 100,
  "stream": false
}
EOF

echo ""
log_info "Sending request..."
start_time=$(date +%s)

response=$(curl -s "$API_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d @/tmp/llama-test-request.json)

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
log_info "Response received in ${duration}s"
echo ""

# Pretty print response
if echo "$response" | jq -e '.choices[0].message.content' &>/dev/null; then
    echo "=== Model Response ==="
    echo "$response" | jq -r '.choices[0].message.content'
    echo ""
    
    # Show token stats
    if echo "$response" | jq -e '.usage' &>/dev/null; then
        echo "=== Token Usage ==="
        echo "$response" | jq '.usage'
        
        prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
        completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        total_time=$(echo "$response" | jq -r '.usage.total_time // 0')
        
        if [ "$completion_tokens" -gt 0 ] && [ "$total_time" != "0" ]; then
            tokens_per_sec=$(echo "scale=2; $completion_tokens / $total_time" | bc 2>/dev/null || echo "N/A")
            echo ""
            log_info "Generation speed: ${tokens_per_sec} tokens/second"
        fi
    fi
else
    log_error "Unexpected response format:"
    echo "$response" | jq . 2>/dev/null || echo "$response"
fi

echo ""
log_info "Test complete!"
