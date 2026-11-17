"""Сирий Modbus-over-BLE probe для EB3A: без бібліотек протоколу, лише bleak."""

import argparse
import asyncio

from bleak import BleakClient, BleakScanner

NOTIFY_UUID = "0000ff01-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def read_cmd(addr: int, count: int) -> bytes:
    body = bytes([0x01, 0x03]) + addr.to_bytes(2, "big") + count.to_bytes(2, "big")
    return body + crc16(body).to_bytes(2, "little")


async def find_device(timeout: float):
    devices = await BleakScanner.discover(timeout=timeout)
    for d in devices:
        print(f"  {d.address}  {d.name}")
    return next((d for d in devices if d.name and d.name.startswith("EB3A")), None)


async def main(address: str | None, scan_time: float):
    if address is None:
        print("Сканую...")
        dev = await find_device(scan_time)
        if dev is None:
            print("EB3A не знайдено")
            return
        address = dev.address
    print(f"\nПідключаюсь до {address}")

    buf = bytearray()
    got = asyncio.Event()

    def on_notify(_, data: bytearray):
        print(f"  <- {data.hex(' ')}")
        buf.extend(data)
        if len(buf) >= 3 and buf[1] == 0x03 and len(buf) >= 5 + buf[2]:
            got.set()

    async with BleakClient(address) as client:
        await client.start_notify(NOTIFY_UUID, on_notify)
        await asyncio.sleep(1)  # зашифровані пристрої шлють handshake ("**...") одразу

        if buf[:2] == b"**":
            print("\nПристрій ініціює обмін ключами: BLE ЗАШИФРОВАНИЙ")
            return

        for name, addr, count in [("type", 10, 6), ("sn", 17, 4), ("power", 36, 8), ("ctrl", 3007, 2)]:
            buf.clear()
            got.clear()
            cmd = read_cmd(addr, count)
            print(f"\n[{name}] -> {cmd.hex(' ')}")
            await client.write_gatt_char(WRITE_UUID, cmd, response=True)
            try:
                await asyncio.wait_for(got.wait(), 5)
            except asyncio.TimeoutError:
                print("  таймаут")
                continue
            frame = bytes(buf[: 5 + buf[2]])
            if crc16(frame[:-2]) != int.from_bytes(frame[-2:], "little"):
                print("  CRC не збігається")
            regs = [int.from_bytes(frame[3 + i : 5 + i], "big") for i in range(0, frame[2], 2)]
            print(f"  regs: {regs}")
            if name == "type":
                print(f"  ascii: {frame[3:-2].decode(errors='replace')!r}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("address", nargs="?", help="адреса (на macOS це UUID з bluetti-scan)")
    p.add_argument("-s", "--scan-time", type=float, default=8)
    a = p.parse_args()
    asyncio.run(main(a.address, a.scan_time))
