###############################################################################
# This Makefile automates running multiple LLM prompts with different models,
# scans Terraform files using KICS, and cleans up generated artifacts. 
# 
# Usage:
#   make all ITERATIONS=<N> TEMPERATURE=<T>      # Run all models
#   make one ITERATIONS=<N> TEMPERATURE=<T> MODEL=<MODEL>   # Run one model
#   make clean                                   # Remove TF files, results, etc.
###############################################################################

# Use bash for our shell and ensure we run everything in one shell
SHELL := /bin/bash
PROMPTS_DIR := ../prompts
LLM_TOOL    := ../../../tools/llm_client.py
KICS_TOOL   := ../../../tools/kics_scanner.py
KICS_QUERIES:= ~/kics/assets/queries/

.ONESHELL:

.PHONY: all one clean scan

all:
	# Activate the virtual environment
	source ../../../.venv/bin/activate

	# Run the LLM client for each model in 'list'
	for i in $$(cat ../model_list); do \
		$(LLM_TOOL) \
			$(PROMPTS_DIR)/system_prompt_01.txt \
			$(PROMPTS_DIR)/user_prompt-aws-refarch-serverless-web-app \
			. $$ITERATIONS $$i "$$TEMPERATURE"; \
	done

	deactivate

scan:
	# Scan each .tf file
	for i in $$(ls *.tf); do \
		$(KICS_TOOL) $$i $(KICS_QUERIES); \
	done

one:
	# Activate the virtual environment
	source ../../../.venv/bin/activate

	# Run the LLM client for a single model in 'list'
	for i in $$(grep $$MODEL ../model_list); do \
		$(LLM_TOOL) \
			$(PROMPTS_DIR)/system_prompt_01.txt \
			$(PROMPTS_DIR)/user_prompt-aws-refarch-serverless-web-app \
			. $$ITERATIONS $$i "$$TEMPERATURE"; \
	done

	deactivate
clean:
	# Remove .results and .json files
	rm -f *.tf
	rm -f *.results
	rm -rf *.json

	# Finally, list directory contents
	ls -la
