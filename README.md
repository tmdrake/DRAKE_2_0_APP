# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit.

Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

| | |
|--|--|
| Device | `TMDrake_tail` |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| **Contract** | [APP_INTERFACE.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_INTERFACE.md) **v1.6** |
| **App requirements** | [APP_TEAM.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_TEAM.md) **← read first** |
| Tracking | [Issue #1 — BLE link service + HB](https://github.com/tmdrake/DRAKE_2_0_APP/issues/1) |

---

## REQUIRED: BLE Link Service + Heartbeat

Not optional. Suit must stay linked in the background.

| # | Requirement |
|---|-------------|
| 1 | Android **foreground service** while “Keep suit linked” is ON |
| 2 | **`autoConnect: true`** after first successful connect |
| 3 | Discover via NUS UUID and/or name `TMDrake_tail` |
| 4 | Send **`HB`** on notify subscribe, every **2–5 s**, and on resume |
| 5 | **`HBACK`** → link healthy; **`STAT`** → sync all UI |
| 6 | No **`HBACK` >10 s** → stale UI + disconnect + autoConnect/rescan |
| 7 | Toggle OFF → stop timer, disconnect, stop FGS |

```text
App  --HB-->  Tail
App  <--HBACK Seq:n U:sec--
App  <--STAT … full snapshot--
```

Firmware already implements HB / HBACK / STAT (`Seq`, `U`). Details in APP_TEAM.md.

---

## Screenshots (v0.2.1)

Control · Status · Settings mockups live under [`docs/screenshots/`](docs/screenshots/).

| Tab | Preview |
|-----|---------|
| **Control** | Modes 0–10, **live Theme circles** (`T0–T4` / `C`), Brightness, Speed, Flash, Resync |
| **Status** | Mic meter, Head Temp / Light, Mode, Sound, **Theme + RGB**, log |
| **Settings** | Sound (Gain / Sensitivity / Gate + presets), Fan, Eyes/CDS, System |

Drop the three JPGs from the app-team artifacts into `docs/screenshots/` as:

- `control.jpg` ← `screenshot_control_v021.jpg`
- `status.jpg` ← `screenshot_status_v021.jpg`
- `settings.jpg` ← `screenshot_settings_v2.jpg`

Then they render here:

![Control](docs/screenshots/control.jpg)

![Status](docs/screenshots/status.jpg)

![Settings](docs/screenshots/settings.jpg)

---

## Screens

| Tab | Contents |
|-----|----------|
| **Control** | Modes 0–10, theme circles + HSV (`T` / `C`), B/V, Flash, Resync, **link indicator** |
| **Status** | Mic, HeadT, HeadB, Theme/RGB, Seq/uptime, log |
| **Settings** | Sound, Fan, Eyes/CDS, **Keep suit linked**, Reboot |

## Commands (firmware live)

```text
M0–10  B  V  S  G  A  E/e  C  T0–4  HB  L  R  Z
F0 F1 F2 FT  I  D  ?
```

## How to run

```bash
git clone https://github.com/tmdrake/DRAKE_2_0_APP.git
cd DRAKE_2_0_APP
mkdir -p assets docs/screenshots
# copy tmdrake_badge.png + tmdrake_icon.png into assets/
# copy control.jpg status.jpg settings.jpg into docs/screenshots/
flutter create . --project-name drake_2_0_app
flutter pub get
flutter run
# or
flutter build apk --release
```

## Links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL
- Requirements: https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_TEAM.md

---

*Contract v1.6 — HB + link-service required · Screenshots section added · July 2026*  
*http://tmdrake.com*
