# Vision Benchmarks

Vision AI inference benchmarks using [OpenVINO](https://docs.openvino.ai/).

#### Key Metrics
 - Model Inference Latency (ms)
 - Model Inference Throughput (FPS)
 - Package Power (W)
 - Power Efficiency (FPS per W)

Results are written to `collateral/results/vision-benchmarks/<Device>/`:

## Usage
```Makefile
Vision Benchmarks
=================

Checks:
  make collateral             Download AI models and media files
  make check                  Verify all required collateral is present

Benchmarks:
  make benchmarks             Sweep all benchmark configurations

  Options:
    DRY_RUN                   Lists all benchmark configurations without running (default: False)
    RESUME                    Skip tests that already have results (default: False)
    DURATION                  Set the duration for each benchmark test (default: 60 seconds)
    POWER                     Enable/Disable power/efficiency metrics (default: True, requires sudo)
    CORES                     Pin the cores for scheduling workload.  (default: all cores)
                              Accepts the following: pcore, ecore, and min-max range (example: 0-11)
                              Performance and efficiency may vary depending on core pinning

Cleanup:
  sudo make clean             Optional: Remove all results
  sudo make clean-venv        Optional: Remove virtual environment
```
## Quick Start

From the repository root:

```bash
# Setup virtual environment + download/convert all models and media
make collateral INCLUDE_GENAI=True

# Alternate: Setup virtual environment + download/convert only vision models
make collateral INCLUDE_MEDIA=False

# Run all Vision workloads
cd workloads/vision-benchmarks
make benchmarks
```

Or from this workload directory:

```bash
# Setup virtual environment, download/convert vision models, and run benchmarks
make collateral
make benchmarks
```

## Running Individual Benchmarks

```bash
./benchmark_vision.sh -m <model_path> -d <device> [-i <duration>] [-e <mode>] [-b <batch>] [-t <cores>] [--concurrent <device2>]
```

**Parameters:**
- `-m` Path to model `.xml` file
- `-d` Inference device: `GPU`, `NPU`, or `CPU`
- `-i` Duration in seconds (default: 120)
- `-e` Inference mode: `tput` (throughput) or `latency` (default: tput)
- `-b` Batch size (default: 1)
- `-t` Core pinning (optional)
- `--concurrent` Run a second inference device concurrently (e.g., `--concurrent NPU`)

**Examples:**
```bash
./benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -i 60
./benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d NPU -e latency -b 1 
./benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -e tput -b 8 --concurrent NPU
```