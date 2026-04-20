#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

basedir="$(realpath "$(dirname -- "$0")")"
mediadir="$(realpath "${basedir}/../../../collateral/media")"

echo "# Media benchmark coverage matrix"
echo "# Format: media_file,codec,resolution,streams"

count=0

# 1080p media: test at 8 streams
for file in bears_1080.h265 apple_1080.h265 bears_1080.h264 apple_1080.h264; do
    [[ -f "${mediadir}/hevc/${file}" || -f "${mediadir}/avc/${file}" ]] || continue
    codec="${file##*.}"
    echo "${file},${codec},1080p,8"
    count=$((count + 1))
done

# 4K media: test at 8 streams
for file in bears_4k.h265 apple_4k.h265 bears_4k.h264 apple_4k.h264; do
    [[ -f "${mediadir}/hevc/${file}" || -f "${mediadir}/avc/${file}" ]] || continue
    codec="${file##*.}"
    echo "${file},${codec},4k,8"
    count=$((count + 1))
done

echo "TOTAL_TESTS=${count}"

if [[ ${count} -eq 0 ]]; then
    echo "[ Warning ] No benchmark tests generated. No media files found in collateral/media/." >&2
    echo "[ Warning ] Run 'make media' from the repository root to download and encode media files." >&2
fi
