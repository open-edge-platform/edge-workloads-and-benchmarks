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
NPU_DRIVER_VERSION="v1.32.0"
NPU_DRIVER_BUILD="20260402-23905121947"
LEVEL_ZERO_VERSION="1.27.0"

LEVEL_ZERO_PKG="libze1_${LEVEL_ZERO_VERSION}-1~24.04~ppa2_amd64.deb"
LEVEL_ZERO_URL="https://snapshot.ppa.launchpadcontent.net/kobuk-team/intel-graphics/ubuntu/20260324T100000Z/pool/main/l/level-zero-loader/${LEVEL_ZERO_PKG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DRIVER_DIR="${SCRIPT_DIR}/npu/${NPU_DRIVER_VERSION}"

# Preserve the original user (not root when running with sudo)
ORIGINAL_USER="${ORIGINAL_USER:-${SUDO_USER:-$USER}}"

echo "NPU Driver Installation"
echo -e "${CYAN}[ Info ]${NC} Driver Version: ${NPU_DRIVER_VERSION}"
echo -e "${CYAN}[ Info ]${NC} Level Zero: ${LEVEL_ZERO_VERSION}"

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
case "$UBUNTU_VERSION" in
    24.04)
        echo -e "${CYAN}[ Info ]${NC} Ubuntu $UBUNTU_VERSION detected"
        ;;
    *)
        echo -e "${RED}[ Error ]${NC} Unsupported Ubuntu version: $UBUNTU_VERSION"
        echo "NPU driver ${NPU_DRIVER_VERSION} requires Ubuntu 24.04"
        exit 1
        ;;
esac

# Check for NPU
echo -e "${CYAN}[ Info ]${NC} Checking for NPU..."
NPU_DETECTED=false
if lspci | grep -i "processing.*intel" > /dev/null 2>&1; then
    echo -e "${CYAN}[ Info ]${NC} NPU detected"
    NPU_DETECTED=true
    echo ""
elif lspci | grep -E "0b40|0bd4|0b70" > /dev/null 2>&1; then
    echo -e "${CYAN}[ Info ]${NC} NPU detected"
    NPU_DETECTED=true
    echo ""
fi

if [ "$NPU_DETECTED" = false ]; then
    echo -e "${YELLOW}[ Warning ]${NC} No NPU detected"
    echo -e "${CYAN}[ Info ]${NC} NPU requires Core Ultra processors (Meteor Lake+)"
    read -p "Continue installation anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Remove existing NPU packages if present
if dpkg -l | grep -q "intel.*npu" 2>/dev/null; then
    echo -e "${CYAN}[ Info ]${NC} Removing existing NPU packages..."
    sudo dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu intel-level-zero-npu-dbgsym 2>/dev/null || true
fi

# Create driver directory
mkdir -p "$DRIVER_DIR"
cd "$DRIVER_DIR"

echo ""
echo -e "${CYAN}[ Info ]${NC} Downloading NPU driver packages..."

NPU_DRIVER_PKG="linux-npu-driver-${NPU_DRIVER_VERSION}.${NPU_DRIVER_BUILD}-ubuntu2404.tar.gz"

# Download NPU driver package if not present
if [ -f "$NPU_DRIVER_PKG" ]; then
    echo -e "${CYAN}[ Info ]${NC} $NPU_DRIVER_PKG already downloaded, skipping"
else
    wget -q --show-progress "https://github.com/intel/linux-npu-driver/releases/download/${NPU_DRIVER_VERSION}/${NPU_DRIVER_PKG}"
fi

if [[ -z "$(find . -maxdepth 1 -name "linux-npu-driver-*" -type d -print -quit)" ]]; then
    echo -e "${CYAN}[ Info ]${NC} Extracting NPU driver package..."
    tar -xf "${NPU_DRIVER_PKG}"
fi

echo -e "${CYAN}[ Info ]${NC} Installing dependencies..."
sudo apt-get update -qq
sudo apt --fix-broken install -y --allow-downgrades -qq 2>/dev/null
sudo apt-get install -y libtbb12

echo -e "${CYAN}[ Info ]${NC} Installing NPU driver packages..."
sudo dpkg -i ./*.deb 2>/dev/null || sudo apt-get install -f -y -qq

# Install Level Zero (libze1) from intel-graphics PPA snapshot.
echo ""
echo -e "${CYAN}[ Info ]${NC} Installing Level Zero ${LEVEL_ZERO_VERSION}..."
if [ -f "$LEVEL_ZERO_PKG" ]; then
    echo -e "${CYAN}[ Info ]${NC} $LEVEL_ZERO_PKG already downloaded, skipping"
else
    wget -q --show-progress "${LEVEL_ZERO_URL}"
fi
sudo dpkg -i "${LEVEL_ZERO_PKG}" 2>/dev/null || {
    echo -e "${CYAN}[ Info ]${NC} Resolving Level Zero conflict..."
    sudo dpkg --purge --force-remove-reinstreq level-zero level-zero-devel 2>/dev/null || true
    sudo dpkg -i "${LEVEL_ZERO_PKG}"
}

echo ""
echo -e "${CYAN}[ Info ]${NC} Adding user ${ORIGINAL_USER} to video and render groups..."
sudo usermod -aG video "${ORIGINAL_USER}"
sudo usermod -aG render "${ORIGINAL_USER}"

if ls /dev/accel/accel* >/dev/null 2>&1; then
    echo -e "${GREEN}[ Success ]${NC} NPU driver installed successfully"
else
    echo -e "${YELLOW}[ Warning ]${NC} Driver installed but NPU devices not detected"
    echo -e "${CYAN}[ Info ]${NC} This requires a system reboot"
fi
