#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"

Timestamp="$(date "+%Y%m%d-%H%M%S")"
System="$(lscpu | grep "Model name" | grep -v "BIOS" | sed -n 's/^Model name://p' | sed 's/.*Intel/Intel/g')"

# Initialize parameters
ModelPath=""
Device=""
Duration=120
Mode="tput"
BatchSize=1
Concurrent=""
Taskset="none"

# Help message
usage()
{
    echo "
Usage:
benchmark_vision.sh -m <model_path> -d <device> [-i <duration_seconds>] [-e <mode>] [-b <batch_size>] [--concurrent <device2>]

Options:
  -m <path>       Path to model .xml file (relative to collateral/models/ or absolute)
  -d <device>     Inference device (CPU, GPU, NPU)
  -i <seconds>    Benchmark duration per run (default: 120)
  -e <mode>       Inference mode hint: tput or latency (default: tput)
  -b <batch>      Batch size (default: 1)
  -t <taskset>    Core pinning (pcore, ecore, lpecore, nopin, or core list)
  --concurrent <device2>  Run -d device and device2 concurrently (batch applies to -d, device2 always BS1)

Example:
benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -i 60
benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -e latency -b 4
benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -e tput -b 8 --concurrent NPU
"
}

# Command line argument parser
argparse()
{
    while getopts "hm:d:i:e:b:t:-:" arg; do
        case $arg in
            m)
            ModelPath=${OPTARG}
            ;;
            d)
            Device=${OPTARG}
            ;;
            i)
            Duration=${OPTARG}
            ;;
            e)
            Mode=${OPTARG}
            ;;
            b)
            BatchSize=${OPTARG}
            ;;
            t)
            Taskset=${OPTARG}
            ;;
            -)
            case "${OPTARG}" in
                concurrent)
                Concurrent=${!OPTIND}
                OPTIND=$((OPTIND + 1))
                ;;
                *)
                echo "[ Error ] Unknown option --${OPTARG}"
                usage; exit 1
                ;;
            esac
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

model_shortname()
{
    local model_path="$1"
    basename "$(dirname "$(dirname "${model_path}")")"
}

argparse "$@"

# Resolve core pinning
source "${basedir}/../../utils/helper_functions.sh"
Cores="$(parse_core_pinning "${Taskset}")"

if [[ -n "${Cores}" && "${Cores}" != "NO_PIN" ]]; then
    TasksetCmd=(taskset -c "${Cores}")
    echo "[ Info ] Core pinning: ${Cores}"
else
    TasksetCmd=()
fi

# Validate parameters
[[ -n "${ModelPath}" ]] || { echo "[ Error ] -m <model_path> is required"; usage; exit 1; }
[[ -n "${Device}" ]] || { echo "[ Error ] -d <device> is required"; usage; exit 1; }

case "${Device}" in
    CPU|NPU|GPU|GPU.[0-9]*)
    ;;
    *)
    echo "[ Error ] Invalid device: ${Device}. Use CPU, GPU, or NPU."
    usage; exit 1
    ;;
esac

case "${Mode}" in
    tput|latency)
    ;;
    *)
    echo "[ Error ] Invalid mode: ${Mode}. Use tput or latency."
    usage; exit 1
    ;;
esac

is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_posint "${Duration}"  || { echo "[ Error ] -i must be a positive integer (seconds)"; exit 1; }
is_posint "${BatchSize}" || { echo "[ Error ] -b must be a positive integer"; exit 1; }

if [[ -n "${Concurrent}" ]]; then
    case "${Concurrent}" in
        CPU|NPU|GPU|GPU.[0-9]*)
        ;;
        *)
        echo "[ Error ] Invalid concurrent device: ${Concurrent}. Use CPU, GPU, or NPU."
        usage; exit 1
        ;;
    esac
    [[ "${Device}" != "${Concurrent}" ]] || { echo "[ Error ] --concurrent device must differ from -d device"; exit 1; }
fi

# Resolve model path
if [[ "${ModelPath}" = /* ]]; then
    ModelAbs="${ModelPath}"
else
    ModelAbs="${basedir}/../../collateral/models/${ModelPath}"
fi
[[ -f "${ModelAbs}" ]] || { echo "[ Error ] Model not found: ${ModelAbs}"; exit 1; }

# Ensure venv exists
if [[ ! -d "${basedir}/venv" ]]; then
    echo "[ Info ] Virtual environment not found. Setting up..."
    bash "${basedir}/vision-utils/setup_env.sh"
fi

cleanup()
{
    power_stop
    [[ -n "${Dev1Pid:-}" ]] && kill "${Dev1Pid}" 2>/dev/null
    [[ -n "${Dev2Pid:-}" ]] && kill "${Dev2Pid}" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup INT TERM EXIT

Shortname="$(model_shortname "${ModelPath}")"

# Set device tag and results directory
if [[ -n "${Concurrent}" ]]; then
    DeviceTag="${Device}-${Concurrent}-Concurrent"
else
    DeviceTag="${Device}"
fi

DeviceDir="${basedir}/../../collateral/results/vision-benchmarks/${DeviceTag}"
mkdir -p "${DeviceDir}"
Filename="vision-benchmark_${Shortname}_${DeviceTag}_${Mode}_BS${BatchSize}_${Timestamp}"

# Power monitoring
power_init "${DeviceDir}" "${Filename}" "${Duration}"
power_start "${Duration}"

source "${basedir}/venv/bin/activate"

LogFile="${DeviceDir}/${Filename}.log"

if [[ -n "${Concurrent}" ]]; then
    Dev1Log="${DeviceDir}/${Filename}_${Device}.log"
    Dev2Log="${DeviceDir}/${Filename}_${Concurrent}.log"

    echo "[ Info ] Running concurrent benchmark_app: model=${Shortname} ${Device}(BS${BatchSize})+${Concurrent}(BS1) mode=${Mode} duration=${Duration}s"

    "${TasksetCmd[@]}" benchmark_app -m "${ModelAbs}" -d "${Device}" -hint "${Mode}" -b "${BatchSize}" -t "${Duration}" > "${Dev1Log}" 2>&1 &
    Dev1Pid=$!

    "${TasksetCmd[@]}" benchmark_app -m "${ModelAbs}" -d "${Concurrent}" -hint "${Mode}" -b 1 -t "${Duration}" > "${Dev2Log}" 2>&1 &
    Dev2Pid=$!

    Failed=0
    wait "${Dev1Pid}" || { echo "[ Error ] ${Device} benchmark_app failed for ${Shortname}"; Failed=1; }
    wait "${Dev2Pid}" || { echo "[ Error ] ${Concurrent} benchmark_app failed for ${Shortname}"; Failed=1; }

    if (( Failed )); then
        deactivate
        exit 1
    fi

    # Combine logs
    cat "${Dev1Log}" "${Dev2Log}" > "${LogFile}"

    # Parse metrics from each device
    Dev1Throughput=$(grep -oP 'Throughput:\s+\K[\d.]+' "${Dev1Log}" || echo "NA")
    Dev2Throughput=$(grep -oP 'Throughput:\s+\K[\d.]+' "${Dev2Log}" || echo "NA")
    Dev1Latency=$(grep -oP 'Median:\s+\K[\d.]+' "${Dev1Log}" || echo "NA")
    Dev2Latency=$(grep -oP 'Median:\s+\K[\d.]+' "${Dev2Log}" || echo "NA")

    # Sum throughputs
    if [[ "${Dev1Throughput}" != "NA" && "${Dev2Throughput}" != "NA" ]]; then
        Throughput="$(LC_ALL=C awk -v a="${Dev1Throughput}" -v b="${Dev2Throughput}" 'BEGIN { printf("%.2f", a + b) }')"
    else
        echo "[ Error ] Concurrent run failed: one or both devices did not produce valid throughput."
        echo "[ Error ] ${Device} FPS: ${Dev1Throughput}, ${Concurrent} FPS: ${Dev2Throughput}"
        Throughput="NA"
    fi
    Latency="NA"
    PrimaryFPS="${Dev1Throughput}"
    SecondaryFPS="${Dev2Throughput}"
else
    echo "[ Info ] Running benchmark_app: model=${Shortname} device=${Device} mode=${Mode} batch=${BatchSize} duration=${Duration}s"

    "${TasksetCmd[@]}" benchmark_app -m "${ModelAbs}" -d "${Device}" -hint "${Mode}" -b "${BatchSize}" -t "${Duration}" > "${LogFile}" 2>&1 || {
        echo "[ Error ] benchmark_app failed for ${Shortname} on ${Device}. See ${LogFile}"
        deactivate
        exit 1
    }

    # Process performance metrics
    Throughput=$(grep -oP 'Throughput:\s+\K[\d.]+' "${LogFile}" || echo "NA")

    Latency=$(grep -oP 'Median:\s+\K[\d.]+' "${LogFile}" || echo "NA")
    PrimaryFPS="NA"
    SecondaryFPS="NA"
fi

deactivate

echo -e "\n\n"

echo "================="
echo "=    Summary    ="
echo "================="

# Process power metrics if available
power_stop
power_collect

echo "[ Info ] Model: ${Shortname}"
echo "[ Info ] Device: ${DeviceTag}"
echo "[ Info ] Mode: ${Mode}"
echo "[ Info ] Batch Size: ${BatchSize}"
echo ""
echo "[ Info ] Median Latency: ${Latency} ms"
echo "[ Info ] Throughput: ${Throughput} FPS"

# Calculate power efficiency
Efficiency="NA"
# shellcheck disable=SC2154  # AvgPower set by power_collect()
if [[ "${AvgPower}" != "NA" && "${Throughput}" != "NA" ]]; then
    Efficiency="$(LC_ALL=C awk -v fps="${Throughput}" -v watts="${AvgPower}" \
        'BEGIN { printf("%.2f", fps / watts) }')"
    echo "[ Info ] Average Power: ${AvgPower} W"
    echo "[ Info ] Power Efficiency: ${Efficiency} FPS/W"
fi
echo -e "\n\n"

# Save results to a CSV file
csv_escape() { printf '%s' "$1" | sed 's/"/""/g'; }

CSVLabels="Timestamp,System,Model,Device,Mode,Batch,Duration (s),Throughput (fps),Median Latency (ms),Concurrent,Avg Power (W),Efficiency (FPS/W),Primary FPS,Secondary FPS,Cores Pinned"

printf '%s\n' "${CSVLabels}" > "${DeviceDir}/${Filename}.csv"
printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$(csv_escape "${Timestamp}")" \
    "$(csv_escape "${System}")" \
    "$(csv_escape "${Shortname}")" \
    "$(csv_escape "${DeviceTag}")" \
    "$(csv_escape "${Mode}")" \
    "$(csv_escape "${BatchSize}")" \
    "$(csv_escape "${Duration}")" \
    "$(csv_escape "${Throughput}")" \
    "$(csv_escape "${Latency}")" \
    "$(csv_escape "${Concurrent:-None}")" \
    "$(csv_escape "${AvgPower}")" \
    "$(csv_escape "${Efficiency}")" \
    "$(csv_escape "${PrimaryFPS}")" \
    "$(csv_escape "${SecondaryFPS}")" \
    "$(csv_escape "${Cores}")" \
    >> "${DeviceDir}/${Filename}.csv"

fix_sudo_permissions "${DeviceDir}"
