#!/bin/bash

# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

basedir="$(realpath "$(dirname -- "$0")")"
mediadir="${basedir}/media"
pipedir="${basedir}/../pipelines"
mkdir -p "${mediadir}/mp4" "${mediadir}/hevc"

ONE_OBJ_VIDEO_URL="https://videos.pexels.com/video-files/6891009/6891009-uhd_3840_2160_30fps.mp4"
TWO_OBJ_VIDEO_URL="https://videos.pexels.com/video-files/18856748/18856748-uhd_3840_2160_60fps.mp4"

download_pexels() {
    (( $# == 2 )) || { echo "[ Error ] download_pexels <url> <out>"; exit 1; }
    local url="$1" out="$2"
    rm -f "${out}.part"
    wget -q --show-progress --tries=5 --timeout=30 -L \
        -O "${out}.part" "${url}"
    mv -f "${out}.part" "${out}"
}

# Download media from Pexels (apple: 1 obj/frame)
if [[ -f "${mediadir}/mp4/apple.mp4" ]]; then
    echo "[ Info ] File \"apple.mp4\" already exists in media directory. Skipping download."
else
    echo "[ Info ] Downloading \"apple.mp4\" video file from Pexels."
    download_pexels "${ONE_OBJ_VIDEO_URL}" "${mediadir}/mp4/apple.mp4"
fi

# Download media from Pexels (bears: 2 obj/frame)
if [[ -f "${mediadir}/mp4/bears.mp4" ]]; then
    echo "[ Info ] File \"bears.mp4\" already exists in media directory. Skipping download."
else
    echo "[ Info ] Downloading \"bears.mp4\" video file from Pexels."
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
    echo "[ Error ] /dev/dri not found; VA-API transcode requires GPU/VA device."
    exit 1
fi

docker_args+=(intel/dlstreamer:weekly-2026.0-20260127-ubuntu24)

transcode_to_h265() {
    local in="$1" out="$2"
    "${docker_args[@]}" gst-launch-1.0 \
        filesrc location="/mnt/media/mp4/${in}" ! \
	decodebin3 ! \
	videorate ! "video/x-raw,framerate=30/1" ! \
	vapostproc ! \
	capsfilter caps="video/x-raw(memory:VAMemory),pixel-aspect-ratio=1/1,width=1920,height=1080,framerate=30/1" ! \
	vah265enc bitrate=2000 b-frames=0 key-int-max=60 ! \
	h265parse ! \
	filesink location="/mnt/media/hevc/${out}"
}

# Convert apple and bear videos into H265 1080p30 2Mbps video files with no B-frames
[[ -f "${mediadir}/hevc/apple.h265" ]] || transcode_to_h265 "apple.mp4" "apple.h265"
[[ -f "${mediadir}/hevc/bears.h265" ]] || transcode_to_h265 "bears.mp4" "bears.h265"

: > "${mediadir}/hevc/apple_loop100.h265"
: > "${mediadir}/hevc/bears_loop100.h265"

for _ in $(seq 100);
do
    cat "${mediadir}/hevc/apple.h265" >> "${mediadir}/hevc/apple_loop100.h265"
    cat "${mediadir}/hevc/bears.h265" >> "${mediadir}/hevc/bears_loop100.h265"
done

# Create media directory structure in ../pipelines
for config in light medium heavy; do
    mkdir -p "${pipedir}/${config}/video"
done

echo "[ Info ] Copying transcoded video files to ${pipedir}."
cp "${mediadir}/hevc/bears_loop100.h265" "${pipedir}/light/video/bears.h265"
cp "${mediadir}/hevc/apple_loop100.h265" "${pipedir}/medium/video/apple.h265"
cp "${mediadir}/hevc/bears_loop100.h265" "${pipedir}/heavy/video/bears.h265"

echo "[ Info ] Transcoded and looped: apple.h265 (x100), bears.h265 (x100)"
echo "[ Success ] Video files successfully converted. Ending media transcode."
