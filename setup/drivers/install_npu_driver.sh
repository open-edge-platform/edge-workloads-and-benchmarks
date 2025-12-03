#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# NPU Compute Driver: v1.23.0


set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
NPU_DRIVER_VERSION="v1.23.0"
LEVEL_ZERO_VERSION="1.22.4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DRIVER_DIR="${SCRIPT_DIR}/npu/${NPU_DRIVER_VERSION}"

echo "NPU Driver Installation"
echo "Driver Version: ${NPU_DRIVER_VERSION}"
echo ""

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
case "$UBUNTU_VERSION" in
    24.04|22.04)
        echo "[ Info ] Ubuntu $UBUNTU_VERSION detected"
        ;;
    *)
        echo -e "${RED}[ Error ]${NC} Unsupported Ubuntu version: $UBUNTU_VERSION"
        echo "NPU drivers require Ubuntu 22.04 or 24.04"
        exit 1
        ;;
esac

# Check for NPU
echo "[ Info ] Checking for NPU..."
NPU_DETECTED=false
if lspci | grep -i "processing.*intel" > /dev/null 2>&1; then
    echo -e "[ Info ] NPU detected${NC}"
    NPU_DETECTED=true
elif lspci | grep -E "0b40|0bd4|0b70" > /dev/null 2>&1; then
    echo -e "[ Info ] NPU detected${NC}"
    NPU_DETECTED=true
fi

if [ "$NPU_DETECTED" = false ]; then
    echo "[ Warning ] No NPU detected"
    echo "[ Info ] NPU requires Core Ultra processors (Meteor Lake+)"
    read -p "Continue installation anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Remove existing NPU packages if present
if dpkg -l | grep -q "intel.*npu" 2>/dev/null; then
    echo "[ Info ] Removing existing NPU packages..."
    sudo dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu 2>/dev/null || true
fi

# Create driver directory
mkdir -p "$DRIVER_DIR"
cd "$DRIVER_DIR"

echo ""
echo "[ Info ] Downloading NPU driver packages..."

if [ "$UBUNTU_VERSION" == "22.04" ]; then
    LEVEL_ZERO_PKG="level-zero_${LEVEL_ZERO_VERSION}+u22.04_amd64.deb"
    NPU_DRIVER_PKG="linux-npu-driver-v1.23.0.20250827-17270089246-ubuntu2204.tar.gz"
elif [ "$UBUNTU_VERSION" == "24.04" ]; then
    LEVEL_ZERO_PKG="level-zero_${LEVEL_ZERO_VERSION}+u24.04_amd64.deb"
    NPU_DRIVER_PKG="linux-npu-driver-v1.23.0.20250827-17270089246-ubuntu2404.tar.gz"
fi

# Download Level Zero if not present
if [ -f "$LEVEL_ZERO_PKG" ]; then
    echo "[ Info ] $LEVEL_ZERO_PKG already downloaded, skipping"
else
    wget -q --show-progress "https://github.com/oneapi-src/level-zero/releases/download/v${LEVEL_ZERO_VERSION}/${LEVEL_ZERO_PKG}"
fi

# Download NPU driver package if not present
if [ -f "$NPU_DRIVER_PKG" ]; then
    echo "[ Info ] $NPU_DRIVER_PKG already downloaded, skipping"
else
    wget -q --show-progress "https://github.com/intel/linux-npu-driver/releases/download/${NPU_DRIVER_VERSION}/${NPU_DRIVER_PKG}"
fi

if [[ -z "$(find . -maxdepth 1 -name "linux-npu-driver-*" -type d -print -quit)" ]]; then
    echo "[ Info ] Extracting NPU driver package..."
    tar -xf "${NPU_DRIVER_PKG}"
fi

echo ""
echo "[ Info ] Installing dependencies..."
sudo apt-get update -qq
sudo apt --fix-broken install -y -qq
sudo apt-get install -y -qq libtbb12

echo ""
echo "[ Info ] Installing NPU driver packages..."
sudo dpkg -i ./*.deb 2>/dev/null || sudo apt-get install -f -y -qq

# Verify installation
echo ""
if ls /dev/accel/accel* >/dev/null 2>&1; then
    echo -e "${GREEN}[ Success ] NPU driver installed successfully${NC}"
    NPU_DEVICES=$(find /dev/accel -name "accel*" -type c 2>/dev/null | wc -l)
    echo "[ Info ] NPU devices detected: ${NPU_DEVICES}"
else
    echo "[ Warning ] Driver installed but NPU devices not detected"
    echo "[ Info ] This requires a system reboot"
fi

echo ""
echo "Installation Complete"
echo "===================="
echo ""
echo "Next Steps:"
echo "1. Verify NPU devices: ls /dev/accel/"
echo "2. Check kernel module: lsmod | grep intel_vpu"
echo "3. Download and convert your models."
echo "4. Download and convert your videos."
echo "5. Run Edge Workloads and Benchmarks pipelines with NPU acceleration"
echo ""

exit 0
