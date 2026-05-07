# Edge Workloads and Benchmarks

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Edge Workloads and Benchmarks is a benchmarking suite for validating media and edge AI video analytics performance on Intel hardware. 

### Target Workloads
| Workload Name | Framework | Description | Key Metrics |
|---------------|-----------|-------------|-------------|
| Edge AI Pipelines | [DL Streamer](https://github.com/open-edge-platform/dlstreamer/) | End-to-end video analytics using [GStreamer](https://gstreamer.freedesktop.org) and Deep Learning Streamer (DL Streamer) | Pipeline Throughput, Stream Density at 30fps
| Vision Benchmarks | [OpenVINO](https://docs.openvino.ai/) | AI model inference benchmarks using [OpenVINO](https://docs.openvino.ai/) benchmark app | Inference Latency, Inference Throughput
| Media Benchmarks | [GStreamer](https://gstreamer.freedesktop.org) | Hardware-Accelerated video decode benchmarks with VA-API | Decode Throughput, Stream Density at 30fps
| GenAI Benchmarks | [OpenVINO GenAI](https://github.com/openvinotoolkit/openvino.genai) | Generative AI inference benchmarks for LLM and VLM models using [OpenVINO GenAI](https://github.com/openvinotoolkit/openvino.genai) | First Token Latency, Second Token Throughput

## Prerequisites

### System Requirements
Repository validated on Ubuntu OS version 24.04.4 LTS with kernel version 6.16
- GPU with video acceleration API (VA-API) media support
- 16+ GB Memory
- 128 GB storage space (16 GB without GenAI models)
- **Optional:** integrated NPU

**Note:** GenAI models require more storage space for the original HuggingFace model, then INT8 and INT4 quantizations. 128 GB of storage is recommended for the initial setup process. Once the model is quantized, you can delete the original Huggingface model in `~/.cache/huggingface/hub/` and the Python3 virtual environments for model conversion in `tools/genai-downloader/`.
### Software Requirements
- Docker software version 20.10 and above ([installation guide](https://docs.docker.com/engine/install/ubuntu/))
- Python programming language version 3.10 and above with virtual environment (venv) support
- Network connectivity for model or media download

## Get Started

The top-level Makefile handles setup, collateral downloads, and reporting. Use `make help` to display available commands:

### Usage
```Makefile
Setup:
  make prereqs                Install dependencies and compute drivers
  make collateral             Download AI models and media files
                              Add 'INCLUDE_GENAI=True' to download GenAI models
  make check                  Optional: Verify everything is ready for benchmarking

Benchmarks:
  Run 'make benchmarks' from inside a workload directory:
    Vision Inference:         workloads/vision-benchmarks
    Media Decode:             workloads/media-benchmarks
    Edge AI Pipelines:        workloads/edge-ai-pipelines
    GenAI Inference:          workloads/genai-benchmarks

Results:
  make status                 Optional: Show benchmark completion status
  make report                 Generate HTML dashboard
  make serve                  Start local dashboard server

Cleanup:
  sudo make clean-results     Optional: Remove benchmark results
  sudo make clean-all         Optional: Remove all generated content
```
**Note:** GPU and NPU compute drivers are installed by **default**. In order to skip driver installation, set `INCLUDE_GPU=False` or `INCLUDE_NPU=False` respectively.

### Quick Start
```bash
make prereqs                                      # Install dependencies
make collateral INCLUDE_GENAI=True                # Download all models and media
cd workloads/edge-ai-pipelines && make benchmarks # Run benchmarks
cd ../../                                         # Return to repository root
make report && make serve                         # View results at http://127.0.0.1:8000
```
Once completed, navigate to the other workload directories and run `make benchmarks` for full workload coverage and `make report` to update the dashboard.
### Further Reading

- [Pipeline Architecture](docs/PIPELINE.md) — Edge AI pipeline configurations and device modes
- [Usage Guide](docs/USAGE.md) — Makefile variables, script parameters, benchmark options, and output format
- [Manual Setup](docs/MANUAL.md) — Step-by-step instructions for running each script directly

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

## License Notice

The **Edge Workload and Benchmarks** project is primarily licensed under the [APACHE 2.0](./LICENSE) license.
However, certain components are derived from code covered by the **GNU Affero General Public License v3.0 (AGPL-3.0)**.
 
- **Apache 2.0** applies to all original work in this repository unless otherwise noted.
- **AGPL-3.0** applies to the following directories/components:
  - `tools/model-conversion/scripts/coco.yaml`

These components include a copy of the AGPL license in their respective folders.
