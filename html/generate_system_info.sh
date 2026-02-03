#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/system_info.json"

echo "[ Info ] Collecting system information..."

# Helper function to replace trademark symbols
replace_trademarks() {
    local text="$1"
    text="${text//(R)/®}"
    text="${text//(TM)/™}"
    text="${text//(C)/©}"
    echo "$text"
}

# System Name
System="$(lscpu | grep "Model name" | grep -v "BIOS" | sed -n 's/^Model name://p' | sed 's/.*Intel/Intel/g' | xargs)"
System="$(replace_trademarks "$System")"

# GPU Driver Version
GPU_Driver="N/A"
if command -v clinfo >/dev/null 2>&1; then
    GPU_Driver=$(clinfo 2>/dev/null | grep -m1 "Driver Version" | awk '{print $3}' || echo "N/A")
fi

# VA-API Version
VAAPI_Version="N/A"
if command -v vainfo >/dev/null 2>&1; then
    VAAPI_Version=$(vainfo 2>&1 | grep "libva info: VA-API version" | awk '{print $NF}' || echo "N/A")
fi

# NPU Driver Version
NPU_Version="N/A"
if dpkg -l 2>/dev/null | grep -q "intel-driver-compiler-npu"; then
    NPU_Version=$(dpkg -l | grep intel-driver-compiler-npu | awk '{print $3}' || echo "N/A")
elif ls /dev/accel/accel* >/dev/null 2>&1; then
    NPU_Version="Hardware detected (driver not installed)"
fi

# DLStreamer Version
DLStreamer_Version="N/A"
if command -v docker >/dev/null 2>&1; then
    if docker images | grep -q "intel/dlstreamer"; then
        DLStreamer_Version=$(docker run --rm --init intel/dlstreamer:weekly-2026.0-20260127-ubuntu24 apt list 2>/dev/null | grep -E "dlstreamer|gstreamer" | head -n1 | awk '{print $2}' || echo "latest")
    fi
fi

# OpenVINO Version
OpenVINO_Version="N/A"
if command -v docker >/dev/null 2>&1; then
    if docker images | grep -q "intel/dlstreamer"; then
        OpenVINO_Version=$(docker run --rm --init intel/dlstreamer:weekly-2026.0-20260127-ubuntu24 apt list 2>/dev/null | grep openvino | head -n1 | awk '{print $2}' || echo "N/A")
    fi
fi

# Docker Version
Docker_Version="N/A"
if command -v docker >/dev/null 2>&1; then
    Docker_Version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "N/A")
fi

# OS Information
OS_Name="Unknown"
OS_Version="Unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_Name="$NAME"
    OS_Version="$VERSION_ID"
fi

# Kernel Version
Kernel_Version=$(uname -r || echo "N/A")

# Timestamp
Timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Generate JSON
cat > "$OUTPUT_FILE" << EOF
{
  "generated": "$Timestamp",
  "system": {
    "name": "$System",
    "os": "$OS_Name $OS_Version",
    "kernel": "$Kernel_Version"
  },
  "compute": {
    "gpu_driver": "$GPU_Driver",
    "npu_driver": "$NPU_Version",
    "vaapi_version": "$VAAPI_Version"

  },
  "software": {
    "dlstreamer_version": "$DLStreamer_Version",
    "openvino_version": "$OpenVINO_Version",
    "docker_version": "$Docker_Version"
  }
}
EOF

echo "[ Info ] System information saved to: $OUTPUT_FILE"
if command -v python3 >/dev/null 2>&1; then
    echo ""
    echo "System Information:"
    echo "===================="
    python3 -m json.tool "$OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE"
else
    cat "$OUTPUT_FILE"
fi

exit 0
