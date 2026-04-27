# LLM Inference Engine

A self-hosted LLM inference stack using **vLLM** with full observability via **Prometheus** and **Grafana**. Ships with an OpenAI-compatible API out of the box.

## Stack

| Service | Port | Description |
|---------|------|-------------|
| **vLLM** | `8000` | OpenAI-compatible inference server |
| **Prometheus** | `9090` | Metrics collection & storage |
| **Grafana** | `3000` | Dashboards & visualization |

**Default model:** [Qwen2.5-3B-Instruct-AWQ](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-AWQ) (~2GB, 4-bit quantized)

## Quick Start

### Prerequisites

- NVIDIA GPU with drivers installed
- Docker & Docker Compose
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### 1. Clone & configure

```bash
git clone <your-repo-url>
cd llm_inference_engine_v1
cp .env.example .env
# Edit .env if you want to change the model, ports, etc.
```

### 2. Start the stack

```bash
docker compose up -d
```

First startup downloads the model (~2GB). Watch progress:

```bash
docker compose logs -f vllm
```

### 3. Verify it's working

```bash
bash scripts/smoke-test.sh
```

### 4. Use the API

The API is fully compatible with the OpenAI SDK:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"  # no auth required
)

response = client.chat.completions.create(
    model="Qwen/Qwen2.5-3B-Instruct-AWQ",
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=100
)

print(response.choices[0].message.content)
```

Or with `curl`:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct-AWQ",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

## Deploy on RunPod

### 1. Create a GPU Pod

- Go to [RunPod](https://runpod.io) and create a new GPU Pod
- **Recommended GPU:** RTX 4000 Ada (20GB VRAM, $0.26/hr) — cheapest option that works well
- **Template:** Runpod Pytorch (any recent version)
- **Enable SSH terminal access**

### 2. SSH into your pod and deploy

```bash
# SSH into the pod (RunPod provides the command)
ssh root@<pod-ip> -p <port> -i ~/.ssh/id_ed25519

# Clone the repo
git clone <your-repo-url>
cd llm_inference_engine_v1

# Run the deployment script (checks prerequisites & sets up .env)
bash scripts/deploy-runpod.sh

# Start the stack
docker compose up -d

# Watch vLLM startup (wait for "Uvicorn running on...")
docker compose logs -f vllm
```

### 3. Access the services

RunPod exposes ports via proxy URLs. Check your pod's connection info for:
- **API:** `https://<pod-id>-8000.proxy.runpod.net/v1`
- **Grafana:** `https://<pod-id>-3000.proxy.runpod.net` (login: admin/admin)
- **Prometheus:** `https://<pod-id>-9090.proxy.runpod.net`

## Monitoring

Grafana comes pre-configured with a **vLLM Inference Dashboard** that shows:

- **Overview:** Running/waiting requests, KV cache usage, prefix cache hit rate
- **Latency:** End-to-end latency, time to first token (TTFT), time per output token (TPOT) — all at p50/p90/p99
- **Throughput:** Requests/s and tokens/s (prompt vs generation)
- **Cache & Memory:** KV cache utilization and prefix cache hit rates over time

Access Grafana at `http://localhost:3000` (default credentials: `admin` / `admin`).

## Benchmarking

Run a simple load test:

```bash
# Default: 10 requests, 100 max tokens, 3 concurrent
bash scripts/benchmark.sh

# Custom: 50 requests, 200 max tokens, 5 concurrent
bash scripts/benchmark.sh 50 200 5
```

## Configuration

All settings are in `.env`. Key options:

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL_NAME` | `Qwen/Qwen2.5-3B-Instruct-AWQ` | HuggingFace model ID |
| `MAX_MODEL_LEN` | `4096` | Max sequence length (tokens) |
| `QUANTIZATION` | `awq` | Quantization method |
| `GPU_MEMORY_UTILIZATION` | `0.90` | GPU memory fraction for model |
| `TENSOR_PARALLEL_SIZE` | `1` | Number of GPUs for tensor parallelism |
| `ENABLE_PREFIX_CACHING` | `true` | Cache common prompt prefixes |
| `VLLM_PORT` | `8000` | vLLM API port |
| `GRAFANA_PORT` | `3000` | Grafana port |
| `PROMETHEUS_PORT` | `9090` | Prometheus port |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Grafana admin password |

### Using a different model

```bash
# Edit .env
MODEL_NAME=Qwen/Qwen2.5-7B-Instruct-AWQ
MAX_MODEL_LEN=8192

# Restart vLLM
docker compose up -d vllm
```

## Project Structure

```
.
├── docker-compose.yml          # Main stack definition
├── .env.example                # Configuration template
├── prometheus/
│   └── prometheus.yml          # Prometheus scrape config
├── grafana/
│   ├── dashboards/
│   │   └── vllm.json           # Pre-built Grafana dashboard
│   └── provisioning/
│       ├── dashboards/
│       │   └── dashboard.yml   # Dashboard auto-provisioning
│       └── datasources/
│           └── datasource.yml  # Prometheus datasource config
└── scripts/
    ├── smoke-test.sh           # Quick health & functionality check
    ├── benchmark.sh            # Load testing script
    └── deploy-runpod.sh        # RunPod setup script
```

## Troubleshooting

### vLLM won't start / OOM

- Lower `GPU_MEMORY_UTILIZATION` in `.env` (try `0.80`)
- Reduce `MAX_MODEL_LEN` (try `2048`)
- Switch to a smaller model

### "NVIDIA Container Toolkit not found"

```bash
# Install on Ubuntu/Debian
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L "https://nvidia.github.io/libnvidia-container/${distribution}/libnvidia-container.list" | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Grafana dashboard shows "No data"

- Wait 1-2 minutes for Prometheus to scrape initial metrics
- Send a few requests to generate data
- Check Prometheus targets at `http://localhost:9090/targets` — vLLM should show as "UP"

### Model download is slow

The HuggingFace cache is stored in a Docker volume (`vllm-hf-cache`). After the first download, restarts are fast. To persist across pod recreations on RunPod, consider attaching a network volume.

## License

See [LICENSE](LICENSE).
