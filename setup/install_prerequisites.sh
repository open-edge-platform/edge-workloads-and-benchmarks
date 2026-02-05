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
#
IS_EMT=false
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
if command -v lsb_release &> /dev/null; then
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
else
    if [ -f /etc/os-release ]; then
        os_name=$(grep -i '^NAME=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"')
        if echo "$os_name" | grep -qi "Edge Microvisor Toolkit"; then
            IS_EMT=true
            echo "[ Info ] Edge Microvisor Toolkit detected"
        else
            echo -e "${RED}[ Error ]${NC} Unsupported OS: $os_name"
            exit 1
        fi
    else
        echo -e "${RED}[ Error ]${NC} Unable to detect OS (missing lsb_release and /etc/os-release)"
        exit 1
    fi
fi

# Get CPU information
cpu_model_name=$(lscpu | grep "Model name:" | awk -F: '{print $2}' | xargs)
echo "[ Info ] CPU: $cpu_model_name"
echo ""

update_package_lists() {
    if [ "$IS_EMT" = true ]; then
        timeout --foreground $APT_UPDATE_TIMEOUT $SUDO_PREFIX tdnf makecache 2>&1
    else
        timeout --foreground $APT_UPDATE_TIMEOUT $SUDO_PREFIX apt-get update 2>&1
    fi
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

    if [ "$IS_EMT" = true ]; then
        timeout --foreground $APT_GET_TIMEOUT $SUDO_PREFIX tdnf install -y "$@" 2>&1 | tee "$log_file"
    else
        timeout --foreground $APT_GET_TIMEOUT $SUDO_PREFIX apt-get install -y --allow-downgrades "$@" 2>&1 | tee "$log_file"
    fi
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
    if [ "$IS_EMT" = true ]; then
        if command -v docker &> /dev/null; then
            echo "[ Info ] Docker preinstalled on Edge Microvisor Toolkit"
            if command -v systemctl &> /dev/null; then
                $SUDO_PREFIX systemctl enable docker
                $SUDO_PREFIX systemctl start docker
            else
                echo -e "${RED}[ Error ]${NC} systemctl not available to start Docker service"
                exit 1
            fi
            return 0
        else
            echo -e "${RED}[ Error ]${NC} Docker not found on Edge Microvisor Toolkit"
            exit 1
        fi
    fi

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
    if [ "$IS_EMT" = true ]; then
        echo "[ Info ] Skipping GPU driver install on Edge Microvisor Toolkit"
        return 0
    fi

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
    if [ "$IS_EMT" = true ]; then
        echo "[ Info ] Skipping NPU driver install on Edge Microvisor Toolkit"
        return 0
    fi

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
if [ "$IS_EMT" = true ]; then
    install_packages \
        ca-certificates \
        curl \
        gnupg \
        build-essential \
        cmake \
        git \
        wget \
        python3-pip \
        cpuid\
        intel-gpu-tools
else
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
fi

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
build_container() {
    echo ""
    echo -e "${GREEN}[ Info ]${NC} Building custom dlstreamer container for EMT"

    local http_proxy_value="${http_proxy:-${HTTP_PROXY:-}}"
    local https_proxy_value="${https_proxy:-${HTTPS_PROXY:-}}"
    local no_proxy_value="${no_proxy:-${NO_PROXY:-}}"

    if [ -z "$http_proxy_value" ]; then
        echo -e "${RED}[ Error ]${NC} http_proxy/HTTP_PROXY not set"
        exit 1
    fi

    if [ -z "$https_proxy_value" ]; then
        echo -e "${RED}[ Error ]${NC} https_proxy/HTTPS_PROXY not set"
        exit 1
    fi

    if [ -z "$no_proxy_value" ]; then
        echo -e "${RED}[ Error ]${NC} no_proxy/NO_PROXY not set"
        exit 1
    fi

    docker build \
        --build-arg YOUR_HTTP_PROXY="$http_proxy_value" \
        --build-arg YOUR_HTTPS_PROXY="$https_proxy_value" \
        --build-arg YOUR_NO_PROXY="$no_proxy_value" \
        --no-cache \
        -t intel/dlstreamer:custom .

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ Error ]${NC} Container image build failed"
        exit 1
    fi
}

if [ "$IS_EMT" = true ]; then
    cho ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}  Docker Container Build${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    build_container
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
