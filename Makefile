PROJ = riscv32i

PIN_DEF = icebreaker.pcf
DEVICE = up5k
PACKAGE = sg48

prog: iceprog

include ./main.mk
