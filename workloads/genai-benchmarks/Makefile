# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

########################################
# GenAI Benchmarks Workload
########################################

.DEFAULT_GOAL := help

# Workload variables
DURATION ?= 60
CORES ?=
POWER ?= True
CLEAR ?= False
DRY_RUN ?= False
RESUME ?= False

SUDO := $(if $(filter True true TRUE yes YES,$(POWER)),sudo,)
VERBOSE ?= 0

# Usage
.PHONY: help
help:
	@echo ""
	@echo "GenAI Benchmarks"
	@echo "================"
	@echo ""
	@echo "Collateral:"
	@echo "  make collateral             Download GenAI models"
	@echo "  make check                  Verify all required collateral is present"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make benchmarks             Sweep all benchmark configurations"
	@echo ""
	@echo "  Options:"
	@echo "    DRY_RUN                   Lists all benchmark configurations without running (default: False)"
	@echo "    RESUME                    Skip tests that already have results (default: False)"
	@echo "    DURATION                  Set the duration for each benchmark test (default: 60 seconds)"
	@echo "    POWER                     Enable/Disable power/efficiency metrics (default: True, requires sudo)"
	@echo "    CORES                     Pin the cores for scheduling workload.  (default: all cores)"
	@echo "                              Accepts the following: pcore, ecore, and min-max range (example: 0-11)"
	@echo "                              Performance and efficiency may vary depending on core pinning"
	@echo ""
	@echo "Cleanup:"
	@echo "  sudo make clean             Optional: Remove all results"
	@echo "  sudo make clean-venv        Optional: Remove virtual environment and cloned repos"
	@echo ""

.PHONY: setup
setup:
	@bash ./genai-utils/setup_genai.sh

.PHONY: check-collateral
check-collateral:
	@$(MAKE) --no-print-directory -C ../../tools/genai-downloader verify VERBOSE=$(VERBOSE)
	@images="$(abspath $(CURDIR)/../../collateral/media/images)"; \
	missing=0; total=0; found=0; \
	for f in "coco_448x448.jpg"; do \
		total=$$((total + 1)); \
		if [ -f "$${images}/$${f}" ]; then \
			found=$$((found + 1)); \
			if [ "$(VERBOSE)" = "1" ]; then echo "[  Found  ] images/$${f}"; fi; \
		else \
			echo "[ Missing ] images/$${f}"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -eq 1 ]; then \
		echo ""; \
		echo "[ Fail ] VLM test images: $${found}/$${total} files found."; \
		echo "  Run:  cd tools/genai-downloader && make download"; \
		exit 1; \
	fi; \
	echo "[ Pass ] VLM test images: $${found}/$${total} files verified."

.PHONY: check
check:
	@echo "GenAI Benchmarks — Collateral Check"
	@echo "===================================="
	@echo ""
	@bash ../../utils/verify_collateral.sh --section genai --verbose || true

.PHONY: collateral
collateral:
	@$(MAKE) --no-print-directory -C ../.. collateral INCLUDE_VISION=False INCLUDE_MEDIA=False INCLUDE_GENAI=True
	@mkdir -p models
	@ln -sfn ../../collateral/models/genai models/genai

.PHONY: benchmarks
benchmarks: check-collateral setup
	@if echo "$(CLEAR)" | grep -qiE '^(true|yes)$$'; then $(MAKE) clean; fi
	@if [ ! -d "venv" ]; then \
		echo "[ Error ] Virtual environment not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@if [ ! -d "genai-utils/openvino.genai" ]; then \
		echo "[ Error ] openvino.genai repo not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "[ Info ] Generating genai benchmark coverage matrix..."
	@coverage_output=$$(./genai-utils/generate_benchmark_coverage.sh); \
	total_tests=$$(echo "$$coverage_output" | grep "^TOTAL_TESTS=" | cut -d= -f2); \
	total_time_s=$$(( total_tests * ($(DURATION) + 10) )); \
	total_time_m=$$(( total_time_s / 60 )); \
	echo "[ Info ] Benchmark sweep: $$total_tests tests, ~$${total_time_m}m estimated"; \
	echo ""; \
	if echo "$(DRY_RUN)" | grep -qiE '^(true|yes)$$'; then \
		echo "[ Dry Run ] Coverage matrix:"; \
		echo "$$coverage_output" | grep -v "^#" | grep -v "^TOTAL_TESTS="; \
		echo ""; \
		echo "[ Dry Run ] $$total_tests tests × $(DURATION)s + 10s cooldown = ~$${total_time_m}m total"; \
		exit 0; \
	fi; \
	current=0; \
	ran=0; \
	start_epoch=$$(date +%s); \
	cores_opt="$(if $(CORES),-t $(CORES),)"; \
	echo "$$coverage_output" | grep -v "^#" | grep -v "^TOTAL_TESTS=" | while IFS=, read -r model device precision type; do \
		current=$$((current + 1)); \
		if echo "$(RESUME)" | grep -qiE '^(true|yes)$$'; then \
			existing=$$(find ../../collateral/results/genai-benchmarks -name "genai-benchmark_$${model}_$${device}_$${precision}_$${type}_*.csv" 2>/dev/null | head -1); \
			if [ -n "$$existing" ]; then \
				echo "[ Info ] [$$current/$$total_tests] Skipping (resume): $$model $$device $$precision — results exist"; \
				continue; \
			fi; \
		fi; \
		pct=$$((current * 100 / total_tests)); \
		now_epoch=$$(date +%s); \
		elapsed=$$((now_epoch - start_epoch)); \
		if [ $$ran -gt 0 ] && [ $$elapsed -gt 0 ]; then \
			rate_ms=$$((elapsed * 1000 / ran)); \
			remaining_ms=$$(( (total_tests - current) * rate_ms )); \
			eta_m=$$((remaining_ms / 60000)); \
			eta_s=$$(( (remaining_ms / 1000) % 60 )); \
			eta_str="ETA: $${eta_m}m$${eta_s}s"; \
		else \
			eta_str="ETA: calculating..."; \
		fi; \
		filled=$$((pct / 5)); \
		empty=$$((20 - filled)); \
		bar="$$(printf '%0.s█' $$(seq 1 $$filled 2>/dev/null))$$(printf '%0.s░' $$(seq 1 $$empty 2>/dev/null))"; \
		echo "[ Info ] [$$current/$$total_tests] $$bar $${pct}%% | $$eta_str | $$model $$device $$precision $$type"; \
		if [ "$$type" = "vlm" ]; then \
			$(SUDO) ./benchmark_genai_vlm.sh -m "$$model" -d "$$device" -p "$$precision" -i $(DURATION) $$cores_opt || { \
				echo "[ FAILED ] Benchmark run failed (model=$$model device=$$device precision=$$precision type=$$type)"; \
				continue; \
			}; \
		else \
			$(SUDO) ./benchmark_genai_llm.sh -m "$$model" -d "$$device" -p "$$precision" -i $(DURATION) $$cores_opt || { \
				echo "[ FAILED ] Benchmark run failed (model=$$model device=$$device precision=$$precision type=$$type)"; \
				continue; \
			}; \
		fi; \
		echo "[ Info ] Sleeping for 10 seconds to prevent thermal throttling."; \
		sleep 10; \
		ran=$$((ran + 1)); \
	done; \
	elapsed_total=$$(( $$(date +%s) - start_epoch )); \
	elapsed_m=$$((elapsed_total / 60)); \
	elapsed_s=$$((elapsed_total % 60)); \
	echo ""; \
	echo "[ Info ] Completed $$total_tests genai benchmark runs in $${elapsed_m}m$${elapsed_s}s."

.PHONY: clean
clean:
	@echo "[ Info ] Cleaning genai benchmark results."
	@find ../../collateral/results/genai-benchmarks -type f \( -name "*.log" -o -name "*.csv" \) -delete 2>/dev/null || true

.PHONY: clean-venv
clean-venv:
	@echo "[ Info ] Removing virtual environment and cloned repos."
	@rm -rf venv
	@rm -rf genai-utils/openvino.genai
