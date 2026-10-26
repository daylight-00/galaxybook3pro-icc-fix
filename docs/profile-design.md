# How SDC4185_D65.icm is built

`SDC4185_D65.icm` is an ICC v4.3 matrix/TRC display profile generated from numbers by
[`tools/build-icc.ps1`](../tools/build-icc.ps1). It contains no data copied from the Samsung file.

## Values

| Item | Value | Source |
|---|---|---|
| Primaries | R (0.6797, 0.3203), G (0.2373, 0.7227), B (0.1396, 0.0498) | Panel EDID |
| White point | D65 (0.3127, 0.3290) | Factory calibration target (assumed) |
| Tone curve | Gamma 2.2 | Panel EDID |
| Luminance | 400 cd/m² | Panel SDR rating |

The colorants are Bradford-adapted to D50, `wtpt` is D50, and the adaptation is stored in `chad`, as
ICC v4 specifies. Windows then reads the white point as D65.

## Assumptions

- **White point.** D65 is assumed because the display is sold as factory-calibrated; it is not a
  measurement of this unit. The EDID lists a slightly bluer white (0.3047, 0.3213), and the Samsung
  profile also describes the panel white as D65. A profile made with a colorimeter for your own unit
  will be more accurate.
- **Primaries.** They only affect saturated colors. Gray balance depends on the white point alone.

## Building

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-icc.ps1
```

The script writes `dist\SDC4185_D65.icm`. The output is deterministic (fixed creation date, MD5
profile ID), so a local build is byte-identical to the release asset and has the same SHA-256. It runs
on Windows PowerShell 5.1 and PowerShell 7.
