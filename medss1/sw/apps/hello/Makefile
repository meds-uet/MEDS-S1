# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
#
# Per-application Makefile.  Copy this directory to start a new app.
PROG    := hello
BSP     := ../../bsp
CROSS   ?= riscv64-unknown-elf-
CFLAGS  := -march=rv64imac_zicsr_zifencei -mabi=lp64 -Os -g -Wall -Wextra \
           -ffunction-sections -fdata-sections -I$(BSP)/include
LDFLAGS := -T$(BSP)/link.ld -nostartfiles -Wl,--gc-sections

SRCS := main.c
OBJS := $(SRCS:.c=.o)

all: $(PROG).elf

$(PROG).elf: $(OBJS)
	$(CROSS)gcc $(CFLAGS) $(LDFLAGS) -o $@ $^ -lc -lgcc

%.o: %.c
	$(CROSS)gcc $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(PROG).elf

.PHONY: all clean
