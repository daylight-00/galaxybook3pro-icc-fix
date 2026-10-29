# Root cause

## The Samsung profile

`SDC4185.icm` ("Samsung AMOLED Profile", installed by Samsung's *Display Color Profile* package) is an
ICC v2.1 matrix/TRC profile containing:

- colorants adapted to the D50 profile connection space,
- a `chad` tag with the Bradford D65 → D50 adaptation,
- a `wtpt` tag of **D65**.

For display profiles that carry a `chad` tag, the ICC v4 convention is `wtpt` = D50, with the actual
white given by `chad`.

## What Windows reads

Windows undoes the `chad` adaptation on the colorants, which recovers the panel primaries, and also on
`wtpt`. Because `wtpt` is already D65, the second adaptation moves it to x 0.2806, y 0.2958
(about 9,500 K). This is the white point DXGI reports for the display.

ACM then compensates for a panel it believes to be bluish and lowers blue by about 20%, so neutral
content looks warm. Modeling the panel with its EDID primaries and a D65 native white puts the
resulting white at about x 0.328, y 0.355 (roughly 5,700 K). On screen the cast is most visible on
white and gray.

Without ACM, Windows does not use this profile to transform the desktop, so the `wtpt` value has no
visible effect. It starts to matter once ACM reads the profile.

## How this was confirmed

| Check | Samsung `SDC4185.icm` | `SDC4185_D65.icm` |
|---|---|---|
| White point from DXGI (`IDXGIOutput6::GetDesc1`) | x 0.2806, y 0.2958 | x 0.3127, y 0.3290 |
| Row sums of the ACM transform in the Intel driver (`OSLinearColorTransformCsc_Wcg_*`) | R 0.985, G 0.994, B 0.794 | R 0.976, G 0.992, B 1.007 |

- The DXGI white point matches the Samsung profile's `wtpt` adapted with the inverse of `chad` to four
  decimals. The reported primaries match the colorants adapted once.
- Making the Samsung profile the default again reproduces the original driver transform exactly.
- Night Light, the gamma ramp (identity), and the Samsung monitor driver were ruled out.

## When Windows ignores the profile

`fix.ps1` associates the profile for the current user. Windows uses per-user associations for a
monitor device only when `UsePerUserProfiles` is 1 in that device's key under
`HKCU\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display` ("Use my settings
for this device" in Color Management).

After a clean Windows install, the profile was applied while the panel was still a *Generic PnP
Monitor*. Windows Update then installed Samsung's monitor driver, which moved the panel to a new device
key. The association was carried over but `UsePerUserProfiles` was not, and after a restart Windows
fell back to a "Microsoft Emulated Color Profile" built from the EDID. The default profile still read
`SDC4185_D65.icm`, but DXGI reported the EDID white (x 0.3047, y 0.3213), which gives a mild warm cast
under ACM. Making another profile the default did not change the DXGI values either.

Setting `UsePerUserProfiles` and associating the profile again restored the D65 white. Windows appears
to read the value only at sign-in or when the device arrives: clearing it again in the same session did
not bring the EDID white back. `fix.ps1 -Apply` sets the value on every device key that lists the
profile.
