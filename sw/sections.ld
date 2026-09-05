MEMORY
{
    /* 64KB RAM at address 0x00000000 */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x10000
}

SECTIONS
{
    .text : {
        *(.text)
        *(.text.*)
    } > RAM

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } > RAM

    .data : {
        *(.data)
        *(.data.*)
    } > RAM

    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
