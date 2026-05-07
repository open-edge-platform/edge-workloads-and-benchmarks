# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

########################################
# GenAI Model Download & Export
########################################

.DEFAULT_GOAL := help

COLLATERAL := $(abspath $(CURDIR)/../../collateral/models/genai)
VERBOSE ?= 0

.PHONY: help
help:
	@echo ""
	@echo "GenAI Model Conversion"
	@echo "======================"
	@echo ""
	@echo "Checks:"
	@echo "  make verify                 Optional: Check that all required model directories are present"
	@echo ""
	@echo "Conversion:"
	@echo "  make setup                  Create Python venv and install export dependencies"
	@echo "  make download               Download and export all GenAI models (~25 GB)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                  Optional: Remove exported models from collateral"
	@echo "  make clean-venv             Optional: Remove the Python virtual environment"
	@echo ""
	@echo "Notes:"
	@echo "  Some models are gated and require a Hugging Face token."
	@echo "  Run 'huggingface-cli login' or export HF_TOKEN=hf_... before download."
	@echo ""

.PHONY: setup
setup:
	@printf "\033[0;36m[ Info ]\033[0m Setting up GenAI download environment...\n"
	@bash setup_env.sh

.PHONY: download
download: setup
	@printf "\033[0;36m[ Info ]\033[0m Downloading and exporting GenAI models...\n"
	@failed=0; \
	bash download_models.sh  || { printf "\033[0;31m[ FAILED ]\033[0m LLM models\n";  failed=$$((failed+1)); }; \
	bash download_minicpm.sh || { printf "\033[0;31m[ FAILED ]\033[0m MiniCPM\n";     failed=$$((failed+1)); }; \
	bash download_gemma3.sh  || { printf "\033[0;31m[ FAILED ]\033[0m Gemma3\n";      failed=$$((failed+1)); }; \
	bash download_phi4mm.sh  || { printf "\033[0;31m[ FAILED ]\033[0m Phi4MM\n";      failed=$$((failed+1)); }; \
	printf "\033[0;36m[ Info ]\033[0m Downloading VLM test images...\n"; \
	bash download_images.sh  || { printf "\033[0;31m[ FAILED ]\033[0m images\n";      failed=$$((failed+1)); }; \
	if [ $$failed -gt 0 ]; then printf "\033[0;31m[ Error ]\033[0m $$failed download(s) failed\n"; exit 1; fi

.PHONY: verify
verify:
	@bash ../../utils/verify_collateral.sh --section genai $(if $(filter 1,$(VERBOSE)),--verbose,)

.PHONY: clean
clean:
	@printf "\033[0;36m[ Info ]\033[0m Removing exported GenAI models from collateral...\n"
	@rm -rf "$(COLLATERAL)"
	@rm -rf "$(abspath $(CURDIR)/../../collateral/media/images)"

.PHONY: clean-venv
clean-venv:
	@printf "\033[0;36m[ Info ]\033[0m Removing virtual environments.\n"
	@rm -rf venv venv-phi4mm
