#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Parses core pinning input and returns a valid core list or NO_PIN
parse_core_pinning() {
    local input="$1"
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local obtain_cores_script="${script_dir}/obtain_cores.sh"
    
    if [[ "${input}" == "none" || "${input}" == "nopin" ]]; then
        echo "NO_PIN"
        return 0
    fi
    
    if [[ "${input}" =~ ^[0-9,\-]+$ ]]; then
        echo "${input}"
        return 0
    fi

    local core_type=""
    case "${input,,}" in
        pcore|p-core|pcores|p-cores)
            core_type="pcore"
            ;;
        ecore|e-core|ecores|e-cores)
            core_type="ecore"
            ;;
        lpecore|lpe-core|lpecores|lpe-cores)
            core_type="lpecore"
            ;;
        *)
            echo "[ Warning ] Unknown core pinning format: '${input}'. Using NO_PIN." >&2
            echo "NO_PIN"
            return 0
            ;;
    esac
    
    if [[ ! -x "${obtain_cores_script}" ]]; then
        echo "[ Warning ] ${obtain_cores_script} not found or not executable. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    local core_output
    core_output=$("${obtain_cores_script}" 2>/dev/null)
    
    if [[ $? -ne 0 || -z "${core_output}" ]]; then
        echo "[ Warning ] Failed to detect core types. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    local core_list=""
    while IFS= read -r line; do
        if [[ "${line}" =~ ^${core_type}:(.+)$ ]]; then
            core_list="${BASH_REMATCH[1]}"
            break
        fi
    done <<< "${core_output}"
    
    if [[ -z "${core_list}" ]]; then
        echo "[ Warning ] Core type '${core_type}' not available on this system. Using NO_PIN." >&2
        echo "NO_PIN"
        return 0
    fi
    
    echo "${core_list}"
    return 0
}

# Fix file ownership when running under sudo so non-root user can access results.
fix_sudo_permissions() {
    local target_dir="$1"
    if [[ -n "${SUDO_USER:-}" && -d "${target_dir}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_GID:-$(id -g "${SUDO_USER}")}" "${target_dir}"
    fi
}

# Power Monitoring
POWER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

power_init() {
    local results_dir="$1"
    local filename="$2"
    local duration="$3"

    PowerPID=""
    PowerLogFile="${results_dir}/${filename}_power.log"
    PowerDelay=$(bc <<< "scale=0; ${duration} / 4")
    PowerDuration=$(bc <<< "scale=0; ${duration} / 2")
    AvgPower="NA"
}

power_start() {
    local duration="$1"

    if [[ -x "${POWER_SCRIPT_DIR}/get_package_power.sh" ]]; then
        timeout --preserve-status "${duration}" "${POWER_SCRIPT_DIR}/get_package_power.sh" \
            -s 1 -i "${PowerDuration}" -d "${PowerDelay}" > "${PowerLogFile}" 2>&1 &
        PowerPID=$!
        sleep 0.5
        if kill -0 "${PowerPID}" 2>/dev/null; then
            echo "[ Info ] Power monitoring started (PID: ${PowerPID})"
        else
            wait "${PowerPID}" 2>/dev/null || true
            PowerPID=""
        fi
    fi
}

power_stop() {
    if [[ -n "${PowerPID:-}" ]]; then
        kill "${PowerPID}" 2>/dev/null || true
        wait "${PowerPID}" 2>/dev/null || true
        PowerPID=""
    fi
}

power_collect() {
    AvgPower="NA"
    if [[ -f "${PowerLogFile}" ]] && grep -q "W$" "${PowerLogFile}" 2>/dev/null; then
        AvgPower=$(grep -oP '\d+\.\d+(?= W)' "${PowerLogFile}" | \
            awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "NA"}')
    fi
}
