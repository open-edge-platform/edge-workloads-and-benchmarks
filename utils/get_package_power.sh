#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Note: Requires root to access /sys/class/drm/*/hwmon/* and/or /sys/class/powercap/*

set -euo pipefail

DRM_ROOT="/sys/class/drm"

# Initialize parameters
Interval=1
Duration=60
Delay=0

# Help message
usage()
{
cat << 'EOF'

Usage:
  get_package_power.sh -i <interval (seconds)> -d <duration (seconds)>

Options:
  -s <seconds>    Sampling interval in seconds (default: 1)
  -i <seconds>    Total duration in seconds (default: 60)
  -d <seconds>    Start Delay in seconds (default: 0)

Output Format:
  [source] card# (driver @ pci): power W
EOF
}

# Command line argument parser
argparse()
{
while getopts "hs:i:d:" arg; do
    case $arg in
        s)
        Interval=${OPTARG}
        ;;
        i)
        Duration=${OPTARG}
        ;;
        d)
        Delay=${OPTARG}
        ;;
        h)
        usage; exit 0
        ;;
        *)
        usage; exit 1
        ;;
    esac
done
}

# Parse arguments
argparse "$@"

# Validation
is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_nonneg() { [[ "$1" =~ ^[0-9][0-9]*$ ]]; }
is_posint "${Interval}" || { echo "[ Error ] -s must be a positive integer" >&2; exit 1; }
is_posint "${Duration}"  || { echo "[ Error ] -i must be a positive integer" >&2; exit 1; }
is_nonneg "${Delay}"  || { echo "[ Error ] -d must be a non-negative integer" >&2; exit 1; }

# Check permissions
check_permissions()
{
    local test_paths=(
        "/sys/class/drm/card0/device/hwmon"
        "/sys/class/powercap/intel-rapl:0/energy_uj"
    )
    
    for path in "${test_paths[@]}"; do
        if [[ -r "$path" ]] 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

if ! check_permissions; then
    echo "[ Warning ] Cannot read power sensors. Skipping power measurements." >&2
    echo "[ Info ] Run with sudo to enable power monitoring." >&2
    exit 2
fi

shopt -s nullglob

lower_strip()
{
    local val="$1"
    val=${val,,}
    val=${val//[[:space:]]/}
    printf "%s" "$val"
}

read_hwmon_package_power()
{
    local device_dir="$1"
    local interval="$2"
    local hwmon_dir label_file base sensor_name value_file start end diff power

    for hwmon_dir in "$device_dir"/hwmon/hwmon*; do
        [[ -d "$hwmon_dir" ]] || continue
        for label_file in "$hwmon_dir"/power*_label "$hwmon_dir"/energy*_label; do
            [[ -f "$label_file" ]] || continue

            local label
            label=$(<"$label_file")
            label=$(lower_strip "$label")
            if [[ "$label" != "card" && "$label" != "package" && "$label" != "pkg" ]]; then
                continue
            fi

            base=${label_file%_label}
            sensor_name=$(basename "$base")
            value_file=""
            if [[ -f "${base}_input" ]]; then
                value_file="${base}_input"
            elif [[ -f "${base}_average" ]]; then
                value_file="${base}_average"
            else
                continue
            fi

            if [[ "$sensor_name" == energy* ]]; then
                start=$(<"$value_file")
                sleep "$interval"
                end=$(<"$value_file")
                diff=$(( end - start ))
                if (( diff < 0 )); then
                    diff=$(( diff + 4294967296 ))
                fi
                power=$(awk -v diff="$diff" -v interval="$interval" \
                    'BEGIN { printf "%.2f", (diff/1000000)/interval }')
                printf "%s" "$power"
                return 0
            else
                sleep "$interval"
                start=$(<"$value_file")
                power=$(awk -v val="$start" 'BEGIN { printf "%.2f", val/1000000 }')
                printf "%s" "$power"
                return 0
            fi
        done

        # fallback: single power sensor without labels
        local power_files=("$hwmon_dir"/power*_input "$hwmon_dir"/power*_average)
        if (( ${#power_files[@]} == 1 )); then
            value_file="${power_files[0]}"
            [[ -f "$value_file" ]] || continue
            sleep "$interval"
            start=$(<"$value_file")
            power=$(awk -v val="$start" 'BEGIN { printf "%.2f", val/1000000 }')
            printf "%s" "$power"
            return 0
        fi
    done
    return 1
}

rapl_energy_path()
{
    local rapl_root="/sys/class/powercap"
    local domain name
    for domain in "$rapl_root"/intel-rapl:*; do
        [[ -d "$domain" ]] || continue
        [[ -f "$domain/name" ]] || continue
        name=$(<"$domain/name")
        name=$(lower_strip "$name")
        if [[ "$name" == package* ]] && [[ -f "$domain/energy_uj" ]]; then
            printf "%s" "$domain/energy_uj"
            return 0
        fi
    done

    for domain in "$rapl_root"/intel-rapl:*; do
        [[ -d "$domain" ]] || continue
        if [[ -f "$domain/energy_uj" ]]; then
            printf "%s" "$domain/energy_uj"
            return 0
        fi
    done
    return 1
}

read_rapl_package_power()
{
    local interval="$1"
    local energy_path start end diff power
    if ! energy_path=$(rapl_energy_path); then
        return 1
    fi

    start=$(<"$energy_path")
    sleep "$interval"
    end=$(<"$energy_path")
    diff=$(( end - start ))
    if (( diff < 0 )); then
        diff=$(( diff + 4294967296 ))
    fi
    power=$(awk -v diff="$diff" -v interval="$interval" \
        'BEGIN { printf "%.2f", (diff/1000000)/interval }')
    printf "%s" "$power"
    return 0
}

collect_power()
{
    declare -a DEVICES
    local found_any=false

    for card_path in "$DRM_ROOT"/card[0-9]*; do
        [[ -d "$card_path" ]] || continue
        driver_path=$(readlink -f "$card_path/device/driver" 2>/dev/null || true)
        [[ -n "$driver_path" ]] || continue
        driver=$(basename "$driver_path")
        if [[ "$driver" != "i915" && "$driver" != "xe" ]]; then
            continue
        fi

        found_any=true
        card_name=$(basename "$card_path")
        pci_slot=$(grep -m1 '^PCI_SLOT_NAME=' "$card_path/device/uevent" 2>/dev/null | cut -d= -f2)
        if [[ -z "$pci_slot" ]]; then
            pci_slot=$(basename "$(readlink -f "$card_path/device")")
        fi

        DEVICES+=("$card_path|$card_name|$driver|$pci_slot")
    done

    if ! $found_any; then
        echo "[ Error ] No i915/xe DRM devices found." >&2
        exit 1
    fi

    # --- Discover sensors for each device ---
    declare -a SENSOR_PATHS SENSOR_TYPES SENSOR_SOURCES
    for idx in "${!DEVICES[@]}"; do
        IFS='|' read -r card_path card_name driver pci_slot <<< "${DEVICES[$idx]}"
        local sensor_path="" sensor_type="" sensor_source=""

        # Try hwmon sensors
        for hwmon_dir in "$card_path/device"/hwmon/hwmon*; do
            [[ -d "$hwmon_dir" ]] || continue
            for label_file in "$hwmon_dir"/power*_label "$hwmon_dir"/energy*_label; do
                [[ -f "$label_file" ]] || continue
                local label
                label=$(<"$label_file")
                label=$(lower_strip "$label")
                if [[ "$label" != "card" && "$label" != "package" && "$label" != "pkg" ]]; then
                    continue
                fi
                local base=${label_file%_label}
                local sname
                sname=$(basename "$base")
                if [[ "$sname" == energy* ]] && [[ -f "${base}_input" ]]; then
                    sensor_path="${base}_input"; sensor_type="energy"; sensor_source="hwmon"; break 2
                elif [[ -f "${base}_input" ]]; then
                    sensor_path="${base}_input"; sensor_type="power"; sensor_source="hwmon"; break 2
                elif [[ -f "${base}_average" ]]; then
                    sensor_path="${base}_average"; sensor_type="power"; sensor_source="hwmon"; break 2
                fi
            done
            if [[ -z "$sensor_path" ]]; then
                local power_files=("$hwmon_dir"/power*_input "$hwmon_dir"/power*_average)
                if (( ${#power_files[@]} == 1 )) && [[ -f "${power_files[0]}" ]]; then
                    sensor_path="${power_files[0]}"; sensor_type="power"; sensor_source="hwmon"; break
                fi
            fi
        done

        # Fallback to RAPL
        if [[ -z "$sensor_path" ]]; then
            if sensor_path=$(rapl_energy_path); then
                sensor_type="energy"; sensor_source="rapl"
            else
                sensor_path=""; sensor_type=""; sensor_source="unavailable"
            fi
        fi

        SENSOR_PATHS[$idx]="$sensor_path"
        SENSOR_TYPES[$idx]="$sensor_type"
        SENSOR_SOURCES[$idx]="$sensor_source"
    done

    local samples
    samples=$(( Duration / Interval ))

    echo "[ Info ] Monitoring for ${Duration}s after a ${Delay}s delay" >&2
    echo "" >&2

    sleep "${Delay}"

    for (( i=0; i<samples; i++ )); do
        # Read start values for energy-based sensors
        declare -a start_vals
        for idx in "${!DEVICES[@]}"; do
            if [[ "${SENSOR_TYPES[$idx]}" == "energy" && -n "${SENSOR_PATHS[$idx]}" ]]; then
                start_vals[$idx]=$(<"${SENSOR_PATHS[$idx]}")
            fi
        done

        # Single sleep per sample interval
        sleep "$Interval"

        # Read end values and compute power for all devices
        for idx in "${!DEVICES[@]}"; do
            IFS='|' read -r card_path card_name driver pci_slot <<< "${DEVICES[$idx]}"
            local power="N/A"
            local source_type="${SENSOR_SOURCES[$idx]:-unavailable}"

            if [[ "${SENSOR_TYPES[$idx]}" == "energy" && -n "${SENSOR_PATHS[$idx]}" ]]; then
                local end_val
                end_val=$(<"${SENSOR_PATHS[$idx]}")
                local diff=$(( end_val - start_vals[$idx] ))
                if (( diff < 0 )); then
                    diff=$(( diff + 4294967296 ))
                fi
                power=$(awk -v diff="$diff" -v interval="$Interval" \
                    'BEGIN { printf "%.2f", (diff/1000000)/interval }')
            elif [[ "${SENSOR_TYPES[$idx]}" == "power" && -n "${SENSOR_PATHS[$idx]}" ]]; then
                local val
                val=$(<"${SENSOR_PATHS[$idx]}")
                power=$(awk -v val="$val" 'BEGIN { printf "%.2f", val/1000000 }')
            fi

            if [[ "$power" != "N/A" ]]; then
                printf "[%s] %s (%s @ %s): %s W\n" \
                    "$source_type" "$card_name" "$driver" "$pci_slot" "$power"
            else
                printf "[%s] %s (%s @ %s): power unavailable\n" \
                    "$source_type" "$card_name" "$driver" "$pci_slot" >&2
            fi
        done
    done

    echo "" >&2
    echo "[ Info ] Monitoring complete" >&2
}

collect_power
