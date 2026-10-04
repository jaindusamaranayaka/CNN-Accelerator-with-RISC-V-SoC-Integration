.section .text.init
.global _start

_start:
    li   sp, 0x10000

    la   a0, _sbss
    la   a1, _ebss
bss_loop:
    bgeu a0, a1, bss_done
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    bss_loop
bss_done:

    call main

halt:
    j halt
