# galaxybook3pro-icc-fix

A corrected display profile for the Samsung Galaxy Book3 Pro 16" (panel `SDC4185`) that keeps whites
neutral when Windows **Auto Color Management (ACM)** is on.

| Profile | White point Windows uses | Result with ACM on |
|---|---|---|
| Samsung `SDC4185.icm` | x 0.2806, y 0.2958 | Warm cast (white at roughly 5,700 K, estimated) |
| `SDC4185_D65.icm` (this repo) | x 0.3127, y 0.3290 (D65) | Neutral white |

## Symptom

With Samsung's display profile installed and *Automatically manage color for apps* enabled, the whole
screen takes on a strong warm cast, most visible on white and gray. Turning ACM off removes it.

## Why it matters

The panel covers a wider gamut than sRGB. Without ACM, ordinary sRGB content looks oversaturated, and
Samsung's screen modes fix that only by limiting the whole display to one color space. ACM shows sRGB
and wide-gamut content correctly at the same time, but only if the display profile describes the panel
correctly. `SDC4185_D65.icm` lets ACM work as intended.

## Cause

The Samsung profile stores its white point tag (`wtpt`) as D65 alongside a `chad` adaptation tag.
Windows applies the adaptation to that white point a second time and treats the panel as much bluer
than it is, so ACM lowers blue by about 20%. Details: [docs/root-cause.md](docs/root-cause.md).

## Install

1. Download `SDC4185_D65.icm` and `fix.ps1` from the
   [latest release](../../releases/latest) into the same folder.

   SHA-256 of `SDC4185_D65.icm`:
   `14f591c880b1e0932c578a22213d19e7c6ccdbb72a34d7ecf6021717eded24d9`

2. In that folder, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Apply
   ```

   This copies the profile to `%WINDIR%\System32\spool\drivers\color` and makes it the default profile
   for SDR (including ACM) and HDR for the current user. Administrator rights are not required.
   To upgrade from v1.0.0, run the same command with the new files.

3. Check the result at any time:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\fix.ps1
   ```

   ```text
   Display           \\.\DISPLAY1 (SDC4185)
   Color mode        SDR with ACM
   Default profile   SDR: SDC4185_D65.icm   HDR: SDC4185_D65.icm
   Profile tags      SDC4185_D65.icm  v4.3  wtpt (0.9642, 1.0000, 0.8249)  chad: yes  MHC2: yes  -> OK
   Windows white     (0.3127, 0.3290)  delta u'v' from D65 = 0.0000  -> OK
   Windows luminance min 0.0042  peak 565.7  full-frame 400.0 cd/m2
   ```

Browsers such as Edge stay within sRGB under ACM unless a per-app compatibility option is enabled; see
[docs/wide-gamut-browsers.md](docs/wide-gamut-browsers.md).

## Revert

```powershell
powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Revert
```

This removes the `SDC4185_D65.icm` association. Windows falls back to the next associated profile.

## Scope

- Tested on one Galaxy Book3 Pro 16" (960XFG, panel `SDC4185`, Intel Iris Xe Graphics) with
  Windows 11 26H1 (build 28000). Other panels are not covered.
- The D65 white point is assumed from the factory calibration, not measured on this unit.
- Reinstalling Samsung's *Display Color Profile* package makes `SDC4185.icm` the default again, and a
  monitor or graphics driver install can make Windows ignore the association
  ([details](docs/root-cause.md#when-windows-ignores-the-profile)). If the check shows `not D65`, run
  `fix.ps1 -Apply` again.

## Documentation

- [Root cause](docs/root-cause.md): how Windows reads the Samsung profile and how this was confirmed.
- [Profile design](docs/profile-design.md): values, assumptions, HDR behavior, and building the profile
  from source.
- [Wide-gamut content in browsers](docs/wide-gamut-browsers.md): enabling the full gamut in Edge and
  other ICC-managed apps.
- [Samsung Display Color Profile package](docs/samsung-display-profile.md): what Samsung's installer
  does and why its screen-mode profiles exist.

## License

[MIT](LICENSE)
