"""Рекламні пакети EB3A: чи транслює стан без підключення."""
import asyncio, sys
from bleak import BleakScanner

async def main(t):
    seen = {}
    def cb(d, a):
        if d.name and d.name.startswith("EB3A"):
            key = (tuple(sorted((k, v.hex()) for k, v in a.manufacturer_data.items())),
                   tuple(sorted((k, v.hex()) for k, v in a.service_data.items())))
            if key not in seen:
                seen[key] = 1
                print(f"{d.address} rssi={a.rssi} uuids={a.service_uuids}\n  manuf={dict(key[0])}\n  svc={dict(key[1])}", flush=True)
    async with BleakScanner(cb):
        await asyncio.sleep(t)
    print("унікальних пакетів:", len(seen))

asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 15))
