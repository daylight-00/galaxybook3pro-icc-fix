<#
.SYNOPSIS
    Checks, applies or reverts the SDC4185_D65.icm display profile on a Galaxy Book3 Pro 16" (panel SDC4185).

.DESCRIPTION
    -Check   (default) Read-only. Shows the color mode and default display profiles, inspects the
             profile in use, and prints the white point and luminance Windows actually uses (DXGI).
    -Apply   Copies SDC4185_D65.icm into the Windows color directory and sets it as the default
             profile for SDR (including Auto Color Management) and HDR, for the current user.
    -Revert  Removes the SDC4185_D65.icm association for the current user.

    No administrator rights are required.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File fix.ps1 -Apply
#>
[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Check')][switch]$Check,
    [Parameter(ParameterSetName = 'Apply', Mandatory = $true)][switch]$Apply,
    [Parameter(ParameterSetName = 'Revert', Mandatory = $true)][switch]$Revert,
    [Parameter(ParameterSetName = 'Apply')][string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProfileName = 'SDC4185_D65.icm'
$PanelId     = 'SDC4185'
$ColorDir    = Join-Path $env:WINDIR 'System32\spool\drivers\color'
$AssociationKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display\{4d36e96e-e325-11ce-bfc1-08002be10318}'

if (-not ('GalaxyBookIcc.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace GalaxyBookIcc {
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    public static class Native {
        [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
        [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, byte[] paths, ref uint modeCount, byte[] modes, IntPtr topology);
        [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(byte[] packet);

        [DllImport("mscms.dll", CharSet = CharSet.Unicode)] public static extern int ColorProfileGetDisplayDefault(int scope, LUID adapter, uint sourceId, int type, int subType, out IntPtr name);
        [DllImport("mscms.dll", CharSet = CharSet.Unicode)] public static extern int ColorProfileAddDisplayAssociation(int scope, string name, LUID adapter, uint sourceId, bool setAsDefault, bool advancedColor);
        [DllImport("mscms.dll", CharSet = CharSet.Unicode)] public static extern int ColorProfileRemoveDisplayAssociation(int scope, string name, LUID adapter, uint sourceId, bool advancedColor);

        [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr factory);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int EnumFn(IntPtr self, uint index, out IntPtr item);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int QueryInterfaceFn(IntPtr self, ref Guid riid, out IntPtr item);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate uint ReleaseFn(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetDescFn(IntPtr self, IntPtr desc);

        static T Method<T>(IntPtr obj, int slot) {
            IntPtr vtable = Marshal.ReadIntPtr(obj);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtable, slot * IntPtr.Size), typeof(T));
        }

        // Returns {Rx, Ry, Gx, Gy, Bx, By, Wx, Wy, MinLuminance, MaxLuminance, MaxFullFrameLuminance}
        // from IDXGIOutput6::GetDesc1 for the given GDI device name, or null.
        public static float[] GetOutputColorimetry(string gdiDeviceName) {
            Guid factoryId = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
            Guid output6Id = new Guid("068346e8-aaec-4b84-add7-137f513f77a1");
            IntPtr factory;
            if (CreateDXGIFactory1(ref factoryId, out factory) != 0) return null;
            float[] result = null;
            try {
                IntPtr adapter;
                for (uint a = 0; result == null && Method<EnumFn>(factory, 12)(factory, a, out adapter) == 0; a++) {
                    IntPtr output;
                    for (uint o = 0; result == null && Method<EnumFn>(adapter, 7)(adapter, o, out output) == 0; o++) {
                        IntPtr output6;
                        if (Method<QueryInterfaceFn>(output, 0)(output, ref output6Id, out output6) == 0) {
                            IntPtr desc = Marshal.AllocHGlobal(256);
                            try {
                                if (Method<GetDescFn>(output6, 27)(output6, desc) == 0 &&
                                    string.Equals(Marshal.PtrToStringUni(desc), gdiDeviceName, StringComparison.OrdinalIgnoreCase)) {
                                    result = new float[11];
                                    Marshal.Copy(IntPtr.Add(desc, 104), result, 0, 11);
                                }
                            } finally { Marshal.FreeHGlobal(desc); }
                            Method<ReleaseFn>(output6, 2)(output6);
                        }
                        Method<ReleaseFn>(output, 2)(output);
                    }
                    Method<ReleaseFn>(adapter, 2)(adapter);
                }
            } finally { Method<ReleaseFn>(factory, 2)(factory); }
            return result;
        }
    }
}
'@
}

function Get-PanelDisplay {
    # Finds the active display path whose EDID identifies the SDC4185 panel.
    $pathCount = [uint32]0; $modeCount = [uint32]0
    [void][GalaxyBookIcc.Native]::GetDisplayConfigBufferSizes(2, [ref]$pathCount, [ref]$modeCount)
    $paths = New-Object byte[] (72 * $pathCount); $modes = New-Object byte[] (64 * $modeCount)
    $rc = [GalaxyBookIcc.Native]::QueryDisplayConfig(2, [ref]$pathCount, $paths, [ref]$modeCount, $modes, [IntPtr]::Zero)
    if ($rc -ne 0) { throw "QueryDisplayConfig failed ($rc)." }

    for ($i = 0; $i -lt $pathCount; $i++) {
        $p = 72 * $i
        $adapter = New-Object GalaxyBookIcc.LUID
        $adapter.LowPart = [BitConverter]::ToUInt32($paths, $p + 20)
        $adapter.HighPart = [BitConverter]::ToInt32($paths, $p + 24)
        $sourceId = [BitConverter]::ToUInt32($paths, $p + 8)
        $targetId = [BitConverter]::ToUInt32($paths, $p + 28)

        # DISPLAYCONFIG_TARGET_DEVICE_NAME (type 2): EDID manufacturer/product codes and device path.
        $target = New-Object byte[] 420
        [BitConverter]::GetBytes([uint32]2).CopyTo($target, 0)
        [BitConverter]::GetBytes([uint32]420).CopyTo($target, 4)
        [Array]::Copy($paths, $p + 20, $target, 8, 8)
        [BitConverter]::GetBytes($targetId).CopyTo($target, 16)
        if ([GalaxyBookIcc.Native]::DisplayConfigGetDeviceInfo($target) -ne 0) { continue }
        $devicePath = [Text.Encoding]::Unicode.GetString($target, 164, 256).TrimEnd([char]0)
        if ($devicePath -notmatch "#$PanelId#") { continue }

        # DISPLAYCONFIG_SOURCE_DEVICE_NAME (type 1): GDI name such as \\.\DISPLAY1.
        $source = New-Object byte[] 84
        [BitConverter]::GetBytes([uint32]1).CopyTo($source, 0)
        [BitConverter]::GetBytes([uint32]84).CopyTo($source, 4)
        [Array]::Copy($paths, $p, $source, 8, 8)
        [BitConverter]::GetBytes($sourceId).CopyTo($source, 16)
        [void][GalaxyBookIcc.Native]::DisplayConfigGetDeviceInfo($source)

        return [pscustomobject]@{
            Adapter  = $adapter
            SourceId = $sourceId
            TargetId = $targetId
            GdiName  = [Text.Encoding]::Unicode.GetString($source, 20, 64).TrimEnd([char]0)
        }
    }
    return $null
}

function Get-ColorMode($display) {
    # DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 (type 15): active color mode 0 = SDR, 1 = WCG (ACM), 2 = HDR.
    $packet = New-Object byte[] 36
    [BitConverter]::GetBytes([uint32]15).CopyTo($packet, 0)
    [BitConverter]::GetBytes([uint32]36).CopyTo($packet, 4)
    [BitConverter]::GetBytes($display.Adapter.LowPart).CopyTo($packet, 8)
    [BitConverter]::GetBytes($display.Adapter.HighPart).CopyTo($packet, 12)
    [BitConverter]::GetBytes($display.TargetId).CopyTo($packet, 16)
    if ([GalaxyBookIcc.Native]::DisplayConfigGetDeviceInfo($packet) -ne 0) { return 'Unknown' }
    switch ([BitConverter]::ToUInt32($packet, 32)) { 0 { 'SDR' } 1 { 'SDR with ACM' } 2 { 'HDR' } default { 'Unknown' } }
}

function Get-DefaultProfile($display, [int]$subType) {
    # subType 7 = standard (SDR, including ACM), 8 = extended (HDR). Scope 1 = current user.
    $name = [IntPtr]::Zero
    $hr = [GalaxyBookIcc.Native]::ColorProfileGetDisplayDefault(1, $display.Adapter, $display.SourceId, 0, $subType, [ref]$name)
    if ($hr -ne 0 -or $name -eq [IntPtr]::Zero) { return $null }
    return [Runtime.InteropServices.Marshal]::PtrToStringUni($name)
}

function Add-Association($display) {
    foreach ($advancedColor in $false, $true) {
        $hr = [GalaxyBookIcc.Native]::ColorProfileAddDisplayAssociation(1, $ProfileName, $display.Adapter, $display.SourceId, $true, $advancedColor)
        if ($hr -ne 0) { throw ('Associating {0} failed (0x{1:X8}).' -f $ProfileName, $hr) }
    }
}

function Remove-Association($display) {
    foreach ($advancedColor in $false, $true) {
        [void][GalaxyBookIcc.Native]::ColorProfileRemoveDisplayAssociation(1, $ProfileName, $display.Adapter, $display.SourceId, $advancedColor)
    }
}

function Enable-PerUserProfiles {
    # Windows ignores the current user's associations for a monitor device unless UsePerUserProfiles is 1
    # ("Use my settings for this device"). Sets it on every device key that lists the profile and returns
    # $true if any key changed.
    $changed = $false
    foreach ($key in Get-ChildItem $AssociationKey -ErrorAction SilentlyContinue) {
        if (@($key.GetValue('ICMProfile')) -contains $ProfileName -and $key.GetValue('UsePerUserProfiles') -ne 1) {
            Set-ItemProperty $key.PSPath UsePerUserProfiles 1 -Type DWord
            $changed = $true
        }
    }
    return $changed
}

function Get-ProfileTags([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    $be32 = { param($o) [uint32]([uint32]$b[$o] * 16777216 + [uint32]$b[$o + 1] * 65536 + [uint32]$b[$o + 2] * 256 + [uint32]$b[$o + 3]) }
    $s15 = { param($o) $v = [int64](& $be32 $o); if ($v -ge 2147483648) { $v -= 4294967296 }; $v / 65536.0 }
    $tags = @{}
    for ($i = 0; $i -lt (& $be32 128); $i++) {
        $o = 132 + 12 * $i
        $tags[[Text.Encoding]::ASCII.GetString($b, $o, 4)] = [int](& $be32 ($o + 4))
    }
    $wtpt = $null
    if ($tags.ContainsKey('wtpt')) { $w = $tags['wtpt']; $wtpt = @((& $s15 ($w + 8)), (& $s15 ($w + 12)), (& $s15 ($w + 16))) }
    return [pscustomobject]@{
        Version = '{0}.{1}' -f $b[8], ($b[9] -shr 4)
        Wtpt    = $wtpt
        HasChad = $tags.ContainsKey('chad')
        HasMhc2 = $tags.ContainsKey('MHC2')
    }
}

function Get-DeltaUV($x, $y) {
    # Distance from D65 in CIE 1976 u'v'.
    $d = -2 * $x + 12 * $y + 3
    $d65 = -2 * 0.3127 + 12 * 0.3290 + 3
    $du = 4 * $x / $d - 4 * 0.3127 / $d65
    $dv = 9 * $y / $d - 9 * 0.3290 / $d65
    return [Math]::Sqrt($du * $du + $dv * $dv)
}

function Wait-OutputChange($display, $before) {
    # Windows updates the output colorimetry asynchronously after an association change.
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 300
        $now = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
        if (-not $before -or -not $now -or (Compare-Object $before $now)) { return }
    }
}

function Show-Status($display) {
    $mode = Get-ColorMode $display
    $sdr = Get-DefaultProfile $display 7
    $hdr = Get-DefaultProfile $display 8

    '{0,-18}{1} ({2})' -f 'Display', $display.GdiName, $PanelId
    '{0,-18}{1}' -f 'Color mode', $mode
    '{0,-18}SDR: {1}   HDR: {2}' -f 'Default profile', $(if ($sdr) { $sdr } else { '(none)' }), $(if ($hdr) { $hdr } else { '(none, EDID)' })

    # SDR and SDR with ACM use the standard association; HDR uses the extended one.
    $active = if ($mode -eq 'HDR') { $hdr } else { $sdr }
    if ($active -and (Test-Path (Join-Path $ColorDir $active))) {
        $tags = Get-ProfileTags (Join-Path $ColorDir $active)
        $notes = @()
        if ($tags.Wtpt) {
            $isD50 = [Math]::Abs($tags.Wtpt[0] - 0.9642) -lt 0.001 -and [Math]::Abs($tags.Wtpt[2] - 0.8249) -lt 0.001
            if ($tags.HasChad -and -not $isD50) { $notes += 'wtpt is not D50 while chad is present; Windows adapts it twice' }
            $wtpt = '({0:N4}, {1:N4}, {2:N4})' -f $tags.Wtpt[0], $tags.Wtpt[1], $tags.Wtpt[2]
        }
        else { $wtpt = '(none)' }
        if ($mode -eq 'HDR' -and -not $tags.HasMhc2) { $notes += 'no MHC2 tag; peak luminance falls back to lumi' }
        '{0,-18}{1}  v{2}  wtpt {3}  chad: {4}  MHC2: {5}  -> {6}' -f 'Profile tags', $active, $tags.Version, $wtpt,
            $(if ($tags.HasChad) { 'yes' } else { 'no' }), $(if ($tags.HasMhc2) { 'yes' } else { 'no' }),
            $(if ($notes) { $notes -join '; ' } else { 'OK' })
    }

    $c = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
    if ($c) {
        $delta = Get-DeltaUV $c[6] $c[7]
        '{0,-18}({1:N4}, {2:N4})  delta u''v'' from D65 = {3:N4}  -> {4}' -f 'Windows white', $c[6], $c[7], $delta,
            $(if ($delta -lt 0.004) { 'OK' } else { 'not D65' })
        if ($delta -ge 0.004 -and $active -eq $ProfileName) {
            '{0,-18}{1}' -f '', "Windows is not using $ProfileName. Run fix.ps1 -Apply again."
        }
        $luminance = 'min {0:N4}  peak {1:N1}  full-frame {2:N1} cd/m2' -f $c[8], $c[9], $c[10]
        if ($mode -eq 'HDR') {
            # In HDR, Windows reports luminance relative to the current SDR white, which it maps to 80 cd/m2.
            $headroom = $c[9] / 80
            $luminance += '  HDR headroom x{0:N2}  -> {1}' -f $headroom, $(if ($headroom -gt 1.01) { 'OK' } else { 'no headroom reported' })
        }
        '{0,-18}{1}' -f 'Windows luminance', $luminance
    }
}

$display = Get-PanelDisplay
if (-not $display) { throw "No active display with panel $PanelId was found. This script only supports the Galaxy Book3 Pro 16 panel." }
$outputBefore = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
$defaultsBefore = '{0}|{1}' -f (Get-DefaultProfile $display 7), (Get-DefaultProfile $display 8)
$contentChanged = $false

if ($Apply) {
    if (-not $ProfilePath) {
        $ProfilePath = @((Join-Path $PSScriptRoot $ProfileName), (Join-Path $PSScriptRoot "..\dist\$ProfileName")) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) { throw "$ProfileName not found. Place it next to this script or pass -ProfilePath." }

    $installed = Join-Path $ColorDir $ProfileName
    $installedBefore = Test-Path $installed
    if ($installedBefore) { $contentChanged = (Get-FileHash $ProfilePath).Hash -ne (Get-FileHash $installed).Hash }
    # Copy before touching the associations so that a failed copy leaves them as they were.
    if (-not $installedBefore -or $contentChanged) { Copy-Item $ProfilePath $installed -Force }
    # Windows keeps the previously loaded profile data until the association changes.
    if ($contentChanged) { Remove-Association $display }
    Add-Association $display
    # A monitor driver install can leave the association on a device key without UsePerUserProfiles.
    if (Enable-PerUserProfiles) {
        Remove-Association $display
        Add-Association $display
        $contentChanged = $true
    }
    "Applied $ProfileName as the default SDR (including ACM) and HDR profile for the current user."
    ''
}
elseif ($Revert) {
    Remove-Association $display
    "Removed the $ProfileName association for the current user."
    ''
}

$defaultsAfter = '{0}|{1}' -f (Get-DefaultProfile $display 7), (Get-DefaultProfile $display 8)
if ($contentChanged -or $defaultsAfter -ne $defaultsBefore) { Wait-OutputChange $display $outputBefore }
Show-Status $display
