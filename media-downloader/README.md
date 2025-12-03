# Media Downloader

Downloads and prepares video files for Edge Workloads and Benchmarks pipelines.

## Usage

```bash
./download_and_encode.sh
```

## Overview

1. Downloads two 4K test videos from Pexels
   - `apple.mp4` - Single object per frame
   - `bears.mp4` - Two objects per frame

2. Transcodes to H.265 format (1080p30, 2Mbps, no B-frames)
   - Uses VA-API hardware acceleration via Docker
   - Requires `/dev/dri` GPU/VA-API device access

3. Loops each video 100x for long-duration benchmarks

4. Saves looped videos to pipeline directories:
   - `pipelines/light/video/bears.h265`
   - `pipelines/medium/video/apple.h265`
   - `pipelines/heavy/video/bears.h265`

## Requirements

- Docker with DLStreamer container (`intel/dlstreamer:latest`)
- GPU with VA-API support (integrated/discrete GPU)