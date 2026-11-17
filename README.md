# Bluetti EB3A

## Застосунок для macOS (рядок меню + віджет)

Потрібно: macOS 26+, Xcode, `brew install xcodegen`, акаунт Apple у Xcode (безкоштовна команда підходить).

```bash
./install.sh
```

Збирає Release, кладе `EB3AMonitor.app` у `/Applications` і запускає. Повторний запуск оновлює застосунок.

- Перший запуск: дозволити Bluetooth. Застосунок сам знайде EB3A поблизу і запам'ятає її.
- Іконка в рядку меню: `⚡` мережа є, `☀ N W` панель, `🔋 N%` заряд, `🔋 —` даних немає.
- Клік по іконці: стан, графік за добу, керування, «Змінити станцію», «Звільнити станцію» (віддати BLE телефону/`live.py`), «Запускати при вході».
- Віджет: ПКМ на робочому столі → «Змінити віджети» → EB3A.
- Одне BLE-з'єднання: поки застосунок підключений, офіційний додаток Bluetti не підключиться — тисни «Звільнити станцію».
- Логи: `/usr/bin/log stream --predicate 'subsystem == "com.legion.eb3amonitor"'`.

Розробка: код у `mac/` (`EB3AKit` — протокол і логіка з тестами, `EB3AMonitor` — застосунок, `EB3AWidget` — віджет).

```bash
swift test --package-path mac/EB3AKit
```

`./snapshot.sh out.png` — рендер поповера в PNG (debug-збірка). Карта регістрів: `REGISTERS.md`.

## Дослідницькі інструменти (Python)


Запускати з Terminal.app, iTerm або терміналу PhpStorm. Перший запуск попросить дозвіл на Bluetooth
(System Settings → Privacy & Security → Bluetooth). Офіційний додаток на телефоні закрити: підключення лише одне.

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt   # уже зроблено
```

1. Знайти пристрій (на macOS адреса це UUID, не MAC):
   `.venv/bin/bluetti-scan -s 10`
2. Сирий probe (hex кадрів, перевірка шифрування):
   `.venv/bin/python probe.py <UUID>`
3. Тип, прошивка, шифрування:
   `.venv/bin/bluetti-detect <UUID>`
4. Усі відомі поля EB3A:
   `.venv/bin/bluetti-read -m <UUID> -t EB3A`
5. Дамп регістрів 0..8000 (для пошуку нових полів, лише читання):
   `.venv/bin/bluetti-readall -m <UUID> -v 1`

6. Знімки живих регістрів (10–219, 3000–3079) і порівняння:
   `.venv/bin/python snap.py take <label>` → `snaps/<label>.json`
   `.venv/bin/python snap.py diff <a> <b>`

7. Live-панель: `.venv/bin/python live.py` → http://127.0.0.1:8765
   (саме 127.0.0.1: на `localhost` IPv6 цей порт займає Logitech-плагін). Тримає BLE-з'єднання, тож snap.py паралельно не працює, знімки робити кнопкою.

Запис (`bluetti-write`) поки не чіпаємо.

Claude запускає ці команди через Terminal.app: `./run.sh <name> <cmd...>`, вивід пишеться в `logs/<name>.log`.

## Мій EB3A (17.11.2026)
UUID `<UUID>`, SN 2200000000001, ARM 2063.03, DSP 2052.11, IoT v1, **без шифрування**.
Дамп: `dumps/`. Валідні адреси лише 10–219 і 3000–3079 (решта повертає помилку).
Ненульові невідомі регістри: 16, 41, 49, 51, 53, 91, 189, 218, 3061.
