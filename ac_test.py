"""Разова перевірка запису AC (3007): вимк -> перевірка -> увімк -> перевірка."""
import asyncio, time
from bleak import BleakClient
from probe import NOTIFY_UUID, WRITE_UUID, crc16, read_cmd
from snap import DEFAULT_ADDRESS

def write_cmd(addr, val):
    b = bytes([1, 6]) + addr.to_bytes(2, "big") + val.to_bytes(2, "big")
    return b + crc16(b).to_bytes(2, "little")

async def main():
    buf = bytearray(); got = asyncio.Event()
    def cb(_, d):
        buf.extend(d)
        if len(buf) >= 3 and (buf[1] & 0x80 or (buf[1] == 6 and len(buf) >= 8) or (buf[1] == 3 and len(buf) >= 5 + buf[2])):
            got.set()
    async def req(cmd):
        buf.clear(); got.clear()
        await c.write_gatt_char(WRITE_UUID, cmd, response=True)
        await asyncio.wait_for(got.wait(), 5)
        return bytes(buf)
    async def regs():
        a = await req(read_cmd(40, 10)); b = await req(read_cmd(3000, 10)); m = await req(read_cmd(210, 10))
        v = lambda f, i: int.from_bytes(f[3 + 2 * i:5 + 2 * i], "big")
        return {"48_ac_on": v(a, 8), "3007": v(b, 7), "217": v(m, 7)}
    async with BleakClient(DEFAULT_ADDRESS) as c:
        await c.start_notify(NOTIFY_UUID, cb)
        print("before", await regs())
        for val in (0, 1):
            t0 = time.time()
            r = await req(write_cmd(3007, val))
            print(f"write 3007={val}: {'ok' if r[:8] == write_cmd(3007, val) else r.hex(' ')} {int((time.time()-t0)*1000)}ms")
            for _ in range(10):
                s = await regs()
                if s["48_ac_on"] == val: break
                await asyncio.sleep(0.2)
            print(f"  after {int((time.time()-t0)*1000)}ms", s)
            await asyncio.sleep(2)

asyncio.run(main())
