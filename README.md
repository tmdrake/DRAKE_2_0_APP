# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit.

Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

> Device: `TMDrake_tail`  
> Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`  
> Contract: [APP_INTERFACE.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_INTERFACE.md) (v1.3) + [SETTINGS.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/SETTINGS.md)

## Screens (v0.2)

| Tab | Contents |
|-----|----------|
| **Control** | Modes 0–10, Theme circles + custom HSV picker, Brightness, Speed, Flash, Resync |
| **Status** | Live Mic meter, Head Temp, Ambient light, current mode/sound, log |
| **Settings** | Sound (reactive toggle, Gain / Sensitivity / Gate, Quiet/Normal/Loud presets, live mic meter), Fan (Off/On/Auto + threshold), Eyes/CDS (dim threshold + dim %), System (Reboot) |

## Commands used

```
M0–10          mode
B0–100         brightness
V0–100         speed
S<n>           sensitivity
G<n>           gate (wake threshold)
A<n>           gain % (50–300)
E / e          sound on / off
C<r>,<g>,<b>   color (optimistic until firmware supports)
T<name>        theme name
L / R / Z      flash / resync / reboot
F0 F1 F2       fan off / on / auto
FT<n>          fan auto °F
I<n>           CDS dim threshold
D<n>           eye dim %
?              status dump → parses STAT line
```

## How to run

```bash
git clone https://github.com/tmdrake/DRAKE_2_0_APP.git
cd DRAKE_2_0_APP
mkdir -p assets
# copy tmdrake_badge.png and tmdrake_icon.png into assets/
flutter create . --project-name drake_2_0_app
flutter pub get
flutter run
# or
flutter build apk --release
```

## Project links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL
- Head / Paws under the same account

---

*v0.2.0 — Full Settings overhaul matching firmware contract · July 2026*  
*http://tmdrake.com*
