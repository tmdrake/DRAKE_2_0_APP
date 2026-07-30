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

Source + sized PNGs are prepared by the app team (see project `artifacts/branding/` or ask for the kit). Copy into the Flutter tree as below.

### Required in repo / build

```text
assets/
  tmdrake_badge.png          # UI header / portrait (use 256 or 512)
  tmdrake_icon.png           # generic square icon (512)

android/app/src/main/res/
  mipmap-mdpi/ic_launcher.png       # 48
  mipmap-hdpi/ic_launcher.png       # 72
  mipmap-xhdpi/ic_launcher.png      # 96
  mipmap-xxhdpi/ic_launcher.png     # 144
  mipmap-xxxhdpi/ic_launcher.png    # 192
  drawable/ic_launcher_foreground.png  # 432 adaptive FG (transparent)
```

### Kit file map

| File | Use |
|------|-----|
| `tmdrake_badge_source.png` | Master art |
| `tmdrake_badge_128/256/512.png` | In-app header, About, Status |
| `tmdrake_icon_48` … `_1024.png` | Launcher / store |
| `ic_launcher_foreground.png` | Android adaptive icon FG |
| `splash_portrait.png` | Optional splash |

### `pubspec.yaml`

```yaml
flutter:
  assets:
    - assets/tmdrake_badge.png
    - assets/tmdrake_icon.png
```

### In-app placement

- **AppBar** — small circular/rounded badge (`tmdrake_badge.png`, ~34–40 logical px)
- **About** — larger badge + “TMDrake / Drake 2.0”
- **Connected chip** — secondary cyan + optional tiny dragon mark
- **Launcher** — adaptive icon with purple/dark background + foreground dragon

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

Binary PNGs: add with local git (agent APIs are text-oriented — see [REPO.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md)).

```bash
cd DRAKE_2_0_APP
mkdir -p assets
# copy kit PNGs → assets/ and android mipmaps
git add assets android/app/src/main/res
git commit -m "Add TMDrake purple-dragon branding assets"
git push
```

---

*Branding pack for field + store · July 2026*
