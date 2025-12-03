#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

PIPE_ROOT="/home/dlstreamer/pipelines"

construct_decode()
{
    local pipeconfig=${1:-light}
    local video

    case "${pipeconfig}" in
        light)
	video="${PIPE_ROOT}/light/video/bears.h265"
	;;
        medium)
	video="${PIPE_ROOT}/medium/video/apple.h265"
	;;
        heavy)
	video="${PIPE_ROOT}/heavy/video/bears.h265"
	;;
	*)
	echo "[ Error ] construct_decode: unknown config ${pipeconfig}" >&2; return 1
	;;
    esac

    DecodePipe="filesrc location=${video} ! h265parse ! vah265dec ! capsfilter caps=\"video/x-raw(memory:VAMemory)\""
    echo "${DecodePipe}"
}

construct_detection()
{
    local pipeconfig=${1:-light}
    local device=${2:-CPU}
    local batch=${3:-1}

    local detmodel detproc modelID
    case "${pipeconfig}" in
        light)
	detmodel="${PIPE_ROOT}/light/detection/yolov11n_640x640/INT8/yolo11n.xml"
	modelID="yolov11n"
	;;
        medium)
	detmodel="${PIPE_ROOT}/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml"
	detproc="${PIPE_ROOT}/medium/detection/yolov5m_640x640/yolo-v5.json"
	modelID="yolov5m"
	;;
        heavy)
	detmodel="${PIPE_ROOT}/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml"
	modelID="yolov11m"
	;;
	*)
	echo "[ Error ] construct_detection: unknown config ${pipeconfig}" >&2; return 1
	;;
    esac

    local ppbackend infconfig
    case "${device}" in
        CPU)
	ppbackend="opencv"
	infconfig=""
	;;
        GPU|GPU.[0-9]*)
	ppbackend="va-surface-sharing"
	infconfig="nireq=2 ie-config=NUM_STREAMS=2"
	;;
        NPU)
	ppbackend="opencv"
	infconfig="nireq=4"
	batch=1
	;;
	*)
	echo "[ Error ] construct_detection: unknown device ${device}" >&2; return 1
	;;
    esac

    DetectPipe="gvadetect model=${detmodel}"
    if [[ -n "${detproc:-}" ]]; then
	DetectPipe+=" model-proc=${detproc}"
    fi

    DetectPipe+=" device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 threshold=0.5 model-instance-id=${modelID}"
    echo "${DetectPipe}"
}

construct_classification()
{
    local pipeconfig=${1:-light}
    local device=${2:-CPU}
    local batch=${3:-1}
    
    local ppbackend infconfig
    case "${device}" in
        CPU)
        ppbackend="opencv"
        infconfig=""
        ;;
        GPU|GPU.[0-9]*)
        ppbackend="va-surface-sharing"
        infconfig="nireq=2 ie-config=NUM_STREAMS=2"
        ;;
        NPU)
        ppbackend="opencv"
        infconfig="nireq=4"
        batch=1
        ;;
        *)
        echo "[ Error ] construct_classification: unknown device ${device}" >&2; return 1
        ;;
    esac

    local classmodel classproc modelID classmodel2 classproc2 modelID2 pipeline1 pipeline2
    case "${pipeconfig}" in
        light)
	classmodel="${PIPE_ROOT}/light/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
	classproc="${PIPE_ROOT}/light/classification/resnet-v1-50-tf/resnet-50.json"
	modelID="resnet50"

	ClassPipe="gvaclassify model=${classmodel} model-proc=${classproc} device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 inference-region=1 model-instance-id=${modelID}"
        ;;
        medium)
        classmodel="${PIPE_ROOT}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
	classproc="${PIPE_ROOT}/medium/classification/resnet-v1-50-tf/resnet-50.json"
	modelID="resnet50"
	classmodel2="${PIPE_ROOT}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml"
	classproc2="${PIPE_ROOT}/medium/classification/mobilenet-v2-1.0-224-tf/mobilenet-v2.json"
	modelID2="mobilenetv2"

	pipeline1="gvaclassify model=${classmodel} model-proc=${classproc} device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 inference-region=1 model-instance-id=${modelID}"
	pipeline2="gvaclassify model=${classmodel2} model-proc=${classproc2} device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 inference-region=1 model-instance-id=${modelID2}"
	ClassPipe="${pipeline1} ! queue ! ${pipeline2}"
        ;;
        heavy)
        classmodel="${PIPE_ROOT}/heavy/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
	classproc="${PIPE_ROOT}/heavy/classification/resnet-v1-50-tf/resnet-50.json"
	modelID="resnet50"
	classmodel2="${PIPE_ROOT}/heavy/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml"
	classproc2="${PIPE_ROOT}/heavy/classification/mobilenet-v2-1.0-224-tf/mobilenet-v2.json"
	modelID2="mobilenetv2"

	pipeline1="gvaclassify model=${classmodel} model-proc=${classproc} device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 inference-region=1 model-instance-id=${modelID}"
	pipeline2="gvaclassify model=${classmodel2} model-proc=${classproc2} device=${device} pre-process-backend=${ppbackend} ${infconfig} batch-size=${batch} inference-interval=3 inference-region=1 model-instance-id=${modelID2}"
	ClassPipe="${pipeline1} ! queue ! ${pipeline2}"
        ;;
        *)
        echo "[ Error ] construct_classification: unknown config ${pipeconfig}" >&2; return 1
        ;;
    esac
    echo "${ClassPipe}"
}
