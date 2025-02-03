# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>

# Buildroot contains the GCC toolchain
BR_OUTPUT_DIR ?= $(realpath $(HERO_ROOT)/cva6-sdk/buildroot/output/)
RISCV          = $(BR_OUTPUT_DIR)/host
RV64_SYSROOT   = $(RISCV)/riscv64-buildroot-linux-gnu/sysroot

# Makefile hacks
comma:= ,
empty:=
space:= $(empty) $(empty)

# Binaries
LLVM_INSTALL := $(HERO_INSTALL)
CC   := $(HERO_INSTALL)/bin/clang
LINK := $(HERO_INSTALL)/bin/ld.lld
COB  := $(HERO_INSTALL)/bin/clang-offload-bundler
DIS  := $(HERO_INSTALL)/bin/llvm-dis
HOP  := $(HERO_INSTALL)/bin/hc-omp-pass
GCC  := $(HERO_INSTALL)/bin/$(TARGET_HOST)-gcc
HOST_OBJDUMP := $(RISCV)/bin/riscv64-buildroot-linux-gnu-objdump
DEV_OBJDUMP  := $(HERO_INSTALL)/bin/llvm-objdump

# Device flags definitions
-include $(HERO_ROOT)/apps/omp/common/devices.mk
# Add device specific flags for each device in $(DEVICES)
$(foreach dev, $(HERO_DEVICE), $(eval $(call add_device,$(dev))))
RENAMED_DEVICES := $(foreach i,$(shell seq 1 $(NUM_DEVICES)),hero$(i))
# Openmp host and device flags
TARGET_HOST := riscv64-hero-linux-gnu
TARGET_DEVS := $(foreach hero_dev,$(RENAMED_DEVICES),riscv32-hero-$(hero_dev)-elf)
# Bundler host and device flags
COB_TARGETS = $(subst $(space),$(comma),host-$(TARGET_HOST) $(foreach target,$(TARGET_DEVS),openmp-$(target)))

# Toolchain(s) selection
CFLAGS       += --gcc-toolchain=$(RISCV) --sysroot=$(RV64_SYSROOT)
CFLAGS       += -target $(TARGET_HOST)
CFLAGS_OMP   := -fopenmp=libomp -fopenmp-targets=$(subst $(space),$(comma),$(foreach target,$(TARGET_DEVS),$(target)))
# Include files used by the OpenMP target RTL
CFLAGS   += -I$(HERO_ROOT)/sw/libhero/include
CFLAGS   += -I$(HERO_ROOT)/apps/omp/common
# Dependancy managements
DEPDIR   := build
BUILDDIR := build
CFLAGS   += -MT $@ -MMD -MP -MF $(DEPDIR)/$*.d

# Link flags
LDFLAGS  += --ld-path=$(RISCV)/bin/riscv64-buildroot-linux-gnu-ld 
# Path to the OpenMP target RTL
LDFLAGS  += -L$(HERO_ROOT)/sw/libomp/lib

APP = $(shell basename `pwd`)$(foreach dev,$(HERO_DEVICE),_$(dev)).elf
EXE = $(APP)

# Unique object after bundling host/devices together
COBJS_BUNDLED = $(addprefix $(BUILDDIR)/,$(patsubst %.c, %-out.ll, $(CSRCS)))
# Objects for each host/devices
COBJS_UNBUNDLED = $(foreach dev,host $(RENAMED_DEVICES),$(patsubst %-out.ll, %-$(dev).ll, $(COBJS_BUNDLED)))
# Objects for host only
COBJS_HOST = $(addprefix $(BUILDDIR)/,$(patsubst %.c, %.o, $(CSRCS_HOST)))

# Targets
all: check_device $(DEPS) $(EXE) $(EXE).dis $(EXE).dev.dis

# Compile C source
$(BUILDDIR)/%.o: $(SRCDIR)/%.c $(DEPDIR)/%.d
	mkdir -p $(dir $@)
	@echo "CC(.o)   <= $<"
	$(CC) $(debug) -c $(DEPFLAGS) $(CFLAGS) $< -o $@

# Compile heterogeneous C source and get a bundled .ll
$(BUILDDIR)/%.ll: $(SRCDIR)/%.c $(DEPDIR)/%.d
	mkdir -p $(dir $@)
	@echo "CC(.ll)  <= $@"
	$(CC) $(debug) -c -emit-llvm -S $(DEPFLAGS) $(CFLAGS) $(CFLAGS_OMP) $< -o $@

# De-bundle %-host.ll and %-heroX.ll
# Note: We need to replace spaces by comma in COB_OUTPUTS
%-host.ll: %.ll
	@echo "COB    <= $<"
	@COB_OUTPUTS="$(foreach tgt,host $(RENAMED_DEVICES),$(<:.ll=-$(tgt).ll))"; \
	  COB_CMD="$(COB) -inputs=$< -outputs=\"$${COB_OUTPUTS// /,}\" -type=ll -targets=\"$(COB_TARGETS)\" -unbundle" ; \
	  echo $$COB_CMD; \
	  eval $$COB_CMD

# Create dependance to %-host.ll for all %-heroX.ll (all created by the rule above)
define add_host_dep =
$(foreach tgt-dev,$(RENAMED_DEVICES),$(patsubst %-host.ll, %-$(tgt-dev).ll, $(1))): $(1)
endef
# Call add_cob_dep for all %-host.ll objects
$(foreach host-obj, $(patsubst %-out.ll, %-host.ll, $(COBJS_BUNDLED)), $(eval $(call add_host_dep,$(host-obj))))

# Different custom LLVMs passes to be applied on host regions
%-host.OMP.ll: %-host.ll
	@echo "HOP    <= $<"
	LLVM_INSTALL=$(HERO_INSTALL)/ $(HOP) $(<) OmpKernelWrapper "HERCULES-omp-kernel-wrapper" $(@:.OMP.ll=.TMP.1.ll)
	@cp $(@:.OMP.ll=.TMP.1.ll) $@

# Different custom LLVMs passes to be applied on devices regions
%.OMP.ll: %.ll
	@echo "HOP    <= $<"
	LLVM_INSTALL=$(HERO_INSTALL) $(HOP) $(<) OmpKernelWrapper "HERCULES-omp-kernel-wrapper" $(@:.OMP.ll=.TMP.1.ll)
	LLVM_INSTALL=$(HERO_INSTALL) $(HOP) $(@:.OMP.ll=.TMP.1.ll) OmpHostPointerLegalizer "HERCULES-omp-host-pointer-legalizer" $(@:.OMP.ll=.TMP.2.ll)
	@cp $(@:.OMP.ll=.TMP.2.ll) $@

# Use COB to re-gather all the targets.OMP.ll into a unique output
%-out.ll: $(foreach dev,host $(RENAMED_DEVICES),%-$(dev).OMP.ll)
	@echo "COB    <= $<"
	@COB_INPUTS="$(foreach dev,host $(RENAMED_DEVICES),$(<:-host.OMP.ll=-$(dev).OMP.ll))"; \
	COB_CMD="$(COB) -inputs=\"$${COB_INPUTS// /,}\" -outputs=$@ -type=ll -targets=\"$(COB_TARGETS)\""; \
	echo $$COB_CMD; \
	eval $$COB_CMD

# Link the final application
$(EXE): $(COBJS_BUNDLED) $(COBJS_HOST)
	@echo "CCLD   <= $<"
	$(CC) $(CFLAGS) $(CFLAGS_OMP) $(COBJS_BUNDLED) $(COBJS_HOST) $(LDFLAGS) -o $@
	echo "done"

# Objdump
$(EXE).dis: $(EXE)
	@echo "OBJDUMP <= $<"
	@$(HOST_OBJDUMP) -d $^ > $@

$(EXE).dev.dis: $(EXE)
	echo "OBJDUMP (device) <= $<"
	device_addr=$$(llvm-readelf $(EXE) -Ws | grep '.omp_offloading.device_image\b' | awk '{print $$2}') \
	device_size=$$(llvm-readelf $(EXE) -Ws | grep '.omp_offloading.device_image\b' | awk '{print $$3}') \
	rodata_addr=$$(llvm-readelf $(EXE) -WS | grep '.rodata\b' | awk '{print $$4}') \
	rodata_off=$$(llvm-readelf $(EXE) -WS | grep '.rodata\b' | awk '{print $$5}') && \
	device_addr=$$((16#$$device_addr - 16#$$rodata_addr + 16#$$rodata_off)) && \
	dd if=$(EXE) skip=$$device_addr bs=1 of=device.bin count=$$device_size && \
	$(DEV_OBJDUMP) -S device.bin > $@

# Dep
$(DEPDIR):
	@mkdir -p $@

DEPFILES := $(CSRCS:%.c=$(DEPDIR)/%.d) $(CSRCS_HOST:%.c=$(DEPDIR)/%.d)
$(DEPFILES):

include $(wildcard $(DEPFILES))

# Phony
clean:
	-rm -vf __hmpp* $(EXE) *~ *.bc *.dis *.elf *.i *.lh *.lk *.ll *.o *.s *.slm a.out* *.dump *.bin
	-rm -rvf $(DEPDIR)
	-rm -vf *-host-llvm *-host-gnu

.PHONY: install
install: $(EXE)
	cp $? $(HERO_ROOT)/board/common/overlay/root

ifndef HERO_ROOT
$(error HERO_INSTALL is not set)
endif

ifndef HERO_INSTALL
$(error HERO_INSTALL is not set)
endif
