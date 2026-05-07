#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Ensures a Hugging Face token is available for gated model downloads.
# Checks HF_TOKEN env var and ~/.cache/huggingface/token cache file.
# If neither exists, prompts the user and persists to the cache file.
# Exits 0 if a token is available, 1 otherwise. Never prints the token.
# ==============================================================================

set -e

HF_TOKEN_FILE="${HOME}/.cache/huggingface/token"

# Colors
if [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Token already available via environment variable — persist to cache if missing
if [[ -n "${HF_TOKEN:-}" ]]; then
    if [[ ! -f "${HF_TOKEN_FILE}" ]]; then
        mkdir -p "$(dirname "${HF_TOKEN_FILE}")"
        printf '%s' "${HF_TOKEN}" > "${HF_TOKEN_FILE}"
        chmod 600 "${HF_TOKEN_FILE}"
    fi
    exit 0
fi

# Token already cached
if [[ -f "${HF_TOKEN_FILE}" ]]; then
    exit 0
fi

# Interactive prompts checking if the user has a token and is authenticated
echo ""
echo -e "${GREEN}=== GenAI: Hugging Face Token Setup ===${NC}"
echo ""
echo "  Some GenAI models require a Hugging Face token with gated access:"
echo "    - meta-llama/Llama-3.2-3B-Instruct"
echo "    - google/gemma-3-4b-it"
echo "    - openbmb/MiniCPM-V-2_6"
echo ""

printf "  Do you have a Hugging Face access token? [y/N] "
read -r has_token
if ! echo "${has_token}" | grep -qiE '^y'; then
    echo ""
    echo "  To get a token:"
    echo "    1. Create an account at https://huggingface.co"
    echo "    2. Go to https://huggingface.co/settings/tokens"
    echo "    3. Create a token with 'Read' access"
    echo ""
    echo "  Then re-run: make collateral INCLUDE_GENAI=True"
    exit 1
fi

printf "  Have you accepted the license for the gated repos listed above? [y/N] "
read -r has_access
if ! echo "${has_access}" | grep -qiE '^y'; then
    echo ""
    echo "  Visit each link above, click 'Agree and access repository',"
    echo "  then re-run: make collateral INCLUDE_GENAI=True"
    exit 1
fi

echo ""
printf "  Enter your Hugging Face token: "
stty -echo
read -r hf_token_input
stty echo
echo ""

if [[ -z "${hf_token_input}" ]]; then
    echo -e "${RED}[ Error ]${NC} No token provided. Aborting GenAI download."
    exit 1
fi

# Persist token to HF cache file
mkdir -p "$(dirname "${HF_TOKEN_FILE}")"
printf '%s' "${hf_token_input}" > "${HF_TOKEN_FILE}"
chmod 600 "${HF_TOKEN_FILE}"

echo -e "${CYAN}[ Info ]${NC} Token saved to ${HF_TOKEN_FILE}."
echo ""
