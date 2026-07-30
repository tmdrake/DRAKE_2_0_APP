# Drake 2.0 App Screenshots

UI mockups for Control / Status / Settings.

## Commit images here

| File | Description |
|------|-------------|
| `control.jpg` | Control tab — modes + theme circles |
| `status.jpg` | Status tab — telemetry + Theme/RGB |
| `settings.jpg` | Settings tab — Gain / Gate / Fan / Eyes |

Typical sources: `screenshot_control_v021.jpg`, `screenshot_status_v021.jpg`, `screenshot_settings_v2.jpg`.

```bash
cp /path/to/screenshot_control_v021.jpg docs/screenshots/control.jpg
# ... status.jpg, settings.jpg
git add docs/screenshots/*.jpg
git commit -m "Add UI screenshots"
git push
```

**Note:** Chat/agent GitHub tools often cannot upload PNG/JPG (text-only APIs). That is a **tooling limit**, not a ban on images. Binary assets and build libraries **are allowed** in this repo — see [REPO.md on Tail](https://github.com/tmdrake/DRAKE_2_0_TAIL/blob/main/REPO.md).
