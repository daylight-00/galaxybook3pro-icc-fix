# Wide-gamut content in browsers

With Auto Color Management (ACM) on, wide-gamut images can look correct in Windows Photos but be limited
to sRGB in Edge or Chrome. This is expected Windows behavior and is independent of the display profile.

## Why

Windows treats apps in two groups when ACM is active
([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wcs/advanced-color-icc-profiles)):

- **ACM-aware apps**, such as Windows Photos, tag their output with its color space. Windows converts it
  to the panel and wide-gamut content keeps its range.
- **Apps that do their own ICC color management**, such as browsers, normally read the display profile
  and convert their content to it. Under ACM, Windows answers that query with "no profile" (sRGB) to
  avoid converting the same content twice. These apps therefore color-manage to sRGB and stay within
  the sRGB gamut.

## Enabling the full gamut for a browser

Windows 11 provides a per-app *display ICC compatibility helper* for the second group:

1. Open the properties of the browser executable, for example
   `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`.
2. On the **Compatibility** tab, select **Use legacy display ICC color management**.
3. Quit the browser completely, including background processes, and start it again.

With the helper on, the browser receives a profile that Windows builds from the display's colorimetry,
here taken from `SDC4185_D65.icm`. Windows then treats the browser's output as targeting the display
and converts it accordingly. The helper applies to the whole process and only takes effect while ACM
is active.

The setting is stored per user as the compatibility layer `TRANSFORMLEGACYCOLORMANAGED` under
`HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers`, keyed by the executable path.

## Checking

The [WebKit color gamut test](https://webkit.org/blog-files/color-gamut/) shows images whose details are
visible only when wide-gamut colors are rendered. Opening the same images in Windows Photos gives a
reference.

## Tested

Edge on the setup described in the [README](../README.md#scope). Other Chromium-based browsers are
expected to behave the same but were not tested; each needs the setting on its own executable.
