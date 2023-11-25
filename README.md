# Riscy

Very naive, facerolled implementation of RISC-V on IceBreaker FPGA.

## Linker script

It applies for currently implemented memory layout.

```ld
MEMORY
{
   BRAM (RWX) : ORIGIN = 0x0000, LENGTH = 0x2000  /* 8kB RAM */
}
SECTIONS
{
    everything :
    {
    . = ALIGN(4);
    *.o (.text)
        *(.*)
    } >BRAM
}
```
