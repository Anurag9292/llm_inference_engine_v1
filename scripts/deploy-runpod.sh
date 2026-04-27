#!/usr/bin/env bash
# =============================================================================
# RunPod Deployment Script
# Run this after SSHing into your RunPod GPU pod
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  RunPod Deployment Setup"
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
    echo "This script must run on a GPU-enabled machine."
    exit 1
fi

# 2. Check Docker
echo -n "[2/5] Checking Docker... "
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "${GREEN}OK${NC} - Docker ${DOCKER_VERSION}"
else
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    echo -e "${GREEN}OK${NC} - Docker installed"
fi

# 3. Check Docker Compose
echo -n "[3/5] Checking Docker Compose... "
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null)
    echo -e "${GREEN}OK${NC} - Docker Compose ${COMPOSE_VERSION}"
else
    echo -e "${YELLOW}Installing Docker Compose plugin...${NC}"
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin > /dev/null 2>&1
    echo -e "${GREEN}OK${NC} - Docker Compose installed"
fi

# 4. Check NVIDIA Container Toolkit
echo -n "[4/5] Checking NVIDIA Container Toolkit... "
if docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC} - GPU passthrough works"
else
    echo -e "${YELLOW}Installing NVIDIA Container Toolkit...${NC}"
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L "https://nvidia.github.io/libnvidia-container/${distribution}/libnvidia-container.list" | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    apt-get update -qq && apt-get install -y -qq nvidia-container-toolkit > /dev/null 2>&1
    nvidia-ctk runtime configure --runtime=docker > /dev/null 2>&1
    systemctl restart docker 2>/dev/null || true
    echo -e "${GREEN}OK${NC} - NVIDIA Container Toolkit installed"
fi

# 5. Setup environment
echo -n "[5/5] Setting up environment... "
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${GREEN}OK${NC} - Created .env from .env.example"
else
    echo -e "${GREEN}OK${NC} - .env already exists"
fi

echo ""
echo "============================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================"
echo ""
echo "  Start the stack:"
echo "    docker compose up -d"
echo ""
echo "  Watch logs:"
echo "    docker compose logs -f vllm"
echo ""
echo "  Run smoke test (after vLLM is ready):"
echo "    bash scripts/smoke-test.sh"
echo ""
echo "  NOTE: First startup downloads the model (~2GB)."
echo "  This may take a few minutes. Watch progress with:"
echo "    docker compose logs -f vllm"
echo ""
