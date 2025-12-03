#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Edge Workloads and Benchmarks System Compatibility Check
# Quick validation of system requirements before installation
# ==============================================================================

echo "========================================================"
echo "Edge Workloads and Benchmarks System Compatibility Check"
echo "========================================================"
echo ""

# Color-coding
print_pass() { echo -e "\e[32m[ Pass ]\e[0m $1"; }
print_fail() { echo -e "\e[31m[ Fail ]\e[0m $1"; }
print_warn() { echo -e "\e[33m[ Warning ]\e[0m $1"; }
print_info() { echo -e "\e[34m[ Info ]\e[0m $1"; }

WARNINGS=0
ERRORS=0

# OS Version
echo "Checking Operating System..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        if [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]]; then
            print_pass "Ubuntu $VERSION_ID detected"
        else
            print_warn "Ubuntu $VERSION_ID detected. Recommendation: 22.04 or 24.04"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        print_warn "Non-Ubuntu system detected: $NAME $VERSION_ID"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_fail "Cannot detect operating system"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Docker Installation
echo "Checking Docker..."
if command -v docker >/dev/null 2>&1; then
    DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
    print_pass "Docker installed: $DOCKER_VERSION"
    
    # Test docker permissions
    if docker run --rm hello-world >/dev/null 2>&1; then
        print_pass "Docker is functional"
    else
        print_fail "Docker installed but cannot run containers"
        print_info "Try: sudo usermod -aG docker \$USER && newgrp docker"
        ERRORS=$((ERRORS + 1))
    fi
else
    print_fail "Docker not installed"
    print_info "Install: https://docs.docker.com/engine/install/ubuntu/"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# GPU Driver
echo "Checking GPU..."
if command -v clinfo >/dev/null 2>&1; then
    GPU_VERSION=$(clinfo 2>/dev/null | grep -m1 "Driver Version" | awk '{print $3}' || echo "unknown")
    if [ "$GPU_VERSION" != "unknown" ] && [ -n "$GPU_VERSION" ]; then
        print_pass "OpenCL detected: $GPU_VERSION"
    else
        print_warn "clinfo installed but no devices found"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_warn "clinfo not installed. Please install with sudo apt install clinfo"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for GPU render devices
if ls /dev/dri/render* >/dev/null 2>&1; then
    RENDER_DEVICES=$(find /dev/dri -name "render*" -type c 2>/dev/null | wc -l)
    print_pass "GPU render devices found: $RENDER_DEVICES device(s)"
else
    print_warn "No GPU render devices found at /dev/dri/render*"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# VAAPI Driver
echo "Checking VA-API..."
if command -v vainfo >/dev/null 2>&1; then
    VAAPI_OUTPUT=$(vainfo 2>&1)
    if echo "$VAAPI_OUTPUT" | grep -q "VAProfileH264"; then
        VAAPI_VERSION=$(echo "$VAAPI_OUTPUT" | grep "libva info: VA-API version" | awk '{print $NF}')
        print_pass "VA-API functional: $VAAPI_VERSION"
    else
        print_warn "vainfo installed but VA-API may not be functional"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_warn "vainfo not installed. Please install with sudo apt install vainfo"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# NPU (Optional)
echo "Checking NPU..."
if ls /dev/accel/accel* >/dev/null 2>&1; then
    NPU_DEVICES=$(find /dev/accel -name "accel*" -type c 2>/dev/null | wc -l)
    print_pass "NPU device(s) detected: $NPU_DEVICES device(s)"

    if dpkg -l | grep -q "intel-driver-compiler-npu"; then
        NPU_VERSION=$(dpkg -l | grep intel-driver-compiler-npu | awk '{print $3}')
        print_pass "NPU driver installed: $NPU_VERSION"
    else
        print_warn "NPU hardware detected but driver not installed"
        print_info "Install NPU drivers with: ./setup/install_npu_driver.sh"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_info "No NPU detected (optional)"
fi
echo ""

# System Resources
echo "Checking System Resources..."
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM_GB" -ge 8 ]; then
    print_pass "RAM: ${TOTAL_RAM_GB}GB (8GB+ recommended)"
else
    print_warn "RAM: ${TOTAL_RAM_GB}GB (8GB+ recommended)"
    WARNINGS=$((WARNINGS + 1))
fi

# Disk Space
AVAILABLE_SPACE=$(df -h . | tail -n1 | awk '{print $4}')
AVAILABLE_SPACE_NUM=$(echo "$AVAILABLE_SPACE" | grep -oP '^\d+' || echo "0")
AVAILABLE_SPACE_UNIT=$(echo "$AVAILABLE_SPACE" | grep -oP '[A-Z]+$' || echo "")

if [ "$AVAILABLE_SPACE_UNIT" = "G" ] && [ "$AVAILABLE_SPACE_NUM" -ge 11 ]; then
    print_pass "Available disk space: ${AVAILABLE_SPACE} (11GB+ recommended)"
elif [ "$AVAILABLE_SPACE_UNIT" = "T" ]; then
    print_pass "Available disk space: ${AVAILABLE_SPACE} (11GB+ recommended)"
else
    print_warn "Available disk space: ${AVAILABLE_SPACE} (11GB+ recommended for models and media)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "================================================"
echo "Compatibility Check Summary"
echo "================================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_pass "All checks passed. System is ready for Edge Workloads and Benchmarks installation."
    echo ""
    echo "Next steps:"
    echo "  1. setup/install_prerequisites.sh [--reinstall-gpu-driver=yes] [--reinstall-npu-driver=yes]"
    echo "  2. cd model-conversion/ && ./convert_models.sh"
    echo "  3. cd media-downloader && ./download_and_encode.sh"
    echo "  4. ./benchmark_edge_pipelines.sh -p light -n 8 -d GPU -c GPU -i 120"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    print_warn "System check completed with $WARNINGS warning(s)"
    echo ""
    echo "You can proceed with installation, but some features may be limited."
    echo "Review the warnings listed above."
    exit 0
else
    print_fail "System check failed with $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo "Please resolve the errors above before proceeding with installation."
    exit 1
fi
