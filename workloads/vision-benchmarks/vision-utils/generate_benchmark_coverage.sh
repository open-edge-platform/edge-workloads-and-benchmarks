#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

# Initialize available devices
has_gpu=false
has_npu=false

# Verbose logging only if VERBOSE=1
log_verbose() {
    if [[ "${VERBOSE:-0}" == "1" ]]; then
        echo "# $*" >&2
    fi
}

detect_devices() {
    log_verbose "[ Info ] Detecting available compute devices..."

    # Check for GPU via /dev/dri
    if [[ -d /dev/dri ]] && compgen -G "/dev/dri/render*" >/dev/null 2>&1; then
        has_gpu=true
        log_verbose "[ Info ] GPU detected (/dev/dri available)"
    else
        log_verbose "[ Info ] GPU not detected"
    fi

    # Check for NPU via /dev/accel
    if [[ -e /dev/accel ]] && compgen -G "/dev/accel/accel*" >/dev/null 2>&1; then
        has_npu=true
        log_verbose "[ Info ] NPU detected (/dev/accel available)"
    else
        log_verbose "[ Info ] NPU not detected"
    fi
}

# Target models for workload sweep
MODELS=(
    "detection/yolov11n_640x640/INT8/yolo11n.xml"
    "detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml"
    "detection/yolov11m_640x640/INT8/yolo11m.xml"
    "classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
    "classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml"
)

# Generate coverage matrix based on available devices
# Format: model_path,device,mode,batch,concurrent_device
generate_coverage() {
    local total_tests=0

    log_verbose "Vision Benchmark Coverage Matrix"
    log_verbose "Format: model_path,device,mode,batch,concurrent_device"
    log_verbose ""

    for model in "${MODELS[@]}"; do
        local shortname
        shortname="$(basename "$(dirname "$(dirname "${model}")")")"

        # GPU tests: BS1 latency, BS1 tput, BS8 tput, BS16 tput
        if [[ "$has_gpu" == true ]]; then
            echo "${model},GPU,latency,1,"
            echo "${model},GPU,tput,1,"
            echo "${model},GPU,tput,8,"
            echo "${model},GPU,tput,16,"
            total_tests=$((total_tests + 4))
            log_verbose "${shortname} GPU: 4 tests (BS1 latency, BS1/8/16 tput)"
        fi

        # NPU tests: BS1 latency, BS1 tput
        if [[ "$has_npu" == true ]]; then
            echo "${model},NPU,latency,1,"
            echo "${model},NPU,tput,1,"
            total_tests=$((total_tests + 2))
            log_verbose "${shortname} NPU: 2 tests (BS1 latency, BS1 tput)"
        fi

        # GPU+NPU Concurrent: BS1 latency, BS1 tput, BS8 tput, BS16 tput
        if [[ "$has_gpu" == true && "$has_npu" == true ]]; then
            echo "${model},GPU,latency,1,NPU"
            echo "${model},GPU,tput,1,NPU"
            echo "${model},GPU,tput,8,NPU"
            echo "${model},GPU,tput,16,NPU"
            total_tests=$((total_tests + 4))
            log_verbose "${shortname} GPU+NPU Concurrent: 4 tests (BS1 latency, BS1/8/16 tput)"
        fi
    done

    echo "TOTAL_TESTS=${total_tests}"

    if [[ ${total_tests} -eq 0 ]]; then
        echo "[ Warning ] No benchmark tests generated. No GPU or NPU device was detected." >&2
        echo "[ Warning ] Please ensure the GPU and/or NPU drivers are installed." >&2
        echo "[ Warning ] See setup/drivers/README.md for installation instructions." >&2
    fi
}

main() {
    detect_devices
    log_verbose ""
    generate_coverage
}

main "$@"
