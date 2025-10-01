# ZDM Proxy ARM64 Build

This directory contains the setup to build ZDM proxy v2.3.4 for ARM64 architecture.

## Build Process

1. Clone the repository
2. Checkout the v2.3.4 tag  
3. Build with ARM64 architecture
4. Load into kind cluster

## Usage

```bash
# Build the ARM64 image
make build-zdm-arm64

# Deploy the custom built image
make zdm-arm64
```

## Files

- `Dockerfile.arm64` - Modified Dockerfile for ARM64 builds
- `build-zdm.sh` - Build script for the custom image