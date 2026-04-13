/*
 * P65 Minimal Bootloader
 *
 * Zahrnuje pouze:
 *   - Seriovy port ACIA (19200 Bd)
 *   - WozMon / EWOZ monitor (prikaz 'm')
 *   - Seriovy bootloader - raw binary do RAM $6000 (prikaz 'w')
 *   - Skok na RAM $6000 (prikaz 's')
 *   - Soft restart (Ctrl+R = 0x12)
 *
 * Zadna zavislost na VDP, PS2, SPI, SD, Gameduino, SAA1099.
 */

#include <stdlib.h>

#include "utils.h"
#include "jumptable.h"
#include "ewoz.h"
#include "acia.h"

/* Prazdne handlery - NMI/IRQ pouzity jen pro interni ucely cc65 runtime */
void IRQ_Event(void) {}
void NMI_Event(void) {}

void main(void) {
    char c;
    const char *banner = "P65 Minimal Bootloader";
    const char *m_w    = "  w - zapis binarniho programu do RAM ($6000)";
    const char *m_m    = "  m - EWOZ / WozMon monitor";
    const char *m_s    = "  s - spustit program z $6000";

    INTDI();
    init_vec();
    irq_init();
    nmi_init();
    acia_init();

    acia_print_nl(banner);
    acia_print_nl(m_w);
    acia_print_nl(m_m);
    acia_print_nl(m_s);

    while (1) {
        c = get_input();

        switch (c) {

            case 'm':
                EWOZ();
                break;

            case 'w':
                acia_print_nl("Cekam na binarni data pro zapis do RAM...");
                acia_print_nl("(odeslej presne 8192 bajtu, posledni 2B na offsetu $1FFC = start adresa)");
                write_to_RAM();
                break;

            case 's':
                acia_print_nl("Spoustim z $6000...");
                start_ram();
                break;

            case 0x12:          /* Ctrl+R - soft restart */
                RST();
                break;

            default:
                break;
        }
    }
}
