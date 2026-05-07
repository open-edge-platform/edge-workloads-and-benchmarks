#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
. "${basedir}/media-utils/helper_functions.sh"
. "${basedir}/../../utils/helper_functions.sh"

Timestamp="$(date "+%Y%m%d-%H%M%S")"
System="$(lscpu | grep "Model name" | grep -v "BIOS" | sed -n 's/^Model name://p' | sed 's/.*Intel/Intel/g')"

# Target per-stream fps and margin of error
# Example: 0.95 == 95% of target. 30 * 0.95 = 28.5 fps
# Example: 1.00 == 100% of target. 30 * 1.00 = 30.0 fps

TARGET_FPS_1080P=30
TARGET_FPS_4K=30

# Initialize parameters
MediaFile=""
NumStreams=1
Duration=120
Taskset="none"

# Help message
usage()
{
    echo "
Usage:
benchmark_media.sh -m <media_file> [-n <num_streams>] [-i <duration_seconds>] [-t <taskset>]

Options:
  -m <file>       Media filename (e.g. bears_1080.h265) or absolute path
  -n <streams>    Number of parallel decode streams (default: 1)
  -i <seconds>    Benchmark duration per run (default: 120)
  -t <taskset>    Core pinning (pcore, ecore, lpecore, nopin, or core list)

Example:
benchmark_media.sh -m bears_1080.h265 -n 8 -i 120
benchmark_media.sh -m bears_4k.h265 -n 1 -i 60
"
}

# Command line argument parser
argparse()
{
    while getopts "hm:n:i:t:" arg; do
        case $arg in
            m)
            MediaFile=${OPTARG}
            ;;
            n)
            NumStreams=${OPTARG}
            ;;
            i)
            Duration=${OPTARG}
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

# Validate parameters
[[ -n "${MediaFile}" ]] || { echo "[ Error ] -m <media_file> is required"; usage; exit 1; }

is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_posint "${NumStreams}" || { echo "[ Error ] -n must be a positive integer"; exit 1; }
is_posint "${Duration}"  || { echo "[ Error ] -i must be a positive integer (seconds)"; exit 1; }

# Determine codec and resolution from filename
Codec="${MediaFile##*.}"
case "${Codec}" in
    h265) Parser="parsebin"; Decoder="decodebin3"; CodecDir="hevc" ;;
    h264) Parser="parsebin"; Decoder="decodebin3"; CodecDir="avc" ;;
    *)    echo "[ Error ] Unsupported codec extension: ${Codec}"; exit 1 ;;
esac

if [[ "${MediaFile}" == *_4k.* ]]; then
    Resolution="4k"
    Width=3840; Height=2160
    TargetFPS="${TARGET_FPS_4K}"
elif [[ "${MediaFile}" == *_1080.* ]]; then
    Resolution="1080p"
    Width=1920; Height=1080
    TargetFPS="${TARGET_FPS_1080P}"
else
    echo "[ Error ] Cannot determine resolution from filename: ${MediaFile}"; exit 1
fi

# Resolve media path
if [[ "${MediaFile}" == /* ]]; then
    MediaAbs="${MediaFile}"
    MediaFile="$(basename "${MediaFile}")"
    ExternalMedia=true
elif [[ "${MediaFile}" == */* ]]; then
    # Relative path — resolve from CWD; mark external if outside collateral tree
    MediaAbs="$(realpath -m "${MediaFile}")"
    MediaFile="$(basename "${MediaFile}")"
    collateral_media="$(realpath "${basedir}/../../collateral/media")"
    if [[ "${MediaAbs}" == "${collateral_media}"/* ]]; then
        ExternalMedia=false
    else
        ExternalMedia=true
    fi
else
    MediaAbs="${basedir}/../../collateral/media/${CodecDir}/${MediaFile}"
    ExternalMedia=false
fi
[[ -f "${MediaAbs}" ]] || { echo "[ Error ] Media file not found: ${MediaAbs}"; exit 1; }
MediaAbs="$(realpath "${MediaAbs}")"

MediaName="$(basename "${MediaFile}" ".${Codec}")"

# Resolve core pinning
Cores="$(parse_core_pinning "${Taskset}")"

# Container path for the media file
if [[ "${ExternalMedia}" == true ]]; then
    ContainerMedia="/home/dlstreamer/external/$(basename "${MediaFile}")"
else
    collateral_media="$(realpath "${basedir}/../../collateral/media")"
    ContainerMedia="/home/dlstreamer/media/${MediaAbs#"${collateral_media}/"}"
fi

# Source element: filesrc for all media files
SourceElement="filesrc location=${ContainerMedia}"

# Construct decode-only pipeline
# shellcheck disable=SC2089
Pipeline="${SourceElement} ! ${Parser} ! ${Decoder} ! gvafpscounter starting-frame=100 ! fakesink sync=false async=false"

# Results
DeviceTag="GPU"
ResultsDir="${basedir}/../../collateral/results/media-benchmarks/${DeviceTag}"
mkdir -p "${ResultsDir}"
Filename="media-benchmark_${MediaName}_${Codec}_${Resolution}_${NumStreams}Str_${Timestamp}"

# Power monitoring
power_init "${ResultsDir}" "${Filename}" "${Duration}"
power_start "${Duration}"

# Configure Docker launch command
ContainerBase="media-benchmark-${Timestamp}-$$"
ContainerName="${ContainerBase}"

DockerCommand=(
    docker run --rm --init
    -v "${basedir}/../../collateral/media:/home/dlstreamer/media:ro"
    --env ONEDNN_VERBOSE=0
    --env OPENCV_OCL_RUNTIME=""
)

# Mount external media directory if an absolute path was provided
if [[ "${ExternalMedia}" == true ]]; then
    DockerCommand+=( -v "$(dirname "${MediaAbs}"):/home/dlstreamer/external:ro" )
fi

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
else
    echo "[ Error ] /dev/dri not found; GPU decode requires VA-API device."
    exit 1
fi

# Core pinning
if [[ -n "${Cores}" && "${Cores}" != "NO_PIN" ]]; then
    DockerCommand+=( --cpuset-cpus "${Cores}" )
fi

cleanup() {
    power_stop
    docker stop -t 2 "${ContainerName}" >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

# Build multi-stream launch command
Command=""
for _ in $(seq 1 "${NumStreams}"); do
    Command="${Command} ${Pipeline}"
done

LogFile="${ResultsDir}/${Filename}.log"

echo "[ Info ] Running media decode benchmark"
echo "[ Info ] Media: ${MediaFile} | Codec: ${CodecDir^^} | Resolution: ${Resolution}"
echo "[ Info ] Streams: ${NumStreams}"
echo "[ Info ] Duration: ${Duration}s"
echo ""
echo "[ Info ] Pipeline: ${Pipeline}"
echo ""

ThisDockerCommand=("${DockerCommand[@]}" --name "${ContainerName}" intel/dlstreamer:2026.1.0-20260505-weekly-ubuntu24)

sleep 1
# shellcheck disable=SC2086,SC2090
timeout --preserve-status "${Duration}s" "${ThisDockerCommand[@]}" gst-launch-1.0 ${Command} 2>&1 | grep --line-buffered -v "longjmp causes uninitialized stack frame" | tee "${LogFile}"

echo -e "\n\n"

echo "================="
echo "=    Summary    ="
echo "================="

# Process performance metrics
Throughput=$(grep 'FpsCounter' "${LogFile}" | grep 'average' | tail -n1 | sed 's/.*total=//' | cut -d' ' -f1)

# Process power metrics
power_stop
power_collect

if [[ -n "${Throughput}" && "${Throughput}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    ThroughputPerStream="$(LC_ALL=C awk -v t="${Throughput}" -v n="${NumStreams}" 'BEGIN { printf("%.2f", t / n) }')"
    TheoreticalStreams="$(LC_ALL=C awk -v t="${Throughput}" -v f="${TargetFPS}" 'BEGIN { printf("%d", int(t / f)) }')"
else
    echo "[ Error ] Could not parse throughput from log: ${LogFile}"
    Throughput="NA"
    ThroughputPerStream="NA"
    TheoreticalStreams="NA"
fi

# Calculate power efficiency
Efficiency="NA"
# shellcheck disable=SC2154  # AvgPower set by power_collect()
if [[ "${AvgPower}" != "NA" && "${Throughput}" != "NA" ]]; then
    Efficiency="$(LC_ALL=C awk -v fps="${Throughput}" -v watts="${AvgPower}" \
        'BEGIN { printf("%.2f", fps / watts) }')"
fi

echo "[ Info ] Media File: ${MediaFile}"
echo "[ Info ] Resolution: ${Resolution}"
echo "[ Info ] Codec: ${CodecDir^^}"
echo ""
echo "[ Info ] Average Total Throughput: ${Throughput} fps"
if [[ "${TheoreticalStreams}" != "NA" ]]; then
    echo "[ Info ] Theoretical Stream Density (@${TargetFPS}fps): ${TheoreticalStreams}"
fi
if [[ "${AvgPower}" != "NA" ]]; then
    echo "[ Info ] Average Power: ${AvgPower} W"
fi
if [[ "${Efficiency}" != "NA" ]]; then
    echo "[ Info ] Power Efficiency: ${Efficiency} FPS/W"
fi
echo -e "\n\n"

# Save results to CSV
csv_escape() { printf '%s' "$1" | sed 's/"/""/g'; }

CSVLabels="Timestamp,System,Media,Codec,Resolution,Streams,Duration (s),Throughput (fps),Throughput per Stream (fps/#),Theoretical Stream Density,Target FPS,Avg Power (W),Efficiency (FPS/W),Pipeline"

printf '%s\n' "${CSVLabels}" > "${ResultsDir}/${Filename}.csv"
printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$(csv_escape "${Timestamp}")" \
    "$(csv_escape "${System}")" \
    "$(csv_escape "${MediaName}")" \
    "$(csv_escape "${Codec}")" \
    "$(csv_escape "${Resolution}")" \
    "$(csv_escape "${NumStreams}")" \
    "$(csv_escape "${Duration}")" \
    "$(csv_escape "${Throughput}")" \
    "$(csv_escape "${ThroughputPerStream}")" \
    "$(csv_escape "${TheoreticalStreams}")" \
    "$(csv_escape "${TargetFPS}")" \
    "$(csv_escape "${AvgPower}")" \
    "$(csv_escape "${Efficiency}")" \
    "$(csv_escape "${Pipeline}")" \
    >> "${ResultsDir}/${Filename}.csv"

echo "[ Info ] Results saved to: ${ResultsDir}/${Filename}.csv"

fix_sudo_permissions "${ResultsDir}"
