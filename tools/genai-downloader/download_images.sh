#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Download a single COCO val2017 image and resize to standard VLM input
# resolutions for use as benchmark collateral.

set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
imgdir="${basedir}/../../collateral/media/images"
mkdir -p "${imgdir}"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Coco validation image
COCO_IMAGE_URL="http://images.cocodataset.org/val2017/000000000139.jpg"
COCO_ORIGINAL="${imgdir}/coco_original.jpg"
COCO_MD5="a0204aa65acc51cd8ffc128e5e94a05c"

# Download the source image
if [[ -f "${COCO_ORIGINAL}" ]]; then
    echo -e "${CYAN}[ Info ]${NC} COCO source image already exists, skipping download."
else
    echo -e "${CYAN}[ Info ]${NC} Downloading COCO val2017 image..."
    wget -q --show-progress --tries=5 --timeout=30 -O "${COCO_ORIGINAL}.part" "${COCO_IMAGE_URL}"
    mv -f "${COCO_ORIGINAL}.part" "${COCO_ORIGINAL}"
fi

# Verify integrity
actual_md5=$(md5sum "${COCO_ORIGINAL}" | awk '{print $1}')
if [[ "${actual_md5}" != "${COCO_MD5}" ]]; then
    echo -e "${RED}[ Error ]${NC} Checksum mismatch for ${COCO_ORIGINAL##*/}"
    echo "  Expected: ${COCO_MD5}"
    echo "  Got:      ${actual_md5}"
    rm -f "${COCO_ORIGINAL}"
    exit 1
fi

# Resize to target VLM input resolutions
SIZES=("224x224" "448x448" "640x640" "1080x1920")

failed=0
for size in "${SIZES[@]}"; do
    outfile="${imgdir}/coco_${size}.jpg"
    if [[ -f "${outfile}" ]]; then
        echo -e "${CYAN}[ Info ]${NC} ${outfile##*/} already exists, skipping."
        continue
    fi
    echo -e "${CYAN}[ Info ]${NC} Resizing to ${size}..."
    python3 -c "
from PIL import Image
img = Image.open('${COCO_ORIGINAL}')
w, h = '${size}'.split('x')
img_resized = img.resize((int(w), int(h)), Image.LANCZOS)
img_resized.save('${outfile}', 'JPEG', quality=95)
" || { echo -e "${RED}[ FAILED ]${NC} Failed to resize to ${size}"; ((failed++)) || true; continue; }
done

echo -e "${GREEN}[ Pass ]${NC} VLM test images ready in collateral/media/images/"

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}[ Error ]${NC} ${failed} resize(s) failed"
    exit 1
fi
