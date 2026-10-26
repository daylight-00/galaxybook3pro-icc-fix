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
   `ce8b37bd99eee5a6a9fe3ba61b862edaec0e44493fbd0955a1495f875240e033`

2. In that folder, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Apply
   ```

   This copies the profile to `%WINDIR%\System32\spool\drivers\color` and makes it the default SDR and
   advanced color (ACM) profile for the current user. Administrator rights are not required.

3. Check the result at any time:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\fix.ps1
   ```

   ```text
   Display           \\.\DISPLAY1 (SDC4185)
   Auto color mgmt   On
   Default profile   SDR: SDC4185_D65.icm   ACM: SDC4185_D65.icm
   Profile tags      SDC4185_D65.icm  v4.3  wtpt (0.9642, 1.0000, 0.8249)  chad: yes  -> OK
   Windows white     (0.3127, 0.3290)  delta u'v' from D65 = 0.0000  -> OK
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
- Reinstalling Samsung's *Display Color Profile* package makes `SDC4185.icm` the default again; run
  `fix.ps1 -Apply` afterwards.

## Documentation

- [Root cause](docs/root-cause.md): how Windows reads the Samsung profile and how this was confirmed.
- [Profile design](docs/profile-design.md): values, assumptions, and building the profile from source.
- [Wide-gamut content in browsers](docs/wide-gamut-browsers.md): enabling the full gamut in Edge and
  other ICC-managed apps.
- [Samsung Display Color Profile package](docs/samsung-display-profile.md): what Samsung's installer
  does and why its screen-mode profiles exist.

## License

[MIT](LICENSE)
