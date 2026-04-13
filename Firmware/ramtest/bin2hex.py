"""bin2hex.py – převede output/ramtest.bin na Intel HEX (output/ramtest.hex)."""
import os, sys

BASE_ADDR = 0x6000
src = os.path.join(os.path.dirname(__file__), 'output', 'ramtest.bin')
dst = os.path.join(os.path.dirname(__file__), 'output', 'ramtest.hex')

with open(src, 'rb') as f:
    data = f.read()

FILL = (0x00, 0xFF)   # byty považované za prázdné

records = []
for i in range(0, len(data), 16):
    chunk = data[i:i+16]
    if all(b in FILL for b in chunk):
        continue
    n     = len(chunk)
    addr  = BASE_ADDR + i
    raw   = n + (addr >> 8) + (addr & 0xFF) + sum(chunk)
    csum  = (-raw) & 0xFF
    hex_b = ''.join(f'{b:02X}' for b in chunk)
    records.append(f':{n:02X}{addr:04X}00{hex_b}{csum:02X}')
records.append(':00000001FF')

with open(dst, 'w', newline='\r\n') as f:
    f.write('\n'.join(records) + '\n')

size = os.path.getsize(dst)
print(f'OK: output\\ramtest.hex  [{size} B, {len(records)-1} records]')
