#include "sd.h"
#include "spi.h"
#include "acia.h"
#include "jumptable.h"

unsigned char sdpage[512];
long int sd_currentsector;
 char cmd0[] = {0x40,0x00,0x00,0x00,0x00,0x95  };
 char cmd8[] = {0x48,0x00,0x00,0x01,0xAA,0x87  };
 char cmd55[] = {0x77,0x00,0x00,0x00,0x00,0x01  };
 char cmd41[] = {0x69,0x40,0x00,0x00,0x00,0x01  };


void sd_check(char c){
  if (c == 0x01) acia_print_nl("Karta nalezena");
  else acia_print_nl("Karta nenalezena");
}

void wstart(){
  spi_begin(1);
}

void stop(){
  spi_end();
}
void SD_INIT(){
  int i;
  char c;
  char x;
  acia_print_nl("Inicializace SD");
  for (i = 0;i<=19;++i){
    spi_write(0xFF);
  }
    sd_check(SD_send_command(cmd0));
    c = SD_send_command(cmd8);

    if (c == 0x01) acia_print_nl("SD v2");
    if (c == 0x05) acia_print_nl("SD v1");
    while (c != 0x00){
      c = SD_send_command(cmd55);
      if (c != 0x01) {
        acia_print_nl("CHYBA SD");
        break;
      }
      c = SD_send_command(cmd41);
    }

    acia_print_nl("Karta Inicializovana");

}

char sd_readbyte(){
  return spi_read(0xFF);
}

void sd_writebyte(char c){
  spi_write(c);
}

void sd_begin(){
  spi_begin(2);
}

void sd_end(){
  spi_end();
}

char SD_send_command(char *cmndn){
  int i;
  char c;
  c= 0xff;
  sd_begin();

  for (i = 0; i <= 5; ++i){
    sd_writebyte(cmndn[i]);
  }

  while (c == 0xFF){
    c = sd_readbyte();
  }


  sd_end();
  return c;
}





#define CMD17                   17
#define CMD17_CRC               0x00
#define SD_MAX_READ_ATTEMPTS    1563
