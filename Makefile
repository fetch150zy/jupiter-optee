SHELL := /bin/bash

PYTHON3 ?= python3

ROOT := $(CURDIR)

OPTEE_OS_PATH       := $(ROOT)/optee_os
OPTEE_FTPM_PATH     := $(ROOT)/optee_ftpm
MS_TPM_20_REF_PATH  := $(ROOT)/ms-tpm-20-ref

OPTEE_OS_OUT        := $(OPTEE_OS_PATH)/out/riscv

CROSS_COMPILE       ?= riscv64-unknown-linux-gnu-

CCACHE              := $(shell which ccache 2>/dev/null)

ARCH                := riscv
COMPILE_S_USER      := 64
COMPILE_S_KERNEL    := 64

OPTEE_OS_TA_DEV_KIT_DIR := $(OPTEE_OS_OUT)/export-ta_rv64

OPTEE_OS_BIN        := $(OPTEE_OS_OUT)/core/tee.bin

FTPM_TA_UUID        := bc50d971-d4c9-42c4-82cb-343fb7f37896

OPTEE_OS_PLATFORM   ?= jupiter

DEBUG               ?= 0
CFG_TEE_CORE_LOG_LEVEL ?= 0

MEASURED_BOOT_FTPM  ?= y

################################################################################
# OP-TEE OS build flags
################################################################################
OPTEE_OS_COMMON_FLAGS := \
	ARCH=$(ARCH) \
	PLATFORM=$(OPTEE_OS_PLATFORM) \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	CROSS_COMPILE_core="$(CCACHE)$(CROSS_COMPILE)" \
	CROSS_COMPILE_ta_rv64="$(CCACHE)$(CROSS_COMPILE)" \
	CFG_RV64_core=y \
	CFG_USER_TA_TARGETS=ta_rv64 \
	CFG_TEE_CORE_LOG_LEVEL=$(CFG_TEE_CORE_LOG_LEVEL) \
	DEBUG=$(DEBUG) \
	O=out/riscv

OPTEE_OS_PLATFORM_FLAGS := \
	CFG_TEE_CORE_NB_CORE=1 \
	CFG_NUM_THREADS=1 \
	CFG_UNWIND=y \
	CFG_SEMIHOSTING_CONSOLE=n \
	CFG_16550_UART=y \
	CFG_UART0_BASE=0xD4017000 \
	CFG_RISCV_PLIC=n \
	CFG_RISCV_MTIME_RATE=24000000 \
	CFG_TDDRAM_START=0x38000000 \
	CFG_TDDRAM_SIZE=0x01000000

CFG_IN_TREE_EARLY_TAS := trusted_keys/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c

################################################################################
# fTPM build flags
################################################################################
FTPM_FLAGS := \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	CFG_MS_TPM_20_REF=$(MS_TPM_20_REF_PATH) \
	CFG_TA_MEASURED_BOOT=y \
	$(if $(filter 1,$(DEBUG)),CFG_TA_DEBUG=y) \
	O=out

################################################################################
# Targets
################################################################################
.PHONY: all clean optee-os optee-os-devkit ftpm check-python-deps

all: optee-os

################################################################################
# Check Python dependencies
# OP-TEE's scripts require cryptography and pyelftools modules
################################################################################
check-python-deps:
	@$(PYTHON3) -c "import cryptography" 2>/dev/null || \
		(echo "ERROR: Python 'cryptography' module is required but not installed." && \
		 echo "Please install it with: pip3 install cryptography" && \
		 exit 1)
	@$(PYTHON3) -c "import elftools" 2>/dev/null || \
		(echo "ERROR: Python 'pyelftools' module is required but not installed." && \
		 echo "Please install it with: pip3 install pyelftools" && \
		 exit 1)

################################################################################
# OP-TEE OS
################################################################################
ifeq ($(MEASURED_BOOT_FTPM),y)
OPTEE_OS_EARLY_TA_FLAGS := EARLY_TA_PATHS=$(OPTEE_FTPM_PATH)/out/$(FTPM_TA_UUID).stripped.elf

optee-os: ftpm
	@echo "Building OP-TEE OS with fTPM as early TA..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		$(OPTEE_OS_EARLY_TA_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)"
	@echo "OP-TEE OS build complete: $(OPTEE_OS_BIN)"
else
optee-os:
	@echo "Building OP-TEE OS without fTPM..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)"
	@echo "OP-TEE OS build complete: $(OPTEE_OS_BIN)"
endif

################################################################################
# OP-TEE OS TA Development Kit
# This is built first, then used to compile TAs (including fTPM)
################################################################################
optee-os-devkit: check-python-deps
	@echo "Building OP-TEE OS TA development kit..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)" \
		ta_dev_kit
	@echo "TA dev kit built: $(OPTEE_OS_TA_DEV_KIT_DIR)"

################################################################################
# fTPM TA
# Requires optee-os-devkit to be built first
################################################################################
ftpm: optee-os-devkit
ifeq ($(MEASURED_BOOT_FTPM),y)
	@echo "Building fTPM TA..."
	$(MAKE) -C $(OPTEE_FTPM_PATH) $(FTPM_FLAGS)
	@echo "fTPM TA built: $(OPTEE_FTPM_PATH)/out/$(FTPM_TA_UUID).stripped.elf"
else
	@echo "fTPM is disabled (MEASURED_BOOT_FTPM != y)"
endif

################################################################################
# Clean targets
################################################################################
clean: optee-os-clean ftpm-clean

optee-os-clean:
	$(MAKE) -C $(OPTEE_OS_PATH) $(OPTEE_OS_COMMON_FLAGS) clean || true
	rm -rf $(OPTEE_OS_OUT)

ftpm-clean:
ifeq ($(MEASURED_BOOT_FTPM),y)
	$(MAKE) -C $(OPTEE_FTPM_PATH) $(FTPM_FLAGS) clean || true
	rm -rf $(OPTEE_FTPM_PATH)/out
endif
