#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
mediadir="${basedir}/media"
collateraldir="${basedir}/../../collateral/media"
mkdir -p "${mediadir}/mp4" "${mediadir}/hevc" "${mediadir}/avc" "${mediadir}/hevc_4k" "${mediadir}/avc_4k"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

ONE_OBJ_VIDEO_URL="https://videos.pexels.com/video-files/6891009/6891009-uhd_3840_2160_30fps.mp4"
TWO_OBJ_VIDEO_URL="https://videos.pexels.com/video-files/18856748/18856748-uhd_3840_2160_60fps.mp4"

echo ""
echo -e "${GREEN}=== Source Videos ===${NC}"

download_pexels() {
    (( $# == 2 )) || { echo -e "${RED}[ Error ]${NC} download_pexels <url> <out>"; exit 1; }
    local url="$1" out="$2"
    rm -f "${out}.part"
    wget -q --show-progress --tries=5 --timeout=30 -L \
        -O "${out}.part" "${url}"
    mv -f "${out}.part" "${out}"
}

# Download media from Pexels (apple: 1 obj/frame)
if [[ -f "${mediadir}/mp4/apple.mp4" ]]; then
    echo -e "${CYAN}[ Info ]${NC} File \"apple.mp4\" already exists in media directory. Skipping download."
else
    echo -e "${CYAN}[ Info ]${NC} Downloading \"apple.mp4\" video file from Pexels."
    download_pexels "${ONE_OBJ_VIDEO_URL}" "${mediadir}/mp4/apple.mp4"
fi

# Download media from Pexels (bears: 2 obj/frame)
if [[ -f "${mediadir}/mp4/bears.mp4" ]]; then
    echo -e "${CYAN}[ Info ]${NC} File \"bears.mp4\" already exists in media directory. Skipping download."
else
    echo -e "${CYAN}[ Info ]${NC} Downloading \"bears.mp4\" video file from Pexels."
    download_pexels "${TWO_OBJ_VIDEO_URL}" "${mediadir}/mp4/bears.mp4"
fi

# /dev/dri (GPU / VA)
docker_args=(docker run --rm --init --user "$(id -u):$(id -g)" -v "${mediadir}:/mnt/media")
if [[ -d /dev/dri ]]; then
    docker_args+=( --device /dev/dri )
    declare -A _seen_gid_dri=()
    if compgen -G "/dev/dri/render*" >/dev/null; then
        for n in /dev/dri/render*; do
            gid="$(stat -c '%g' "$n" 2>/dev/null || true)"
            [[ -n "${gid}" && -z "${_seen_gid_dri[$gid]:-}" ]] && {
                docker_args+=( --group-add "${gid}" )
                _seen_gid_dri["$gid"]=1
            }
        done
    fi
else
    echo -e "${RED}[ Error ]${NC} /dev/dri not found; VA-API transcode requires GPU/VA device."
    exit 1
fi

docker_args+=(intel/dlstreamer:2026.1.0-20260505-weekly-ubuntu24)

# Transcode video: transcode <input> <output> <codec: h265|h264> <resolution: 1080p|4k>
transcode() {
    local in="$1" out="$2" codec="$3" res="$4"
    local width height bitrate encoder parser outdir ext

    if [[ "${res}" == "4k" ]]; then
        width=3840; height=2160
    else
        width=1920; height=1080
    fi

    if [[ "${codec}" == "h265" ]]; then
        parser="h265parse"; ext="h265"
        if [[ "${res}" == "4k" ]]; then outdir="hevc_4k"; else outdir="hevc"; fi
        encoder="vah265enc"
        if [[ "${res}" == "4k" ]]; then bitrate=8000; else bitrate=2000; fi
    else
        parser="h264parse"; ext="h264"
        if [[ "${res}" == "4k" ]]; then outdir="avc_4k"; else outdir="avc"; fi
        encoder="vah264enc"
        if [[ "${res}" == "4k" ]]; then bitrate=12000; else bitrate=3000; fi
    fi

    local name="${in%.mp4}"
    echo -e "\n${CYAN}[ Info ]${NC} Transcoding ${name} to ${res} ${codec^^}."

    "${docker_args[@]}" gst-launch-1.0 \
        filesrc location="/mnt/media/mp4/${in}" ! \
        decodebin3 ! \
        videorate ! "video/x-raw,framerate=30/1" ! \
        vapostproc ! \
        capsfilter caps="video/x-raw(memory:VAMemory),pixel-aspect-ratio=1/1,width=${width},height=${height},framerate=30/1" ! \
        ${encoder} bitrate=${bitrate} b-frames=0 key-int-max=60 ! \
        ${parser} ! \
        filesink location="/mnt/media/${outdir}/${out}" \
        2>&1 | grep -v -E '^\(gst-plugin-scanner:|libva info:|Redistribute latency|Got context from element'
}

# Transcode 1080p HEVC and AVC
echo ""
echo -e "${GREEN}=== Transcode ===${NC}"
transcode_failed=0
[[ -f "${collateraldir}/hevc/apple_1080.h265" ]] || transcode "apple.mp4" "apple_1080.h265" h265 1080p || { echo -e "${RED}[ FAILED ]${NC} apple 1080p HEVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/hevc/bears_1080.h265" ]] || transcode "bears.mp4" "bears_1080.h265" h265 1080p || { echo -e "${RED}[ FAILED ]${NC} bears 1080p HEVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/avc/apple_1080.h264" ]]  || transcode "apple.mp4" "apple_1080.h264" h264 1080p || { echo -e "${RED}[ FAILED ]${NC} apple 1080p AVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/avc/bears_1080.h264" ]]  || transcode "bears.mp4" "bears_1080.h264" h264 1080p || { echo -e "${RED}[ FAILED ]${NC} bears 1080p AVC"; ((transcode_failed++)) || true; }

# Transcode 4K HEVC and AVC
[[ -f "${collateraldir}/hevc/apple_4k.h265" ]]   || transcode "apple.mp4" "apple_4k.h265" h265 4k || { echo -e "${RED}[ FAILED ]${NC} apple 4K HEVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/hevc/bears_4k.h265" ]]   || transcode "bears.mp4" "bears_4k.h265" h265 4k || { echo -e "${RED}[ FAILED ]${NC} bears 4K HEVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/avc/apple_4k.h264" ]]    || transcode "apple.mp4" "apple_4k.h264" h264 4k || { echo -e "${RED}[ FAILED ]${NC} apple 4K AVC"; ((transcode_failed++)) || true; }
[[ -f "${collateraldir}/avc/bears_4k.h264" ]]    || transcode "bears.mp4" "bears_4k.h264" h264 4k || { echo -e "${RED}[ FAILED ]${NC} bears 4K AVC"; ((transcode_failed++)) || true; }

# Loop 1080p files 100x for longer testing and move to collateral
mkdir -p "${collateraldir}/hevc" "${collateraldir}/avc"
echo ""
echo -e "${GREEN}=== Finalize ===${NC}"
needs_loop=0
for f in hevc/apple_1080.h265 hevc/bears_1080.h265 avc/apple_1080.h264 avc/bears_1080.h264; do
    [[ -f "${collateraldir}/${f}" ]] || { needs_loop=1; break; }
done

if [[ "${needs_loop}" -eq 1 ]]; then
    echo -e "${CYAN}[ Info ]${NC} Looping 1080p files x100 for continuous streaming."
    for pair in \
        "hevc/apple_1080.h265" \
        "hevc/bears_1080.h265" \
        "avc/apple_1080.h264"  \
        "avc/bears_1080.h264"; do
        [[ -f "${collateraldir}/${pair}" ]] && continue
        codec_dir="${pair%%/*}"
        filename="${pair##*/}"
        : > "${mediadir}/${codec_dir}/${filename%.???}_loop100.${filename##*.}"
        for _ in $(seq 100); do
            cat "${mediadir}/${codec_dir}/${filename}" >> "${mediadir}/${codec_dir}/${filename%.???}_loop100.${filename##*.}" || { echo -e "${RED}[ Error ]${NC} Failed to loop ${pair}"; break; }
        done
        mv "${mediadir}/${codec_dir}/${filename%.???}_loop100.${filename##*.}" "${collateraldir}/${pair}" || true
    done
else
    echo -e "${CYAN}[ Info ]${NC} 1080p looped files already in collateral. Skipping."
fi

# Move 4K files to collateral
for pair in \
    "hevc_4k/apple_4k.h265:hevc/apple_4k.h265" \
    "hevc_4k/bears_4k.h265:hevc/bears_4k.h265" \
    "avc_4k/apple_4k.h264:avc/apple_4k.h264"   \
    "avc_4k/bears_4k.h264:avc/bears_4k.h264"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    if [[ ! -f "${collateraldir}/${dst}" && -f "${mediadir}/${src}" ]]; then
        mv "${mediadir}/${src}" "${collateraldir}/${dst}" || true
    fi
done

echo -e "${CYAN}[ Info ]${NC} 1080p (looped x100): hevc/apple_1080.h265, hevc/bears_1080.h265, avc/apple_1080.h264, avc/bears_1080.h264"
echo -e "${CYAN}[ Info ]${NC} 4K (single-clip): hevc/apple_4k.h265, hevc/bears_4k.h265, avc/apple_4k.h264, avc/bears_4k.h264"
echo -e "${GREEN}[ Success ]${NC} Video files successfully converted. Ending media transcode."

if [[ ${transcode_failed} -gt 0 ]]; then
    echo -e "${RED}[ Error ]${NC} ${transcode_failed} transcode(s) failed"
    exit 1
fi