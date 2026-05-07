#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
venvdir="${basedir}/../venv"

# Create virtual environment and install OpenVINO if it doesn't exist
if [[ -d "${venvdir}" ]]; then
    echo "[ Info ] Virtual environment already exists at ${venvdir}"
    exit 0
fi

echo "[ Info ] Creating virtual environment and installing OpenVINO..."
python3 -m venv "${venvdir}"

source "${venvdir}/bin/activate"
pip install --upgrade pip
pip install openvino==2026.1.0
deactivate
echo "[ Info ] Setup complete."
