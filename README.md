# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit.

Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

> Device: `TMDrake_tail`  
> Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`  
> Contract: [APP_INTERFACE.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_INTERFACE.md) **v1.5**

## Screens (v0.2.1)

| Tab | Contents |
|-----|----------|
| **Control** | Modes 0–10, **live Theme circles + HSV picker** (`T0–T4` / `C`), Brightness, Speed, Flash, Resync |
| **Status** | Live Mic, Head Temp, Ambient light, Mode/Sound, **Theme + RGB**, log |
| **Settings** | Sound (Gain / Sensitivity / Gate + presets), Fan, Eyes/CDS, System |

## Color & Themes (now live)

Firmware implements:

| Cmd | Effect |
|-----|--------|
| `T0`…`T4` or named | Preset RGB + Solid mode 9, fan-out to Head/PAWB |
| `C<r>,<g>,<b>` | Custom RGB + Solid mode 9 |

Theme map matches firmware exactly (purple / fire / ice / gold / emerald).

STAT now carries `C:` and `T:` so the UI stays in sync after reconnect.

## How to run

```bash
git clone https://github.com/tmdrake/DRAKE_2_0_APP.git
cd DRAKE_2_0_APP
mkdir -p assets
# copy tmdrake_badge.png + tmdrake_icon.png into assets/
flutter create . --project-name drake_2_0_app
flutter pub get
flutter run
# or
flutter build apk --release
```

## Project links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL

---

*v0.2.1 — Color/Theme fully live for hardware field test · July 2026*  
*http://tmdrake.com*
