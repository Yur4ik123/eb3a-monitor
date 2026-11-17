"""Live-монітор EB3A: BLE-опитування + http://127.0.0.1:8765"""

import asyncio
import concurrent.futures
import csv
import json
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from bleak import BleakClient

from probe import NOTIFY_UUID, WRITE_UUID, crc16
from snap import CHUNK, DEFAULT_ADDRESS, KNOWN, RANGES, SNAPS, read_block

ROOT = Path(__file__).parent
PORT = 8765
FULL_EVERY = 10.0  # повне сканування, с
FAST = [(36, 14), (50, 10), (77, 1), (80, 10), (210, 10), (3000, 10), (3030, 10), (3060, 10)]  # ключові + MPPT + налаштування

state = {"connected": False, "error": None, "updated": None, "poll_ms": None,
         "regs": {}, "baseline": {}, "changed_at": {}, "log": []}
lock = threading.Lock()


def apply(regs: dict[int, int]):
    """Злиття (повного або часткового) зчитування в стан + журнал змін."""
    now = time.time()
    stamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    events = []
    with lock:
        prev = state["regs"]
        for a, v in regs.items():
            if a in prev and prev[a] != v:
                state["changed_at"][a] = now
                e = {"t": stamp, "addr": a, "name": KNOWN.get(a), "old": prev[a], "new": v}
                state["log"].insert(0, e)
                events.append(e)
        del state["log"][200:]
        state["regs"] = {**prev, **regs}
        if not state["baseline"]:
            state["baseline"] = dict(regs)
        state["updated"] = now
    if events:
        with (ROOT / "logs" / f"events-{datetime.now():%Y%m%d}.log").open("a") as f:
            for e in events:
                f.write(f"{datetime.now():%Y-%m-%d} {e['t']} r{e['addr']} {e['name'] or '?'} {e['old']} -> {e['new']}\n")


def append_fast_csv(regs: dict[int, int]):
    """Швидкі вибірки ключових регістрів з мілісекундами."""
    path = ROOT / "logs" / f"fast-{datetime.now():%Y%m%d}.csv"
    addrs = sorted(regs)
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["time"] + [f"r{a}" + (f"_{KNOWN[a]}" if a in KNOWN else "") for a in addrs])
        w.writerow([datetime.now().isoformat(timespec="milliseconds")] + [regs[a] for a in addrs])


def append_csv(regs: dict[int, int]):
    """Один рядок на цикл: час + всі регістри. Новий файл на кожен день."""
    path = ROOT / "logs" / f"history-{datetime.now():%Y%m%d}.csv"
    addrs = sorted(regs)
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["time"] + [f"r{a}" + (f"_{KNOWN[a]}" if a in KNOWN else "") for a in addrs])
        w.writerow([datetime.now().isoformat(timespec="seconds")] + [regs[a] for a in addrs])


HISTORY_COLS = {"soc": "r43_battery_soc", "ac_in": "r37_ac_input_power", "dc_in": "r36_dc_input_power",
                "ac_out": "r38_ac_output_power", "dc_out": "r39_dc_output_power"}
MAX_POINTS = 1500


def load_history(minutes: float) -> dict:
    """Ряди з CSV за останні N хвилин (0 = усе), проріджені до MAX_POINTS."""
    since = time.time() - minutes * 60 if minutes else 0
    rows = []
    for path in sorted((ROOT / "logs").glob("history-*.csv")):
        with path.open(newline="") as f:
            for row in csv.DictReader(f):
                ts = datetime.fromisoformat(row["time"]).timestamp()
                if ts >= since:
                    rows.append((ts, row))
    step = max(1, len(rows) // MAX_POINTS)
    rows = rows[::step]
    out = {"t": [ts for ts, _ in rows]}
    for key, col in HISTORY_COLS.items():
        out[key] = [int(r.get(col) or 0) for _, r in rows]
    return out


# Дозволені записи: адреса -> допустимі значення. 3060 (вимкнення) свідомо відсутній.
WRITABLE = {3007: {0, 1}, 3008: {0, 1}, 3034: {1, 2, 3, 4}, 3061: {0, 1}, 3063: {0, 1},
            3064: {1, 2, 3, 4}, 3065: {0, 1, 2}, 3066: {0, 1}}
write_queue: asyncio.Queue | None = None
loop_ref: asyncio.AbstractEventLoop | None = None


async def write_and_confirm(client, buf, got, mode, addr: int, value: int) -> dict:
    """FC 0x06 + очікування, поки регістр покаже нове значення."""
    cmd = bytes([1, 6]) + addr.to_bytes(2, "big") + value.to_bytes(2, "big")
    cmd += crc16(cmd).to_bytes(2, "little")
    t0 = time.time()
    buf.clear()
    got.clear()
    mode["write"] = True
    try:
        await client.write_gatt_char(WRITE_UUID, cmd, response=True)
        await asyncio.wait_for(got.wait(), 5)
    finally:
        mode["write"] = False
    resp = bytes(buf[:8])
    if resp[1] & 0x80:
        raise ValueError(f"Modbus exception {resp[2]}")
    if resp != cmd:
        raise ValueError(f"неочікувана відповідь {resp.hex(' ')}")
    ack_ms = int((time.time() - t0) * 1000)
    block = addr // CHUNK * CHUNK
    while time.time() - t0 < 6:
        vals = await read_block(client, buf, got, block, CHUNK)
        regs = {block + i: v for i, v in enumerate(vals)}
        apply(regs)
        if regs[addr] == value:
            return {"ok": True, "addr": addr, "value": value, "ack_ms": ack_ms,
                    "confirm_ms": int((time.time() - t0) * 1000)}
        await asyncio.sleep(0.1)
    return {"ok": False, "addr": addr, "value": value, "ack_ms": ack_ms,
            "error": f"пристрій підтвердив запис, але регістр = {regs[addr]}"}


READ_FCS = {1, 2, 3, 4, 0x11}


async def raw_request(client, buf, got, fc: int, addr: int = 0, count: int = 1, timeout: float = 2.0) -> dict:
    """Довільний запит лише на читання. Повертає data (hex) / exc / timeout."""
    body = bytes([1, fc]) if fc == 0x11 else bytes([1, fc]) + addr.to_bytes(2, "big") + count.to_bytes(2, "big")
    cmd = body + crc16(body).to_bytes(2, "little")
    buf.clear()
    got.clear()
    await client.write_gatt_char(WRITE_UUID, cmd, response=True)
    try:
        await asyncio.wait_for(got.wait(), timeout)
    except asyncio.TimeoutError:
        return {"timeout": True, "raw": bytes(buf).hex(" ")}
    if buf[1] & 0x80:
        await asyncio.sleep(0.05)  # дочекатися хвоста кадру (CRC), щоб не змішати з наступним
        return {"exc": buf[2]}
    return {"data": bytes(buf[3 : 3 + buf[2]]).hex()}


async def scan_job(client, buf, got, fc: int, start: int, end: int, chunk: int):
    found, errors = {}, {}
    t0 = time.time()
    for addr in range(start, end, chunk):
        r = await raw_request(client, buf, got, fc, addr, min(chunk, end - addr), timeout=1.5)
        if "data" in r:
            found[addr] = r["data"]
        else:
            key = f"exc{r['exc']}" if "exc" in r else "timeout"
            errors[key] = errors.get(key, 0) + 1
        with lock:
            state["scan"] = {"fc": fc, "start": start, "end": end, "at": addr, "found": len(found),
                             "errors": errors, "running": True}
    path = ROOT / "dumps" / f"scan-fc{fc}-{start}-{end}-{datetime.now():%H%M%S}.json"
    path.write_text(json.dumps({"fc": fc, "start": start, "end": end, "chunk": chunk, "found": found,
                                "errors": errors, "seconds": int(time.time() - t0)}, indent=1))
    with lock:
        state["scan"] = {**state["scan"], "running": False, "file": path.name, "at": end}


async def process_writes(client, buf, got, mode):
    while not write_queue.empty():
        kind, args, fut = write_queue.get_nowait()
        try:
            if kind == "write":
                res = await write_and_confirm(client, buf, got, mode, *args)
            elif kind == "raw":
                res = await raw_request(client, buf, got, *args)
            else:
                res = await scan_job(client, buf, got, *args)
        except Exception as e:
            res = {"ok": False, "error": repr(e)}
            with lock:
                if state.get("scan", {}).get("running"):
                    state["scan"].update(running=False, error=repr(e))
        with (ROOT / "logs" / f"events-{datetime.now():%Y%m%d}.log").open("a") as f:
            f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S.%f}"[:-3] + f" {kind.upper()} {args} -> {res}\n")
        if fut:
            fut.set_result(res)


def submit_write(addr: int, value: int) -> dict:
    """Викликається з HTTP-потоку."""
    if WRITABLE.get(addr) is None or value not in WRITABLE[addr]:
        return {"ok": False, "error": f"запис r{addr}={value} не дозволено"}
    with lock:
        if not state["connected"]:
            return {"ok": False, "error": "немає з'єднання з пристроєм"}
    return submit("write", (addr, value))


def submit(kind: str, args: tuple, wait: bool = True) -> dict:
    with lock:
        if not state["connected"]:
            return {"ok": False, "error": "немає з'єднання з пристроєм"}
        if state.get("scan", {}).get("running"):
            return {"ok": False, "error": "йде сканування"}
    fut = concurrent.futures.Future() if wait else None
    loop_ref.call_soon_threadsafe(write_queue.put_nowait, (kind, args, fut))
    if not wait:
        return {"ok": True, "started": True}
    try:
        return fut.result(timeout=20)
    except concurrent.futures.TimeoutError:
        return {"ok": False, "error": "таймаут"}


EXTRA_NOTIFY_UUID = "0000ff04-0000-1000-8000-00805f9b34fb"


def log_line(text: str):
    with (ROOT / "logs" / f"events-{datetime.now():%Y%m%d}.log").open("a") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S.%f}"[:-3] + f" {text}\n")


def on_extra(_, data: bytearray):
    """Пасивне прослуховування ff04: лише лог."""
    log_line(f"FF04 {bytes(data).hex(' ')} {bytes(data).decode(errors='replace')!r}")
    with lock:
        state.setdefault("ff04", []).insert(0, {"t": datetime.now().strftime("%H:%M:%S.%f")[:-3], "hex": bytes(data).hex(" ")})
        del state["ff04"][50:]


async def poll_loop(address: str):
    global write_queue, loop_ref
    write_queue = asyncio.Queue()
    loop_ref = asyncio.get_running_loop()
    buf = bytearray()
    got = asyncio.Event()
    mode = {"write": False}

    def on_notify(_, data: bytearray):
        buf.extend(data)
        if len(buf) < 3:
            return
        if mode["write"]:
            if (buf[1] & 0x80 and len(buf) >= 5) or len(buf) >= 8:
                got.set()
        elif buf[1] & 0x80 or len(buf) >= 5 + buf[2]:
            got.set()

    while True:
        try:
            async with BleakClient(address) as client:
                await client.start_notify(NOTIFY_UUID, on_notify)
                try:
                    await client.start_notify(EXTRA_NOTIFY_UUID, on_extra)
                except Exception as e:
                    log_line(f"ff04 notify недоступний: {e!r}")
                with lock:
                    state.update(connected=True, error=None)
                while client.is_connected:
                    t0 = time.time()
                    regs = {}
                    for start, length in RANGES:
                        for addr in range(start, start + length, CHUNK):
                            vals = await read_block(client, buf, got, addr, CHUNK)
                            regs.update({addr + i: v for i, v in enumerate(vals)})
                    apply(regs)
                    with lock:
                        state["poll_ms"] = int((time.time() - t0) * 1000)
                    (ROOT / "logs" / "live_state.json").write_text(snapshot_state())
                    append_csv(regs)
                    t_full = time.time()
                    while client.is_connected and time.time() - t_full < FULL_EVERY:
                        await process_writes(client, buf, got, mode)
                        t1 = time.time()
                        fast = {}
                        for start, count in FAST:
                            vals = await read_block(client, buf, got, start, count)
                            fast.update({start + i: v for i, v in enumerate(vals)})
                        apply(fast)
                        append_fast_csv(fast)
                        with lock:
                            state["fast_ms"] = int((time.time() - t1) * 1000)
        except Exception as e:
            with lock:
                state.update(connected=False, error=repr(e))
            await asyncio.sleep(3)


def snapshot_state() -> str:
    with lock:
        return json.dumps({**state, "known": KNOWN})


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, code, body: bytes, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self.send(200, (ROOT / "live.html").read_bytes(), "text/html; charset=utf-8")
        elif path == "/state":
            self.send(200, snapshot_state().encode())
        elif path == "/history":
            minutes = float(parse_qs(urlparse(self.path).query).get("minutes", ["0"])[0] or 0)
            self.send(200, json.dumps(load_history(minutes)).encode())
        else:
            self.send(404, b"{}")

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/baseline":
            with lock:
                state["baseline"] = dict(state["regs"])
            self.send(200, b'{"ok":true}')
        elif u.path == "/write":
            q = parse_qs(u.query)
            try:
                addr, value = int(q["addr"][0]), int(q["value"][0])
            except (KeyError, ValueError):
                self.send(400, b'{"ok":false,"error":"addr/value"}')
                return
            self.send(200, json.dumps(submit_write(addr, value)).encode())
        elif u.path in ("/raw", "/scan"):
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            try:
                fc = int(q.get("fc", "3"), 0)
                if fc not in READ_FCS:
                    raise ValueError("fc")
                if u.path == "/raw":
                    res = submit("raw", (fc, int(q.get("addr", "0")), int(q.get("count", "10"))))
                else:
                    start, end, chunk = int(q["start"]), int(q["end"]), int(q.get("chunk", "10"))
                    if not (0 <= start < end <= 65536 and 1 <= chunk <= 100):
                        raise ValueError("range")
                    res = submit("scan", (fc, start, end, chunk), wait=False)
            except (KeyError, ValueError) as e:
                res = {"ok": False, "error": f"параметри: {e}"}
            self.send(200, json.dumps(res).encode())
        elif u.path == "/snap":
            label = parse_qs(u.query).get("label", [""])[0].strip() or datetime.now().strftime("snap_%H%M%S")
            label = "".join(c for c in label if c.isalnum() or c in "-_")
            with lock:
                regs = dict(state["regs"])
            SNAPS.mkdir(exist_ok=True)
            (SNAPS / f"{label}.json").write_text(json.dumps(
                {"label": label, "time": datetime.now().isoformat(timespec="seconds"), "regs": regs}, indent=1))
            self.send(200, json.dumps({"ok": True, "label": label}).encode())
        else:
            self.send(404, b"{}")


if __name__ == "__main__":
    import sys
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"http://127.0.0.1:{PORT}")
    asyncio.run(poll_loop(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ADDRESS))
