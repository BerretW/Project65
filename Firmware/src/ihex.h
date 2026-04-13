/* ihex.h – Intel HEX loader
 *
 * Vraci: 0   = OK
 *        $FF = preruseno ESC
 *        1..254 = pocet zaznamu s chybou checksumu
 */
extern unsigned char ihex_load(void);
