# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

########################################
# Edge Workloads and Benchmarks
########################################

.DEFAULT_GOAL := help

# Setup variables
INCLUDE_GPU ?= True
INCLUDE_NPU ?= True

# Collateral download flags
INCLUDE_VISION ?= True
INCLUDE_MEDIA ?= True
INCLUDE_GENAI ?= False

# HTML report variables
PORT ?= 8000
HOSTIP ?= 127.0.0.1
REPORT_NAME ?= report

# Usage
.PHONY: help
help:
	@echo ""
	@echo "Edge Workloads and Benchmarks"
	@echo "============================="
	@echo "See 'Quick Start' below for step-by-step setup instructions."
	@echo ""
	@echo "Setup:"
	@echo "  make prereqs                Install dependencies and compute drivers"
	@echo "  make collateral             Download AI models and media files"
	@echo "                              Add 'INCLUDE_GENAI=True' to download GenAI models"
	@echo "  make check                  Optional: Verify everything is ready for benchmarking"
	@echo ""
	@echo "Benchmarks:"
	@echo "  Run 'make benchmarks' from inside a workload directory:"
	@echo "    Vision Inference:         workloads/vision-benchmarks"
	@echo "    Media Decode:             workloads/media-benchmarks"
	@echo "    Edge AI Pipelines:        workloads/edge-ai-pipelines"
	@echo "    GenAI Inference:          workloads/genai-benchmarks"
	@echo ""
	@echo "    Note: Run 'make help' inside any workload directory before"
	@echo "    running 'make benchmarks' for additional command options"
	@echo ""
	@echo "Results:"
	@echo "  make status                 Optional: Show benchmark completion status"
	@echo "  make report                 Generate HTML dashboard"
	@echo "  make serve                  Start local dashboard server"
	@echo ""
	@echo "Cleanup:"
	@echo "  sudo make clean-results     Optional: Remove benchmark results"
	@echo "  sudo make clean-all         Optional: Remove all generated content"
	@echo ""
	@echo "============================="
	@echo "Quick Start:"
	@echo "  1. make prereqs"
	@echo "  2. make collateral INCLUDE_GENAI=True"
	@echo "  3. cd workloads/edge-ai-pipelines && make benchmarks"
	@echo "  4. cd ../../"
	@echo "  5. make report && make serve"
	@echo "  6. Open http://127.0.0.1:8000"
	@echo ""

# Prerequisites — delegates to setup/Makefile
.PHONY: prereqs
prereqs:
	@$(MAKE) --no-print-directory -C setup prereqs INCLUDE_GPU=$(INCLUDE_GPU) INCLUDE_NPU=$(INCLUDE_NPU)

# Collateral download — enabled by default except GenAI
.PHONY: collateral
collateral:
	@enabled=0; \
	if echo "$(INCLUDE_GENAI)" | grep -qiE '^(true|yes)$$'; then \
		bash utils/check_hf_token.sh || exit 1; \
	fi; \
	if echo "$(INCLUDE_VISION)" | grep -qiE '^(true|yes)$$'; then \
		enabled=$$((enabled + 1)); \
		echo ""; \
		printf "\033[0;32m=== Vision Models ===\033[0m\n"; \
		$(MAKE) --no-print-directory -C tools/model-conversion download; \
		echo ""; \
	fi; \
	if echo "$(INCLUDE_MEDIA)" | grep -qiE '^(true|yes)$$'; then \
		enabled=$$((enabled + 1)); \
		echo ""; \
		printf "\033[0;32m=== Media Files ===\033[0m\n"; \
		$(MAKE) --no-print-directory -C tools/media-downloader download; \
		echo ""; \
	fi; \
	if echo "$(INCLUDE_GENAI)" | grep -qiE '^(true|yes)$$'; then \
		enabled=$$((enabled + 1)); \
		echo ""; \
		printf "\033[0;32m=== GenAI Models ===\033[0m\n"; \
		$(MAKE) --no-print-directory -C tools/genai-downloader download; \
		echo ""; \
	fi; \
	if [ "$$enabled" -eq 0 ]; then \
		echo "[ Info ] No collateral selected. Enable at least one:"; \
		echo "  INCLUDE_VISION=True  INCLUDE_MEDIA=True  INCLUDE_GENAI=True"; \
		exit 1; \
	fi; \
	printf "\033[0;32m=== Linking Collateral ===\033[0m\n"; \
	if echo "$(INCLUDE_VISION)" | grep -qiE '^(true|yes)$$'; then \
		mkdir -p workloads/vision-benchmarks/models; \
		ln -sfn ../../collateral/models/classification workloads/vision-benchmarks/models/classification; \
		ln -sfn ../../collateral/models/detection workloads/vision-benchmarks/models/detection; \
		printf "\033[0;36m[ Info ]\033[0m Linked vision models → workloads/vision-benchmarks/models/\n"; \
	fi; \
	if echo "$(INCLUDE_MEDIA)" | grep -qiE '^(true|yes)$$'; then \
		ln -sfn ../../collateral/media workloads/media-benchmarks/media; \
		printf "\033[0;36m[ Info ]\033[0m Linked media files  → workloads/media-benchmarks/media\n"; \
	fi; \
	if echo "$(INCLUDE_GENAI)" | grep -qiE '^(true|yes)$$'; then \
		mkdir -p workloads/genai-benchmarks/models; \
		ln -sfn ../../collateral/models/genai workloads/genai-benchmarks/models/genai; \
		printf "\033[0;36m[ Info ]\033[0m Linked GenAI models → workloads/genai-benchmarks/models/\n"; \
	fi

# Pre-flight check: system compatibility + all collateral verification
.PHONY: check
check:
	@echo ""
	@echo "--- System ---"
	@if [ -x setup/check-compatibility.sh ]; then \
		setup/check-compatibility.sh || true; \
	else \
		echo "[ Warning ] setup/check-compatibility.sh not found"; \
	fi
	@echo ""
	@echo "--- Collateral ---"
	@bash utils/verify_collateral.sh || true
	@echo ""

# HTML report generation — delegates to tools/html/Makefile
.PHONY: report
report:
	@$(MAKE) --no-print-directory -C tools/html report REPORT_NAME=$(REPORT_NAME)

# Serve HTML dashboard locally
.PHONY: serve
serve:
	@$(MAKE) -C tools/html serve PORT=$(PORT) HOSTIP=$(HOSTIP)

# Results inventory
.PHONY: status
status:
	@bash utils/show_status.sh

# Clean benchmark results — optionally scoped by WORKLOAD
# Usage: make clean-results [WORKLOAD=vision,media,genai,pipeline]
.PHONY: clean-results
clean-results:
	@if [ -z "$(WORKLOAD)" ]; then \
		targets="vision media genai pipeline"; \
	else \
		targets="$$(echo '$(WORKLOAD)' | tr ',' ' ')"; \
	fi; \
	for wl in $$targets; do \
		case "$$wl" in \
			vision)   dir="collateral/results/vision-benchmarks" ;; \
			media)    dir="collateral/results/media-benchmarks" ;; \
			genai)    dir="collateral/results/genai-benchmarks" ;; \
			pipeline) dir="collateral/results/edge-ai-pipelines" ;; \
			*) echo "[ Error ] Unknown workload: $$wl (valid: vision, media, genai, pipeline)"; exit 1 ;; \
		esac; \
		if [ -d "$$dir" ]; then \
			count=$$(find "$$dir" -type f | wc -l); \
			rm -rf "$$dir"; \
			echo "[ Done ] Removed $$dir ($$count files)"; \
		else \
			echo "[ Skip ] $$dir (not found)"; \
		fi; \
	done
	@rm -f tools/html/data.json

# Remove all generated content: venvs, models, media, results, drivers
.PHONY: clean-all
clean-all: clean-results
	@echo "Removing virtual environments..."
	@rm -rf tools/model-conversion/venv
	@rm -rf tools/genai-downloader/venv tools/genai-downloader/venv-*
	@rm -rf workloads/vision-benchmarks/venv
	@rm -rf workloads/genai-benchmarks/venv
	@rm -rf workloads/genai-benchmarks/genai-utils/openvino.genai
	@echo "Removing models..."
	@rm -rf collateral/models
	@rm -rf tools/model-conversion/source-models tools/model-conversion/models tools/model-conversion/datasets
	@echo "Removing media..."
	@rm -rf collateral/media
	@rm -rf tools/media-downloader/media
	@echo "Removing reports..."
	@rm -rf collateral/reports
	@echo "Removing drivers..."
	@rm -rf setup/drivers/gpu/*/ setup/drivers/npu/*/
	@echo "Removing workload symlinks..."
	@unlink workloads/vision-benchmarks/models/classification 2>/dev/null || true
	@unlink workloads/vision-benchmarks/models/detection 2>/dev/null || true
	@rmdir workloads/vision-benchmarks/models 2>/dev/null || true
	@unlink workloads/media-benchmarks/media 2>/dev/null || true
	@unlink workloads/genai-benchmarks/models/genai 2>/dev/null || true
	@rmdir workloads/genai-benchmarks/models 2>/dev/null || true
	@echo "Removing __pycache__ directories..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "[ Done ] Repository cleaned"
