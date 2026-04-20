#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

basedir="$(realpath "$(dirname -- "$0")")"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Create virtual environment if it doesn't exist
if [[ -d "${basedir}/venv" ]]; then
    echo -e "${CYAN}[ Info ]${NC} Virtual environment already exists, skipping creation."
else
    echo -e "${CYAN}[ Info ]${NC} Creating Python virtual environment..."
    python3 -m venv "${basedir}/venv"
fi

source "${basedir}/venv/bin/activate"

# Pip install required dependencies
echo -e "${CYAN}[ Info ]${NC} Installing model export dependencies..."
pip install -q --upgrade pip
pip install -q openvino "optimum-intel[openvino]" nncf \
    peft Pillow torchvision librosa \
    "transformers>=4.50.0" torch sentencepiece decord \
    --extra-index-url https://download.pytorch.org/whl/cpu

deactivate
echo -e "${CYAN}[ Info ]${NC} GenAI downloader environment ready."
