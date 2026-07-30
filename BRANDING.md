# TMDrake branding — companion app

Purple-dragon look for Drake 2.0. Use these colors and assets so the phone UI matches the suit identity.

**Art credit:** badge art by *marymouse* (source file provided by project).

---

## Color palette (Material 3 dark)

| Role | Hex | Notes |
|------|-----|--------|
| Scaffold / void | `#0D0618` | App background |
| Surface | `#1A0B2E` | Cards, sheets |
| Surface high | `#2A1A40` | Buttons, chips |
| Primary (purple) | `#9D4EDD` | Theme 0 / brand |
| Primary deep | `#7B2CBF` | Seed / accents |
| Secondary (cyan) | `#00D4FF` | Live / linked / meters |
| Fire accent | `#FF3C00` | Theme 1 |
| Gold accent | `#FFB428` | Theme 3 / Flash |
| On-dark text | `#F0E6FF` | Primary text |
| Muted | `#A090B8` | Secondary text |

### Firmware theme map (keep UI circles exact)

| Id | Name | RGB |
|----|------|-----|
| 0 | purple | `157, 78, 221` |
| 1 | fire | `255, 60, 0` |
| 2 | ice | `80, 180, 255` |
| 3 | gold | `255, 180, 40` |
| 4 | emerald | `20, 200, 100` |

---

## Asset kit (for app developer)

Source + sized PNGs are prepared by the app team (`artifacts/branding/` in the project workspace).

### Head portrait (face / upper head crop)

Use for AppBar avatar, About hero, circular profile chip.

| File | Use |
|------|-----|
| `tmdrake_head_portrait_source.png` | Master head crop |
| `tmdrake_head_square_128/256/512/1024.png` | Square avatar on void bg `#0D0618` |
| `tmdrake_head_transparent_256/512.png` | Overlay / circular clip (no bg) |
| `tmdrake_head_portrait_384x512.png` | 3:4 portrait |
| `tmdrake_head_portrait_768x1024.png` | High-res 3:4 |

**Suggested in-app:**

```dart
ClipOval(
  child: Image.asset('assets/tmdrake_head.png', width: 40, height: 40, fit: BoxFit.cover),
)
```

Copy kit → `assets/tmdrake_head.png` (prefer `tmdrake_head_square_256.png` or transparent 256).

### Full badge + launcher

| File | Use |
|------|-----|
| `tmdrake_badge_128/256/512.png` | Full badge (dragon + PCB + wordmark) |
| `tmdrake_icon_48` … `_1024.png` | Legacy launcher densities |
| `ic_launcher_foreground.png` | Android adaptive icon FG (432px, transparent) |
| `splash_portrait.png` | Optional splash |

### Android adaptive icon (API 26+)

XML stubs (add under `android/app/src/main/res/`):

```text
values/colors.xml
  ic_launcher_background = #0D0618

mipmap-anydpi-v26/ic_launcher.xml
mipmap-anydpi-v26/ic_launcher_round.xml
  background = @color/ic_launcher_background
  foreground = @drawable/ic_launcher_foreground

drawable/ic_launcher_foreground.png   ← from kit
mipmap-mdpi … xxxhdpi/ic_launcher.png ← from tmdrake_icon_*
```

Manifest already uses `android:icon="@mipmap/ic_launcher"`.

### Flutter assets

```yaml
flutter:
  assets:
    - assets/tmdrake_badge.png
    - assets/tmdrake_icon.png
    - assets/tmdrake_head.png
```

### In-app placement

- **AppBar** — head portrait in a circle (~34–40 px) or small full badge
- **About** — large head or full badge + “TMDrake / Drake 2.0”
- **Connected chip** — cyan + optional tiny head mark
- **Launcher** — adaptive icon (void bg + dragon FG)

---

## Flutter theme snippet

```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: const Color(0xFF7B2CBF),
  brightness: Brightness.dark,
  primary: const Color(0xFF9D4EDD),
  secondary: const Color(0xFF00D4FF),
  surface: const Color(0xFF1A0B2E),
),
scaffoldBackgroundColor: const Color(0xFF0D0618),
```

---

## Drop-in (local git)

Binary PNGs: add with local git (see Tail [REPO.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md)).

```bash
cd DRAKE_2_0_APP
mkdir -p assets android/app/src/main/res/drawable
mkdir -p android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}
mkdir -p android/app/src/main/res/mipmap-anydpi-v26
# copy head / badge / icons from branding kit
git add assets android/app/src/main/res BRANDING.md
git commit -m "Add TMDrake head portrait + adaptive icon branding"
git push
```

---

*Branding pack — head portrait + adaptive icon · July 2026*
