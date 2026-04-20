#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
workdir="${basedir}/.."

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

python3 -m venv "${workdir}/venv"
source "${workdir}/venv/bin/activate"

python3 -m pip install -q --upgrade pip
pip install -q torch==2.9.1 torchvision==0.24.1 --index-url https://download.pytorch.org/whl/cpu
pip install -q -r "${workdir}/requirements.txt"

# Download coco.yaml at setup time (AGPL-3.0 licensed in third-party-software.txt)
COCO_YAML="${workdir}/scripts/coco.yaml"
COCO_YAML_URL="https://raw.githubusercontent.com/ultralytics/ultralytics/refs/heads/main/ultralytics/cfg/datasets/coco.yaml"
if [[ ! -f "${COCO_YAML}" ]]; then
    echo -e "${CYAN}[ Info ]${NC} Downloading coco.yaml from Ultralytics (AGPL-3.0)..."
    wget -q --show-progress --tries=5 --timeout=30 -O "${COCO_YAML}" "${COCO_YAML_URL}"
else
    echo -e "${CYAN}[ Info ]${NC} coco.yaml already exists, skipping download."
fi
