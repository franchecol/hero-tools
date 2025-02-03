# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>

# Path to the root of the repository
HERO_ROOT ?= $(realpath ../..)

# cva6 and sg2042 supported
HERO_HOST   ?=
# occamy_snitch_cluster carfield_safety_island carfield_spatz_cluster carfield_snitch_cluster
HERO_DEVICE ?=

# Toolchain
CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
AR      := $(CROSS_COMPILE)ar
OBJDUMP := $(CROSS_COMPILE)objdump

# Host specific variables
CFLAGS_cva6   := -DHOST_MBOX_CYCLES=50
CFLAGS_sg2042 := -DHOST_COHERENT_IO -DHOST_MBOX_CYCLES="(1*2000000000/25000000)"

# Device specific variables
CFLAGS_carfield_safety_island := -I src/carfield -I $(HERO_ROOT)/sw/hero-driver/carfield
SRCS_carfield_safety_island   := src/carfield/safety_island.c

CFLAGS_carfield_spatz_cluster := -I src/carfield -I $(HERO_ROOT)/sw/hero-driver/carfield -DDEVICE_IOMMU
SRCS_carfield_spatz_cluster   := src/carfield/spatz_cluster.c

CFLAGS_carfield_snitch_cluster := -I src/carfield -I $(HERO_ROOT)/sw/hero-driver/carfield -DDEVICE_IOMMU
SRCS_carfield_snitch_cluster   := src/carfield/snitch_cluster.c

CFLAGS_occamy_snitch_cluster := -I src/occamy -I $(HERO_ROOT)/sw/hero-driver/occamy
SRCS_occamy_snitch_cluster   := src/occamy/snitch_cluster.c

# Final variables
CFLAGS := $(CFLAGS_$(HERO_HOST)) $(CFLAGS_$(HERO_DEVICE))

# Normal CFLAGS
CFLAGS += -Wall -O3 -g -fPIC
CFLAGS += -Iinclude -Isrc/common -Ivendor/o1heap/o1heap

SRCS   := $(SRCS_$(HERO_DEVICE)) src/common/hero_api.c vendor/o1heap/o1heap/o1heap.c
OBJS   := $(SRCS:%.c=%.o)

INSTALL_DIR := lib

# Outputs
all: $(INSTALL_DIR)/libhero_$(HERO_DEVICE).so $(INSTALL_DIR)/libhero_$(HERO_DEVICE).a $(INSTALL_DIR)/libhero_$(HERO_DEVICE).dump

%.o : %.c
	$(CC) $(CFLAGS) $^ -c -o $@
	$(CC) $(CFLAGS) $^ -MM -c > $*.d

%.dump : %.a
	$(OBJDUMP) -S $^ > $@

%.so: $(OBJS) | check_platform $(INSTALL_DIR)
	$(CC) $(CFLAGS) -shared -o $@ $^

%.a: $(OBJS) | check_platform $(INSTALL_DIR)
	$(AR) rvs -o $@ $^

$(INSTALL_DIR):
	mkdir -p $@

check_platform:
	@if [ -z "$(CFLAGS_$(HERO_HOST))" ]; then echo "Incorrect HERO_HOST selected"; exit 1; fi
	@if [ -z "$(CFLAGS_$(HERO_DEVICE))" ]; then echo "Incorrect HERO_DEVICE selected"; exit 1; fi

.PHONY: clean check_platform

clean:
	find . -name "*.o" -delete
	find . -name "*.d" -delete
	find . -name "*.so" -delete
	find . -name "*.a" -delete
