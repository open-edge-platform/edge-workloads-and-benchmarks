# Media Downloader

Downloads and prepares video files for Edge Workloads and Benchmarks.

#### Required for the following workloads:
 - Edge AI Pipelines
 - Media Benchmarks

## Usage

```Makefile
Media Conversion
================

Checks:
  make verify                 Optional: Check that all required media files are present

Conversion:
  make download               Download source videos and transcode to H.264/H.265

Cleanup:
  make clean                  Optional: Remove transcoded media from collateral
```
## Requirements

- Docker software with Deep Learning Streamer (DL Streamer) container (`intel/dlstreamer:2026.1.0-20260505-weekly-ubuntu24`).
- GPU with VA-API support (integrated or discrete GPU).


## Overview

1. Downloads two 4K test videos from Pexels platform.
   - `apple.mp4` - Single object per frame
   - `bears.mp4` - Two objects per frame

2. Transcodes to multiple formats using video acceleration API (VA-API) hardware acceleration via Docker software:
   - H.265 (HEVC) at 1080p30 and 4K
   - H.264 (AVC) at 1080p30 and 4K

3. Loops each video 100 times for long-duration benchmarks.

4. Saves looped videos to `collateral/media/` at the repository root.

## Media Sources
| Video Name | Description | Link |
|------------|-------------|------|
| Apple | One apple, rotating in the center of the frame | [Download Link (Pexels)](https://videos.pexels.com/video-files/6891009/6891009-uhd_3840_2160_30fps.mp4) |
| Bears | Two bears, sitting in the forest | [Download Link (Pexels)](https://videos.pexels.com/video-files/18856748/18856748-uhd_3840_2160_60fps.mp4)