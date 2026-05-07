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
    NPU_Version=$(dpkg -l | grep intel-driver-compiler-npu | awk '{print $3}' | cut -d. -f1-3 || echo "N/A")
elif ls /dev/accel/accel* >/dev/null 2>&1; then
    NPU_Version="Hardware detected (driver not installed)"
fi

# DLStreamer and OpenVINO Versions (from Docker container)
DLStreamer_Version="N/A"
OpenVINO_Version="N/A"
if command -v docker >/dev/null 2>&1; then
    if docker images | grep -q "intel/dlstreamer"; then
        _apt_list=$(docker run --rm --init intel/dlstreamer:2026.1.0-20260505-weekly-ubuntu24 apt list 2>/dev/null || true)
        DLStreamer_Version=$(echo "${_apt_list}" | grep -E "dlstreamer|gstreamer" | head -n1 | awk '{print $2}' || echo "latest")
        OpenVINO_Version=$(echo "${_apt_list}" | grep openvino | head -n1 | awk '{print $2}' | cut -d. -f1-3 || echo "N/A")
        unset _apt_list
    fi
fi

# OpenVINO Version (from Python virtual environment)
OpenVINO_Native="N/A"
VENV_PATH="${SCRIPT_DIR}/../../workloads/vision-benchmarks/venv"
if [ -d "$VENV_PATH" ]; then
    OpenVINO_Native=$("$VENV_PATH/bin/python3" -c "import openvino; print(openvino.__version__)" 2>/dev/null | grep -oP '^\d+\.\d+\.\d+' || echo "N/A")
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

# Memory Information (requires sudo)
Mem_Capacity="N/A"
Mem_Type="N/A"
Mem_Speed="N/A"
DMI_OUTPUT=$(sudo dmidecode -t memory 2>/dev/null || true)
if [ -n "$DMI_OUTPUT" ]; then
    # Count populated modules and their sizes
    Num_Modules=$(echo "$DMI_OUTPUT" | grep -c '^\s*Size: [0-9]' || true)
    Module_Size=$(echo "$DMI_OUTPUT" | grep -m1 '^\s*Size:' | awk '{print $2}' || true)
    Module_Unit=$(echo "$DMI_OUTPUT" | grep -m1 '^\s*Size:' | awk '{print $3}' || true)
    if [ "$Num_Modules" -gt 0 ] && [ -n "$Module_Size" ] 2>/dev/null; then
        Total=$((Num_Modules * Module_Size))
        if [ "$Module_Unit" = "MB" ]; then
            Total=$((Total / 1024))
            Module_Unit="GB"
        fi
        Mem_Capacity="${Total}GB (${Num_Modules}x${Module_Size}${Module_Unit})"
    fi
    # Memory type (e.g. LPDDR5, DDR5) and form factor (e.g. SODIMM)
    Raw_Type=$(echo "$DMI_OUTPUT" | grep -m1 '^\s*Type:' | awk '{print $2}' || true)
    Form_Factor=$(echo "$DMI_OUTPUT" | grep -m1 '^\s*Form Factor:' | sed 's/.*Form Factor:\s*//' | xargs || true)
    if [ -n "$Raw_Type" ] && [ "$Raw_Type" != "Unknown" ]; then
        if [ -n "$Form_Factor" ] && [ "$Form_Factor" != "Unknown" ] && [ "$Form_Factor" != "Other" ] && [ "$Form_Factor" != "Row Of Chips" ]; then
            Mem_Type="${Raw_Type} ${Form_Factor}"
        else
            Mem_Type="$Raw_Type"
        fi
    fi
    # Configured memory speed
    Configured_Speed=$(echo "$DMI_OUTPUT" | grep -m1 'Configured Memory Speed:' | sed 's/.*Configured Memory Speed:\s*//' | xargs || true)
    if [ -n "$Configured_Speed" ] && [ "$Configured_Speed" != "Unknown" ]; then
        Mem_Speed="$Configured_Speed"
    fi
fi

# Timestamp
Timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Generate JSON output
jq -n \
    --arg generated "$Timestamp" \
    --arg sys_name "$System" \
    --arg sys_os "$OS_Name $OS_Version" \
    --arg sys_kernel "$Kernel_Version" \
    --arg mem_capacity "$Mem_Capacity" \
    --arg mem_type "$Mem_Type" \
    --arg mem_speed "$Mem_Speed" \
    --arg gpu_driver "$GPU_Driver" \
    --arg npu_driver "$NPU_Version" \
    --arg vaapi "$VAAPI_Version" \
    --arg dls "$DLStreamer_Version" \
    --arg ov_container "$OpenVINO_Version" \
    --arg ov_native "$OpenVINO_Native" \
    --arg docker "$Docker_Version" \
    '{
      generated: $generated,
      system: { name: $sys_name, os: $sys_os, kernel: $sys_kernel },
      memory: { capacity: $mem_capacity, type: $mem_type, speed: $mem_speed },
      compute: { gpu_driver: $gpu_driver, npu_driver: $npu_driver, vaapi_version: $vaapi },
      software: {
        dlstreamer_version: $dls,
        openvino_container_version: $ov_container,
        openvino_native_version: $ov_native,
        docker_version: $docker
      }
    }' > "$OUTPUT_FILE"

echo "[ Info ] System information saved to: $OUTPUT_FILE"
echo ""
echo "System Information:"
echo "===================="
cat "$OUTPUT_FILE"

exit 0
