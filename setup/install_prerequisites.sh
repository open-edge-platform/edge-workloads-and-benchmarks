#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Edge Workloads and Benchmarks Prerequisites Installer
# ==============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO_PREFIX="sudo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
REINSTALL_GPU_DRIVER='no'
REINSTALL_NPU_DRIVER='no'

# Show help message
show_help() {
    cat <<EOF

Usage: $(basename "$0") [OPTIONS]

Prerequisites installer for Edge Workloads and Benchmarks Pipelines

Options:
  -h, --help                          Show this help message and exit
  --reinstall-gpu-driver=yes          Install GPU driver (default: no)
  --reinstall-npu-driver=yes          Install NPU driver (default: no)

Examples:
  $(basename "$0")                                            # Prerequisites only (no drivers)
  $(basename "$0") --reinstall-gpu-driver=yes                 # Prerequisites + GPU driver
  $(basename "$0") --reinstall-gpu-driver=yes --reinstall-npu-driver=yes  # All drivers

Note: Driver installation is optional. The system will use existing drivers if available.
      NPU Driver installation requires system reboot to take effect.

EOF
}

# Parse command-line arguments
for i in "$@"; do
    case $i in
        -h|--help)
            show_help
            exit 0
        ;;
        --reinstall-gpu-driver=*)
            REINSTALL_GPU_DRIVER="${i#*=}"
            shift
        ;;
        --reinstall-npu-driver=*)
            REINSTALL_NPU_DRIVER="${i#*=}"
            shift
        ;;
        *)
            echo -e "${RED}[ Error ]${NC} Unknown option: $i"
            show_help
            exit 1
        ;;
    esac
done

echo "Edge Workloads and Benchmarks Prerequisites Installation"
echo "GPU driver: $REINSTALL_GPU_DRIVER"
echo "NPU driver: $REINSTALL_NPU_DRIVER"
echo ""

# Timeout configuration
APT_UPDATE_TIMEOUT=60
APT_GET_TIMEOUT=600

# Check if running as root
if [[ $EUID -eq 0 ]] && [[ "${SUDO_PREFIX}" != "" ]]; then
   echo -e "${RED}[ Error ]${NC} This script should not be run as root"
   exit 1
fi

# Detect Ubuntu version
ubuntu_version=$(lsb_release -rs)
case "$ubuntu_version" in
    24.04|22.04)
        echo "[ Info ] Ubuntu $ubuntu_version detected"
        ;;
    *)
        echo -e "${RED}[ Error ]${NC} Unsupported Ubuntu version: $ubuntu_version"
        exit 1
        ;;
esac

# Get CPU information
cpu_model_name=$(lscpu | grep "Model name:" | awk -F: '{print $2}' | xargs)
echo "[ Info ] CPU: $cpu_model_name"
echo ""

update_package_lists() {
    timeout --foreground $APT_UPDATE_TIMEOUT $SUDO_PREFIX apt-get update 2>&1
    local update_exit_code=$?

    if [ $update_exit_code -eq 124 ]; then
        echo -e "${RED}[ Error ]${NC} Update process timed out"
        exit 1
    elif [ $update_exit_code -ne 0 ]; then
        echo -e "${RED}[ Error ]${NC} Failed to update package lists"
        exit 1
    fi
}

install_packages() {
    local log_file
    log_file=$(mktemp)

    timeout --foreground $APT_GET_TIMEOUT $SUDO_PREFIX apt-get install -y --allow-downgrades "$@" 2>&1 | tee "$log_file"
    local status=${PIPESTATUS[0]}

    if [[ $status -eq 124 ]]; then
        echo -e "${RED}[ Error ]${NC} Installation timed out"
        rm -f "$log_file"
        exit 1
    elif [ "$status" -ne 0 ]; then
        echo -e "${RED}[ Error ]${NC} Package installation failed"
        rm -f "$log_file"
        exit 1
    fi
    rm -f "$log_file"
}

add_user_to_group() {
    local group="$1"
    if ! getent group "$group" > /dev/null; then
        echo -e "${RED}[ Error ]${NC} Group '$group' does not exist"
        exit 1
    fi

    if id -nG "$USER" | tr ' ' '\n' | grep -q "^$group$"; then
        return 0
    else
        $SUDO_PREFIX usermod -aG "$group" "$USER"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[ Success ]${NC} Added user $USER to group $group"
            return 0
        else
            echo -e "${RED}[ Error ]${NC} Failed to add user to group $group"
            exit 1
        fi
    fi
}

# Docker install function
install_docker() {
    if command -v docker &> /dev/null; then
        local docker_version
	docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')

        echo "[ Info ] Docker already installed (version $docker_version)"
        return 0
    fi

    echo "[ Info ] Docker not found - installing..."

    # Add Docker GPG key
    $SUDO_PREFIX install -m 0755 -d /etc/apt/keyrings
    $SUDO_PREFIX curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    $SUDO_PREFIX chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      $SUDO_PREFIX tee /etc/apt/sources.list.d/docker.list > /dev/null

    update_package_lists
    install_packages \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    echo "[ Info ] Docker installation complete"
}

# GPU compute driver installation (optional)
install_gpu_driver() {
    if [ "$REINSTALL_GPU_DRIVER" = "yes" ]; then
        echo ""
        echo -e "${GREEN}[ GPU Driver Installation ]${NC}"
        bash "$SCRIPT_DIR/drivers/install_gpu_driver.sh"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ Error ]${NC} GPU driver installation failed"
            exit 1
        fi
    fi
}

# NPU compute driver installation (optional)
install_npu_driver() {
    if [ "$REINSTALL_NPU_DRIVER" = "yes" ]; then
        echo ""
        echo -e "${GREEN}[ NPU Driver Installation ]${NC}"
        bash "$SCRIPT_DIR/drivers/install_npu_driver.sh"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ Error ]${NC} NPU driver installation failed"
            exit 1
        fi
    fi
}

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  Prerequisites Installation  ${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""

echo "[ Info ] Updating package lists..."
update_package_lists
install_gpu_driver 
install_npu_driver

echo ""
echo "[ Info ] Installing essential packages..."
$SUDO_PREFIX apt --fix-broken install -y -qq
install_packages \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    cmake \
    git \
    wget \
    python3-dev \
    python3-pip \
    python3-venv \
    ffmpeg \
    cpuid\
    vainfo \
    clinfo \
    intel-gpu-tools

echo ""
install_docker

need_to_logout=0
add_user_to_group docker
if [ $? -eq 1 ]; then
    need_to_logout=1
fi

# Add user to render group for GPU/NPU compute access
if [ -d /dev/dri ]; then
    add_user_to_group render
    if [ $? -eq 1 ]; then
        need_to_logout=1
    fi
fi

echo ""
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}  Installation Complete${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""

if [ $need_to_logout -eq 1 ]; then
    echo -e "${GREEN}[ Success ]${NC} Please log out and back in for group changes to take effect"
fi

echo ""
echo "[ Info ] Run setup/check-compatibility.sh to verify your system"
echo ""
