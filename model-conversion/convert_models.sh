#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
modeldir="${basedir}/models"
datasetdir="${basedir}/datasets"
pipedir="${basedir}/../pipelines"

usage() {
echo "
Downloads, converts, and quantizes Yolo-v11n/s/m, Resnet-50, and Mobilenet-V2

Usage:
convert_models.sh -i <ImageNet Root Dir>

Example:
convert_models.sh -i datasets/imagenet-packages/
"
}

IMAGENET_ROOT=""

argparse() {
while getopts "hi:" arg; do
    case ${arg} in
        h)
        usage; exit 0
        ;;
        i)
        IMAGENET_ROOT="${OPTARG}"
        ;;
        *)
        usage; exit 1
        ;;
    esac
done
}

validate_imagenet_root() {
    local root="$1"
    if [[ ! -d "${root}" ]]; then
        echo "[ Info ] ImageNet root directory not found: ${root}" >&2
        echo "[ Info ] Defaulting to CIFAR-100 Dataset for Classification Quantization." >&2
    else
        local missing=()
        local requires=(
            "ILSVRC2012_devkit_t12.tar.gz"
	    "ILSVRC2012_img_val.tar"
        )

        for f in "${requires[@]}";
        do
	    [[ -f "${root}/${f}" ]] || missing+=("${f}")
        done
        if (( ${#missing[@]} > 0 )); then
	    echo "[ Error ] Missing expected ImageNet packages in ${root}:" >&2
	    for m in "${missing[@]}"; do echo " - ${m}" >&2; done
	    usage; exit 1
	fi
    fi
}

ensure_venv() {
    if [[ -d "${basedir}/venv" ]]; then
        echo "[ Info ] Using existing virtual environment at ${basedir}/venv"
    else
        echo "[ Info ] Creating virtual environment..."
	"${basedir}/scripts/setup_env.sh"
    fi
}

download_raw() {
    local url="$1" out="$2"
    mkdir -p "$(dirname -- "${out}")"
    echo "[ Download ] ${url} -> ${out}"
    rm -f "${out}.part"
    wget -q --tries=5 --timeout=30 -O "${out}.part" "${url}"
    mv -f "${out}.part" "${out}"
}

argparse "$@"
ensure_venv
source "${basedir}/venv/bin/activate"

echo ""
echo "[ Info ] Starting model download and conversion..."
echo ""

# Classification models (ResNet-50, MobileNet-v2)
if [[ -d "${IMAGENET_ROOT}" ]]; then
    validate_imagenet_root "${IMAGENET_ROOT}"
    echo "[ Info ] Converting ResNet-50 with ImageNet calibration..."
    python3 "${basedir}/download-models/resnet_downloader.py" -i="${IMAGENET_ROOT}"
    echo ""
    echo "[ Info ] Converting MobileNet-v2 with ImageNet calibration..."
    python3 "${basedir}/download-models/mobilenet_downloader.py" -i="${IMAGENET_ROOT}"
    echo ""
else
    echo "[ Info ] Converting ResNet-50 with CIFAR-100 calibration..."
    python3 "${basedir}/download-models/resnet_downloader.py"
    echo ""
    echo "[ Info ] Converting MobileNet-v2 with CIFAR-100 calibration..."
    python3 "${basedir}/download-models/mobilenet_downloader.py"
    echo ""
fi

# Detection models (YOLO variants with COCO calibration)
echo "[ Info ] Initializing Ultralytics settings..."
python3 "download-models/initialize_ultralytics.py" -i "${datasetdir}"
echo ""
echo "[ Info ] Converting YOLOv11n with COCO calibration..."
python3 "download-models/yolo_downloader.py" -m yolo11n -i "${datasetdir}" -o "${modeldir}"
echo ""
echo "[ Info ] Converting YOLOv11m with COCO calibration..."
python3 "download-models/yolo_downloader.py" -m yolo11m -i "${datasetdir}" -o "${modeldir}"
echo ""

echo "[ Info ] Downloading pre-converted YOLOv5m model..."
mkdir -p "${modeldir}/yolo-v5m"

download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/FP16-INT8/yolov5m-640_INT8.xml" "${modeldir}/yolo-v5m/yolov5m-640_INT8.xml"
download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/FP16-INT8/yolov5m-640_INT8.bin" "${modeldir}/yolo-v5m/yolov5m-640_INT8.bin"
download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/yolo-v5.json" "${modeldir}/yolo-v5m/yolo-v5.json"

mkdir -p "${modeldir}/resnet-50" "${modeldir}/mobilenet-v2"
download_raw "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/refs/heads/main/samples/gstreamer/model_proc/public/classification-optimized.json" "${modeldir}/resnet-50/resnet-50.json"
download_raw "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/refs/heads/main/samples/gstreamer/model_proc/public/classification-optimized.json" "${modeldir}/mobilenet-v2/mobilenet-v2.json"

echo ""
echo "[ Info ] Creating pipeline directory structure..."

# Make Pipelines Directory Structure
mkdir -p \
    "${pipedir}/light/detection" \
    "${pipedir}/light/classification" \
    "${pipedir}/medium/detection" \
    "${pipedir}/medium/classification" \
    "${pipedir}/heavy/detection" \
    "${pipedir}/heavy/classification"

mkdir -p "${pipedir}/light/detection/yolov11n_640x640/INT8/"
mkdir -p "${pipedir}/medium/detection/yolov5m_640x640/INT8/"
mkdir -p "${pipedir}/heavy/detection/yolov11m_640x640/INT8/"

mkdir -p "${pipedir}/medium/classification/resnet-v1-50-tf/INT8/"
mkdir -p "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/"

echo "[ Info ] Copying models to pipeline directories..."

# Fill Directory
cp "${modeldir}/resnet-50/resnet-50_int8.xml" "${pipedir}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml"
cp "${modeldir}/resnet-50/resnet-50_int8.bin" "${pipedir}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin"
cp "${modeldir}/resnet-50/resnet-50.json" "${pipedir}/medium/classification/resnet-v1-50-tf/."
cp -r "${pipedir}/medium/classification/resnet-v1-50-tf" "${pipedir}/light/classification/."
cp -r "${pipedir}/medium/classification/resnet-v1-50-tf" "${pipedir}/heavy/classification/."

cp "${modeldir}/mobilenet-v2/mobilenetv2_int8.xml" "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml"
cp "${modeldir}/mobilenet-v2/mobilenetv2_int8.bin" "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin"
cp "${modeldir}/mobilenet-v2/mobilenet-v2.json" "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/."
cp -r "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf" "${pipedir}/heavy/classification/."

cp "${modeldir}/yolo11n/yolo11n_int8.xml" "${pipedir}/light/detection/yolov11n_640x640/INT8/yolo11n.xml"
cp "${modeldir}/yolo11n/yolo11n_int8.bin" "${pipedir}/light/detection/yolov11n_640x640/INT8/yolo11n.bin"

cp "${modeldir}/yolo-v5m/yolov5m-640_INT8.xml" "${pipedir}/medium/detection/yolov5m_640x640/INT8/."
cp "${modeldir}/yolo-v5m/yolov5m-640_INT8.bin" "${pipedir}/medium/detection/yolov5m_640x640/INT8/."
cp "${modeldir}/yolo-v5m/yolo-v5.json" "${pipedir}/medium/detection/yolov5m_640x640/."

cp "${modeldir}/yolo11m/yolo11m_int8.xml" "${pipedir}/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml"
cp "${modeldir}/yolo11m/yolo11m_int8.bin" "${pipedir}/heavy/detection/yolov11m_640x640/INT8/yolo11m.bin"

echo ""
echo "[ Info ] Validating model conversion..."
echo ""

# Validation function
validate_model() {
    local name="$1"
    local xml_path="$2"
    local bin_path="$3"
    
    if [[ -f "${xml_path}" && -f "${bin_path}" ]]; then
        echo -e "\033[0;32m[ PASS ]\033[0m ${name}"
        return 0
    else
        echo -e "\033[0;31m[ FAIL ]\033[0m ${name}"
        [[ ! -f "${xml_path}" ]] && echo "        Missing: ${xml_path}"
        [[ ! -f "${bin_path}" ]] && echo "        Missing: ${bin_path}"
        return 1
    fi
}

# Track failures
failed=0

# Validate detection models
echo "Detection Models:"
validate_model "YOLOv11n (light)" \
    "${pipedir}/light/detection/yolov11n_640x640/INT8/yolo11n.xml" \
    "${pipedir}/light/detection/yolov11n_640x640/INT8/yolo11n.bin" || ((failed++))

validate_model "YOLOv5m (medium)" \
    "${pipedir}/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml" \
    "${pipedir}/medium/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.bin" || ((failed++))

validate_model "YOLOv11m (heavy)" \
    "${pipedir}/heavy/detection/yolov11m_640x640/INT8/yolo11m.xml" \
    "${pipedir}/heavy/detection/yolov11m_640x640/INT8/yolo11m.bin" || ((failed++))

echo ""
echo "Classification Models:"

# Validate classification models (check one copy, others are duplicates)
validate_model "ResNet-50" \
    "${pipedir}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" \
    "${pipedir}/medium/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" || ((failed++))

validate_model "MobileNet-v2" \
    "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml" \
    "${pipedir}/medium/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin" || ((failed++))

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "\033[0;32m[ SUCCESS ]\033[0m All models converted successfully"
    echo ""
    echo "Models are ready in: ${pipedir}/"
    echo "Next step: cd ../media-downloader && ./download_and_encode.sh"
    exit 0
else
    echo -e "\033[0;31m[ ERROR ]\033[0m ${failed} model(s) failed to convert"
    echo ""
    echo "Check the output above for specific errors."
    echo "You may need to rerun: ./convert_models.sh"
    exit 1
fi
