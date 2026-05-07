#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Gemma 3 4B IT — Multimodal Vision-Language Model
# https://huggingface.co/google/gemma-3-4b-it
#
# 4B parameters
# Model License: gemma — gated model requires accepting
# terms at huggingface.co and providing an access token.

set -e

basedir="$(realpath "$(dirname -- "$0")")"
models_dir="${basedir}/../../collateral/models/genai"
mkdir -p "${models_dir}"
models_dir="$(realpath "${models_dir}")"

SHORT_NAME="gemma-3-4b-it"
HF_ID="google/gemma-3-4b-it"
VENV_DIR="${basedir}/venv"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Hugging Face token check 
HF_TOKEN_FILE="${HOME}/.cache/huggingface/token"
if [[ -z "${HF_TOKEN:-}" ]] && [[ ! -f "${HF_TOKEN_FILE}" ]]; then
    echo ""
    echo -e "${YELLOW}[ Warning ]${NC} No Hugging Face token found."
    echo "  Gemma 3 is a gated model — you must accept Google's terms at:"
    echo "    https://huggingface.co/google/gemma-3-4b-it"
    echo ""
    echo "  Then provide a token via:"
    echo "    1. Run: huggingface-cli login"
    echo "    2. Or:  export HF_TOKEN=hf_..."
    echo ""
    printf "Enter your Hugging Face token (or press Enter to try without): "
    read -rs user_token
    echo ""
    if [[ -n "${user_token}" ]]; then
        mkdir -p "$(dirname "${HF_TOKEN_FILE}")"
        printf '%s' "${user_token}" > "${HF_TOKEN_FILE}"
        chmod 600 "${HF_TOKEN_FILE}"
        export HF_TOKEN="${user_token}"
        echo -e "${CYAN}[ Info ]${NC} Token saved to ${HF_TOKEN_FILE}."
    else
        echo -e "${CYAN}[ Info ]${NC} Continuing without token — download may fail."
    fi
fi

# Virtual environment check
[[ -d "${VENV_DIR}" ]] || { echo -e "${RED}[ Error ]${NC} Downloader venv not found. Run setup_env.sh first."; exit 1; }
source "${VENV_DIR}/bin/activate"

# Validation functions
model_exists() {
    local dest="$1"
    # Multimodal exports produce per-component files instead of a single openvino_model.xml
    [[ -d "${dest}" ]] && [[ -f "${dest}/openvino_language_model.xml" ]]
}

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

    local extra_flags=()
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
echo -e "${GREEN}=== Gemma 3 4B IT ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Starting Gemma 3 4B IT model export..."

failed=0
export_model "int8" "INT8_ASYM" || { echo -e "${RED}[ FAILED ]${NC} ${SHORT_NAME} int8"; ((failed++)) || true; }
echo ""
export_model "int4" "INT4_SYM_CW" || { echo -e "${RED}[ FAILED ]${NC} ${SHORT_NAME} int4"; ((failed++)) || true; }

deactivate

echo ""
echo -e "${CYAN}[ Info ]${NC} Gemma 3 4B IT export complete."

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}[ Error ]${NC} ${failed} export(s) failed"
    exit 1
fi
