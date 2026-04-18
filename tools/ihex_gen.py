#!/usr/bin/env python3
"""
ihex_gen.py — Convert raw binary to Intel HEX

Usage:
    python ihex_gen.py <file.bin> <start_addr_hex> [out.hex]

    Third argument is the output file (recommended on Windows — PowerShell
    redirect '>' writes UTF-16 which breaks the Intel HEX parser).
    If omitted, writes plain ASCII to stdout.

Examples:
    python ihex_gen.py hello.bin     3000 hello.hex
    python ihex_gen.py vera_test.bin 3100 vera_test.hex

Intel HEX format:  :LLAAAATT[DD...]CC
    LL   = byte count in this record
    AAAA = 16-bit load address
    TT   = record type  (00=data, 01=EOF, 04=extended linear address)
    DD   = data bytes
    CC   = two's complement checksum of LL+AAAA+TT+DD bytes
"""

import sys
import os

BYTES_PER_LINE = 16


def checksum(data: list) -> int:
    return (~sum(data) + 1) & 0xFF


def make_record(addr: int, record_type: int, data: list) -> str:
    ll = len(data)
    body = [ll, (addr >> 8) & 0xFF, addr & 0xFF, record_type] + data
    cc = checksum(body)
    return ":{:02X}{:04X}{:02X}{}{:02X}".format(
        ll, addr, record_type,
        "".join("{:02X}".format(b) for b in data),
        cc,
    )


def make_extended_addr(segment: int) -> str:
    data = [(segment >> 8) & 0xFF, segment & 0xFF]
    return make_record(0, 0x04, data)


def bin_to_ihex(data: bytes, start: int) -> list:
    lines = []
    current_segment = -1
    offset = 0
    total = len(data)

    while offset < total:
        addr = start + offset
        segment = addr >> 16

        if segment != current_segment:
            lines.append(make_extended_addr(segment))
            current_segment = segment

        chunk_size = min(BYTES_PER_LINE, total - offset)
        chunk = list(data[offset:offset + chunk_size])
        lines.append(make_record(addr & 0xFFFF, 0x00, chunk))
        offset += chunk_size

    lines.append(make_record(0, 0x01, []))
    return lines


def main():
    if len(sys.argv) < 3:
        print("Usage: ihex_gen.py <file.bin> <start_hex> [out.hex]", file=sys.stderr)
        sys.exit(1)

    bin_path = sys.argv[1]
    out_path = sys.argv[3] if len(sys.argv) >= 4 else None

    try:
        start = int(sys.argv[2], 16)
    except ValueError:
        print(f"Error: invalid hex address '{sys.argv[2]}'", file=sys.stderr)
        sys.exit(1)

    try:
        with open(bin_path, "rb") as f:
            data = f.read()
    except OSError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if not data:
        print("Error: input file is empty", file=sys.stderr)
        sys.exit(1)

    lines = bin_to_ihex(data, start)
    content = "\r\n".join(lines) + "\r\n"

    if out_path:
        with open(out_path, "w", encoding="ascii", newline="") as f:
            f.write(content)
        print(f"OK: {out_path}  ({len(data)} B → {len(lines)} records)", file=sys.stderr)
    else:
        # stdout — na Windows přepni na ASCII aby PowerShell redirect nepřidal BOM
        if sys.platform == "win32":
            sys.stdout = open(sys.stdout.fileno(), mode="w", encoding="ascii",
                              errors="replace", closefd=False, newline="")
        for line in lines:
            print(line)


if __name__ == "__main__":
    main()
