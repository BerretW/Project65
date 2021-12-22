
extern void GD_Begin();
extern void GD_End();
extern void GD_Init();
extern char GD_Test();
extern void GD_xhide();
extern void _start(unsigned addr);
extern void _wstart(unsigned addr);
extern void _end(void);
extern char GD_rd(unsigned addr);
extern void GD_wr(unsigned addr, char v);

extern void GD_res_cur();
extern void GD_set_cur(char x, char y);
extern void GD_Print(const char *s);
extern void GD_Print_char(char c);
extern void GD_Printnl(const char *s);
extern void GD_NewLine();
extern void GD_cursor_LEFT();
extern void GD_cursor_RIGHT();
extern void GD_cursor_UP();
extern void GD_cursor_DOWN();
extern void GD_background(char b);
extern void CLR_txt();
extern void CLR_scr();

extern void GD_fill(unsigned addr, char v, unsigned count);
extern void GD_wr16(unsigned addr, unsigned v);
extern unsigned char GD_rd16(unsigned addr);
extern void GD_sprite(char spr, int x, int y, char image, char palette, char rot, char jk);
extern void GD_setpal(char pal, unsigned rgb);
extern void GD_ascii();

extern void GD_copy(unsigned addr, char *src, int count);

#define RGB(r,g,b) ((((r) >> 3) << 10) | (((g) >> 3) << 5) | ((b) >> 3))
#define COLS          50
#define ROWS          37

#define TRANSPARENT (1 << 15) // transparent for chars and sprites

#define RAM_PIC     0x0000    // Screen Picture, 64 x 64 = 4096 bytes
#define RAM_CHR     0x1000    // Screen Characters, 256 x 16 = 4096 bytes
#define RAM_PAL     0x2000    // Screen Character Palette, 256 x 8 = 2048 bytes

#define IDENT         0x2800
#define REV           0x2801
#define FRAME         0x2802
#define VBLANK        0x2803
#define SCROLL_X      0x2804
#define SCROLL_Y      0x2806
#define JK_MODE       0x2808
#define J1_RESET      0x2809
#define SPR_DISABLE   0x280a
#define SPR_PAGE      0x280b
#define IOMODE        0x280c

#define BG_COLOR      0x280e
#define SAMPLE_L      0x2810
#define SAMPLE_R      0x2812

#define MODULATOR     0x2814
#define VIDEO_MODE    0x2815

#define MODE_800x600_72   0
#define MODE_800x600_60   1

#define SCREENSHOT_Y  0x281e

#define PALETTE16A 0x2840   // 16-color palette RAM A, 32 bytes
#define PALETTE16B 0x2860   // 16-color palette RAM B, 32 bytes
#define PALETTE4A  0x2880   // 4-color palette RAM A, 8 bytes
#define PALETTE4B  0x2888   // 4-color palette RAM A, 8 bytes
#define COMM       0x2890   // Communication buffer
#define COLLISION  0x2900   // Collision detection RAM, 256 bytes
#define VOICES     0x2a00   // Voice controls
#define J1_CODE    0x2b00   // J1 coprocessor microcode RAM
#define SCREENSHOT 0x2c00   // screenshot line RAM

#define RAM_SPR     0x3000    // Sprite Control, 512 x 4 = 2048 bytes
#define RAM_SPRPAL  0x3800    // Sprite Palettes, 4 x 256 = 2048 bytes
#define RAM_SPRIMG  0x4000    // Sprite Image, 64 x 256 = 16384 bytes
