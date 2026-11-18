"""Знімки живих регістрів EB3A і їх порівняння.

  snap.py take <label> [address]   -> snaps/<label>.json
  snap.py diff <a> <b>             -> змінені регістри
"""

import asyncio
import os
import json
import sys
from datetime import datetime
from pathlib import Path

from bleak import BleakClient

from probe import NOTIFY_UUID, WRITE_UUID, crc16, read_cmd

DEFAULT_ADDRESS = os.environ.get("EB3A_ADDRESS", "")  # UUID з bluetti-scan
RANGES = [(10, 210), (3000, 80)]
CHUNK = 10
SNAPS = Path(__file__).parent / "snaps"

KNOWN = {
    10: "device_type", 17: "sn", 23: "ver_arm", 25: "ver_dsp",
    36: "dc_input_power", 37: "ac_input_power", 38: "ac_output_power", 39: "dc_output_power",
    41: "generated_kwh_x10", 43: "battery_soc", 44: "dc_in_present", 45: "ac_in_present", 46: "pv_charging", 47: "ups_active", 48: "ac_out_on", 49: "dc_out_on",
    53: "charge_state", 54: "mppt_state?", 60: "over_temp", 91: "pack_count", 77: "ac_input_voltage", 86: "dc_input_voltage", 217: "ac_mirror", 218: "dc_mirror",
    3007: "ctrl_ac", 3008: "ctrl_dc", 3034: "led_mode", 3060: "power_off", 3061: "eco_2?",
    3063: "eco", 3064: "eco_time", 3065: "charging_mode", 3066: "power_lifting",
}


async def read_block(client, buf, got, addr, count):
    buf.clear()
    got.clear()
    await client.write_gatt_char(WRITE_UUID, read_cmd(addr, count), response=True)
    await asyncio.wait_for(got.wait(), 5)
    frame = bytes(buf[: 5 + buf[2]])
    if crc16(frame[:-2]) != int.from_bytes(frame[-2:], "little"):
        raise ValueError(f"CRC @ {addr}")
    return [int.from_bytes(frame[3 + i : 5 + i], "big") for i in range(0, frame[2], 2)]


async def take(label: str, address: str):
    buf = bytearray()
    got = asyncio.Event()

    def on_notify(_, data: bytearray):
        buf.extend(data)
        if len(buf) >= 3 and buf[1] & 0x80:  # Modbus exception
            got.set()
        elif len(buf) >= 3 and len(buf) >= 5 + buf[2]:
            got.set()

    regs: dict[int, int] = {}
    async with BleakClient(address) as client:
        await client.start_notify(NOTIFY_UUID, on_notify)
        for start, length in RANGES:
            for addr in range(start, start + length, CHUNK):
                for attempt in range(3):
                    try:
                        vals = await read_block(client, buf, got, addr, CHUNK)
                        regs.update({addr + i: v for i, v in enumerate(vals)})
                        break
                    except (asyncio.TimeoutError, ValueError, IndexError) as e:
                        print(f"  {addr}: retry {attempt + 1} ({e!r})")

    SNAPS.mkdir(exist_ok=True)
    path = SNAPS / f"{label}.json"
    path.write_text(json.dumps({"label": label, "time": datetime.now().isoformat(timespec="seconds"),
                                "regs": regs}, indent=1))
    print(f"{path.name}: {len(regs)} регістрів")
    for a, v in regs.items():
        if v and a in KNOWN:
            print(f"  {a:5} {KNOWN[a]:18} {v}")


def load(label: str) -> dict[int, int]:
    return {int(k): v for k, v in json.loads((SNAPS / f"{label}.json").read_text())["regs"].items()}


def diff(a: str, b: str):
    ra, rb = load(a), load(b)
    changed = [k for k in sorted(set(ra) | set(rb)) if ra.get(k) != rb.get(k)]
    print(f"{a} -> {b}: змінено {len(changed)}")
    for k in changed:
        va, vb = ra.get(k), rb.get(k)
        print(f"  {k:5} {KNOWN.get(k, '?'):18} {va} -> {vb}  (0x{va or 0:04x} -> 0x{vb or 0:04x})")


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["take", label, *rest]:
            asyncio.run(take(label, rest[0] if rest else DEFAULT_ADDRESS))
        case ["diff", a, b]:
            diff(a, b)
        case _:
            print(__doc__)
