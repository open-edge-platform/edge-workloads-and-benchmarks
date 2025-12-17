# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

########################################
# Edge Workloads and Benchmarks Pipeline
########################################

.DEFAULT_GOAL := help

# Model accuracy and compute driver setup variables
IMAGENET_ROOT ?=
INCLUDE_GPU ?= False
INCLUDE_NPU ?= False

# Workload variables
CONFIG ?= light
DETECT ?= CPU
CLASSIFY ?= CPU
DURATION ?= 120
CORES ?=

# HTML generation and serving variables
PORT ?= 8000

GPU_FLAG := $(if $(filter True true TRUE yes YES,$(INCLUDE_GPU)),--reinstall-gpu-driver=yes,)
NPU_FLAG := $(if $(filter True true TRUE yes YES,$(INCLUDE_NPU)),--reinstall-npu-driver=yes,)

# Usage
.PHONY: help
help:
	@echo "Edge Workloads and Benchmarks Pipeline Make Targets"
	@echo "--------------------------------------------------"
	@echo "# System and Workload Setup"
	@echo "make prereqs          - Install system dependencies (INCLUDE_GPU=True INCLUDE_NPU=True for compute drivers)"
	@echo "make models           - Download and convert models (IMAGENET_ROOT=/path to use ImageNet for optional Resnet and Mobilenet accuracy check. Refer to model-conversion/README.md)"
	@echo "make media            - Download and transcode video files"
	@echo ""
	@echo "# Run Benchmarks"
	@echo "make benchmarks       - Sweeps through all benchmark configurations. (optional: CORES={core-type} DURATION={seconds})"
	@echo "sudo make benchmarks  - Recommended: Adds power and efficiency metrics to report. Requires root permissions to read power sensors"
	@echo ""
	@echo "# Generate results"
	@echo "make html-report      - Generate HTML dashboard from benchmark results. Requires serve-report to view locally."
	@echo "make serve-report     - Host HTML dashboard locally (default: PORT=8000)"
	@echo ""
	@echo "#Optional: display pipeline demo (requires display access permissions)"
	@echo "make display          - Visualized pipeline demo (CONFIG={light,medium,heavy} DETECT={CPU,GPU,NPU} CLASSIFY={CPU,GPU,NPU} DURATION={seconds} CORES={core-type})"
	@echo ""
	@echo "# Cleanup"
	@echo "make clean            - Remove all results"
	@echo "make clean-all        - Remove all generated collateral (models, media, results, venv)"
	@echo ""
	@echo "# Core Pinning (CORES variable):"
	@echo "  CORES='pcore'       - P-cores only for workload scheduling"
	@echo "  CORES='ecore'       - E-cores only for workload scheduling (Recommended)"
	@echo "  CORES='lpecore'     - Lowpower E-cores only for workload scheduling"
	@echo "  CORES='nopin'       - No core pinning (default)"
	@echo ""
	@echo "Example: make prereqs INCLUDE_GPU=True INCLUDE_NPU=True"
	@echo "Example: make benchmarks CORES=ecore DURATION=120"
	@echo "Example: make display CONFIG=light DETECT=GPU CLASSIFY=NPU CORES='ecore'"
	@echo "Example: make serve-report PORT=8000"

.PHONY: prereqs
prereqs:
	@echo "[ Info ] Running prerequisite setup (INCLUDE_GPU=$(INCLUDE_GPU) INCLUDE_NPU=$(INCLUDE_NPU))"
	@if [ -x setup/install_prerequisites.sh ]; then \
		echo "[ Info ] Executing install_prerequisites.sh $(GPU_FLAG) $(NPU_FLAG)"; \
		cd setup && ./install_prerequisites.sh $(GPU_FLAG) $(NPU_FLAG); \
	else \
		echo "[ Error ] setup/install_prerequisites.sh not found or not executable"; \
		exit 1; \
	fi

.PHONY: models
models: 
	@echo "[ Info ] Downloading and quantizing models"
	@if [ -n "$(IMAGENET_ROOT)" ]; then \
		cd model-conversion && ./convert_models.sh -i "$(IMAGENET_ROOT)"; \
	else \
		cd model-conversion && ./convert_models.sh; \
	fi

.PHONY: media
media: 
	@echo "[ Info ] Downloading and transcoding media"
	cd media-downloader && ./download_and_encode.sh

.PHONY: display
display:
	@if ! bash -c ". ./utils/helper_functions.sh; validate_assets $(CONFIG) \"$$(realpath pipelines)\"" >/dev/null 2>&1; then \
		echo ""; \
		echo "[ Error ] Missing required pipeline assets for '$(CONFIG)' configuration."; \
		echo ""; \
		echo "Please run the following commands to generate the required assets:"; \
		echo "  1. make models    # Download and convert AI models"; \
		echo "  2. make media     # Download and transcode video files"; \
		echo ""; \
		exit 1; \
	fi
	@echo "[ Info ] Launching display pipeline: config=$(CONFIG) detect=$(DETECT) classify=$(CLASSIFY) duration=$(DURATION) cores=$(CORES)"
	./display_pipeline.sh -p $(CONFIG) -d $(DETECT) -c $(CLASSIFY) -i $(DURATION) $(if $(CORES),-t $(CORES),)

# Benchmark sweep using dynamic coverage matrix generation
# 8 Streams ran during workload runtime. Theoretical stream density calculated as Total Throughput / Target FPS.

.PHONY: benchmarks
benchmarks: clean
	@if ! bash -c ". ./utils/helper_functions.sh; validate_assets light \"$$(realpath pipelines)\"" >/dev/null 2>&1; then \
		echo ""; \
		echo "[ Error ] Missing required pipeline assets for benchmarking."; \
		echo ""; \
		echo "Please run the following commands to generate the required assets:"; \
		echo "  1. make models    # Download and convert AI models"; \
		echo "  2. make media     # Download and transcode video files"; \
		echo ""; \
		exit 1; \
	fi
	@echo "[ Info ] Generating benchmark coverage matrix..."
	@coverage_output=$$(./utils/generate_benchmark_coverage.sh); \
	total_tests=$$(echo "$$coverage_output" | grep "^TOTAL_TESTS=" | cut -d= -f2); \
	echo "[ Info ] Starting benchmark sweep ($$total_tests tests)$(if $(CORES), with core pinning: $(CORES),)"; \
	echo ""; \
	current=0; \
	cores_opt="$(if $(CORES),-t $(CORES),)"; \
	echo "$$coverage_output" | grep -v "^#" | grep -v "^TOTAL_TESTS=" | while IFS=, read -r cfg det cls batch concurrent; do \
		current=$$((current + 1)); \
		mode_desc="$$( [ -n "$$concurrent" ] && echo " (concurrent pipelines for each device)" || echo "" )"; \
		echo "[ Info ] [$$current/$$total_tests] cfg=$$cfg det=$$det cls=$$cls batch=$$batch streams=8 duration=$(DURATION)$$mode_desc"; \
		./benchmark_edge_pipelines.sh -p $$cfg -n 8 -b $$batch -d $$det -c $$cls -i $(DURATION) $$concurrent $$cores_opt || { \
			echo "[ Error ] Benchmark run failed (cfg=$$cfg det=$$det cls=$$cls batch=$$batch $$concurrent)"; \
			exit 1; \
		echo "[ Info ] Sleeping for 10 seconds to prevent thermal throttling."; \
		sleep 10; \
		}; \
	done; \
	echo ""; \
	echo "[ Info ] Completed $$total_tests benchmark runs."

.PHONY: html-report
html-report:
	@bash html/generate_system_info.sh
	@echo "[ Info ] Generating HTML dashboard from CSV results."
	@python3 html/generate_report.py

.PHONY: serve-report
serve-report:
	@if [ ! -f html/index.html ]; then \
		echo "[ Error ] html/index.html not found. Run 'make html-report' first."; \
		exit 1; \
	fi
	@echo "[ Info ] Starting HTTP server for HTML dashboard"
	@echo "[ Info ] Dashboard available at: http://localhost:$(PORT)"
	@echo "[ Info ] Press Ctrl+C to stop the server"
	@cd html && python3 -m http.server $(PORT) --bind 127.0.0.1

.PHONY: clean
clean:
	@echo "[ Info ] Cleaning results directory (logs & CSV)."
	@find results -type f \( -name "*.log" -o -name "*.csv" \) -delete 2>/dev/null || true

.PHONY: clean-all
clean-all: clean
	@echo "[ Info ] Removing all generated media and model collateral."
	@rm -rf media-downloader/media
	@rm -rf model-conversion/source-models model-conversion/datasets model-conversion/models model-conversion/venv
	@rm -rf pipelines/
	@echo "[ Info ] All generated collateral cleared."
