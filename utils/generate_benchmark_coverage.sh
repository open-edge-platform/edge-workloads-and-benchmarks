#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
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
    
    log_verbose "[ Info ] CPU is always available"
}

# Generate coverage matrix based on available devices
generate_coverage() {
    local configs=("light" "medium" "heavy")
    local total_tests=0
    
    log_verbose "Benchmark Coverage Matrix"
    log_verbose "Format: config,detect_device,classify_device,batch,concurrent_flag"
    log_verbose ""
    
    for config in "${configs[@]}"; do
        
        # GPU-Only tests
        if [[ "$has_gpu" == true ]]; then
            echo "${config},GPU,GPU,1,"
            echo "${config},GPU,GPU,8,"
            total_tests=$((total_tests + 2))
            log_verbose "${config} GPU-Only: 2 tests (batch 1, 8)"
        fi
        
        # NPU-Only tests
        if [[ "$has_npu" == true ]]; then
            echo "${config},NPU,NPU,1,"
            total_tests=$((total_tests + 1))
            log_verbose "${config} NPU-Only: 1 test (batch 1)"
        fi
        
        # GPU-NPU Split Mode
        if [[ "$has_gpu" == true && "$has_npu" == true ]]; then
            echo "${config},GPU,NPU,1,"
            echo "${config},GPU,NPU,8,"
            total_tests=$((total_tests + 2))
            log_verbose "${config} GPU-NPU Split: 2 tests (batch 1, 8)"
        fi
        
        # GPU-NPU Concurrent Mode
        if [[ "$has_gpu" == true && "$has_npu" == true ]]; then
            echo "${config},GPU,NPU,1,--concurrent"
            echo "${config},GPU,NPU,8,--concurrent"
            total_tests=$((total_tests + 2))
            log_verbose "${config} GPU-NPU Concurrent: 2 tests (batch 1, 8)"
        fi
        
    done
    echo "TOTAL_TESTS=${total_tests}"
}

main() {
    detect_devices
    log_verbose ""
    generate_coverage
}

main "$@"
