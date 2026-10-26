# galaxybook3pro-icc-fix

A corrected display profile for the Samsung Galaxy Book3 Pro 16" (panel `SDC4185`) that keeps whites
neutral when Windows **Auto Color Management (ACM)** is on.

| Profile | White point Windows uses | Result with ACM on |
|---|---|---|
| Samsung `SDC4185.icm` | x 0.2806, y 0.2958 | Yellow cast (white at roughly 5,700 K, estimated) |
| `SDC4185_D65.icm` (this repo) | x 0.3127, y 0.3290 (D65) | Neutral white |

## Symptom

With Samsung's display profile installed and *Automatically manage color for apps* enabled, the whole
screen turns noticeably yellow. Turning ACM off removes the cast.

## Cause

`SDC4185.icm` ("Samsung AMOLED Profile", installed by Samsung's *Display Color Profile* package) is an
ICC v2.1 matrix/TRC profile containing:

- colorants adapted to the D50 profile connection space,
- a `chad` tag with the Bradford D65 → D50 adaptation,
- a `wtpt` tag of **D65**.

Windows undoes the `chad` adaptation on the colorants, which recovers the panel primaries, and also on
`wtpt`. Because `wtpt` is already D65, the second adaptation moves it to x 0.2806, y 0.2958
(about 9,500 K). This is the white point DXGI reports for the display. ACM then compensates for a panel
it believes to be bluish and lowers blue by about 20%, so neutral content appears yellow.

For display profiles that carry a `chad` tag, the ICC v4 convention is `wtpt` = D50, with the actual
white given by `chad`.

<details>
<summary>How this was confirmed</summary>

- The DXGI white point (`IDXGIOutput6::GetDesc1`) matches the profile's `wtpt` adapted with the inverse
  of `chad` to four decimals. The reported primaries match the colorants adapted once.
- The ACM color transform stored by the Intel driver (`OSLinearColorTransformCsc_Wcg_*`) has row sums of
  R 0.985, G 0.994, B 0.794 with the Samsung profile, and R 0.976, G 0.992, B 1.007 with
  `SDC4185_D65.icm`.
- Making the Samsung profile the default again reproduces the original matrix exactly.
- Night Light, the gamma ramp (identity), and the Samsung monitor driver were ruled out.

</details>

## The fix

`SDC4185_D65.icm` is an ICC v4.3 profile generated from numbers by
[`tools/build-icc.ps1`](tools/build-icc.ps1). It contains no data copied from the Samsung file.

| Item | Value | Source |
|---|---|---|
| Primaries | R (0.6797, 0.3203), G (0.2373, 0.7227), B (0.1396, 0.0498) | Panel EDID |
| White point | D65 (0.3127, 0.3290) | Factory calibration target (assumed) |
| Tone curve | Gamma 2.2 | Panel EDID |
| Luminance | 400 cd/m² | Panel SDR rating |

The colorants are Bradford-adapted to D50, `wtpt` is D50, and the adaptation is stored in `chad`, as
ICC v4 specifies. Windows then reads the white point as D65.

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

## Revert

```powershell
powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Revert
```

This removes the `SDC4185_D65.icm` association. Windows falls back to the next associated profile.

## Build from source

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-icc.ps1
```

The output, `dist\SDC4185_D65.icm`, is byte-identical to the release asset (same SHA-256).

## Scope and assumptions

- Tested on one Galaxy Book3 Pro 16" (960XFG, panel `SDC4185`, Intel Iris Xe Graphics) with
  Windows 11 26H1 (build 28000). Other panels are not covered.
- The D65 white point is an assumption based on the display being factory-calibrated, not a
  measurement of this unit. The EDID lists a slightly bluer white (0.3047, 0.3213). A profile made with
  a colorimeter for your own unit will be more accurate.
- The primaries only affect saturated colors. Gray balance depends on the white point.
- Reinstalling Samsung's *Display Color Profile* package makes `SDC4185.icm` the default again; run
  `fix.ps1 -Apply` afterwards. See [docs/samsung-display-profile.md](docs/samsung-display-profile.md)
  for what the package installs.

## License

[MIT](LICENSE)
