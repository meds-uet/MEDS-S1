# MEDS-S1 M-07 CoreMark RISC-V bare-metal port
#
# Toolchain:
#   GCC 16.1.0
#   Binutils 2.46
#   Newlib 4.6.0
#
# CoreMark benchmark sources are not modified.
# Only the core_portme* files are target-specific.

OUTFLAG = -o

CC = riscv64-unknown-elf-gcc
LD = riscv64-unknown-elf-gcc
AS = riscv64-unknown-elf-as

# Baseline benchmark optimization.
# Additional flags are supplied through XCFLAGS.
PORT_CFLAGS = -O2 -march=rv64imac_zicsr_zifencei_zicbom_zicboz -mabi=lp64

FLAGS_STR = "$(PORT_CFLAGS) $(XCFLAGS) $(XLFLAGS) $(LFLAGS_END)"

CFLAGS = $(PORT_CFLAGS) \
         -I$(PORT_DIR) \
         -I. \
         -DFLAGS_STR=\"$(FLAGS_STR)\"

SEPARATE_COMPILE = 1

OBJOUT = -o
OFLAG  = -o
COUT   = -c

LFLAGS = $(PORT_CFLAGS) -nostartfiles

# Keep linker flags at the end of the command.
LFLAGS_END =

ASFLAGS =

PLATFORM_DIR = ../platform/barebones_riscv

PORT_SRCS = $(PORT_DIR)/core_portme.c \
            $(PORT_DIR)/ee_printf.c \
            $(PLATFORM_DIR)/crt0.S

PORT_OBJS = core_portme.o ee_printf.o crt0.o

vpath %.c $(PORT_DIR)
vpath %.s $(PORT_DIR)
#
# Bare-metal MEDS execution hooks.
#
# These are intentionally kept as commands rather than pretending that
# a host executable can be executed by Linux.
#
LOAD = echo "MEDS LOAD: $(OUTFILE)"

RUN = spike \
      --isa=RV64IMAC_Zicsr_Zicntr_Zifencei_Zicbom_Zicboz \
      -m0x10000:0x1000000

OEXT = .o
EXE  = .elf

$(OPATH)%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

./crt0.o : $(PLATFORM_DIR)/crt0.S
	$(CC) $(CFLAGS) $(XCFLAGS) -c $< -o $@

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.s
	$(AS) $(ASFLAGS) $< $(OBJOUT) $@

.PHONY : port_prebuild port_postbuild port_prerun port_postrun \
         port_preload port_postload

port_pre% port_post% :

OPATH = ./
MKDIR = mkdir -p
