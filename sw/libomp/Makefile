# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>
#
# This file builds all the OpenMP target libraries on RV64
# it requires ../libllvm to be compiled

# Path to the root of the repository
HERO_ROOT ?= $(realpath ../..)

# cva6 and sg2042 supported
HERO_HOST   ?=
# occamy_snitch_cluster carfield_safety_island carfield_spatz_cluster carfield_snitch_cluster
HERO_DEVICE ?=

# Toolchain
CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
CXX     := $(CROSS_COMPILE)g++
AR      := $(CROSS_COMPILE)ar
OBJDUMP := $(CROSS_COMPILE)objdump

LLVM_DIR := $(realpath ../libllvm)
LIBOMPTARGET_LLVM_INCLUDE_DIRS := $(realpath ../libllvm/include/llvm)
HERO_LIBHERO_DIR := $(realpath ../../sw/libhero)
HOST ?=

LLVM_COMPILE_FLAGS_sg2042:= \
       -DLIBOMPTARGET_DEP_LIBFFI_LIBRARIES='/usr/lib64/' \
       -DLIBOMPTARGET_DEP_LIBFFI_INCLUDE_DIRS='/usr/inlude'

LLVM_COMPILE_FLAGS_cva6:= \
       -DLIBOMPTARGET_DEP_LIBFFI_LIBRARIES='$(RISCV)/riscv64-buildroot-linux-gnu/sysroot/usr/lib/' \
       -DLIBOMPTARGET_DEP_LIBFFI_INCLUDE_DIRS='$(RISCV)/riscv64-buildroot-linux-gnu/sysroot/usr/include'

LLVM_COMPILE_FLAGS := \
LLVM_COMPILE_FLAGS= \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_CROSSCOMPILING=True \
	-DCMAKE_SYSTEM_NAME=Linux \
	-DCLANG_TABLEGEN=$(HERO_ROOT)/install/bin/clang-tblgen \
	-DCMAKE_C_FLAGS='-O3 -march=rv64imafdc' \
	-DCMAKE_CXX_FLAGS='-O3 -march=rv64imafdc' \
	-DLLVM_TARGETS_TO_BUILD=RISCV \
	-DLLVM_ENABLE_ASSERTIONS=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLIBOMPTARGET_DEP_LIBFFI_LIBRARIES='$(RISCV)/riscv64-buildroot-linux-gnu/sysroot/usr/lib/' \
	-DLIBOMPTARGET_DEP_LIBFFI_INCLUDE_DIRS='$(RISCV)/riscv64-buildroot-linux-gnu/sysroot/usr/include/' \
	-DLIBOMPTARGET_BUILD_CUDA_PLUGIN=0 \
	-DLIBOMPTARGET_HERO_BUILD=ON \
	-DLIBOMPTARGET_HERO_DEV_TYPE='$(HERO_DEVICE)' \
	-DLIBOMPTARGET_LLVM_INCLUDE_DIRS=$(LIBOMPTARGET_LLVM_INCLUDE_DIRS) \
	-DLIBOMPTARGET_ENABLE_DEBUG=1 \
	-DLIBOMPTARGET_ENABLE_DEBUG=1 \
	$(LLVM_COMPILE_FLAGS_$(HERO_HOST))

# Outputs
all: lib/libomp.so lib/libomptarget.so

lib/libomp.so: compile

build.ninja: configure

# LLVM Cmake flow
configure:
	LLVM_DIR=$(LLVM_DIR) CC=$(CC) CXX=$(CXX) HERO_LIBHERO_DIR=$(HERO_LIBHERO_DIR) HERO_DEV_INC_DIR=$(HERO_LIBHERO_DIR)/include cmake ${LLVM_COMPILE_FLAGS} -G Ninja $(HERO_ROOT)/toolchain/llvm-project/openmp

lib/libomptarget.so: compile
lib/libomp.so: compile
compile: build.ninja
	ninja -j 8 -v
	mkdir -p lib include
	find . -name "*.so" -not -path "./lib/*"     | xargs -I{} cp {} lib
	find . -name "*.a"  -not -path "./lib/*"     | xargs -I{} cp {} lib
	find . -name "*.h"  -not -path "./include/*" | xargs -I{} cp {} include

# Clean everything but Makefile and gitignore
clean:
	find . -not -name Makefile -not -name .gitignore -delete

.PHONY: all configure compile clean
