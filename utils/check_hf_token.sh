#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Prompts user to input their Hugging Face token and checks for gated access to required models
# Uses HF_TOKEN environment variable if already set. Prints token to terminal
# ==============================================================================

set -e

HF_TOKEN_FILE="${HOME}/.cache/huggingface/token"

# Colors
if [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Checks if token already exists
if [[ -n "${HF_TOKEN:-}" ]]; then
    echo "${HF_TOKEN}"
    exit 0
fi

if [[ -f "${HF_TOKEN_FILE}" ]]; then
    cat "${HF_TOKEN_FILE}"
    exit 0
fi

# Interactive prompts checking if the user has a token and is authenticated
exec 3>&1  # save stdout
exec 1>&2  # redirect stdout to stderr for prompts

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

echo -e "${CYAN}[ Info ]${NC} Token set for this session."
echo ""

# Print token to terminal
echo "${hf_token_input}" >&3
