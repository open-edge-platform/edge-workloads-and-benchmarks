# Edge AI Pipelines

Media + AI benchmarks using Deep Learning Streamer ([DL Streamer](https://github.com/open-edge-platform/dlstreamer/)).

#### Key Metrics
 - Pipeline Throughput (FPS)
 - Estimated Stream Density @ 30fps per stream (#)
 - Package Power (W)
 - Power Efficiency (FPS per W)

Results are written to `collateral/results/edge-ai-pipelines/<Device>/`.

## Usage
```Makefile
Edge AI Pipelines
=================

Checks:
  make collateral             Download AI models and media files
  make check                  Verify all required collateral is present

Benchmarks:
  make benchmarks             Sweep all benchmark configurations

  Options:
    DRY_RUN                   Lists all benchmark configurations without running (default: False)
    RESUME                    Skip tests that already have results (default: False)
    DURATION                  Set the duration for each benchmark test (default: 120 seconds)
    POWER                     Enable/Disable power/efficiency metrics (default: True, requires sudo)
    CORES                     Pin the cores for scheduling workload.  (default: all cores)
                              Accepts the following: pcore, ecore, and min-max range (example: 0-11)
                              Performance and efficiency may vary depending on core pinning

Display:
  make display                Optional: Visualized pipeline demo (requires display access)

  Options:
    CONFIG                    Pipeline configuration (light, medium, or heavy)
    DETECT                    Inference Device for Detection (CPU|GPU|NPU)
    CLASSIFY                  Inference Device for Classification (CPU|GPU|NPU)

Cleanup:
  sudo make clean             Optional: Remove all results
```

## Quick Start

From the repository root:

```bash
# Setup virtual environment + download/convert all models and media
make collateral INCLUDE_GENAI=True

# Alternate: Download/convert only vision models and media
make collateral

# Run all Edge AI pipelines
cd workloads/edge-ai-pipelines
make benchmarks
```

Or from this workload directory:

```bash
# Download/convert media + vision models, and run benchmarks
make collateral
make benchmarks
```

## Running Individual Benchmarks

```bash
./benchmark_edge_pipelines.sh -p <config> -d <detect_device> -c <classify_device> \
                              [-n <streams>] [-b <batch>] [-i <seconds>] [-t <cores>] [--concurrent]
```

**Parameters:**
- `-p` Pipeline configuration: `light`, `medium`, or `heavy`
- `-d` Inference device for detection (`CPU`, `GPU`, `NPU`)
- `-c` Inference device for classification (`CPU`, `GPU`, `NPU`)
- `-n` Number of parallel decode streams (default: 1)
- `-b` Batch size for inference (default: 1)
- `-i` Duration in seconds (default: 120)
- `-t` Core pinning: `pcore`, `ecore`, `lpecore`, `nopin`, or a core list (e.g., `0-11`)
- `--concurrent` Split streams across detect/classify devices

**Examples:**
```bash
# 8 streams, GPU detection + NPU classification, 120s
./benchmark_edge_pipelines.sh -p light -n 8 -b 8 -d GPU -c NPU -i 120

# 4 streams, heavy pipeline, E-core pinning
./benchmark_edge_pipelines.sh -p heavy -n 4 -b 1 -d GPU -c NPU -i 120 -t ecore

# Concurrent mode: split streams across GPU and NPU
./benchmark_edge_pipelines.sh -p medium -n 8 -d GPU -c NPU -i 120 --concurrent
```

## Display Demo

Run the following commands to allow X server connection in the Docker container, so that the display pipeline sample can access the host's display:
```bash
xhost local:root
setfacl -m user:1000:r ~/.Xauthority
```

Run a single visualized pipeline with on-screen bounding box overlay (requires X11 display):
```bash
./display_pipeline.sh -p <config> -d <detect_device> -c <classify_device> [-i <seconds>] [-t <cores>]
```

**Examples:**
```bash
./display_pipeline.sh -p light -d GPU -c NPU -i 120
./display_pipeline.sh -p heavy -d GPU -c NPU -i 60 -t pcore
```