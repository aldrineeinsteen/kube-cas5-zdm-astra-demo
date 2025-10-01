#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    source .env
fi

ZDM_VERSION=${ZDM_VERSION:-v2.3.4}

echo -e "${YELLOW}Building ZDM Proxy ARM64 image for version ${ZDM_VERSION}...${NC}"

# Build the image with Podman
podman build \
    --build-arg ZDM_VERSION=${ZDM_VERSION} \
    --tag zdm-proxy-local:${ZDM_VERSION} \
    --file k8s/zdm-proxy/Dockerfile \
    k8s/zdm-proxy/

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully built zdm-proxy-local:${ZDM_VERSION}${NC}"
else
    echo -e "${RED}❌ Failed to build image${NC}"
    exit 1
fi

# Save image as tar and load into kind cluster
echo -e "${YELLOW}Saving image and loading into kind cluster...${NC}"
TEMP_TAR="/tmp/zdm-proxy-${ZDM_VERSION}.tar"
podman save -o "${TEMP_TAR}" zdm-proxy-local:${ZDM_VERSION}

# Load into kind cluster
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-zdm-demo}
kind load image-archive "${TEMP_TAR}" --name "${KIND_CLUSTER_NAME}"

# Also tag the image for podman/docker compatibility
podman tag zdm-proxy-local:${ZDM_VERSION} docker.io/library/zdm-proxy-local:${ZDM_VERSION}
podman save -o "${TEMP_TAR}" docker.io/library/zdm-proxy-local:${ZDM_VERSION}
kind load image-archive "${TEMP_TAR}" --name "${KIND_CLUSTER_NAME}"

rm -f "${TEMP_TAR}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully loaded image into kind cluster${NC}"
    echo -e "${GREEN}You can now run 'make zdm' to deploy the ZDM proxy${NC}"
else
    echo -e "${RED}❌ Failed to load image into kind cluster${NC}"
    exit 1
fi