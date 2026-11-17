"""Витягує Modbus-кадри з логу PacketLogger (.pklg): python3 pklg_modbus.py dumps/bluetti.pklg"""

import struct
import sys
from collections import Counter

from probe import crc16

KNOWN = {10: "model", 17: "sn", 23: "ver", 36: "power", 70: "details", 3000: "settings"}


def records(data: bytes):
    """Записи pklg: len(4) ts(8) type(1) payload. Порядок байтів визначаємо за правдоподібністю довжини."""
    i = 0
    while i + 13 <= len(data):
        be = struct.unpack(">I", data[i:i + 4])[0]
        le = struct.unpack("<I", data[i:i + 4])[0]
        n = be if 9 <= be <= 70000 else le
        if not 9 <= n <= 70000 or i + 4 + n > len(data):
            break
        ts_hi, ts_lo = struct.unpack(">II", data[i + 4:i + 12])
        yield ts_hi + ts_lo / 1e6, data[i + 12], data[i + 13:i + 4 + n]
        i += 4 + n


def att_packets(data: bytes):
    """ACL (type 2 = TX, 3 = RX) → складені L2CAP-кадри каналу ATT (CID 4)."""
    partial = {}
    for ts, typ, p in records(data):
        if typ not in (2, 3) or len(p) < 4:
            continue
        hf = struct.unpack("<H", p[:2])[0]
        handle, pb = hf & 0x0FFF, (hf >> 12) & 0x3
        body = p[4:]
        key = (handle, typ)
        if pb == 1:  # продовження
            if key in partial:
                partial[key][1] += body
        else:
            partial[key] = [ts, bytearray(body)]
        ts0, buf = partial.get(key, (None, b""))
        if len(buf) >= 4:
            ln, cid = struct.unpack("<HH", buf[:4])
            if len(buf) >= 4 + ln:
                if cid == 4:
                    yield ts0, "TX" if typ == 2 else "RX", bytes(buf[4:4 + ln])
                partial.pop(key, None)


def modbus(frame: bytes):
    return len(frame) >= 5 and frame[0] == 1 and crc16(frame[:-2]) == int.from_bytes(frame[-2:], "little")


def main(path):
    data = open(path, "rb").read()
    reads, writes, other = Counter(), Counter(), Counter()
    rx_buf = bytearray()
    for ts, d, att in att_packets(data):
        op = att[0]
        if d == "TX" and op in (0x12, 0x52) and len(att) >= 3:  # Write Request / Command
            handle, val = struct.unpack("<H", att[1:3])[0], att[3:]
            if modbus(val) and val[1] == 3:
                reads[(struct.unpack(">H", val[2:4])[0], struct.unpack(">H", val[4:6])[0])] += 1
            elif modbus(val) and val[1] == 6:
                writes[(struct.unpack(">H", val[2:4])[0], struct.unpack(">H", val[4:6])[0])] += 1
            else:
                other[(f"write h=0x{handle:04x}", val[:12].hex(" "))] += 1
        elif d == "RX" and op == 0x1B:  # Notification
            handle = struct.unpack("<H", att[1:3])[0]
            if not att[3:4] == b"\x01":
                other[(f"notify h=0x{handle:04x}", att[3:15].hex(" "))] += 1

    print("== FC03 читання (старт, кількість) × разів")
    for (a, n), c in sorted(reads.items()):
        tag = next((v for k, v in KNOWN.items() if k == a), "")
        print(f"  {a:5}..{a + n - 1:<5} ×{c:<4} {tag}")
    print("== FC06 записи (адреса = значення) × разів")
    for (a, v), c in sorted(writes.items()):
        print(f"  {a} = {v} ×{c}")
    print("== Інше (не Modbus / інші характеристики)")
    for (k, v), c in other.most_common(30):
        print(f"  {k}  {v}  ×{c}")


if __name__ == "__main__":
    main(sys.argv[1])
