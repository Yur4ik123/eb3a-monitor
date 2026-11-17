"""Перелік GATT-сервісів і читання читабельних характеристик."""
import asyncio, sys
from bleak import BleakClient

async def main(addr):
    async with BleakClient(addr) as c:
        for s in c.services:
            print(f"SERVICE {s.uuid} {s.description}")
            for ch in s.characteristics:
                line = f"  CHAR {ch.uuid} {ch.description} props={ch.properties}"
                if "read" in ch.properties:
                    try:
                        v = await c.read_gatt_char(ch)
                        line += f" value={v.hex()} {v.decode(errors='replace')!r}"
                    except Exception as e:
                        line += f" read_err={e!r}"
                print(line)

asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "<UUID>"))
