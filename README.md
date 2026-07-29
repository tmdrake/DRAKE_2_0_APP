# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit (Tail first).

Big mode buttons, live sliders, theme/color picker, one-tap Flash / Sound / Save.  
Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

> Device: `TMDrake_tail`  
> Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`

## Features (v0.1.1)

- One big **Connect to Tail** button
- Large tappable **mode cards** (Sound Phase, Rainbow, Dragonfire, Comet, Blackout…)
- **Theme circles**: Purple / Fire / Ice / Gold / Emerald + full custom HSV color picker
- Sliders for Brightness, Sensitivity, Speed
- Quick actions: Sound On/Off, Flash, Save to NVS, Status
- Live response log
- Dark purple dragon theme + your TMDrake badge as portrait / logo
- Big touch targets, portrait phone-first

## Commands sent

```
M0 … M10          mode
B0-100            brightness
S0-100            sensitivity
V0-100            animation speed
C<r>,<g>,<b>      base / theme color
T<name>           named theme (purple/fire/ice/…)
E0 / E1           sound off / on
L                 flash
W                 save settings
?                 status
```

## How to load it on your phone (Android)

1. Install Flutter + Android Studio (or Flutter CLI + Android SDK)
2. Clone this repo
3. **Add the dragon assets** (important!):
   ```bash
   mkdir -p assets
   # Copy the badge image you provided (or the resized versions)
   # Place as:
   #   assets/tmdrake_badge.png   ← used in the app UI portrait
   #   assets/tmdrake_icon.png    ← for launcher icon later
   ```
   You can grab the high-res original or the resized versions prepared for the app.

4. Then:
   ```bash
   flutter create . --project-name drake_2_0_app
   flutter pub get
   flutter run
   ```
   or build a sideloadable APK:
   ```bash
   flutter build apk --release
   ```
   APK → `build/app/outputs/flutter-apk/app-release.apk`

5. Grant Bluetooth (and Location if asked) on first run.

### App icon (optional polish)

After `flutter create`, you can replace the default launcher icons with the square `tmdrake_icon_512.png` using the `flutter_launcher_icons` package, or just drop the 512 px version into the Android mipmap folders.

## Project links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL  
- Head / Paws under the same account

## Notes

- DualKiosk was a different test project. This app is purpose-built for the suit.
- Firmware still needs the full command set (`B`, `V`, `C`, new modes…) for everything to light up. Existing commands (`M`, `E`, `L`, `?`…) already work.

---

*Hatched for easy claw-and-tap control — July 2026*  
*http://tmdrake.com*
