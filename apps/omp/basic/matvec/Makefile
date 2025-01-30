# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Cyril Koenig <cykoenig@iis.ee.ethz.ch>

DEVICES ?= snitch_cluster

SRCDIR          = $(realpath $(HERO_ROOT)/apps/omp)

CSRCS_HOST      =
CSRCS           = basic/matvec/main.c

CFLAGS   += -O3 -g
# CFLAGS   += -v -debug -save-temps=obj

-include ../../common/default.mk
