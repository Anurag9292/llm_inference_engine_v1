#!/usr/bin/env bash
# =============================================================================
# RunPod Direct Run Script
# Runs vLLM directly (no Docker needed — the pod IS the container)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load .env if it exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

MODEL_NAME="${MODEL_NAME:-Qwen/Qwen2.5-3B-Instruct-AWQ}"
QUANTIZATION="${QUANTIZATION:-awq}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"
VLLM_PORT="${VLLM_PORT:-8000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

echo "============================================"
echo "  RunPod Direct Deployment"
echo "============================================"
echo ""

# 1. Check GPU
echo -n "[1/5] Checking GPU... "
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1)
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo -e "${GREEN}OK${NC} - ${GPU_NAME} (${GPU_MEM} MiB)"
else
    echo -e "${RED}FAIL${NC} - nvidia-smi not found"
    exit 1
fi

# 2. Install vLLM
echo -n "[2/5] Installing vLLM... "
if python3 -c "import vllm" 2>/dev/null; then
    VLLM_VER=$(python3 -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    echo -e "${GREEN}OK${NC} - vLLM ${VLLM_VER} already installed"
else
    echo -e "${YELLOW}Installing...${NC}"
    pip install vllm --quiet 2>&1 | tail -1
    VLLM_VER=$(python3 -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    echo -e "${GREEN}OK${NC} - vLLM ${VLLM_VER} installed"
fi

# 3. Install Prometheus
echo -n "[3/5] Setting up Prometheus... "
if [ ! -f /usr/local/bin/prometheus ]; then
    PROM_VERSION="2.53.0"
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz" -O /tmp/prometheus.tar.gz
    tar -xzf /tmp/prometheus.tar.gz -C /tmp/
    cp "/tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus" /usr/local/bin/
    cp "/tmp/prometheus-${PROM_VERSION}.linux-amd64/promtool" /usr/local/bin/
    rm -rf /tmp/prometheus*
    echo -e "${GREEN}OK${NC} - Prometheus ${PROM_VERSION} installed"
else
    echo -e "${GREEN}OK${NC} - Prometheus already installed"
fi

# 4. Install Grafana
echo -n "[4/5] Setting up Grafana... "
if ! command -v grafana-server &> /dev/null; then
    apt-get install -y -qq adduser libfontconfig1 musl > /dev/null 2>&1 || true
    GRAFANA_VERSION="11.1.0"
    wget -q "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb" -O /tmp/grafana.deb
    dpkg -i /tmp/grafana.deb > /dev/null 2>&1
    rm /tmp/grafana.deb
    echo -e "${GREEN}OK${NC} - Grafana ${GRAFANA_VERSION} installed"
else
    echo -e "${GREEN}OK${NC} - Grafana already installed"
fi

# 5. Configure & update Prometheus config for direct mode
echo -n "[5/5] Configuring services... "
# Update prometheus config to point to localhost instead of docker service name
mkdir -p /etc/prometheus
cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "vllm"
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:${VLLM_PORT}"]
        labels:
          service: "vllm-inference"
EOF

# Configure Grafana datasource
mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/datasource.yml <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:${PROMETHEUS_PORT}
    isDefault: true
    editable: false
EOF

# Configure Grafana dashboard provisioning
mkdir -p /etc/grafana/provisioning/dashboards
cat > /etc/grafana/provisioning/dashboards/dashboard.yml <<EOF
apiVersion: 1
providers:
  - name: "vLLM Dashboards"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

# Copy dashboard
mkdir -p /var/lib/grafana/dashboards
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cp "${REPO_DIR}/grafana/dashboards/vllm.json" /var/lib/grafana/dashboards/

echo -e "${GREEN}OK${NC}"

echo ""
echo "============================================"
echo -e "  ${GREEN}Setup complete! Starting services...${NC}"
echo "============================================"
echo ""

# Start Prometheus in background
echo "Starting Prometheus on port ${PROMETHEUS_PORT}..."
nohup prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.retention.time=7d \
    --web.listen-address=":${PROMETHEUS_PORT}" \
    > /var/log/prometheus.log 2>&1 &
echo "  PID: $!"

# Start Grafana in background
echo "Starting Grafana on port ${GRAFANA_PORT}..."
nohup grafana-server \
    --homepath=/usr/share/grafana \
    --config=/etc/grafana/grafana.ini \
    web > /var/log/grafana.log 2>&1 &
echo "  PID: $!"

# Give monitoring services a moment to start
sleep 2

# Start vLLM (foreground so you can see logs)
echo ""
echo "Starting vLLM on port ${VLLM_PORT}..."
echo "  Model: ${MODEL_NAME}"
echo "  Quantization: ${QUANTIZATION}"
echo "  Max model length: ${MAX_MODEL_LEN}"
echo ""
echo "  Waiting for 'Uvicorn running on http://0.0.0.0:${VLLM_PORT}'..."
echo "  (First run downloads the model — this may take a few minutes)"
echo ""
echo "============================================"
echo ""

python3 -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_NAME}" \
    --quantization "${QUANTIZATION}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
    --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}" \
    --enable-prefix-caching \
    --host 0.0.0.0 \
    --port "${VLLM_PORT}"
