#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
modeldir="${basedir}/models"
datasetdir="${basedir}/datasets"
collateraldir="${basedir}/../../collateral/models"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

usage() {
    echo "
Downloads, converts, and quantizes Yolo-v11n/m, Resnet-50, and Mobilenet-V2

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
        echo -e "${CYAN}[ Info ]${NC} Using existing virtual environment at ${basedir}/venv"
    else
        echo -e "${CYAN}[ Info ]${NC} Creating virtual environment..."
        "${basedir}/scripts/setup_env.sh"
    fi
}

download_raw() {
    local url="$1" out="$2"
    mkdir -p "$(dirname -- "${out}")"
    echo -e "${CYAN}[ Download ]${NC} ${url} -> ${out}"
    rm -f "${out}.part"
    wget -q --show-progress --tries=5 --timeout=30 -L -O "${out}.part" "${url}"
    mv -f "${out}.part" "${out}"
}

argparse "$@"
ensure_venv
source "${basedir}/venv/bin/activate"

# Suppress verbose library output
export NNCF_LOG_LEVEL=WARNING
export PYTHONWARNINGS="ignore::UserWarning"
export YOLO_VERBOSE=false
export TORCH_CPP_LOG_LEVEL=ERROR

echo ""
echo -e "${CYAN}[ Info ]${NC} Starting model download and conversion..."
echo ""

conv_failed=0

# Classification models (ResNet-50, MobileNet-v2)
if [[ -d "${IMAGENET_ROOT}" ]]; then
    validate_imagenet_root "${IMAGENET_ROOT}"
    echo -e "${GREEN}=== ResNet-50 ===${NC}"
    echo -e "${CYAN}[ Info ]${NC} Converting ResNet-50 with ImageNet calibration..."
    python3 "${basedir}/download-models/resnet_downloader.py" -i="${IMAGENET_ROOT}" || { echo -e "${RED}[ FAILED ]${NC} ResNet-50"; ((conv_failed++)) || true; }
    echo ""
    echo -e "${GREEN}=== MobileNet-v2 ===${NC}"
    echo -e "${CYAN}[ Info ]${NC} Converting MobileNet-v2 with ImageNet calibration..."
    python3 "${basedir}/download-models/mobilenet_downloader.py" -i="${IMAGENET_ROOT}" || { echo -e "${RED}[ FAILED ]${NC} MobileNet-v2"; ((conv_failed++)) || true; }
    echo ""
else
    echo -e "${GREEN}=== ResNet-50 ===${NC}"
    echo -e "${CYAN}[ Info ]${NC} Converting ResNet-50 with CIFAR-100 calibration..."
    python3 "${basedir}/download-models/resnet_downloader.py" || { echo -e "${RED}[ FAILED ]${NC} ResNet-50"; ((conv_failed++)) || true; }
    echo ""
    echo -e "${GREEN}=== MobileNet-v2 ===${NC}"
    echo -e "${CYAN}[ Info ]${NC} Converting MobileNet-v2 with CIFAR-100 calibration..."
    python3 "${basedir}/download-models/mobilenet_downloader.py" || { echo -e "${RED}[ FAILED ]${NC} MobileNet-v2"; ((conv_failed++)) || true; }
    echo ""
fi

# Detection models (YOLO variants with COCO calibration)
echo -e "${GREEN}=== Ultralytics Setup ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Initializing Ultralytics settings..."
python3 "${basedir}/download-models/initialize_ultralytics.py" -i "${datasetdir}" || { echo -e "${RED}[ FAILED ]${NC} Ultralytics setup"; ((conv_failed++)) || true; }
echo ""
echo -e "${GREEN}=== YOLOv11n ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Converting YOLOv11n with COCO calibration..."
python3 "${basedir}/download-models/yolo_downloader.py" -m yolo11n -i "${datasetdir}" -o "${modeldir}" -s "128" --subset-size "512" || { echo -e "${RED}[ FAILED ]${NC} YOLOv11n"; ((conv_failed++)) || true; }
echo ""
echo -e "${GREEN}=== YOLOv11m ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Converting YOLOv11m with COCO calibration..."
python3 "${basedir}/download-models/yolo_downloader.py" -m yolo11m -i "${datasetdir}" -o "${modeldir}" -s "128" --subset-size "512" || { echo -e "${RED}[ FAILED ]${NC} YOLOv11m"; ((conv_failed++)) || true; }
echo ""

echo -e "${GREEN}=== YOLOv5m ===${NC}"
echo -e "${CYAN}[ Info ]${NC} Downloading pre-converted YOLOv5m model..."
mkdir -p "${modeldir}/yolo-v5m"

download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/FP16-INT8/yolov5m-640_INT8.xml" "${modeldir}/yolo-v5m/yolov5m-640_INT8.xml" || { echo -e "${RED}[ FAILED ]${NC} YOLOv5m xml"; ((conv_failed++)) || true; }
download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/FP16-INT8/yolov5m-640_INT8.bin" "${modeldir}/yolo-v5m/yolov5m-640_INT8.bin" || { echo -e "${RED}[ FAILED ]${NC} YOLOv5m bin"; ((conv_failed++)) || true; }
download_raw "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/refs/heads/main/storage/yolov5m-640_INT8/yolo-v5.json" "${modeldir}/yolo-v5m/yolo-v5.json" || { echo -e "${RED}[ FAILED ]${NC} YOLOv5m json"; ((conv_failed++)) || true; }

mkdir -p "${modeldir}/resnet-50" "${modeldir}/mobilenet-v2"
download_raw "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/refs/heads/main/samples/gstreamer/model_proc/public/classification-optimized.json" "${modeldir}/resnet-50/resnet-50.json" || { echo -e "${RED}[ FAILED ]${NC} ResNet-50 json"; ((conv_failed++)) || true; }
download_raw "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/refs/heads/main/samples/gstreamer/model_proc/public/classification-optimized.json" "${modeldir}/mobilenet-v2/mobilenet-v2.json" || { echo -e "${RED}[ FAILED ]${NC} MobileNet-v2 json"; ((conv_failed++)) || true; }

echo ""
echo -e "${CYAN}[ Info ]${NC} Copying models to collateral directory..."

# Create collateral model directories
mkdir -p "${collateraldir}/detection/yolov11n_640x640/INT8"
mkdir -p "${collateraldir}/detection/yolov5m_640x640/INT8"
mkdir -p "${collateraldir}/detection/yolov11m_640x640/INT8"
mkdir -p "${collateraldir}/classification/resnet-v1-50-tf/INT8"
mkdir -p "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/INT8"

# Detection models
mv "${modeldir}/yolo11n/yolo11n_int8.xml" "${collateraldir}/detection/yolov11n_640x640/INT8/yolo11n.xml" 2>/dev/null || true
mv "${modeldir}/yolo11n/yolo11n_int8.bin" "${collateraldir}/detection/yolov11n_640x640/INT8/yolo11n.bin" 2>/dev/null || true

mv "${modeldir}/yolo-v5m/yolov5m-640_INT8.xml" "${collateraldir}/detection/yolov5m_640x640/INT8/." 2>/dev/null || true
mv "${modeldir}/yolo-v5m/yolov5m-640_INT8.bin" "${collateraldir}/detection/yolov5m_640x640/INT8/." 2>/dev/null || true
mv "${modeldir}/yolo-v5m/yolo-v5.json" "${collateraldir}/detection/yolov5m_640x640/." 2>/dev/null || true

mv "${modeldir}/yolo11m/yolo11m_int8.xml" "${collateraldir}/detection/yolov11m_640x640/INT8/yolo11m.xml" 2>/dev/null || true
mv "${modeldir}/yolo11m/yolo11m_int8.bin" "${collateraldir}/detection/yolov11m_640x640/INT8/yolo11m.bin" 2>/dev/null || true

# Classification models
mv "${modeldir}/resnet-50/resnet-50_int8.xml" "${collateraldir}/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" 2>/dev/null || true
mv "${modeldir}/resnet-50/resnet-50_int8.bin" "${collateraldir}/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" 2>/dev/null || true
mv "${modeldir}/resnet-50/resnet-50.json" "${collateraldir}/classification/resnet-v1-50-tf/." 2>/dev/null || true

mv "${modeldir}/mobilenet-v2/mobilenetv2_int8.xml" "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml" 2>/dev/null || true
mv "${modeldir}/mobilenet-v2/mobilenetv2_int8.bin" "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin" 2>/dev/null || true
mv "${modeldir}/mobilenet-v2/mobilenet-v2.json" "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/." 2>/dev/null || true

echo ""
echo -e "${CYAN}[ Info ]${NC} Validating model conversion..."
echo ""

# Validation function
validate_model() {
    local name="$1"
    local xml_path="$2"
    local bin_path="$3"
    
    if [[ -f "${xml_path}" && -f "${bin_path}" ]]; then
        echo -e "${GREEN}[ Pass ]${NC} ${name}"
        return 0
    else
        echo -e "${RED}[ Fail ]${NC} ${name}"
        [[ ! -f "${xml_path}" ]] && echo "        Missing: ${xml_path}"
        [[ ! -f "${bin_path}" ]] && echo "        Missing: ${bin_path}"
        return 1
    fi
}

# Track failures
failed=${conv_failed}

# Validate detection models
echo "Detection Models:"
validate_model "YOLOv11n" \
    "${collateraldir}/detection/yolov11n_640x640/INT8/yolo11n.xml" \
    "${collateraldir}/detection/yolov11n_640x640/INT8/yolo11n.bin" || { ((failed++)) || true; }

validate_model "YOLOv5m" \
    "${collateraldir}/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.xml" \
    "${collateraldir}/detection/yolov5m_640x640/INT8/yolov5m-640_INT8.bin" || { ((failed++)) || true; }

validate_model "YOLOv11m" \
    "${collateraldir}/detection/yolov11m_640x640/INT8/yolo11m.xml" \
    "${collateraldir}/detection/yolov11m_640x640/INT8/yolo11m.bin" || { ((failed++)) || true; }

echo ""

# Validate classification models
echo "Classification Models:"
validate_model "ResNet-50" \
    "${collateraldir}/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.xml" \
    "${collateraldir}/classification/resnet-v1-50-tf/INT8/resnet-v1-50-tf.bin" || { ((failed++)) || true; }

validate_model "MobileNet-v2" \
    "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.xml" \
    "${collateraldir}/classification/mobilenet-v2-1.0-224-tf/INT8/mobilenet-v2-1.0-224.bin" || { ((failed++)) || true; }

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}[ Success ]${NC} All models converted successfully"
    echo ""
    echo "Models are ready in: ${collateraldir}/"
    echo "Next step: cd ../media-downloader && ./download_and_encode.sh"
    exit 0
else
    echo -e "${RED}[ Error ]${NC} ${failed} model(s) failed to convert"
    echo ""
    echo "Check the output above for specific errors."
    echo "You may need to rerun: ./convert_models.sh"
    exit 1
fi
