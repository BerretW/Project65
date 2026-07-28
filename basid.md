# P65 BASIC — syntax a manuál

Tento dokument popisuje syntaxi a chování BASICu implementovaného v [Firmware/src/os/appartus_basic.asm](Firmware/src/os/appartus_basic.asm).

## 1. Co je to za BASIC?

P65 BASIC je minimalistický line-oriented BASIC pro Project65 SBC.

- pracuje s celými čísly, 16bitovými a znaménkovými
- používá proměnné A až Z
- program je ukládán do paměti RAM jako seznam řádků
- podporuje direktivní příkazy i programové příkazy

## 2. Základní pravidla

### 2.1 Čísla

- desetinná čísla nejsou podporována
- všechny hodnoty jsou 16-bitové signed integery
- záporná čísla jsou podporována
- hexadecimální konstanta se zapisuje s předponou `$`

Příklady:

- `10`
- `-5`
- `$1F`
- `$FF00`

### 2.2 Proměnné

Proměnné jsou pojmenovány jedním písmenem `A` až `Z`.

Příklady:

- `A = 10`
- `B = A + 5`

### 2.3 Programové řádky

Každý řádek programu začíná číslem řádku:

```basic
10 PRINT "Ahoj"
20 END
```

Řádkové číslo může být zadáno jako desetinné číslo nebo hexadecimální konstanta.

## 3. Direktivní příkazy

Tyto příkazy se spouštějí přímo z promptu, nikoli jako programové řádky.

### 3.1 NEW

Smaže celý program.

```basic
NEW
```

### 3.2 LIST

Vypíše uložený program.

```basic
LIST
```

### 3.3 RUN

Spustí program od prvního řádku.

```basic
RUN
```

### 3.4 SAVE

Uloží program do RAMDisku pod jméno.

```basic
SAVE "HELLO"
```

- název může mít maximálně 8 znaků
- uložení se provádí do RAMDisku

### 3.5 LOAD

Načte program z RAMDisku.

```basic
LOAD "HELLO"
```

### 3.6 BYE

Vrátí se zpět do shellu OS.

```basic
BYE
```

## 4. Programové příkazy

### 4.1 REM

Komentář. Vše za `REM` je ignorováno.

```basic
10 REM Toto je komentář
20 PRINT 1
```

### 4.2 PRINT

Vypíše text nebo hodnotu výrazu.

```basic
10 PRINT "HELLO"
20 PRINT A
30 PRINT 10 + 5
```

Více položek lze oddělit znakem `;` nebo `,`.

```basic
10 PRINT "A=", A
20 PRINT 1; 2; 3
```

- `;` znamená bez nového řádku mezi položkami
- `,` vypíše mezery mezi položkami

### 4.3 INPUT

Načte vstup z konzole a uloží do proměnné.

```basic
10 INPUT A
```

Volitelně lze zadat prompt:

```basic
10 INPUT "Zadej cislo: ", A
```

### 4.4 Přiřazení

Podporováno je `LET` i implicitní přiřazení.

```basic
10 LET A = 10
20 B = A + 5
```

### 4.5 IF ... THEN

Podmínka se vyhodnotí a pokud je pravdivá, skočí na zadaný řádek.

```basic
10 IF A > 0 THEN 30
20 PRINT "NE"
30 PRINT "ANO"
```

Poznámka: `THEN` je nepovinný v implementaci, ale doporučený zápis je s ním.

### 4.6 FOR ... TO ... STEP ...

Smyčka s počítadlem.

```basic
10 FOR A = 1 TO 5
20 PRINT A
30 NEXT
```

Volitelný krok:

```basic
10 FOR A = 0 TO 10 STEP 2
20 PRINT A
30 NEXT
```

### 4.7 NEXT

Konec smyčky `FOR`.

```basic
10 FOR A = 1 TO 3
20 PRINT A
30 NEXT
```

### 4.8 WHILE ... WEND

Podmíněná smyčka.

```basic
10 A = 0
20 WHILE A < 3
30 PRINT A
40 A = A + 1
50 WEND
```

### 4.9 GOTO

Nepodmíněný skok na jiný řádek.

```basic
10 GOTO 30
20 PRINT "Tento řádek se nepřeskočí"
30 PRINT "Skok funguje"
```

### 4.10 GOSUB / RETURN

Volání podprogramu.

```basic
10 GOSUB 30
20 END
30 PRINT "Podprogram"
40 RETURN
```

### 4.11 END

Ukončí běh programu.

```basic
10 PRINT "Konec"
20 END
```

### 4.12 POKE

Zapíše hodnotu do paměti na zadanou adresu.

```basic
10 POKE 40960, 255
```

## 5. Výrazy

### 5.1 Operátory

Podporované operátory:

- `+` sčítání
- `-` odčítání / unární negace
- `*` násobení
- `/` dělení

### 5.2 Porovnání

Podporované porovnání:

- `=` rovnost
- `<>` nerovnost
- `<` menší
- `>` větší
- `<=` menší nebo rovno
- `>=` větší nebo rovno

Porovnání vrací `0` pro nepravdu a `1` pro pravdu.

### 5.3 Závorky

```basic
10 PRINT (2 + 3) * 4
```

### 5.4 PEEK

Načte bajt z paměti na dané adrese.

```basic
10 PRINT PEEK(1024)
```

Poznámka: `PEEK` vrací 8bitovou hodnotu a horní byte je nulový.

## 6. Priorita operátorů

Priorita je následující (od nejnižší po nejvyšší):

1. porovnání
2. `+` a `-`
3. `*` a `/`
4. unární `-` a primární výrazy

## 7. Chyby a hlášky

Při chybě BASIC vypíše jednu z těchto hlášek:

- `?SYNTAX ERROR` — špatný syntax
- `?UNDEFINED LINE` — neexistující řádek pro `GOTO`, `GOSUB`, `IF`
- `?FOR OVF` — přetečení zásobníku `FOR`
- `?NEXT WO FOR` — `NEXT` bez odpovídajícího `FOR`
- `?WHILE OVF` — přetečení zásobníku `WHILE`
- `?WEND WO WHILE` — `WEND` bez odpovídajícího `WHILE`
- `?GOSUB OVF` — přetečení zásobníku `GOSUB`
- `?RET WO GOSUB` — `RETURN` bez `GOSUB`
- `?DIV/0` — dělení nulou
- `?PROG FULL` — programová paměť je plná
- `?Save err.` — chyba při ukládání
- `?Not found.` — soubor nenalezen při `LOAD`

## 8. Příklad programu

```basic
10 REM Jednoduchý program
20 INPUT "Zadej cislo: ", A
30 IF A > 0 THEN 60
40 PRINT "Cislo je zaporne"
50 GOTO 70
60 PRINT "Cislo je kladne"
70 END
```

## 9. Praktické poznámky

- BASIC je určený pro jednoduché skripty a testování
- není to plnohodnotný moderní BASIC
- je vhodný pro práci s pamětí, jednoduchými rutinnami a obsluhou vstupu/výstupu
- programy jsou uloženy jako textové řádky s číslem řádku a nulovým terminátorem

## 10. Shrnutí

Nejčastější konstrukce jsou:

```basic
10 PRINT "Text"
20 INPUT A
30 IF A > 0 THEN 50
40 GOTO 60
50 FOR A = 1 TO 5
60 NEXT
70 WHILE A < 3
80 WEND
90 END
```
