#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

basedir="$(realpath "$(dirname -- "$0")")"
models_dir="${basedir}/../../collateral/models/genai"
mkdir -p "${models_dir}"
models_dir="$(realpath "${models_dir}")"
main_venv="${basedir}/venv"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

[[ -d "${main_venv}" ]] || { echo -e "${RED}[ Error ]${NC} Downloader venv not found. Run setup_env.sh first."; exit 1; }

source "${main_venv}/bin/activate"

# Hugging Face token check 
# Several models (Llama, Mistral) are gated and require accepting the
# license on huggingface.co and providing an access token.
HF_TOKEN_FILE="${HOME}/.cache/huggingface/token"
if [[ -z "${HF_TOKEN:-}" ]] && [[ ! -f "${HF_TOKEN_FILE}" ]]; then
    echo ""
    echo -e "${YELLOW}[ Warning ]${NC} No Hugging Face token found."
    echo "  Some models are gated and require a token to download."
    echo "  Accept model licenses at huggingface.co, then either:"
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
        echo -e "${CYAN}[ Info ]${NC} Continuing without token — gated model downloads may fail."
    fi
fi

MODELS=(
    "llama-3.2-3b-instruct|meta-llama/Llama-3.2-3B-Instruct|llm"
    "deepseek-qwen-1.5b|deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B|llm"
    "mistral-7b|mistralai/Mistral-7B-v0.1|llm"
)

precision_dir() {
    case "$1" in
        int8) echo "INT8_ASYM" ;;
        int4) echo "INT4_SYM_CW" ;;
    esac
}

# Validation function
model_exists() {
    local dest="$1"
    [[ -d "${dest}" ]] || return 1
    [[ -f "${dest}/openvino_model.xml" ]]
}

# Export LLM models
export_model() {
    local short_name="$1"
    local hf_id="$2"
    local weight_fmt="$3"
    local model_type="$4"
    local out_dir_name
    out_dir_name="$(precision_dir "${weight_fmt}")"
    local dest="${models_dir}/${short_name}/${out_dir_name}"

    if model_exists "${dest}"; then
        echo -e "${CYAN}[ Info ]${NC} Model already exists: ${short_name}/${out_dir_name} — skipping."
        return 0
    fi

    if [[ -d "${dest}" ]]; then
        echo -e "${CYAN}[ Info ]${NC} Removing incomplete export: ${short_name}/${out_dir_name}"
        rm -rf "${dest}"
    fi

    mkdir -p "${dest}"
    echo -e "${CYAN}[ Info ]${NC} Exporting ${hf_id} → ${short_name}/${out_dir_name} (weight-format=${weight_fmt})..."

    local extra_flags=(--trust-remote-code)
    if [[ "${weight_fmt}" == "int4" ]]; then
        extra_flags+=(--sym --ratio 1.0 --group-size -1)
    fi

    optimum-cli export openvino \
        -m "${hf_id}" \
        --weight-format "${weight_fmt}" \
        "${extra_flags[@]}" \
        "${dest}"

    if ! model_exists "${dest}"; then
        echo -e "${RED}[ Error ]${NC} Export failed — no openvino_model.xml in ${dest}"
        return 1
    fi
}

echo -e "${CYAN}[ Info ]${NC} Downloading and converting GenAI models..."

failed=0
for entry in "${MODELS[@]}"; do
    IFS='|' read -r short_name hf_id model_type <<< "${entry}"
    echo ""
    echo -e "${GREEN}=== ${short_name} (${hf_id}) ===${NC}"

    export_model "${short_name}" "${hf_id}" "int8" "${model_type}" || { echo -e "${RED}[ FAILED ]${NC} ${short_name} int8"; ((failed++)) || true; }
    echo ""
    export_model "${short_name}" "${hf_id}" "int4" "${model_type}" || { echo -e "${RED}[ FAILED ]${NC} ${short_name} int4"; ((failed++)) || true; }
done

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}[ Error ]${NC} ${failed} model export(s) failed"
    deactivate
    exit 1
fi

deactivate

echo ""
echo -e "${CYAN}[ Info ]${NC} GenAI model download and conversion complete."
