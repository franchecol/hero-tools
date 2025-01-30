# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>
#
# This file builds LLVM runtime librairies on RV64 as they are required
# to build libomp.so on RV64

HERO_ROOT ?= $(realpath ../..)

# Toolchain
CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
CXX     := $(CROSS_COMPILE)g++
AR      := $(CROSS_COMPILE)ar
OBJDUMP := $(CROSS_COMPILE)objdump

LLVM_DIR := $(HERO_INSTALL)/lib/cmake/llvm
LIBOMPTARGET_LLVM_INCLUDE_DIRS := $(HERO_INSTALL)/include/llvm

# Note LLVM_TABLEGEN may be replaced by LLVM_NATIVE_TOOL_DIR in newer LLVM

LLVM_COMPILE_FLAGS= \
	-DCMAKE_BUILD_TYPE=Debug \
	-DCMAKE_CROSSCOMPILING=True \
	-DCMAKE_SYSTEM_NAME=Linux \
	-DLLVM_TABLEGEN=$(HERO_ROOT)/install/bin/llvm-tblgen \
	-DCLANG_TABLEGEN=$(HERO_ROOT)/install/bin/clang-tblgen \
	-DLLVM_DEFAULT_TARGET_TRIPLE=riscv64-unknown-linux-gnu \
	-DCMAKE_C_FLAGS='-march=rv64imafdc' \
	-DCMAKE_CXX_FLAGS='-march=rv64imafdc' \
	-DLLVM_TARGETS_TO_BUILD=RISCV \
	-DLLVM_TARGET_ARCH=riscv64 \
	-DLLVM_ENABLE_ASSERTIONS=OFF \
	-DLLVM_BUILD_TOOLS=OFF \
	-DLLVM_INCLUDE_TESTS=OFF

all: compile

configure:
	CC=$(CC) CXX=$(CXX) LLVM_BUILD_TOOLS=OFF cmake $(LLVM_COMPILE_FLAGS) -G Ninja $(HERO_ROOT)/toolchain/llvm-project/llvm

build.ninja: configure

compile: build.ninja
	ninja -j `nproc`
# Bin takes a lost of space for nothing
	rm -rf bin

# Clean everything but Makefile and gitignore
clean:
	find . -not -name Makefile -not -name .gitignore -delete

.PHONY: all configure compile clean
