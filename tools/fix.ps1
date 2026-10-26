<#
.SYNOPSIS
    Checks, applies or reverts the SDC4185_D65.icm display profile on a Galaxy Book3 Pro 16" (panel SDC4185).

.DESCRIPTION
    -Check   (default) Read-only. Shows the default display profiles, inspects the default profile's
             white point tags, and prints the white point Windows actually uses (DXGI).
    -Apply   Copies SDC4185_D65.icm into the Windows color directory and sets it as the default
             profile for both SDR and Auto Color Management, for the current user.
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

        // Returns {Rx, Ry, Gx, Gy, Bx, By, Wx, Wy} from IDXGIOutput6::GetDesc1 for the given GDI device name, or null.
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
                                    result = new float[8];
                                    Marshal.Copy(IntPtr.Add(desc, 104), result, 0, 8);
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
            GdiName  = [Text.Encoding]::Unicode.GetString($source, 20, 64).TrimEnd([char]0)
        }
    }
    return $null
}

function Get-DefaultProfile($display, [int]$subType) {
    # subType 7 = standard (SDR) color mode, 8 = advanced color (ACM/HDR). Scope 1 = current user.
    $name = [IntPtr]::Zero
    $hr = [GalaxyBookIcc.Native]::ColorProfileGetDisplayDefault(1, $display.Adapter, $display.SourceId, 0, $subType, [ref]$name)
    if ($hr -ne 0 -or $name -eq [IntPtr]::Zero) { return $null }
    return [Runtime.InteropServices.Marshal]::PtrToStringUni($name)
}

function Get-WhitePointTags([string]$path) {
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

function Wait-WhitePointChange($display, $before) {
    # Windows updates the output colorimetry asynchronously after an association change.
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 300
        $now = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
        if (-not $before -or -not $now -or $now[6] -ne $before[6] -or $now[7] -ne $before[7]) { return }
    }
}

function Show-Status($display) {
    $acm = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorDataStore' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like "$PanelId*" } | Select-Object -First 1 |
        ForEach-Object { (Get-ItemProperty $_.PSPath).AutoColorManagementEnabled }
    $sdr = Get-DefaultProfile $display 7
    $acmProfile = Get-DefaultProfile $display 8

    '{0,-18}{1} ({2})' -f 'Display', $display.GdiName, $PanelId
    '{0,-18}{1}' -f 'Auto color mgmt', $(if ($acm -eq 1) { 'On' } elseif ($acm -eq 0) { 'Off' } else { 'Unknown' })
    '{0,-18}SDR: {1}   ACM: {2}' -f 'Default profile', $(if ($sdr) { $sdr } else { '(none)' }), $(if ($acmProfile) { $acmProfile } else { '(none)' })

    $active = if ($acmProfile) { $acmProfile } else { $sdr }
    if ($active -and (Test-Path (Join-Path $ColorDir $active))) {
        $tags = Get-WhitePointTags (Join-Path $ColorDir $active)
        if ($tags.Wtpt) {
            $isD50 = [Math]::Abs($tags.Wtpt[0] - 0.9642) -lt 0.001 -and [Math]::Abs($tags.Wtpt[2] - 0.8249) -lt 0.001
            $note = if ($tags.HasChad -and -not $isD50) { 'wtpt is not D50 while chad is present; Windows adapts it twice' } else { 'OK' }
            '{0,-18}{1}  v{2}  wtpt ({3:N4}, {4:N4}, {5:N4})  chad: {6}  -> {7}' -f 'Profile tags', $active, $tags.Version,
                $tags.Wtpt[0], $tags.Wtpt[1], $tags.Wtpt[2], $(if ($tags.HasChad) { 'yes' } else { 'no' }), $note
        }
        else { '{0,-18}{1}  v{2}  no wtpt tag' -f 'Profile tags', $active, $tags.Version }
    }

    $c = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
    if ($c) {
        $delta = Get-DeltaUV $c[6] $c[7]
        '{0,-18}({1:N4}, {2:N4})  delta u''v'' from D65 = {3:N4}  -> {4}' -f 'Windows white', $c[6], $c[7], $delta,
            $(if ($delta -lt 0.004) { 'OK' } else { 'not D65; ACM will tint the screen' })
    }
}

$display = Get-PanelDisplay
if (-not $display) { throw "No active display with panel $PanelId was found. This script only supports the Galaxy Book3 Pro 16 panel." }
$whiteBefore = [GalaxyBookIcc.Native]::GetOutputColorimetry($display.GdiName)
$defaultsBefore = '{0}|{1}' -f (Get-DefaultProfile $display 7), (Get-DefaultProfile $display 8)

if ($Apply) {
    if (-not $ProfilePath) {
        $ProfilePath = @((Join-Path $PSScriptRoot $ProfileName), (Join-Path $PSScriptRoot "..\dist\$ProfileName")) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) { throw "$ProfileName not found. Place it next to this script or pass -ProfilePath." }

    Copy-Item $ProfilePath (Join-Path $ColorDir $ProfileName) -Force
    foreach ($advancedColor in $false, $true) {
        $hr = [GalaxyBookIcc.Native]::ColorProfileAddDisplayAssociation(1, $ProfileName, $display.Adapter, $display.SourceId, $true, $advancedColor)
        if ($hr -ne 0) { throw ('Associating {0} failed (0x{1:X8}).' -f $ProfileName, $hr) }
    }
    "Applied $ProfileName as the default SDR and ACM profile for the current user."
    ''
}
elseif ($Revert) {
    foreach ($advancedColor in $false, $true) {
        [void][GalaxyBookIcc.Native]::ColorProfileRemoveDisplayAssociation(1, $ProfileName, $display.Adapter, $display.SourceId, $advancedColor)
    }
    "Removed the $ProfileName association for the current user."
    ''
}

$defaultsAfter = '{0}|{1}' -f (Get-DefaultProfile $display 7), (Get-DefaultProfile $display 8)
if ($defaultsAfter -ne $defaultsBefore) { Wait-WhitePointChange $display $whiteBefore }
Show-Status $display
