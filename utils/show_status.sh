#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ==============================================================================
# Shows CSV/log counts per workload and report completion count
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/collateral/results"

# Color support
if [ -t 1 ]; then
    _G="\033[0;32m"; _Y="\033[0;33m"; _B="\033[0;34m"; _D="\033[0;90m"; _N="\033[0m"
else
    _G=""; _Y=""; _B=""; _D=""; _N=""
fi

echo ""
echo "================================================"
echo "  Benchmark Results Inventory"
echo "================================================"

total=0
for wl in edge-ai-pipelines vision-benchmarks media-benchmarks genai-benchmarks; do
    dir="${RESULTS_DIR}/${wl}"
    if [[ -d "${dir}" ]]; then
        count=$(find "${dir}" -name "*.csv" 2>/dev/null | wc -l)
        logs=$(find "${dir}" -name "*.log" 2>/dev/null | wc -l)
        total=$((total + count))
        if [[ "${count}" -gt 0 ]]; then
            latest=$(find "${dir}" -name "*.csv" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
            latest_ts=$(stat -c '%y' "${latest}" 2>/dev/null | cut -d. -f1)
            echo -e "  ${_G}${wl}${_N}: ${count} CSVs, ${logs} logs ${_D}(latest: ${latest_ts})${_N}"
        else
            echo -e "  ${_D}${wl}: no results${_N}"
        fi
    else
        echo -e "  ${_D}${wl}: no results${_N}"
    fi
done

echo "================================================"
echo -e "  Total: ${_B}${total}${_N} CSV result files"
echo ""

# Report number of completed reports detected
bash "${REPO_ROOT}/tools/html/check_report_status.sh"
