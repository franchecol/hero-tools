# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Helper variables to locate the Buildroot-generated Linux host toolchain.
# Some local checkouts produce a `linux-uclibc` tuple while the original
# HeroSDK makefiles assume `linux-gnu`, so detect the live tuple from
# `cva6-sdk/buildroot/output/host` instead of hardcoding it everywhere.

HERO_BR_OUTPUT_DIR ?= $(realpath $(HERO_ROOT)/cva6-sdk/buildroot/output/)
HERO_BR_HOST_DIR ?= $(HERO_BR_OUTPUT_DIR)/host

_HERO_LINUX_GCC_CANDIDATES := \
  $(wildcard $(HERO_BR_HOST_DIR)/bin/riscv64-buildroot-linux-*-gcc) \
  $(wildcard $(HERO_BR_HOST_DIR)/bin/riscv64-buildroot-linux-*-gcc.br_real)

_HERO_LINUX_TUPLE_FROM_GCC := \
  $(patsubst %-gcc.br_real,%,$(patsubst %-gcc,%,$(notdir $(firstword $(_HERO_LINUX_GCC_CANDIDATES)))))

_HERO_LINUX_SYSROOT_CANDIDATES := \
  $(wildcard $(HERO_BR_HOST_DIR)/riscv64-buildroot-linux-*/sysroot)

_HERO_LINUX_TUPLE_FROM_SYSROOT := \
  $(notdir $(patsubst %/sysroot,%,$(firstword $(_HERO_LINUX_SYSROOT_CANDIDATES))))

ifeq ($(strip $(_HERO_LINUX_TUPLE_FROM_GCC)),)
HERO_LINUX_TUPLE ?= $(_HERO_LINUX_TUPLE_FROM_SYSROOT)
else
HERO_LINUX_TUPLE ?= $(_HERO_LINUX_TUPLE_FROM_GCC)
endif

ifeq ($(strip $(HERO_LINUX_TUPLE)),)
HERO_LINUX_TUPLE := riscv64-buildroot-linux-gnu
endif

HERO_LINUX_CROSS_COMPILE ?= $(HERO_BR_HOST_DIR)/bin/$(HERO_LINUX_TUPLE)-
HERO_LINUX_SYSROOT ?= $(firstword $(_HERO_LINUX_SYSROOT_CANDIDATES))

ifeq ($(strip $(HERO_LINUX_SYSROOT)),)
HERO_LINUX_SYSROOT := $(HERO_BR_HOST_DIR)/$(HERO_LINUX_TUPLE)/sysroot
endif

HERO_LINUX_GCC ?= $(HERO_LINUX_CROSS_COMPILE)gcc
HERO_LINUX_GXX ?= $(HERO_LINUX_CROSS_COMPILE)g++
HERO_LINUX_LD ?= $(HERO_LINUX_CROSS_COMPILE)ld
HERO_LINUX_OBJDUMP ?= $(HERO_LINUX_CROSS_COMPILE)objdump
