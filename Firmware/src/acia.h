extern void acia_init();
extern void __fastcall__ acia_putc(char c);
extern void __fastcall__ acia_puts(const char * s);
extern void acia_put_newline();
extern char acia_getc();
extern char acia_scan();
extern void acia_print_nl(const char * s);

extern void __fastcall__ acia_gets(char * buffer, unsigned char n);
