#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo -e "${BLUE}Building custom ZDM proxy from source...${NC}"

# Load environment variables
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    echo -e "${YELLOW}Loading environment variables from .env file...${NC}"
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found at ${PROJECT_ROOT}/.env${NC}"
    exit 1
fi

# Set default version if not specified
ZDM_VERSION="${ZDM_VERSION:-v2.3.4}"
echo -e "${BLUE}Building ZDM proxy version: ${ZDM_VERSION}${NC}"

# Build image name
IMAGE_NAME="localhost/zdm-demo/zdm-proxy:${ZDM_VERSION}"

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo -e "${RED}Error: podman is required but not installed${NC}"
    exit 1
fi

# Check if kind is available and cluster exists
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is required but not installed${NC}"
    exit 1
fi

if ! kind get clusters | grep -q "zdm-demo"; then
    echo -e "${RED}Error: kind cluster 'zdm-demo' not found. Run 'make up' first.${NC}"
    exit 1
fi

# Build the image
echo -e "${BLUE}Building ZDM proxy image for local architecture...${NC}"
cd "${SCRIPT_DIR}"

if podman build \
    --file Dockerfile.custom \
    --build-arg ZDMVERSION="${ZDM_VERSION}" \
    --build-arg TARGETARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
    --tag "${IMAGE_NAME}" \
    .; then
    echo -e "${GREEN}ZDM proxy image built successfully: ${IMAGE_NAME}${NC}"
else
    echo -e "${RED}Failed to build ZDM proxy image${NC}"
    exit 1
fi

# Load image into kind cluster
echo -e "${BLUE}Loading image into kind cluster...${NC}"
if podman save "${IMAGE_NAME}" | kind load image-archive --name zdm-demo /dev/stdin; then
    echo -e "${GREEN}Image loaded into kind cluster successfully${NC}"
else
    echo -e "${RED}Failed to load image into kind cluster${NC}"
    exit 1
fi

echo -e "${GREEN}Custom ZDM proxy build completed successfully!${NC}"
echo -e "${YELLOW}Image: ${IMAGE_NAME}${NC}"
echo -e "${YELLOW}Version: ${ZDM_VERSION}${NC}"
echo -e "${YELLOW}Architecture: $(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')${NC}"