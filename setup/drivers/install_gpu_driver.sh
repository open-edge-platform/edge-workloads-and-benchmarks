#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
GPU_DRIVER_VERSION="26.09.37435.1"
IGC_VERSION="2.30.1"
IGC_BUILD="20950"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DRIVER_DIR="${SCRIPT_DIR}/gpu/${GPU_DRIVER_VERSION}"

# Preserve the original user (not root when running with sudo)
ORIGINAL_USER="${ORIGINAL_USER:-${SUDO_USER:-$USER}}"

echo "GPU Driver Installation"
echo -e "${CYAN}[ Info ]${NC} Driver Version: ${GPU_DRIVER_VERSION}"
echo -e "${CYAN}[ Info ]${NC} IGC Version: ${IGC_VERSION}"

# Check for GPU
echo -e "${CYAN}[ Info ]${NC} Checking for GPU..."
if lspci | grep -E 'VGA|Display|3D' | grep -qi "Intel"; then
    echo -e "${CYAN}[ Info ]${NC} GPU detected"
else
    echo -e "${RED}[ Error ]${NC} No Intel GPU detected"
    exit 1
fi
echo ""

# Create driver directory
mkdir -p "$DRIVER_DIR"
cd "$DRIVER_DIR"

echo ""
echo -e "${CYAN}[ Info ]${NC} Downloading GPU driver packages..."

# Package list
declare -a packages=(
    "https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC_VERSION}/intel-igc-core-2_${IGC_VERSION}+${IGC_BUILD}_amd64.deb"
    "https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC_VERSION}/intel-igc-opencl-2_${IGC_VERSION}+${IGC_BUILD}_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-ocloc-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-ocloc_${GPU_DRIVER_VERSION}-0_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-opencl-icd-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/intel-opencl-icd_${GPU_DRIVER_VERSION}-0_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libigdgmm12_22.9.0_amd64.deb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libze-intel-gpu1-dbgsym_${GPU_DRIVER_VERSION}-0_amd64.ddeb"
    "https://github.com/intel/compute-runtime/releases/download/${GPU_DRIVER_VERSION}/libze-intel-gpu1_${GPU_DRIVER_VERSION}-0_amd64.deb"
)

# Download packages if not already present
download_failed=0
for url in "${packages[@]}"; do
    filename=$(basename "$url")
    if [ -f "$filename" ]; then
        echo -e "${CYAN}[ Info ]${NC} $filename already downloaded, skipping"
    else
        wget -q --show-progress "$url" || { echo -e "${RED}[ FAILED ]${NC} Failed to download $filename"; download_failed=1; }
    fi
done

if [[ "${download_failed}" -eq 1 ]]; then
    echo -e "${RED}[ Error ]${NC} Some packages failed to download. Please retry."
    exit 1
fi

echo ""
echo -e "${CYAN}[ Info ]${NC} Installing OpenCL ICD loader..."
sudo apt-get update -qq
sudo apt --fix-broken install -y --allow-downgrades -qq 2>/dev/null
sudo apt-get install -y ocl-icd-libopencl1

echo -e "${CYAN}[ Info ]${NC} Installing GPU driver packages..."
sudo dpkg -i ./*.deb 2>/dev/null || sudo apt-get install -f -y -qq

echo ""
echo -e "${CYAN}[ Info ]${NC} Adding user ${ORIGINAL_USER} to video and render groups..."
sudo usermod -aG video "${ORIGINAL_USER}"
sudo usermod -aG render "${ORIGINAL_USER}"

if command -v clinfo >/dev/null 2>&1; then
    if clinfo 2>/dev/null | grep -qi "intel"; then
        echo -e "${GREEN}[ Success ]${NC} GPU driver installed successfully"
    else
        echo -e "${YELLOW}[ Warning ]${NC} Driver installed but OpenCL device not detected"
        echo -e "${CYAN}[ Info ]${NC} This may require a system reboot"
    fi
else
    sudo apt-get install -y -qq clinfo
    if clinfo 2>/dev/null | grep -qi "intel"; then
        echo -e "${GREEN}[ Success ]${NC} GPU driver installed successfully"
    else
        echo -e "${YELLOW}[ Warning ]${NC} Driver installed but OpenCL device not detected"
        echo -e "${CYAN}[ Info ]${NC} This may require a system reboot"
    fi
fi
