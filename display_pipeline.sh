#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
. "${basedir}/utils/pipeline_constructor.sh"
. "${basedir}/utils/helper_functions.sh"
Timestamp="$(date "+%Y%m%d-%H%M%S")"

IS_EMT=false
if [ -f /etc/os-release ]; then
    os_name=$(grep -i '^NAME=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"')
    if echo "$os_name" | grep -qi "Edge Microvisor Toolkit"; then
        IS_EMT=true
    fi
fi

if [ "$IS_EMT" = true ]; then
    echo "[ Info ] Skipping display pipeline on Edge Microvisor Toolkit (no desktop environment)"
    exit 0
fi

# Initialize parameters
PipelineConfig="none"

DeviceDetect="CPU"
DeviceClassify="CPU"
BatchSize=1

Duration=120
Taskset="none"

# Help message
usage()
{
echo "
Usage:
display_pipeline.sh -p <Pipeline Config (light,medium,heavy)> -d <DetectDevice> -c <Classify Device> -i <Test Duration (sec)> -t <Taskset Core List>

Taskset Options:
  -t \"0,1,2\"       : Comma-separated core list
  -t \"0-4\"         : Core range
  -t pcore         : Use P-cores only
  -t ecore         : Use E-cores only
  -t lpecore       : Use LP-E-cores only
  -t nopin         : No core pinning (default)

Example:
display_pipeline.sh -p light -d GPU -c NPU -i 120 -t \"6-9\"
display_pipeline.sh -p heavy -d GPU -c NPU -i 120 -t pcore
"
}

# Command line argument parser
argparse()
{
while getopts "hp:d:c:i:t:" arg; do
    case $arg in
	p)
	PipelineConfig=${OPTARG}
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
    echo "[ Error ] Please select from light, medium, or heavy (Example: -p light)."
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
is_posint "${Duration}"   || { echo "[ Error ] -i must be a positive integer (seconds)"; exit 1; }

validate_assets "${PipelineConfig}" "${basedir}/pipelines" || exit 1

# Construct GStreamer pipeline
DecodePipe="$(construct_decode "${PipelineConfig}")"
DetectPipe="$(construct_detection "${PipelineConfig}" "${DeviceDetect}" "${BatchSize}")"
ClassifyPipe="$(construct_classification "${PipelineConfig}" "${DeviceClassify}" "${BatchSize}")"
Launch="${DecodePipe} ! queue ! ${DetectPipe} ! queue ! gvatrack tracking-type=1 config=tracking_per_class=false ! queue ! ${ClassifyPipe} ! queue ! gvawatermark ! videoconvert ! gvafpscounter starting-frame=60 ! ximagesink sync=true"


# Build pipeline commands
ContainerName="e2e-edge-pipeline-${Timestamp}-$$"
DockerCommand=(
    docker run --rm --init
    --network host
    -e "DISPLAY=${DISPLAY:-}"
    --name "${ContainerName}"
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

# /dev/accel (NPU) - optional
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
    docker stop -t 2 "${ContainerName}" >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

DockerCommand+=( intel/dlstreamer:latest )
Command="gst-launch-1.0 ${Launch}"
echo "[ Info ] Pipeline Command: ${Command}"

# Run pipeline
# shellcheck disable=SC2086
timeout --preserve-status "${Duration}s" "${DockerCommand[@]}" ${Command}
echo "[ Info ] Done!"
