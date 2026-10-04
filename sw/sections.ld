MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x10000
}

SECTIONS
{
    .text : {
        *(.text.init)
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
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _ebss = .;
    } > RAM
}
