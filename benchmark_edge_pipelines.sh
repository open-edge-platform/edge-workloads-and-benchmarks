#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
. "${basedir}/utils/pipeline_constructor.sh"
. "${basedir}/utils/helper_functions.sh"

Timestamp="$(date "+%Y%m%d-%H%M%S")"
System="$(lscpu | grep "Model name" | grep -v "BIOS" | sed -n 's/^Model name://p' | sed 's/.*Intel/Intel/g')"

# Target per-stream fps and margin of error
# Example: 0.95 == 95% of target. 30 * 0.95 = 28.5 fps
# Example: 1.00 == 100% of target. 30 * 1.00 = 30.0 fps

TARGET_FPS=30
ERROR_MARGIN=1.00

# Initialize parameters
PipelineConfig="none"
NumStreams=1

DeviceDetect="CPU"
DeviceClassify="CPU"
BatchSize=1

Duration=120
Taskset="none"
Concurrent=false

# Help message
usage()
{
echo "
Usage:
benchmark_edge_pipelines.sh -p <Pipeline Config (light,medium,heavy)> -n <Num Streams (#)> -b <Batch Size (#)> -d <DetectDevice> -c <Classify Device> -i <Test Duration (sec)> -t <Taskset Core List> --concurrent

Taskset Options:
  -t \"0,1,2\"       : Comma-separated core list
  -t \"0-4\"         : Core range
  -t pcore         : Use P-cores only
  -t ecore         : Use E-cores only (recommended)
  -t lpecore       : Use LP-E-cores only
  -t nopin         : No core pinning (default)

Example:
benchmark_edge_pipelines.sh -p light -n 8 -b 8 -d GPU -c NPU -i 120 -t \"6-9\" --concurrent
benchmark_edge_pipelines.sh -p heavy -n 4 -b 1 -d GPU -c NPU -i 120 -t ecore
"
}

# Command line argument parser
argparse()
{
while getopts "hp:n:b:d:c:i:t:-:" arg; do
    case $arg in
	p)
	PipelineConfig=${OPTARG}
	;;
	n)
	NumStreams=${OPTARG}
	;;
	b)
	BatchSize=${OPTARG}
	;;
	d)
	DeviceDetect=${OPTARG}
	;;
	c)
	DeviceClassify=${OPTARG}
	;;
	i)
	Duration=${OPTARG}
	;;
	t)
	Taskset=${OPTARG}
	;;
	-)
	case "${OPTARG}" in
	    concurrent)
	    Concurrent=true
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

argparse "$@"

# Validate parameters
case "${PipelineConfig}" in
    light|medium|heavy)
    ;;
    *)
    echo "[ Error ] Please select from light, medium, or heavy."
    usage; exit 1
    ;;
esac

case "${DeviceDetect}" in
    CPU|NPU|GPU|GPU.[0-9]*)
    ;;
    *)
    echo "[ Error ] Invalid device for detection: ${DeviceDetect}"
    usage; exit 1
    ;;
esac

case "${DeviceClassify}" in
    CPU|NPU|GPU|GPU.[0-9]*)
    ;;
    *)
    echo "[ Error ] Invalid device for classification: ${DeviceClassify}"
    usage; exit 1
    ;;
esac

# Resolve core pinning using helper function
Cores="$(parse_core_pinning "${Taskset}")"

is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_posint "${NumStreams}" || { echo "[ Error ] -n must be a positive integer"; exit 1; }
is_posint "${BatchSize}"  || { echo "[ Error ] -b must be a positive integer"; exit 1; }
is_posint "${Duration}"   || { echo "[ Error ] -i must be a positive integer (seconds)"; exit 1; }

validate_assets "${PipelineConfig}" "${basedir}/pipelines" || { echo "[ Error ] Validation failed."; exit 1; }

# Construct GStreamer pipeline
DecodePipe="$(construct_decode "${PipelineConfig}")"

# Build pipeline commands
Commands=()
PipelineTemplates=()
PipelineDescriptions=()

if [[ "${Concurrent}" == true && "${DeviceDetect}" != "${DeviceClassify}" ]]; then
    # If concurrent, then split streams based off of Detect/Classify devices
    DetectStreams=$(( (NumStreams + 1) / 2 ))  # Round up
    ClassifyStreams=$(( NumStreams - DetectStreams ))
    
    if [[ ${DetectStreams} -gt 0 ]]; then
        # Build device-1 pipeline (using DeviceDetect for both detect and classify)
        DetectPipeOnly="$(construct_detection "${PipelineConfig}" "${DeviceDetect}" "${BatchSize}")"
        ClassifyPipeOnly="$(construct_classification "${PipelineConfig}" "${DeviceDetect}" "${BatchSize}")"
        DetectLaunch="${DecodePipe} ! queue ! ${DetectPipeOnly} ! queue ! gvatrack tracking-type=1 config=tracking_per_class=false ! queue ! ${ClassifyPipeOnly} ! queue ! gvafpscounter starting-frame=2000 ! fakesink sync=false async=false"
        
        DetectCommand=""
        for i in $(seq 1 "${DetectStreams}"); do
            DetectCommand="${DetectCommand} ${DetectLaunch}"
        done
        Commands+=("${DetectCommand}")

        PipelineTemplates+=("${DetectLaunch}")
        PipelineDescriptions+=("${DetectStreams} streams using ${DeviceDetect} for both detection and classification")
    fi
    
    if [[ ${ClassifyStreams} -gt 0 ]]; then
        # Build device-2 pipeline (using DeviceClassify for both detect and classify)
        DetectPipeOnly="$(construct_detection "${PipelineConfig}" "${DeviceClassify}" "${BatchSize}")"
        ClassifyPipeOnly="$(construct_classification "${PipelineConfig}" "${DeviceClassify}" "${BatchSize}")"
        ClassifyLaunch="${DecodePipe} ! queue ! ${DetectPipeOnly} ! queue ! gvatrack tracking-type=1 config=tracking_per_class=false ! queue ! ${ClassifyPipeOnly} ! queue ! gvafpscounter starting-frame=2000 ! fakesink sync=false async=false"
        
        ClassifyCommand=""
        for i in $(seq 1 "${ClassifyStreams}"); do
            ClassifyCommand="${ClassifyCommand} ${ClassifyLaunch}"
        done
        Commands+=("${ClassifyCommand}")

        PipelineTemplates+=("${ClassifyLaunch}")
        PipelineDescriptions+=("${ClassifyStreams} streams using ${DeviceClassify} for both detection and classification")
    fi
else
    # Otherwise, use the default pipeline template
    DetectPipe="$(construct_detection "${PipelineConfig}" "${DeviceDetect}" "${BatchSize}")"
    ClassifyPipe="$(construct_classification "${PipelineConfig}" "${DeviceClassify}" "${BatchSize}")"
    Launch="${DecodePipe} ! queue ! ${DetectPipe} ! queue ! gvatrack tracking-type=1 config=tracking_per_class=false ! queue ! ${ClassifyPipe} ! queue ! gvafpscounter starting-frame=2000 ! fakesink sync=false async=false"

    Command=""
    for i in $(seq 1 "${NumStreams}"); do
        Command="${Command} ${Launch}"
    done
    Commands=("${Command}")

    PipelineTemplates=("${Launch}")
    PipelineDescriptions=("${NumStreams} streams using ${DeviceDetect} for detection and ${DeviceClassify} for classification")
fi

# Generate container names for all containers
if [[ "${Concurrent}" == true && "${DeviceDetect}" != "${DeviceClassify}" ]]; then
    ContainerBase="e2e-edge-pipeline-${Timestamp}-$$"
    DeviceTag="${DeviceDetect}-${DeviceClassify}-Concurrent"
else
    if [[ "${DeviceDetect}" == "${DeviceClassify}" ]]; then
        DeviceName="${DeviceDetect}-Only"
        DeviceTag="${DeviceDetect}-Only"
    else
        DeviceName="${DeviceDetect}-${DeviceClassify}-Split"
        DeviceTag="${DeviceDetect}-${DeviceClassify}-Split"
    fi
    ContainerBase="e2e-edge-pipeline-${DeviceName}-${Timestamp}-$$"
fi

ResultsDir="${basedir}/results/${DeviceTag}"
mkdir -p "${ResultsDir}"
Filename="e2e-edge-pipeline_${PipelineConfig}_${NumStreams}Str_${DeviceDetect}-Det_${DeviceClassify}-Class_BS${BatchSize}_${Timestamp}"

# Power monitoring
PowerPID=""
PowerLogFile="${ResultsDir}/${Filename}_power.log"
PowerDelay=$(bc <<< "scale=0; ${Duration} / 4")
PowerDuration=$(bc <<< "scale=0; ${Duration} / 2")

if [[ -x "${basedir}/utils/get_package_power.sh" ]]; then
    "${basedir}/utils/get_package_power.sh" -s 1 -i "${PowerDuration}" -d "${PowerDelay}" > "${PowerLogFile}" 2>&1 &
    PowerPID=$!
    sleep 0.5
    if kill -0 "${PowerPID}" 2>/dev/null; then
        echo "[ Info ] Power monitoring started (PID: ${PowerPID})"
    else
        wait "${PowerPID}" 2>/dev/null || true
        PowerPID=""
    fi
fi

docker ps -aq --filter "name=e2e-edge-pipeline-*-${Timestamp}" 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true

# Configure Docker launch command
DockerCommand=(
    docker run --rm --init
    -v "${basedir}/pipelines:/home/dlstreamer/pipelines"
    --env ONEDNN_VERBOSE=0
    --env OPENCV_OCL_RUNTIME=""
)

# /dev/dri (GPU/VA)
if [[ -d /dev/dri ]]; then
    DockerCommand+=( --device /dev/dri )
    declare -A _seen_gid_dri=()
    if compgen -G "/dev/dri/render*" >/dev/null; then
        for n in /dev/dri/render*; do
	    gid="$(stat -c '%g' "$n" 2>/dev/null || true)"
	    [[ -n "${gid}" && -z "${_seen_gid_dri[$gid]:-}" ]] && {
	        DockerCommand+=( --group-add "${gid}" )
	        _seen_gid_dri["$gid"]=1
	    }
	done
    fi
fi

# /dev/accel (NPU)
if [[ -e /dev/accel ]]; then
    DockerCommand+=( --device /dev/accel )
    declare -A _seen_gid_accel=()
    if compgen -G "/dev/accel/accel*" >/dev/null; then
	for n in /dev/accel/accel*; do
	    gid="$(stat -c '%g' "$n" 2>/dev/null || true)"
	    [[ -n "${gid}" && -z "${_seen_gid_accel[$gid]:-}" ]] && {
		DockerCommand+=( --group-add "${gid}" )
	        _seen_gid_accel["$gid"]=1
	    }
        done
    fi
fi

# Core pinning for workload scheduling
if [[ -n "${Cores}" && "${Cores}" != "NO_PIN" ]]; then
    DockerCommand+=( --cpuset-cpus "${Cores}" )
fi

cleanup() {

    if [[ -n "${PowerPID:-}" ]]; then
        kill "${PowerPID}" 2>/dev/null || true
        wait "${PowerPID}" 2>/dev/null || true
    fi
    
    if [[ ${#Commands[@]} -gt 1 ]]; then
        ContainerName1="${ContainerBase}-${DeviceDetect}"
        ContainerName2="${ContainerBase}-${DeviceClassify}"
        docker stop -t 2 "${ContainerName1}" >/dev/null 2>&1 || true
        docker stop -t 2 "${ContainerName2}" >/dev/null 2>&1 || true
    else
        ContainerName="${ContainerBase}"
        docker stop -t 2 "${ContainerName}" >/dev/null 2>&1 || true
    fi
}
trap cleanup INT TERM EXIT

LogFiles=()
if [[ ${#Commands[@]} -gt 1 ]]; then
    DeviceNames=("${DeviceDetect}" "${DeviceClassify}")
    for i in "${!Commands[@]}"; do
        ContainerName="${ContainerBase}-${DeviceNames[$i]}"
        LogFile="${ResultsDir}/${Filename}_part${i}.log"
        LogFiles+=("${LogFile}")
        
        echo "[ Info ] Running pipeline ${i}: ${PipelineDescriptions[$i]}"
        echo "[ Info ] Container: ${ContainerName}"
        echo ""
        echo "[ Info ] Pipeline Template: ${PipelineTemplates[$i]}"
        ThisDockerCommand=("${DockerCommand[@]}" --name "${ContainerName}" intel/dlstreamer:latest)
        
        # Run the pipelines
	# shellcheck disable=SC2086
        timeout --preserve-status "${Duration}s" "${ThisDockerCommand[@]}" gst-launch-1.0 ${Commands[$i]} 2>&1 | grep --line-buffered -v "longjmp causes uninitialized stack frame" | tee "${LogFile}" &
    done
    wait
else
    ContainerName="${ContainerBase}"
    LogFile="${ResultsDir}/${Filename}.log"
    
    echo "[ Info ] Running pipeline: ${PipelineDescriptions[0]}"
    echo "[ Info ] Container: ${ContainerName}"
    echo ""
    echo "[ Info ] Pipeline Template: ${PipelineTemplates[0]}"
    ThisDockerCommand=("${DockerCommand[@]}" --name "${ContainerName}" intel/dlstreamer:latest)
    
    # Run the pipelines
    # shellcheck disable=SC2086
    sleep 1
    timeout --preserve-status "${Duration}s" "${ThisDockerCommand[@]}" gst-launch-1.0 ${Commands[0]} 2>&1 | grep --line-buffered -v "longjmp causes uninitialized stack frame" | tee "${LogFile}"
fi

# Combine all log files into a single log for analysis in concurrent mode
if [[ "${Concurrent}" == true && ${#LogFiles[@]} -gt 1 ]]; then
    cat "${LogFiles[@]}" > "${ResultsDir}/${Filename}.log"
fi

echo -e "\n\n"

echo "================="
echo "=    Summary    ="
echo "================="

# Process performance metrics
Throughput=$(grep 'FpsCounter' "${ResultsDir}/${Filename}.log" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)

# Process power metrics if available
AvgPower="NA"
if [[ -n "${PowerPID:-}" ]]; then
    kill "${PowerPID}" 2>/dev/null || true
    wait "${PowerPID}" 2>/dev/null || true
    if [[ -f "${PowerLogFile}" ]] && grep -q "W$" "${PowerLogFile}" 2>/dev/null; then
        AvgPower=$(grep -oP '\d+\.\d+(?= W)' "${PowerLogFile}" | \
            awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "NA"}')
        if [[ "${AvgPower}" != "NA" ]]; then
            echo "[ Info ] Average Power: ${AvgPower} W"
        fi
    fi
fi

# Add up throughputs from all parts if using concurrent mode
if [[ "${Concurrent}" == true && ${#LogFiles[@]} -gt 1 ]]; then
    TotalThroughput=0
    for LogFile in "${LogFiles[@]}"; do
        PartThroughput=$(grep 'FpsCounter' "${LogFile}" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)
        if [[ -n "${PartThroughput}" && "${PartThroughput}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            TotalThroughput="$(LC_ALL=C awk -v total="${TotalThroughput}" -v part="${PartThroughput}" 'BEGIN { printf("%.2f", total + part) }')"
        fi
    done
    Throughput="${TotalThroughput}"
fi
if [[ -n "${Throughput}" && "${Throughput}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    ThroughputPerStream="$(LC_ALL=C awk -v t="${Throughput}" -v n="${NumStreams}" 'BEGIN { printf("%.2f", t / n) }')"
    TheoreticalStreams="$(LC_ALL=C awk -v t="${Throughput}" -v f="${TARGET_FPS}" -v m="${ERROR_MARGIN}" 'BEGIN { printf("%d", int(t / (f*m))) }')"

    echo "[ Info ] Average Total Throughput: ${Throughput} fps"
    echo "[ Info ] Throughput per Stream (${NumStreams}): ${ThroughputPerStream} fps/stream"
    echo "[ Info ] Theoretical Stream Density (@${TARGET_FPS}): ${TheoreticalStreams}"
else
    echo "[ Error ] Could not parse throughput from log: ${ResultsDir}/${Filename}.log"
    Throughput="NA"
    ThroughputPerStream="NA"
    TheoreticalStreams="NA"
fi

# Calculate power efficiency if power data available
Efficiency="NA"
if [[ "${AvgPower}" != "NA" && "${Throughput}" != "NA" ]]; then
    Efficiency="$(LC_ALL=C awk -v fps="${Throughput}" -v watts="${AvgPower}" \
        'BEGIN { printf("%.2f", fps / watts) }')"
    echo "[ Info ] Power Efficiency: ${Efficiency} FPS/W"
fi
echo -e "\n\n"

# Save results to a CSV file
csv_escape() { printf '%s' "$1" | sed 's/"/""/g'; }

if [[ ${#Commands[@]} -gt 1 ]]; then
    # Multiple pipelines in concurrent mode
    CSVLabels="Timestamp,System,Duration (s),Cores Pinned,Pipeline Config,Detect Device,Classify Device,Batch,Throughput (fps),Throughput per Stream (fps/#),Theoretical Stream Density (@${TARGET_FPS}fps±5%),Measured Stream Density (#),Concurrent Mode,Device Configuration,Avg Power (W),Efficiency (FPS/W),Pipeline1,Pipeline2"
    
    printf '%s\n' "${CSVLabels}" > "${ResultsDir}/${Filename}.csv"
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "$(csv_escape "${Timestamp}")" \
        "$(csv_escape "${System}")" \
        "$(csv_escape "${Duration}")" \
        "$(csv_escape "${Cores}")" \
        "$(csv_escape "${PipelineConfig}")" \
        "$(csv_escape "${DeviceDetect}")" \
        "$(csv_escape "${DeviceClassify}")" \
        "$(csv_escape "${BatchSize}")" \
        "$(csv_escape "${Throughput}")" \
        "$(csv_escape "${ThroughputPerStream}")" \
        "$(csv_escape "${TheoreticalStreams}")" \
        "$(csv_escape "${NumStreams}")" \
        "$(csv_escape "${Concurrent}")" \
        "$(csv_escape "${DeviceTag}")" \
        "$(csv_escape "${AvgPower}")" \
        "$(csv_escape "${Efficiency}")" \
        "$(csv_escape "${PipelineTemplates[0]}")" \
        "$(csv_escape "${PipelineTemplates[1]}")" \
        >> "${ResultsDir}/${Filename}.csv"
else
    # Not concurrent mode
    CSVLabels="Timestamp,System,Duration (s),Cores Pinned,Pipeline Config,Detect Device,Classify Device,Batch,Throughput (fps),Throughput per Stream (fps/#),Theoretical Stream Density (@${TARGET_FPS}fps±5%),Measured Stream Density (#),Concurrent Mode,Device Configuration,Avg Power (W),Efficiency (FPS/W),Pipeline"
    
    printf '%s\n' "${CSVLabels}" > "${ResultsDir}/${Filename}.csv"
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "$(csv_escape "${Timestamp}")" \
        "$(csv_escape "${System}")" \
        "$(csv_escape "${Duration}")" \
        "$(csv_escape "${Cores}")" \
        "$(csv_escape "${PipelineConfig}")" \
        "$(csv_escape "${DeviceDetect}")" \
        "$(csv_escape "${DeviceClassify}")" \
        "$(csv_escape "${BatchSize}")" \
        "$(csv_escape "${Throughput}")" \
        "$(csv_escape "${ThroughputPerStream}")" \
        "$(csv_escape "${TheoreticalStreams}")" \
        "$(csv_escape "${NumStreams}")" \
        "$(csv_escape "${Concurrent}")" \
        "$(csv_escape "${DeviceTag}")" \
        "$(csv_escape "${AvgPower}")" \
        "$(csv_escape "${Efficiency}")" \
        "$(csv_escape "${PipelineTemplates[0]}")" \
        >> "${ResultsDir}/${Filename}.csv"
fi
