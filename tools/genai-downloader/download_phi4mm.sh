#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Phi-4-Multimodal-Instruct — Multimodal Vision/Speech/Language Model
# https://huggingface.co/microsoft/Phi-4-multimodal-instruct
#
# 5.6B parameters
# Model License: MIT license — no gating, no HF token required.

set -e

basedir="$(realpath "$(dirname -- "$0")")"
models_dir="${basedir}/../../collateral/models/genai"
mkdir -p "${models_dir}"
models_dir="$(realpath "${models_dir}")"

SHORT_NAME="phi-4-multimodal"
HF_ID="microsoft/Phi-4-multimodal-instruct"
VENV_DIR="${basedir}/venv-phi4mm"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Virtual environment setup
if [[ -d "${VENV_DIR}" ]]; then
    echo -e "${CYAN}[ Info ]${NC} Using existing Phi-4 multimodal venv at ${VENV_DIR}"
else
    echo -e "${CYAN}[ Info ]${NC} Creating Phi-4 multimodal virtual environment..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate"
    pip install -q --upgrade pip
    pip install -q "transformers==4.51" "torch==2.8" "torchvision==0.23.0" \
        soundfile Pillow backoff "peft==0.17.1" librosa \
        --extra-index-url https://download.pytorch.org/whl/cpu
    pip install -q -U "openvino>=2025.1.0" "nncf>=2.16"
    pip install -q "git+https://github.com/huggingface/optimum-intel.git" \
        --extra-index-url https://download.pytorch.org/whl/cpu
    deactivate
    echo -e "${CYAN}[ Info ]${NC} Phi-4 multimodal venv ready."
fi

source "${VENV_DIR}/bin/activate"

# Validation function
model_exists() {
    local dest="$1"
    [[ -d "${dest}" ]] && [[ -f "${dest}/openvino_language_model.xml" ]]
}

# Export Phi 4 Multimodal
export_model() {
    local weight_fmt="$1"
    local out_dir_name="$2"
    local dest="${models_dir}/${SHORT_NAME}/${out_dir_name}"

    if model_exists "${dest}"; then
        echo -e "${CYAN}[ Info ]${NC} Model already exists: ${SHORT_NAME}/${out_dir_name} — skipping."
        return 0
    fi

    if [[ -d "${dest}" ]]; then
        echo -e "${CYAN}[ Info ]${NC} Removing incomplete export: ${SHORT_NAME}/${out_dir_name}"
        rm -rf "${dest}"
    fi

    mkdir -p "${dest}"
    echo -e "${CYAN}[ Info ]${NC} Exporting ${HF_ID} → ${SHORT_NAME}/${out_dir_name} (weight-format=${weight_fmt})..."

    local extra_flags=(--trust-remote-code)
    if [[ "${weight_fmt}" == "int4" ]]; then
        extra_flags+=(--sym --ratio 1.0 --group-size -1)
    fi

    optimum-cli export openvino \
        -m "${HF_ID}" \
        --task image-text-to-text \
        --weight-format "${weight_fmt}" \
        "${extra_flags[@]}" \
        "${dest}"

    if ! model_exists "${dest}"; then
        echo -e "${RED}[ Error ]${NC} Export failed — no openvino_language_model.xml in ${dest}"
        return 1
    fi

    echo -e "${GREEN}[ Pass ]${NC} ${SHORT_NAME}/${out_dir_name} exported successfully."
}

# Export INT8 and INT4
echo ""
echo -e "${GREEN}=== Phi-4 Multimodal ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Starting Phi-4 Multimodal model export..."

failed=0
export_model "int8" "INT8_ASYM" || { echo -e "${RED}[ FAILED ]${NC} ${SHORT_NAME} int8"; ((failed++)) || true; }
echo ""
export_model "int4" "INT4_SYM_CW" || { echo -e "${RED}[ FAILED ]${NC} ${SHORT_NAME} int4"; ((failed++)) || true; }

deactivate

echo ""
echo -e "${CYAN}[ Info ]${NC} Phi-4 Multimodal export complete."

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}[ Error ]${NC} ${failed} export(s) failed"
    exit 1
fi
