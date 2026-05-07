# Manual Setup

If you prefer step-by-step control over the automated `make` workflow, follow these instructions. All relative directory navigation assumes starting at the repository root.

## Step 1. Prerequisites

```bash
cd ./setup/
./install_prerequisites.sh
# Optional: --reinstall-gpu-driver=yes and/or --reinstall-npu-driver=yes
```

## Step 2. Vision Models

```bash
cd ./tools/model-conversion/
./convert_models.sh
# Optional: -i "$HOME/datasets/imagenet-packages" for ImageNet accuracy validation
```

## Step 3. GenAI Models

```bash
cd ./tools/genai-downloader/
./download_models.sh
./download_minicpm.sh
./download_gemma3.sh
./download_images.sh # image files required for VLM inference
```

## Step 4. Media

```bash
cd ./tools/media-downloader/
./download_and_encode.sh
```

## Step 5. Run Benchmarks

### Edge AI Pipelines

```bash
cd ./workloads/edge-ai-pipelines/
./benchmark_edge_pipelines.sh \
	-p <light|medium|heavy> \
	-n <num_streams> \
	-b <batch_size> \
	-d <DetectDevice> \
	-c <ClassifyDevice> \
	-i <duration_sec> \
	-t <scheduling_core_type>

# Example
./benchmark_edge_pipelines.sh -p light -n 8 -b 8 -d GPU -c NPU -i 120 -t ecore
```

### Vision Benchmarks

```bash
cd ./workloads/vision-benchmarks/
make setup    # First time only: create venv + install OpenVINO
./benchmark_vision.sh -m <model_path> -d <device> -i <duration_sec> -t <scheduling_core_type>

# Example
./benchmark_vision.sh -m detection/yolov11n_640x640/INT8/yolo11n.xml -d GPU -i 120 -t ecore
```

### Media Benchmarks

```bash
cd ./workloads/media-benchmarks/
./benchmark_media.sh -m <media_file> -n <num_streams> -i <duration_sec> -t <scheduling_core_type>

# Example
./benchmark_media.sh -m bears_1080.h265 -n 8 -i 120 -t ecore
```

### GenAI Benchmarks

```bash
cd ./workloads/genai-benchmarks/
make setup       # First time only: create venv, install deps, clone openvino.genai
make collateral  # First time only: download and convert models

# LLM Benchmark
./benchmark_genai_llm.sh -m <model_name> -d <device> -p <precision> -i <duration_sec> -t <scheduling_core_type>

# Example
./benchmark_genai_llm.sh -m llama-3.2-3b-instruct -d GPU -p INT4_SYM_CW -i 60 -t ecore

# VLM Benchmark
./benchmark_genai_vlm.sh -m <model_name> -d <device> -p <precision> -i <duration_sec> -t <scheduling_core_type>

# Example
./benchmark_genai_vlm.sh -m phi-4-multimodal -d GPU -p INT4_SYM_CW -i 60 -t ecore
```

## Step 6. Display Results

```bash
# Generate and view dashboard (from repository root)
python3 ./tools/html/generate_report.py
cd ./tools/html && python3 -m http.server 8000  # Access at http://localhost:8000
```

Or use the Makefile from the repository root:

```bash
make report && make serve
```
