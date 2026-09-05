.section .text
.global _start

_start:
    /* Set the stack pointer to the end of RAM (64KB = 0x10000) */
    li sp, 0x10000

    /* Call main function */
    call main

    /* Infinite loop if main returns */
loop:
    j loop
