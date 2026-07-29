# DRAKE_2_0_APP

**TMDrake / Drake Dragon branded companion app** for the Drake 2.0 suit.

Controls the Tail (ESP32 + NimBLE Nordic UART Service), with future expansion to Head and Paws.

> Device name: `TMDrake_tail`  
> NUS Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`

## Recommended Stack

- **Flutter** (single codebase → Android + iOS)
- BLE library: `flutter_blue_plus`
- Dark purple / blue dragon theme, suit-inspired icons, animated reactive dragon head optional

Native Kotlin Android is also fine if you want to stay pure-Android first (see DualKiosk for style reference).

## Core Features (v1)

- Scan & connect to `TMDrake_tail` (filter by NUS UUID)
- Mode selector (grid/carousel with dragon-themed icons)
- Live sliders:
  - Master Brightness (0–100)
  - Sound Sensitivity
  - Animation Speed
- Color / theme picker
- Quick actions: Flash (`L`), Resync (`R`), Save preset (`W`)
- Live status dump (`?`)
- Sound enable/disable (`E0`/`E1`)

## BLE Command Protocol (human-readable, keep compatible)

```
M<mode>          // Set mode 0-10+
B<0-100>         // Master brightness
S<value>         // Sensitivity
E0 / E1          // Sound off / on
V<0-100>         // Animation speed
C<r>,<g>,<b>     // Base / theme color
T<theme>         // Named theme
P<preset>        // Load preset
W                // Write / save settings to NVS
R                // Resync / reset animation state
L                // Flash
?                // Status dump
```

Responses arrive as NUS TX notifications.

## Modes (from Tail firmware)

| Mode | Name              | Notes |
|------|-------------------|-------|
| 0    | Sound Phase       | Current color-phase reactive |
| 1    | Sound Distinct    | Hard color cycle |
| 2    | VU Meter          | Classic bar |
| 3    | Rainbow Chase     | New |
| 4    | Comet / Meteor    | New |
| 5    | Breathing Pulse   | New |
| 6    | Fire Flicker      | New |
| 7    | Sparkle / Twinkle | New |
| 8    | Wave / Undulate   | New |
| 9    | Solid / Static    | New |
| 10   | Off / Blackout    | New |

## Project Links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL
- Head: https://github.com/tmdrake/DRAKE_2_0_HEAD
- Paws: https://github.com/tmdrake/DRAKE_2_0_PAWB
- Full roadmap lives in the Tail repo `IMPROVEMENTS.md`

## Quick Start (Flutter)

```bash
flutter create .
# then add flutter_blue_plus and start scanning for the NUS service
```

Or open in Android Studio / VS Code and build the Android target first.

---

*Hatched by the dragon hardware/software engineer — July 2026*
*http://tmdrake.com*
