# Media Benchmarks

Video decode benchmarks using [VA-API](https://github.com/intel/libva) via [GStreamer](https://gstreamer.freedesktop.org). 

#### Key Metrics
 - Decode Throughput (FPS)
 - Estimated Stream Density @ 30fps per stream (#)
 - Package Power (W)
 - Power Efficiency (FPS per W)

Results are written to `collateral/results/media-benchmarks/GPU/`:

## Usage
```Makefile
Media Benchmarks
================

Checks:
  make collateral             Download media files
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

Cleanup:
  sudo make clean             Remove all results
```

## Quick Start

From the repository root:

```bash
# Setup virtual environment + download/convert all models and media
make collateral INCLUDE_GENAI=True

# Alternate: Download/convert only media
make collateral INCLUDE_VISION=False

# Run all Media workloads
cd workloads/media-benchmarks
make benchmarks
```

Or from this workload directory:

```bash
# Download/convert media and run benchmarks
make collateral
make benchmarks
```

## Running Individual Benchmarks

```bash
./benchmark_media.sh -m <media_file> [-n <num_streams>] [-i <duration>] [-t <cores>]
```

**Parameters:**
- `-m` Path to media file (e.g., `bears.h265`)
- `-n` Number of parallel decode streams (default: 1)
- `-i` Duration in seconds (default: 120)
- `-t` Core pinning (optional)

**Examples:**
```bash
./benchmark_media.sh -m bears_1080.h265 -n 8 -i 120
./benchmark_media.sh -m bears_4k.h264 -n 1 -i 60 -t ecore
```