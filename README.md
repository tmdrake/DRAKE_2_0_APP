# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit (Tail first).

Big mode buttons, live sliders, one-tap Flash / Sound / Save. Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

> Device: `TMDrake_tail`  
> Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`

## What it does (v0.1)

- One big **Connect to Tail** button → scans for the NUS UUID / name and connects
- Large tappable **mode cards** (Sound Phase, Rainbow, Fire, Off, …)
- Sliders for **Brightness**, **Sensitivity**, **Speed** (sends on release)
- Quick actions: Sound On/Off, Flash, Save to NVS, Status dump
- Live response log at the bottom
- Dark purple dragon theme, big touch targets, portrait phone-first

## Commands sent (compatible with current Tail firmware)

```
M0 … M10     mode
B0-100       brightness
S0-100       sensitivity
V0-100       animation speed
E0 / E1      sound off / on
L            flash
W            save settings
?            status
```

## How to load it on your phone

### Easiest path (Android)

1. Install **Flutter** + Android Studio (or just the Android SDK + Flutter CLI)
2. Clone this repo
3. From the project folder:
   ```bash
   flutter pub get
   flutter run
   ```
   or build a release APK you can sideload:
   ```bash
   flutter build apk --release
   ```
   The APK lands in `build/app/outputs/flutter-apk/app-release.apk`

4. Grant Bluetooth & (if asked) Location permission when the app starts.

### iOS

Same Flutter project works; open in Xcode after `flutter create .` / pod install and add the Bluetooth usage description if needed.

## Project links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL  
- Head / Paws also exist under the same account

## Notes

- DualKiosk was just a test / different project. This app is purpose-built for the suit.
- Firmware must still implement the extra commands (`B`, `V`, `S` range, new modes, etc.) for full effect. Current Tail already accepts `M`, `E`, `L`, `R`, `Z`, `?`.
- Future: color picker, presets, animated dragon head reacting to mic level, multi-device (Head + Tail).

---

*Hatched for easy claw-and-tap control — July 2026*  
*http://tmdrake.com*
