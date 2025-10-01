#!/bin/bash
set -e

echo "Building ZDM Proxy v2.3.4 for ARM64..."

# Create temporary directory for build
BUILD_DIR="/tmp/zdm-proxy-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone the repository
echo "Cloning ZDM proxy repository..."
git clone https://github.com/datastax/zdm-proxy.git .

# Checkout v2.3.4 tag
echo "Checking out v2.3.4..."
git checkout v2.3.4

# Copy our ARM64 Dockerfile
echo "Using ARM64 Dockerfile..."
cp /Users/aldrine.einsteen/projects/kube-cas5-zdm-astra-demo/k8s/zdm-proxy/Dockerfile.arm64 ./Dockerfile

# Build the image
echo "Building Docker image for ARM64..."
podman build -t zdm-proxy:2.3.4-arm64 .

# Save and load into kind cluster
echo "Loading image into kind cluster..."
podman save zdm-proxy:2.3.4-arm64 -o /tmp/zdm-proxy-arm64.tar
kind load image-archive /tmp/zdm-proxy-arm64.tar --name zdm-demo

# Cleanup
echo "Cleaning up..."
rm -rf "$BUILD_DIR"
rm -f /tmp/zdm-proxy-arm64.tar

echo "✅ ZDM Proxy v2.3.4 ARM64 build complete!"
echo "Image available as: zdm-proxy:2.3.4-arm64"