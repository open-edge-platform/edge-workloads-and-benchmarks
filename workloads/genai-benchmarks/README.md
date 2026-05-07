# GenAI Benchmarks

Generative AI inference benchmarks for LLM and VLM models using [OpenVINO GenAI](https://github.com/openvinotoolkit/openvino.genai). 

#### Key Metrics
 - First-token Latency (ms)
 - Second-token Throughput (tok/s)
 - Package Power (W)
 - Power Efficiency (tok/s per W)


Results are written to `collateral/results/genai-benchmarks/<Device>/`:

## Usage
```Makefile
GenAI Benchmarks
================

Collateral:
  make collateral             Download GenAI models
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
  sudo make clean-venv        Optional: Remove virtual environment and cloned repos
```
## Quick Start

From the repository root:

```bash
# Setup virtual environment + download/convert all models and media
make collateral INCLUDE_GENAI=True

# Alternate: Setup virtual environment + download/convert only GenAI models
make collateral INCLUDE_VISION=False INCLUDE_MEDIA=False INCLUDE_GENAI=True

# Run all GenAI workloads
cd workloads/genai-benchmarks
make benchmarks
```

Or from this workload directory:

```bash
# Setup virtual environment, download/convert GenAI models, and run benchmarks
make collateral
make benchmarks
```


## Running Individual Benchmarks

### LLM

```bash
./benchmark_genai_llm.sh -m <model_name> -d <device> -p <precision> [-i <duration>] [-t <cores>]
```

**Parameters:**
- `-m` Model short name (e.g., `llama-3.2-3b-instruct`)
- `-d` Device: `GPU`, `NPU`, or `CPU`
- `-p` Precision: `INT8_ASYM` or `INT4_SYM_CW`
- `-i` Duration in seconds (default: 60)
- `-t` Core pinning (optional)

**Examples:**
```bash
./benchmark_genai_llm.sh -m llama-3.2-3b-instruct -d GPU -p INT4_SYM_CW -i 60
./benchmark_genai_llm.sh -m deepseek-qwen-1.5b -d NPU -p INT4_SYM_CW -i 60 -t ecore
```

### VLM

```bash
./benchmark_genai_vlm.sh -m <model_name> -d <device> -p <precision> [-i <duration>] [-t <cores>] [-g <image>]
```

**Additional parameters:**
- `-g` Path to input image (default: `collateral/media/images/coco_448x448.jpg`)

**Examples:**
```bash
./benchmark_genai_vlm.sh -m minicpm-v-2.6 -d GPU -p INT4_SYM_CW -i 60
./benchmark_genai_vlm.sh -m gemma-3-4b-it -d GPU -p INT8_ASYM -i 60 -g /path/to/image_SIZExSIZE.jpg
```