# DRAKE_2_0_APP

**Easy phone companion** for the Drake 2.0 dragonsuit.

Talks Nordic UART Service (NUS) over BLE to `TMDrake_tail`.

| | |
|--|--|
| Device | `TMDrake_tail` |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| **Contract** | [APP_INTERFACE.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_INTERFACE.md) **v1.6** |
| **App requirements** | [APP_TEAM.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_TEAM.md) **← read first** |
| **Repo / assets policy** | [REPO.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md) |
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

## Screenshots & assets

Images, icons, and any **libraries needed for the build** belong in git when ready.

- Screenshots → `docs/screenshots/` (see that folder’s README)
- Branding → `assets/` (badge, app icon PNGs)

Add them with **local `git add` / `git push` or GitHub Upload**. Automated agent file APIs are text-oriented and often fail on PNG/JPG — that is **not** a project ban on binaries. Full note: [REPO.md](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md).

```bash
mkdir -p assets docs/screenshots
# copy PNGs/JPGs into place, then:
git add assets docs/screenshots
git commit -m "Add branding and UI screenshots"
git push
```

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
# add badge/icon PNGs and screenshots (local git — see above)
flutter create . --project-name drake_2_0_app
flutter pub get
flutter run
# or
flutter build apk --release
```

## Links

- Tail firmware: https://github.com/tmdrake/DRAKE_2_0_TAIL
- Requirements: https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/APP_TEAM.md
- Repo policy: https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md

---

*Contract v1.6 — HB + link-service required · July 2026*  
*http://tmdrake.com*
