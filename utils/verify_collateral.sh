#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Checks that all required models, media files, and GenAI assets are present.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color
if [ -t 1 ]; then
    _G="\033[0;32m"; _Y="\033[0;33m"; _R="\033[0;31m"; _N="\033[0m"
else
    _G=""; _Y=""; _R=""; _N=""
fi
print_pass()    { echo -e "${_G}[ Pass ]${_N} $1"; }
print_fail()    { echo -e "${_R}[ Fail ]${_N} $1"; }
print_ok()      { echo -e "${_G}[  Found  ]${_N} $1"; }
print_missing() { echo -e "${_Y}[ Missing ]${_N} $1"; }

# Parse arguments
SECTION=""
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --section) SECTION="$2"; shift 2 ;;
        --verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

ERRORS=0

# ── Vision models ──────────────────────────────────────────────────────────────
verify_vision() {
    local base="${REPO_ROOT}/collateral/models"
    local missing=0 total=0 found=0
    local files=(
        "detection/yolov11n_640x640/INT8/yolo11n.xml"
        "detection/yolov11n_640x640/INT8/yolo11n.bin"
        "detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml"
        "detection/yolov5m_640x640/INT8/yolov5m-640_INT8.bin"
        "detection/yolov5m_640x640/yolo-v5.json"
        "detection/yolov11m_640x640/INT8/yolo11m.xml"
        "detection/yolov11m_640x640/INT8/yolo11m.bin"
        "classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
        "classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin"
        "classification/resnet-v1-50-tf/resnet-50.json"
        "classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml"
        "classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin"
        "classification/mobilenet-v2-1.0-224-tf/mobilenet-v2.json"
    )

    for f in "${files[@]}"; do
        total=$((total + 1))
        if [[ -f "${base}/${f}" ]]; then
            found=$((found + 1))
            [[ "${VERBOSE}" -eq 1 ]] && print_ok "${f}"
        else
            print_missing "${f}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        print_fail "Vision models: ${found}/${total} files found"
        ERRORS=$((ERRORS + 1))
    else
        print_pass "Vision models: ${found}/${total} files verified"
    fi
}

# ── Media files ──────────────────────────────────────────────────────────────
verify_media() {
    local base="${REPO_ROOT}/collateral/media"
    local missing=0 total=0 found=0
    local files=(
        "hevc/bears_1080.h265"
        "hevc/apple_1080.h265"
        "avc/bears_1080.h264"
        "avc/apple_1080.h264"
        "hevc/bears_4k.h265"
        "hevc/apple_4k.h265"
        "avc/bears_4k.h264"
        "avc/apple_4k.h264"
    )

    for f in "${files[@]}"; do
        total=$((total + 1))
        if [[ -f "${base}/${f}" ]]; then
            found=$((found + 1))
            [[ "${VERBOSE}" -eq 1 ]] && print_ok "${f}"
        else
            print_missing "${f}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        print_fail "Media files: ${found}/${total} files found"
        ERRORS=$((ERRORS + 1))
    else
        print_pass "Media files: ${found}/${total} files verified"
    fi
}

# ── GenAI models ──────────────────────────────────────────────────────────────
verify_genai() {
    local base="${REPO_ROOT}/collateral/models/genai"
    local missing=0 total=0 found=0
    local dirs=(
        "llama-3.2-3b-instruct/INT8_ASYM"
        "llama-3.2-3b-instruct/INT4_SYM_CW"
        "deepseek-qwen-1.5b/INT8_ASYM"
        "deepseek-qwen-1.5b/INT4_SYM_CW"
        "mistral-7b/INT8_ASYM"
        "mistral-7b/INT4_SYM_CW"
        "minicpm-v-2.6/INT8_ASYM"
        "minicpm-v-2.6/INT4_SYM_CW"
        "gemma-3-4b-it/INT8_ASYM"
        "gemma-3-4b-it/INT4_SYM_CW"
        "phi-4-multimodal/INT8_ASYM"
        "phi-4-multimodal/INT4_SYM_CW"
    )

    for d in "${dirs[@]}"; do
        total=$((total + 1))
        if [[ -f "${base}/${d}/openvino_model.xml" ]] || [[ -f "${base}/${d}/openvino_language_model.xml" ]]; then
            found=$((found + 1))
            [[ "${VERBOSE}" -eq 1 ]] && print_ok "${d}"
        else
            print_missing "${d}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        print_fail "GenAI models: ${found}/${total} models found"
        ERRORS=$((ERRORS + 1))
    else
        print_pass "GenAI models: ${found}/${total} models verified"
    fi
}

# ── Run checks ──────────────────────────────────────────────────────────────
case "${SECTION}" in
    vision) verify_vision ;;
    media)  verify_media ;;
    genai)  verify_genai ;;
    *)
        verify_vision
        echo ""
        verify_media
        echo ""
        verify_genai
        ;;
esac

exit "${ERRORS}"
