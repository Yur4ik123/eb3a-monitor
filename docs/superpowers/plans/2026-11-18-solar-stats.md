# Solar Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Вікно «Сонце» з порівнянням днів (30 днів), деталями й погодинним профілем дня.

**Architecture:** Денні підсумки (`DaySummary`) рахуються в EB3AKit з хвилинних `HistoryRecord` і зберігаються в `solar-days.json` (App Group, 90 днів). `HistoryRecorder` оновлює поточний день на кожен хвилинний запис і робить бекфіл при старті. Окрема SwiftUI `Window` показує дані.

**Tech Stack:** Swift, SwiftUI, Swift Charts, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-18-solar-stats-design.md`

## Global Constraints
- Енергія хвилини = `solarW / 60` Wh. Генерація «є», якщо `solarW > 5`.
- Дні — за локальним календарем (`Calendar.current`), ключ `yyyy-MM-dd`.
- Неповний день: `minutesCovered < 0.9 × хвилин дня` (для сьогодні — хвилин, що минули).
- Зберігати 90 днів; у вікні — 30.
- Коментарі мінімальні; UI українською.

## Review Focus
- Перехід через північ: запис 23:59 і 00:00 потрапляють у різні дні — `testSplitsAtLocalMidnight` (Task 1).
- Повторний бекфіл тієї самої історії не подвоює енергію (upsert за ключем дня) — `testUpsertReplacesDay` (Task 1).
- День без жодної хвилини з сонцем: wh 0, peak nil, вікно генерації nil — `testDayWithoutSun` (Task 1).
- Порожній/битий `solar-days.json` → порожній список, без падіння — `testCorruptStoreIsEmpty` (Task 1).
- Порівняння тижнів, коли минулого тижня даних немає → відсоток nil, не ∞ — `testWeekComparisonNoPrevious` (Task 1).

---

### Task 1: DaySummary, сховище, порівняння тижнів (EB3AKit)

**Files:**
- Create: `mac/EB3AKit/Sources/EB3AKit/SolarDays.swift`
- Test: `mac/EB3AKit/Tests/EB3AKitTests/SolarDaysTests.swift`

**Interfaces:**
- Consumes: `HistoryRecord`
- Produces:
  - `struct DaySummary: Codable, Equatable, Sendable { day: String; wh: Double; hourlyWh: [Double] /*24*/; peakW: Double; peakAt: Date?; firstAt: Date?; lastAt: Date?; minutesCovered: Int; func coverage(now: Date, calendar: Calendar) -> Double }`
  - `enum SolarDays { static func build(from: [HistoryRecord], calendar: Calendar) -> [DaySummary]; static func merge(_ existing: [DaySummary], _ new: [DaySummary], keepDays: Int, now: Date, calendar: Calendar) -> [DaySummary] /*upsert, sorted, trimmed*/; static func dayKey(_ d: Date, calendar: Calendar) -> String; static func weekComparison(_ days: [DaySummary], now: Date, calendar: Calendar) -> (thisWh: Double, lastWh: Double, changePct: Double?) /*останні 7 днів vs попередні 7*/ }`
  - `final class SolarDaysStore { init(fileURL: URL); func load() -> [DaySummary]; func save(_: [DaySummary]) throws }`

- [ ] Tests (UTC calendar для детермінізму): `testBuildSumsAndHourly` (60 хв × 120 W о 10:00 → wh 120, hourlyWh[10] 120, peak 120, firstAt 10:00, lastAt 10:59, minutesCovered 60), `testSplitsAtLocalMidnight`, `testUpsertReplacesDay`, `testDayWithoutSun`, `testMergeTrimsTo90Days`, `testCorruptStoreIsEmpty`, `testWeekComparison` (this 700 / last 350 → +100 %), `testWeekComparisonNoPrevious`.
- [ ] Run `swift test --package-path mac/EB3AKit --filter SolarDaysTests` — FAIL
- [ ] Implement
- [ ] Run `swift test --package-path mac/EB3AKit` — PASS
- [ ] Commit `feat(kit): solar day summaries`

### Task 2: Запис підсумків у застосунку + вікно «Сонце»

**Files:**
- Modify: `mac/EB3AMonitor/HistoryRecorder.swift` (поле `days: [DaySummary]`; бекфіл при init: `merge(load, build(from: store.records(since: now−7d)))`; на кожен новий хвилинний запис — перебудувати поточний день з `last24h` і зберегти)
- Create: `mac/EB3AMonitor/SolarStatsView.swift` (підсумки тижня + найкращий день; `Chart` BarMark 30 днів, сьогодні акцентним кольором, неповні дні приглушено; вибраний день → енергія, пік і час, вікно генерації, «неповний (N %)», погодинний BarMark)
- Modify: `mac/EB3AMonitor/App.swift` (`Window("Сонце", id: "solar")`), `PopoverView.swift` (кнопка-іконка `chart.bar` у рядку «Сонце» → `openWindow(id: "solar")` + `NSApp.activate`)
- Modify: `mac/EB3AMonitor/Snapshot.swift` (`SNAP_SOLAR` рендерить вікно з тестовими 30 днями), `README.md` (скриншот `docs/screenshots/solar-stats.png`)

- [ ] Build; `SNAP_SOLAR=1 ./snapshot.sh docs/screenshots/solar-stats.png`, переглянути рендер
- [ ] `./install.sh`; лог без помилок; файл `solar-days.json` створюється (через лог шляху)
- [ ] Commit `feat(app): solar stats window`
