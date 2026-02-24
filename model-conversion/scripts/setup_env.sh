#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
workdir="${basedir}/.."

python3 -m venv "${workdir}/venv"
source "${workdir}/venv/bin/activate"

python3 -m pip install --upgrade pip
pip install torch==2.9.1 torchvision==0.24.1 --index-url https://download.pytorch.org/whl/cpu
pip install -r "${workdir}/requirements.txt"
