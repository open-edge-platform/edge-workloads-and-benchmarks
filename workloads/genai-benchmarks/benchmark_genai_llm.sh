#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"

Timestamp="$(date "+%Y%m%d-%H%M%S")"
System="$(lscpu | grep "Model name" | grep -v "BIOS" | sed -n 's/^Model name://p' | sed 's/.*Intel/Intel/g')"

ModelName=""
Device=""
Duration=60
Precision=""
Type="llm"
Taskset="none"

usage()
{
    echo "
Usage:
benchmark_genai_llm.sh -m <model_name> -d <device> -p <precision> [-i <duration_seconds>] [-t <taskset>]

Options:
  -m <name>       Model short name (e.g. llama-3.2-3b-instruct)
  -d <device>     Inference device (CPU, GPU, NPU)
  -p <precision>  Model precision (INT8_ASYM, INT4_SYM_CW)
  -i <seconds>    Benchmark duration per run (default: 60)
  -t <taskset>    Core pinning (pcore, ecore, lpecore, nopin, or core list)

Example:
benchmark_genai_llm.sh -m llama-3.2-3b-instruct -d GPU -p INT4_SYM_CW -i 60
benchmark_genai_llm.sh -m deepseek-qwen-1.5b -d NPU -p INT4_SYM_CW -i 60 -t ecore
"
}

argparse()
{
    while getopts "hm:d:i:p:t:" arg; do
        case $arg in
            m)
            ModelName=${OPTARG}
            ;;
            d)
            Device=${OPTARG}
            ;;
            i)
            Duration=${OPTARG}
            ;;
            p)
            Precision=${OPTARG}
            ;;
            t)
            Taskset=${OPTARG}
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

argparse "$@"

source "${basedir}/../../utils/helper_functions.sh"
source "${basedir}/genai-utils/helper_functions.sh"
Cores="$(parse_core_pinning "${Taskset}")"

if [[ -n "${Cores}" && "${Cores}" != "NO_PIN" ]]; then
    TasksetCmd=(taskset -c "${Cores}")
    echo "[ Info ] Core pinning: ${Cores}"
else
    TasksetCmd=()
fi

[[ -n "${ModelName}" ]] || { echo "[ Error ] -m <model_name> is required"; usage; exit 1; }
[[ -n "${Device}" ]] || { echo "[ Error ] -d <device> is required"; usage; exit 1; }
[[ -n "${Precision}" ]] || { echo "[ Error ] -p <precision> is required"; usage; exit 1; }

case "${Device}" in
    CPU|NPU|GPU|GPU.[0-9]*)
    ;;
    *)
    echo "[ Error ] Invalid device: ${Device}. Use CPU, GPU, or NPU."
    usage; exit 1
    ;;
esac

case "${Precision}" in
    INT8_ASYM|INT4_SYM_CW)
    ;;
    *)
    echo "[ Error ] Invalid precision: ${Precision}. Use INT8_ASYM or INT4_SYM_CW."
    usage; exit 1
    ;;
esac

is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_posint "${Duration}" || { echo "[ Error ] -i must be a positive integer (seconds)"; exit 1; }

ModelDir="${basedir}/../../collateral/models/genai/${ModelName}/${Precision}"
[[ -d "${ModelDir}" ]] || { echo "[ Error ] Model directory not found: ${ModelDir}"; exit 1; }

# Ensure venv exists
if [[ ! -d "${basedir}/venv" ]] || [[ ! -d "${basedir}/genai-utils/openvino.genai/tools/llm_bench" ]]; then
    echo "[ Info ] GenAI runtime environment not found. Setting up..."
    bash "${basedir}/genai-utils/setup_genai.sh"
fi
LLM_BENCH="${basedir}/genai-utils/openvino.genai/tools/llm_bench"
[[ -d "${LLM_BENCH}" ]] || { echo "[ Error ] openvino.genai llm_bench setup failed."; exit 1; }

cleanup()
{
    local benchpid
    benchpid=$(pgrep -f "${LLM_BENCH:-__no_match__}/benchmark.py" 2>/dev/null) || true
    [[ -n "${benchpid}" ]] && kill "${benchpid}" 2>/dev/null
    power_stop
    wait 2>/dev/null
}
trap cleanup INT TERM EXIT

DeviceDir="${basedir}/../../collateral/results/genai-benchmarks/${Device}"
mkdir -p "${DeviceDir}"
Filename="genai-benchmark_${ModelName}_${Device}_${Precision}_llm_${Timestamp}"

power_init "${DeviceDir}" "${Filename}" "${Duration}"

source "${basedir}/venv/bin/activate"

python3 -c "import matplotlib" 2>/dev/null  # pre-warm font cache

LogFile="${DeviceDir}/${Filename}.log"

LLM_PROMPT_FILE="${basedir}/genai-utils/openvino.genai/tools/llm_bench/prompts/llama-2-7b-chat_l.jsonl"

BenchCmd=("${TasksetCmd[@]}" python3 "${LLM_BENCH}/benchmark.py"
    -m "${ModelDir}"
    -d "${Device}"
    -n 256
    -ic 256
    -bs 1
    -pf "${LLM_PROMPT_FILE}"
)

echo "[ Info ] Running llm_bench: model=${ModelName} device=${Device} precision=${Precision} duration=${Duration}s"

# Wait for warm-up to complete before starting the duration timer and power
# monitoring, so model loading time is excluded from the measured duration.
stdbuf -oL "${BenchCmd[@]}" 2>&1 | tee "${LogFile}" | while IFS= read -r line; do
    if [[ "${line}" == *"[warm-up][P0] start:"* ]]; then
        echo "[ Info ] Model loaded. Starting ${Duration}s benchmark timer and power monitoring."

        power_start "${Duration}"

        sleep "${Duration}"

        echo "[ Info ] Duration reached. Stopping benchmark."
        benchpid=$(pgrep -f "${LLM_BENCH}/benchmark.py") || true
        if [[ -n "${benchpid}" ]]; then
            kill "${benchpid}" 2>/dev/null
        fi
        break
    fi
done

deactivate

if ! grep -qP '^\[ INFO \] \[\d+\]\[P\d+\] First token latency:' "${LogFile}" 2>/dev/null; then
    echo "[ Error ] llm_bench produced no iteration data for ${ModelName} on ${Device}. See ${LogFile}"
    exit 1
fi

echo -e "\n\n"

echo "================="
echo "=    Summary    ="
echo "================="

# Compute per-iteration averages from non-warmup iterations
FirstTokenLatency=$(
    grep -Pi '\[\d+\]\[P\d+\].*First token latency:\s*[\d.]+\s*ms' "${LogFile}" \
    | grep -v '\[warm-up\]' | grep -v '\[0\]\[P' \
    | grep -oP 'First token latency:\s*\K[\d.]+' \
    | awk '{sum+=$1; n++} END {if(n>0) printf "%.2f", sum/n; else print "NA"}'
)

SecondTokenThroughput=$(
    grep -Pi '\[\d+\]\[P\d+\].*other tokens latency:\s*[\d.]+\s*ms' "${LogFile}" \
    | grep -v '\[warm-up\]' | grep -v '\[0\]\[P' \
    | grep -oP 'other tokens latency:\s*\K[\d.]+' \
    | awk '{if($1>0){sum+=1000/$1; n++}} END {if(n>0) printf "%.2f", sum/n; else print "NA"}'
)

[[ -n "${FirstTokenLatency}" ]] || FirstTokenLatency="NA"
[[ -n "${SecondTokenThroughput}" ]] || SecondTokenThroughput="NA"

power_collect

Efficiency="NA"
# shellcheck disable=SC2154  # AvgPower set by power_collect()
if [[ "${AvgPower}" != "NA" && "${SecondTokenThroughput}" != "NA" ]]; then
    Efficiency="$(LC_ALL=C awk -v tpt="${SecondTokenThroughput}" -v watts="${AvgPower}" \
        'BEGIN { printf("%.2f", tpt / watts) }')"
fi

echo "[ Info ] Model: ${ModelName}"
echo "[ Info ] Precision: ${Precision}"
echo "[ Info ] Type: ${Type^^}"
echo "[ Info ] Device: ${Device}"
echo ""
echo "[ Info ] 1st Token Latency: ${FirstTokenLatency} ms"
echo "[ Info ] 2nd Token Throughput: ${SecondTokenThroughput} tok/s"
if [[ "${AvgPower}" != "NA" ]]; then
    echo "[ Info ] Average Power: ${AvgPower} W"
fi
if [[ "${Efficiency}" != "NA" ]]; then
    echo "[ Info ] Power Efficiency: ${Efficiency} tpt/W"
fi
echo -e "\n\n"

csv_escape() { printf '%s' "$1" | sed 's/"/""/g'; }

CSVLabels="Timestamp,System,Model,Device,Precision,Type,Duration (s),1st Token Latency (ms),2nd Token Throughput (tok/s),Avg Power (W),Efficiency (tpt/W),Cores Pinned"

printf '%s\n' "${CSVLabels}" > "${DeviceDir}/${Filename}.csv"
printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$(csv_escape "${Timestamp}")" \
    "$(csv_escape "${System}")" \
    "$(csv_escape "${ModelName}")" \
    "$(csv_escape "${Device}")" \
    "$(csv_escape "${Precision}")" \
    "$(csv_escape "${Type}")" \
    "$(csv_escape "${Duration}")" \
    "$(csv_escape "${FirstTokenLatency}")" \
    "$(csv_escape "${SecondTokenThroughput}")" \
    "$(csv_escape "${AvgPower}")" \
    "$(csv_escape "${Efficiency}")" \
    "$(csv_escape "${Cores}")" \
    >> "${DeviceDir}/${Filename}.csv"

fix_sudo_permissions "${DeviceDir}"
