#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

require_file() {
    [[ -f "$1" ]] || { echo "[ Error ] Missing required file: $1"; return 1; }
}

parse_core_pinning() {
    local input="$1"
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local obtain_cores_script="${script_dir}/obtain_cores.sh"
    
    if [[ "${input}" == "none" || "${input}" == "nopin" ]]; then
        echo "NO_PIN"
        return 0
    fi
    
    if [[ "${input}" =~ ^[0-9,\-]+$ ]]; then
        echo "${input}"
        return 0
    fi

    local core_type=""
    case "${input,,}" in
        pcore|p-core|pcores|p-cores)
            core_type="pcore"
            ;;
        ecore|e-core|ecores|e-cores)
            core_type="ecore"
            ;;
        lpecore|lpe-core|lpecores|lpe-cores)
            core_type="lpecore"
            ;;
        *)
            echo "[ Warning ] Unknown core pinning format: '${input}'. Using NO_PIN." >&2
            echo "NO_PIN"
            return 0
            ;;
    esac
    
    if [[ ! -x "${obtain_cores_script}" ]]; then
        echo "[ Warning ] ${obtain_cores_script} not found or not executable. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    local core_output
    core_output=$("${obtain_cores_script}" 2>/dev/null)
    
    if [[ $? -ne 0 || -z "${core_output}" ]]; then
        echo "[ Warning ] Failed to detect core types. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    local core_list=""
    while IFS= read -r line; do
        if [[ "${line}" =~ ^${core_type}:(.+)$ ]]; then
            core_list="${BASH_REMATCH[1]}"
            break
        fi
    done <<< "${core_output}"
    
    if [[ -z "${core_list}" ]]; then
        echo "[ Warning ] Core type '${core_type}' not available on this system. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    echo "${core_list}"
    return 0
}

validate_assets() {
    (( $# == 2 )) || { echo "[ Error ] validate_assets <config> <pipelines_root>"; return 1; }
    local config="$1" root="$2" missing=0

    case "${config}" in
        light)
            require_file "${root}/light/video/bears.h265" || missing=1
            require_file "${root}/light/detection/yolov11n_640x640/INT8/yolo11n.xml" || missing=1
            require_file "${root}/light/detection/yolov11n_640x640/INT8/yolo11n.bin" || missing=1
            require_file "${root}/light/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" || missing=1
            require_file "${root}/light/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" || missing=1
            require_file "${root}/light/classification/resnet-v1-50-tf/resnet-50.json" || missing=1
            ;;
        medium)
            require_file "${root}/medium/video/apple.h265" || missing=1
            require_file "${root}/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml" || missing=1
            require_file "${root}/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.bin" || missing=1
            require_file "${root}/medium/detection/yolov5m_640x640/yolo-v5.json" || missing=1
            require_file "${root}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" || missing=1
            require_file "${root}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" || missing=1
            require_file "${root}/medium/classification/resnet-v1-50-tf/resnet-50.json" || missing=1
            require_file "${root}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml" || missing=1
            require_file "${root}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin" || missing=1
            require_file "${root}/medium/classification/mobilenet-v2-1.0-224-tf/mobilenet-v2.json" || missing=1
            ;;
        heavy)
            require_file "${root}/heavy/video/bears.h265" || missing=1
            require_file "${root}/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml" || missing=1
            require_file "${root}/heavy/detection/yolov11m_640x640/INT8/yolo11m.bin" || missing=1
            require_file "${root}/heavy/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" || missing=1
            require_file "${root}/heavy/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" || missing=1
            require_file "${root}/heavy/classification/resnet-v1-50-tf/resnet-50.json" || missing=1
            require_file "${root}/heavy/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml" || missing=1
            require_file "${root}/heavy/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin" || missing=1
            require_file "${root}/heavy/classification/mobilenet-v2-1.0-224-tf/mobilenet-v2.json" || missing=1
            ;;
        *)
            echo "[ Error ] validate_assets: unknown config ${config}"; return 1
            ;;
    esac

    if (( missing )); then
        echo "[ Error ] One or more required pipeline assets are missing. Run model and media preparation scripts first."; return 1
    fi
    return 0
}
