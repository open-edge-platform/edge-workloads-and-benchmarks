# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

########################################
# Vision Benchmarks Workload
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
	@echo "Vision Benchmarks"
	@echo "================="
	@echo ""
	@echo "Checks:"
	@echo "  make collateral             Download AI models and media files"
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
	@echo "  sudo make clean-venv        Optional: Remove virtual environment"
	@echo ""

.PHONY: setup
setup:
	@./vision-utils/setup_env.sh

.PHONY: check-collateral
check-collateral:
	@$(MAKE) --no-print-directory -C ../../tools/model-conversion verify VERBOSE=$(VERBOSE)

.PHONY: check
check:
	@echo "Vision Benchmarks — Collateral Check"
	@echo "====================================="
	@echo ""
	@bash ../../utils/verify_collateral.sh --section vision --verbose || true

.PHONY: collateral
collateral:
	@$(MAKE) --no-print-directory -C ../.. collateral INCLUDE_VISION=True INCLUDE_MEDIA=False INCLUDE_GENAI=False
	@mkdir -p models
	@ln -sfn ../../collateral/models/classification models/classification
	@ln -sfn ../../collateral/models/detection models/detection

.PHONY: benchmarks
benchmarks: check-collateral setup
	@if echo "$(CLEAR)" | grep -qiE '^(true|yes)$$'; then $(MAKE) clean; fi
	@if [ ! -d "venv" ]; then \
		echo "[ Error ] Virtual environment not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "[ Info ] Generating vision benchmark coverage matrix..."
	@coverage_output=$$(./vision-utils/generate_benchmark_coverage.sh); \
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
	echo "$$coverage_output" | grep -v "^#" | grep -v "^TOTAL_TESTS=" | while IFS=, read -r model device mode batch concurrent; do \
		current=$$((current + 1)); \
		shortname=$$(basename "$$(dirname "$$(dirname "$$model")")"); \
		if [ -n "$$concurrent" ]; then \
			devicetag="$${device}-$${concurrent}-Concurrent"; \
		else \
			devicetag="$$device"; \
		fi; \
		if echo "$(RESUME)" | grep -qiE '^(true|yes)$$'; then \
			existing=$$(find ../../collateral/results/vision-benchmarks -name "vision-benchmark_$${shortname}_$${devicetag}_$${mode}_BS$${batch}_*.csv" 2>/dev/null | head -1); \
			if [ -n "$$existing" ]; then \
				echo "[ Info ] [$$current/$$total_tests] Skipping (resume): $$shortname $$devicetag $$mode BS$$batch — results exist"; \
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
		mode_desc="$$( [ -n "$$concurrent" ] && echo " (concurrent $$concurrent)" || echo "" )"; \
		echo "[ Info ] [$$current/$$total_tests] $$bar $${pct}%% | $$eta_str | $$shortname $$device $$mode BS$$batch$$mode_desc"; \
		concurrent_opt="$$( [ -n "$$concurrent" ] && echo "--concurrent $$concurrent" || echo "" )"; \
		$(SUDO) ./benchmark_vision.sh -m "$$model" -d "$$device" -e "$$mode" -b "$$batch" -i $(DURATION) $$concurrent_opt $$cores_opt || { \
			echo "[ FAILED ] Benchmark run failed (model=$$model device=$$device mode=$$mode batch=$$batch$$mode_desc)"; \
			continue; \
		}; \
		echo "[ Info ] Sleeping for 10 seconds to prevent thermal throttling."; \
		sleep 10; \
		ran=$$((ran + 1)); \
	done; \
	elapsed_total=$$(( $$(date +%s) - start_epoch )); \
	elapsed_m=$$((elapsed_total / 60)); \
	elapsed_s=$$((elapsed_total % 60)); \
	echo ""; \
	echo "[ Info ] Completed $$total_tests vision benchmark runs in $${elapsed_m}m$${elapsed_s}s."

.PHONY: clean
clean:
	@echo "[ Info ] Cleaning vision benchmark results."
	@find ../../collateral/results/vision-benchmarks -type f \( -name "*.log" -o -name "*.csv" \) -delete 2>/dev/null || true

.PHONY: clean-venv
clean-venv:
	@echo "[ Info ] Removing virtual environment."
	@rm -rf venv
