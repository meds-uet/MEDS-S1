# ================================================================
# Dhrystone 2.1 - MEDS-S1 M-07 bare-metal harness
# ================================================================

CC      = riscv64-unknown-elf-gcc
SPIKE   = spike

TARGET  = dhrystone.elf

PLATFORM_DIR = ../platform/barebones_riscv

CFLAGS = -O2 \
         -DMEDS_RISCV \
         -march=rv64imac_zicsr_zifencei_zicbom_zicboz \
         -mabi=lp64 \
         -Wno-implicit-function-declaration \
         -Wno-old-style-definition

LDFLAGS = -nostartfiles

DHRY_RUNS ?= 10000

SPIKE_ISA = RV64IMAC_Zicsr_Zicntr_Zifencei_Zicbom_Zicboz
SPIKE_MEM = 0x10000:0x1000000

SRCS = dhry_1.c \
       dhry_2.c \
       $(PLATFORM_DIR)/syscalls.c \
       $(PLATFORM_DIR)/crt0.S

OBJS = dhry_1.o \
       dhry_2.o \
       syscalls.o \
       crt0.o

.PHONY: all compile run clean

all: $(TARGET)

compile: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

dhry_1.o: dhry_1.c dhry.h
	$(CC) $(CFLAGS) -DDHRY_RUNS=$(DHRY_RUNS) -c $< -o $@

dhry_2.o: dhry_2.c dhry.h
	$(CC) $(CFLAGS) -c $< -o $@

syscalls.o: $(PLATFORM_DIR)/syscalls.c
	$(CC) $(CFLAGS) -c $< -o $@

crt0.o: $(PLATFORM_DIR)/crt0.S
	$(CC) $(CFLAGS) -c $< -o $@

run: $(TARGET)
	$(SPIKE) \
		--isa=$(SPIKE_ISA) \
		-m$(SPIKE_MEM) \
		./$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET)
