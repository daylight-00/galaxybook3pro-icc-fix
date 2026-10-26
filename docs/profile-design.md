# How SDC4185_D65.icm is built

`SDC4185_D65.icm` is an ICC v4.3 matrix/TRC display profile generated from numbers by
[`tools/build-icc.ps1`](../tools/build-icc.ps1). It contains no data copied from the Samsung file.

## Values

| Item | Value | Source |
|---|---|---|
| Primaries | R (0.6797, 0.3203), G (0.2373, 0.7227), B (0.1396, 0.0498) | Panel EDID |
| White point | D65 (0.3127, 0.3290) | Factory calibration target (assumed) |
| Tone curve | Gamma 2.2 | Panel EDID |
| Luminance | Peak 565.7, full-frame 400, minimum 0.0043 cd/m² | Panel EDID (HDR static metadata) |

The colorants are Bradford-adapted to D50, `wtpt` is D50, and the adaptation is stored in `chad`, as
ICC v4 specifies. Windows then reads the white point as D65.

`lumi` holds the full-frame luminance. A Microsoft `MHC2` tag holds the minimum and peak luminance; its
matrix and LUTs are identity, so it changes no pixel values.

## Assumptions

- **White point.** D65 is assumed because the display is sold as factory-calibrated; it is not a
  measurement of this unit. The EDID lists a slightly bluer white (0.3047, 0.3213), and the Samsung
  profile also describes the panel white as D65. A profile made with a colorimeter for your own unit
  will be more accurate.
- **Primaries.** They only affect saturated colors. Gray balance depends on the white point alone.

## HDR mode

Windows keeps two default profile associations per display: *standard*, used for SDR including ACM,
and *extended*, used in HDR mode
([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wcs/advanced-color-icc-profiles)).
`fix.ps1 -Apply` sets this profile for both.

In HDR mode, Windows takes the peak and minimum luminance from `MHC2` and the full-frame luminance from
`lumi`. Without `MHC2`, it uses `lumi` for the peak as well. Version 1.0.0 had no `MHC2` tag, so in HDR
mode Windows reported the peak as equal to the full-frame level (no headroom) and the minimum as 0; apps
that tone-map to the reported peak would compress highlights to SDR white. SDR behavior was not affected.

On this laptop, luminance in HDR mode is reported relative to the current SDR white level, which Windows
maps to 80 cd/m². Measured with the EDID luminance values:

| Brightness | Peak reported | Full-frame reported | Implied SDR white |
|---|---|---|---|
| 100% | 113.1 | 80.0 | 400 cd/m² |
| 50% | 502.9 | 355.6 | 90 cd/m² |
| 20% | 1,885.7 | 1,333.3 | 24 cd/m² |

At full brightness, SDR white already uses the panel's 400 cd/m² full-frame level, so the HDR headroom
is 565.7 / 400 ≈ 1.41×. This reading is inferred from the measurements rather than from documentation.

The white point reported in HDR mode follows the profile (D65). The driver's HDR color transform stayed
identity with every profile tested, so the white point does not change pixel values in HDR mode.

## Building

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-icc.ps1
```

The script writes `dist\SDC4185_D65.icm`. The output is deterministic (fixed creation date, MD5
profile ID), so a local build is byte-identical to the release asset and has the same SHA-256. It runs
on Windows PowerShell 5.1 and PowerShell 7.
