/*
 * MEDS-S1 M-07 temporary bare-metal CRT0
 *
 * Purpose:
 *   Provide minimal startup for CoreMark under Spike while the
 *   official MEDS-S1 BSP/CRT0 is not yet available.
 *
 * Temporary memory model:
 *   Spike memory:
 *       base = 0x00010000
 *       size = 0x01000000
 *       top  = 0x01010000
 *
 * Therefore the temporary stack starts at:
 *       0x01010000
 *
 * This must later be replaced/adapted to the official MEDS-S1 BSP.
 */

    .section .text.startup
    .align  2
    .globl  _start
    .type   _start, @function

_start:

    /*
     * ------------------------------------------------------------
     * 1. Initialize stack pointer
     * ------------------------------------------------------------
     *
     * Spike memory ends at:
     *
     *   0x00010000 + 0x01000000 = 0x01010000
     *
     * Stack grows downward.
     */
    li      sp, 0x01010000

    /*
     * ------------------------------------------------------------
     * 2. Initialize global pointer
     * ------------------------------------------------------------
     */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /*
     * ------------------------------------------------------------
     * 3. Clear BSS
     * ------------------------------------------------------------
     */
    la      t0, __bss_start
    la      t1, __BSS_END__

    beq     t0, t1, 2f

1:
    sd      zero, 0(t0)
    addi    t0, t0, 8
    bltu    t0, t1, 1b

2:

    /*
     * ------------------------------------------------------------
     * 4. Initialize Newlib
     * ------------------------------------------------------------
     *
     * This executes constructors/init functions required by libc.
     */
    call    __libc_init_array

    /*
     * ------------------------------------------------------------
     * 5. Enter CoreMark main()
     * ------------------------------------------------------------
     *
     * CoreMark does not require argc/argv.
     */
    call    main

    /*
     * ------------------------------------------------------------
     * 6. Terminate through our Spike HTIF _exit()
     * ------------------------------------------------------------
     *
     * main() return value is already in a0.
     */
    call    _exit

    /*
     * ------------------------------------------------------------
     * 7. Safety loop
     * ------------------------------------------------------------
     */
3:
    wfi
    j       3b

    .size _start, .-_start
