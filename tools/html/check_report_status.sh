#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Check whether the HTML report is up to date with benchmark results.
# Called by: make status (top-level Makefile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RESULTS_DIR="${ROOT_DIR}/collateral/results"
REPORTS_DIR="${ROOT_DIR}/collateral/reports"
DATA_JSON="${SCRIPT_DIR}/data.json"

# Count CSV results on disk
disk_count=0
for wl in edge-ai-pipelines vision-benchmarks media-benchmarks genai-benchmarks; do
    dir="${RESULTS_DIR}/${wl}"
    if [[ -d "${dir}" ]]; then
        n=$(find "${dir}" -name "*.csv" 2>/dev/null | wc -l)
        disk_count=$((disk_count + n))
    fi
done

# Find the latest report
latest_report=""
if [[ -d "${REPORTS_DIR}" ]]; then
    latest_report=$(find "${REPORTS_DIR}" -name "*.html" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
fi

# Check if no report exists ---
if [[ -z "${latest_report}" ]]; then
    if [[ "${disk_count}" -gt 0 ]]; then
        echo "[ Warning ] No report generated yet (${disk_count} CSV results on disk)"
        echo "  Run:  make report"
    fi
    exit 0
fi

# Get report name and timestamp
report_ts=$(stat -c '%Y' "${latest_report}")
report_name="${latest_report##*/}"
report_date=$(stat -c '%y' "${latest_report}" | cut -d. -f1)

# Find newest completed benchmark result on disk
newest_csv=""
if [[ "${disk_count}" -gt 0 ]]; then
    newest_csv=$(find "${RESULTS_DIR}" -name "*.csv" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
fi

# Count results captured in data.json
report_count=0
if [[ -f "${DATA_JSON}" ]]; then
    report_count=$(python3 -c "
import json, sys
try:
    with open('${DATA_JSON}') as f:
        d = json.load(f)
    total = 0
    for k in ['edge_ai_pipelines','vision_benchmarks','media_benchmarks','genai_benchmarks']:
        total += len(d.get(k, {}).get('raw', []))
    print(total)
except Exception:
    print(0)
" 2>/dev/null)
fi

# Update the report if stale or counts differ
stale=false

# Check timestamp for newer completed results (stale)
if [[ -n "${newest_csv}" ]]; then
    csv_ts=$(stat -c '%Y' "${newest_csv}")
    if [[ "${csv_ts}" -gt "${report_ts}" ]]; then
        stale=true
    fi
fi

# Check count for difference in completed result count (stale)
delta=$((disk_count - report_count))

if [[ "${stale}" == true ]] || [[ "${delta}" -ne 0 ]]; then
    msg="[ Warning ] Report is out of date (${report_name}, ${report_date})"
    if [[ "${delta}" -gt 0 ]]; then
        msg="${msg} — ${delta} new result(s) since last report"
    elif [[ "${delta}" -lt 0 ]]; then
        msg="${msg} — ${delta#-} result(s) removed since last report"
    else
        msg="${msg} — results have been updated since last report"
    fi
    echo "${msg}"
    echo "  Run:  make report"
    exit 0
fi

# If count matches and latest report, then up to date
echo "[ Info ] Report is up to date (${report_name}, ${report_date})"
