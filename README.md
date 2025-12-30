# Edge Workloads and Benchmarks Pipelines

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Edge Workloads and Benchmarks are performance-optimized pipelines that utilizes the [GStreamer multimedia framework](https://gstreamer.freedesktop.org) and the [Deep Learning Streamer (DL Streamer)](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/libraries/dl-streamer) for validating media and edge AI video analytics. The pipelines measure end-to-end throughput in frames per second (fps), pipeline stream density in fps, package power in watts, and workload efficiency in fps per package watt.

### Pipeline Architecture

HEVC 1080p Video Decode (GPU Hardware-Accelerated) → Object Detection (GPU or NPU) → Object Tracking → 1-2x Object Classification (GPU or NPU)

## Pipeline Configurations
| Config | Video | Detection | Classification |
|------|-------|-----------|----------------|
| light | bears.h265 (2 obj/frame) | YOLOv11n (640x640) INT8 | ResNet‑50 (224x224) INT8 |
| medium | apple.h265 (1 obj/frame) | YOLOv5m (640x640) INT8 | ResNet‑50 + MobileNet‑V2 (224x224) INT8 |
| heavy | bears.h265 (2 obj/frame) | YOLOv11m (640x640) INT8 | ResNet‑50 + MobileNet‑V2 (224x224) INT8 |

Pipeline configurations include single-device pipelines (GPU or NPU only), pipelines with multiple devices (GPU Detect and NPU Classify), and multiple single-device pipelines running concurrently in separate processes (GPU only and NPU only, concurrently).

## Prerequisites

### System Requirements

A GPU with video acceleration API (VA-API) media support that:
- Is validated on Ubuntu OS version 24.04.3 LTS with kernel version 6.16 and above
- Has Docker software installed and the user added in the docker group
- Has Integrated GPU
- Has NPU (optional)


### Software Requirements

- Docker software version 20.10 and above ([installation guide](https://docs.docker.com/engine/install/ubuntu/))
- Python programming language version 3.8 and above with virtual environment (venv) support
- Network connectivity for model or media download

### Storage Space Requirements

Breakdown of space required:
- Models: 230 MB
- COCO dataset: 950 MB
- CIFAR-100 dataset: 162 MB
- Videos: 1.9 GB
- Virtual Environment: 7.7 GB

Total space required: 10.9 GB

Optional ImageNet Dataset Download: 6.5GB. You will need to download this manually. See [model-conversion](model-conversion/README.md).

### Display Pipeline

Run the following commands to allow X server connection in the Docker container, so that the display pipeline sample can access the host's display:

```bash
xhost local:root
setfacl -m user:1000:r ~/.Xauthority
```

## Get Started

The Makefile automates the entire workflow. Use `make help` to display the following:

```bash
# Three-step setup
make prereqs          # Install dependencies (params: INCLUDE_GPU=True INCLUDE_NPU=True).
make models           # Download and convert models (params: IMAGENET_ROOT, optional)
make media            # Download and transcode video files

# Run benchmarks
make benchmarks       # Run all pipeline configurations (params: CORES={cores-to-pin-workload} DURATION={seconds})
sudo make benchmarks  # Recommended: Adds power and efficiency metrics to report. Requires root permissions to read power sensors

# Generate results
make html-report      # Generate HTML dashboard from benchmark results. Requires serve-report to view locally.
make serve-report     # Host dashboard locally (params: PORT, default host: http://localhost:8000)

# Optional: display pipeline demo (requires display access permissions)
make display          # Visualized pipeline demo (params: CONFIG={light,medium,heavy} DETECT={CPU,GPU,NPU} CLASSIFY={CPU,GPU,NPU} DURATION={seconds})

# Cleanup
make clean            # Remove all results
make clean-all        # Remove all generated collateral (models, media, results, and venv)
```

### Examples

- Prereqs: `make prereqs INCLUDE_GPU=True INCLUDE_NPU=True`
- Display: `make display CONFIG=light DETECT=GPU CLASSIFY=NPU DURATION=60`
- Benchmarks: `sudo make benchmarks CORES=ecore DURATION=60`

### Makefile Variables

- `IMAGENET_ROOT` - Path to pre-downloaded the ImageNet dataset for accuracy validation on ResNet architecture and MobileNet networks (see [model-conversion](model-conversion/README.md))
- `INCLUDE_GPU` - Install GPU drivers during setup
- `INCLUDE_NPU` - Install NPU drivers during setup (requires reboot)
- `DURATION` - Duration to run pipeline in seconds
- `CONFIG=light|medium|heavy` - Pipeline configuration, tiered by compute complexity
- `DETECT/CLASSIFY=CPU|GPU|NPU` - Inference device assignment
- `CORES=pcore|ecore|lpecore` - CPU core pinning based on core type
- `PORT` - HTTP server port for dashboard (default: 8000)

### Manual Setup (Alternative)

If you prefer step-by-step control:

Step 1. Prerequisites:

```bash
cd setup/
./install_prerequisites.sh
# Optional: --reinstall-gpu-driver=yes and/or --reinstall-npu-driver=yes
```

Step 2. Models:

```bash
cd ../model-conversion/
./convert_models.sh
# Optional: -i "$HOME/datasets/imagenet-packages" for ImageNet quantization
```

Step 3. Media:

```bash
cd ../media-downloader/
./download_and_encode.sh
```

Step 4. Run benchmark:

```bash
cd ..
./benchmark_edge_pipelines.sh \
	-p <light|medium|heavy> \
	-n <num_streams> \
	-b <batch_size> \
	-d <DetectDevice> \
	-c <ClassifyDevice> \
	-i <duration_sec> \
	-t <scheduling_core_type>

# Example command line
./benchmark_edge_pipelines.sh -p light -n 8 -b 8 -d GPU -c NPU -i 120 -t ecore
```
**Parameters:**
* `-p` Pipeline config: `light` | `medium` | `heavy` (required)
* `-n` Number of parallel streams (default: 1)
* `-b` Batch size (default: 1)
* `-d` Detection device: `CPU` | `GPU` | `GPU.<idx>` | `NPU` (default: CPU)
* `-c` Classification device: `CPU` | `GPU` | `GPU.<idx>` | `NPU` (default: CPU)
* `-i` Duration in seconds (default: 120)
* `-t` CPU core type for pinning, e.g., `"ecore"` (optional)
* `--concurrent` Enable concurrent GPU or NPU execution mode (optional)

**Note:** Intel recommends the GPU or NPU for AI inference workloads.

Step 5. Display Results:

```bash
# Generate and view dashboard
python3 html/generate_report.py
cd html && python3 -m http.server 8000  # Access at http://localhost:8000
```

### Output

Results are saved to the `results/` folder, organized by execution mode:

* `*.log` – Full GStreamer pipeline output (stdout or stderr)
* `*.csv` – Performance metrics (FPS, stream density, and configuration)

## Get Help or Contribute

If you want to participate in the GitHub community for Edge Workloads and Benchmarks, you can
contribute code, propose a design, download and try out a release, open an issue,
benchmark application performance, and participate in
[Discussions](https://github.com/open-edge-platform/edge-workloads-and-benchmarks/discussions).

To learn more, check out the following resources:

- [Open an issue](https://github.com/open-edge-platform/edge-workloads-and-benchmarks/issues)
- [Submit a pull request](https://github.com/open-edge-platform/edge-workloads-and-benchmarks/pulls)
- [Read the Contribution Guide](https://github.com/open-edge-platform/edge-microvisor-toolkit/blob/3.0/docs/developer-guide/emt-contribution.md)
- [Report a security vulnerability](https://github.com/open-edge-platform/edge-workloads-and-benchmarks/blob/main/SECURITY.md)

Before submitting a new report, check the existing issues to see if a similar one has been filed.

## Notices

The **Edge Workload and Benchmarks** project is licensed under the [APACHE 2.0](./LICENSE) license.
