#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# GPU Compute Driver: 25.27.34303.5

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
GPU_DRIVER_VERSION="25.27.34303.5"
IGC_VERSION="2.14.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DRIVER_DIR="${SCRIPT_DIR}/gpu/${GPU_DRIVER_VERSION}"

echo "GPU Driver Installation"
echo "Driver Version: ${GPU_DRIVER_VERSION}"
echo ""

# Check for GPU
echo "[ Info ] Checking for GPU..."
if lspci | grep -E 'VGA|Display|3D' | grep -qi "Intel"; then
    echo -e "[ Info ] GPU detected${NC}"
else
    echo -e "${RED}[ Error ]${NC} No GPU detected"
    exit 1
fi

# Create driver directory
mkdir -p "$DRIVER_DIR"
cd "$DRIVER_DIR"

echo ""
echo "[ Info ] Downloading GPU driver packages..."

# Package list
declare -a packages=(
    "https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC_VERSION}/intel-igc-core-2_${IGC_VERSION}+19448_amd64.deb"
    "https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC_VERSION}/intel-igc-opencl-2_${IGC_VERSION}+19448_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-ocloc-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-ocloc_${GPU_DRIVER_VERSION}-0_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-opencl-icd-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-opencl-icd_${GPU_DRIVER_VERSION}-0_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libigdgmm12_22.7.2_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libze-intel-gpu1-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libze-intel-gpu1_${GPU_DRIVER_VERSION}-0_amd64.deb"
)

# Download packages if not already present
for url in "${packages[@]}"; do
    filename=$(basename "$url")
    if [ -f "$filename" ]; then
        echo "[ Info ] $filename already downloaded, skipping"
    else
        wget -q --show-progress "$url"
    fi
done

echo ""
echo "[ Info ] Installing OpenCL ICD loader..."
sudo apt-get update -qq
sudo apt --fix-broken install -y -qq
sudo apt-get install -y -qq ocl-icd-libopencl1

echo ""
echo "[ Info ] Installing GPU driver packages..."
sudo dpkg -i ./*.deb 2>/dev/null || sudo apt-get install -f -y -qq

# Verify installation
echo ""
if command -v clinfo >/dev/null 2>&1; then
    if clinfo 2>/dev/null | grep -qi "intel"; then
        echo -e "${GREEN}[ Success ] GPU driver installed successfully${NC}"
    else
        echo "[ Warning ] Driver installed but OpenCL device not detected"
        echo "[ Info ] This may require a system reboot"
    fi
else
    echo "[ Info ] Installing clinfo for verification..."
    sudo apt-get install -y -qq clinfo
    if clinfo 2>/dev/null | grep -qi "intel"; then
        echo -e "${GREEN}[ Info ] GPU driver installed successfully${NC}"
    else
        echo "[ Warning ] Driver installed but OpenCL device not detected"
        echo "[ Info ] This may require a system reboot"
    fi
fi

echo ""
echo "Installation Complete"
echo "===================="
echo ""
echo "Next Steps:"
echo "1. Verify with: clinfo | grep Version"
echo "2. Download and convert your models."
echo "3. Download and convert your videos."
echo "4. Run Edge Workloads and Benchmarks pipelines with GPU acceleration"
echo "(Optional) Install NPU driver."
echo ""

exit 0
