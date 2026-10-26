# Samsung Display Color Profile package

Notes on what Samsung's *Display Color Profile* package (5.4.0.0; MSI product "Display Profile" 5.3)
installs on a Galaxy Book3 Pro 16" (panel `SDC4185`), and how its profiles relate to Windows Auto Color
Management (ACM).

## Installation flow

1. `Inst.exe` runs the commands listed in `Inst.ini` silently: it uninstalls the previous version of
   the product, then installs `setup\DisplayProfileSetup.msi`.
2. The MSI copies its payload to `C:\ProgramData\ColorMode`:
   - per-GPU configuration files (Intel, AMD, NVIDIA),
   - ICC profiles for several Samsung panels (`icc\`),
   - 3D LUTs for some non-Samsung panels (`lut\`),
   - `DisplayProfileRegister.exe` and a Task Scheduler definition.
3. A deferred custom action runs `DisplayProfileRegister.exe /INSTALL` as SYSTEM. It:
   - identifies the panel and looks it up in the configuration files, which list it as panel part
     `ATNA60CL03` and map it to the `SDC4185` profiles,
   - installs the five `SDC4185` profiles into the Windows color directory and associates them with the
     display,
   - sets `SDC4185.icm` as the default profile,
   - registers the scheduled task `InitDisplayProfile`, which runs `DisplayProfileRegister.exe` at every
     logon.
4. Uninstalling the MSI runs `DisplayProfileRegister.exe /REMOVE`.

On the tested unit, the same five profiles were already present from the factory image.

## Profiles

| File | Description tag | Content |
|---|---|---|
| `SDC4185.icm` | Samsung AMOLED Profile | Native panel gamut, gamma 2.2, 400 cd/m². Default profile. |
| `SDC4185Settings.icm` | Samsung Settings Auto mode | Same colorants as `SDC4185.icm`. |
| `SDC4185S.icm` | Samsung AMOLED sRGB Profile | sRGB colorants plus an `MHC2` tag. |
| `SDC4185P.icm` | Samsung AMOLED P3 Profile | Display P3 colorants plus an `MHC2` tag. |
| `SDC4185A.icm` | Samsung AMOLED AdobeRGB Profile | Adobe RGB colorants plus an `MHC2` tag. |

All five are ICC v2.1 profiles with D50-adapted colorants, a Bradford `chad` tag, and `wtpt` = D65.
The `MHC2` tag is Microsoft's hardware calibration tag. It carries a 3×4 matrix (and here an identity
1D LUT) that Windows applies to everything shown on the display.

The Samsung monitor driver (`sec_mon7.inf`, "Samsung OLED Display") is separate from this package. It
only sets `EnableBoostRefreshRateByDefault` and contains no color settings.

## Why the mode profiles exist

Without ACM, Windows sends application output to the panel unchanged. Most applications produce sRGB,
which looks oversaturated on a wide-gamut panel; only color-managed applications read the display
profile. The `MHC2` mode profiles let Windows apply a matrix to the whole desktop so that the panel
emulates sRGB, Display P3 or Adobe RGB. Reviews measured an average ΔE of about 0.5 in these modes
([Expert Reviews](https://www.expertreviews.co.uk/technology/laptops/samsung-galaxy-book3-pro-14-inch-review)).
Only one mode can be active at a time.

The timing fits this role. The package files are dated December 2022, shortly before the Galaxy Book3
Pro went on sale. Windows 11 22H2 had introduced ACM for SDR displays in October 2022, but only on
select, specially provisioned displays
([DirectX blog](https://devblogs.microsoft.com/directx/?p=6990)). It was extended to SDR displays in
general during 2023 ([Pureinfotech](https://pureinfotech.com/?p=152933)) and is off by default
([MSI](https://ua.msi.com/faq/faq-11010)). The `MHC2` tag itself has been supported since Windows 10
version 2004 ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wcs/display-calibration-mhc)).
At the time, the mode profiles offered desktop-wide color emulation that Windows did not yet provide on
this hardware.

## With ACM

ACM composes the desktop in a wide color space and converts each application's content to the panel,
treating unmanaged content as sRGB. It needs one accurate description of the panel rather than a set of
emulation modes, so sRGB content and wide-gamut content are each shown correctly at the same time.

ACM takes that description from the default profile. With `SDC4185.icm` it reads the white point as
x 0.2806, y 0.2958, which causes the warm cast described in the [README](../README.md).
`SDC4185_D65.icm` describes the same panel with the white point read as D65.

Because `DisplayProfileRegister.exe` sets `SDC4185.icm` as the default when it runs, reinstalling the
package brings the cast back. Running `fix.ps1 -Apply` again restores `SDC4185_D65.icm` as the default.
