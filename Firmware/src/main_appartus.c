/*
 * main_appartus.c - AppartusOS C entry point
 *
 * Minimal C glue: initialises hardware then hands off to the ASM shell.
 * _os_main() never returns.
 *
 * Interrupt handlers are defined in appartus_shell.asm.
 */

#include "utils.h"
#include "jumptable.h"
#include "acia.h"

extern void __fastcall__ os_main(void);

void main(void) {
    INTDI();
    init_vec();
    acia_init();
    os_main();      /* defined in appartus_shell.asm – never returns */
}
