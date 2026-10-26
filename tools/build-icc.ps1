<#
.SYNOPSIS
    Builds dist/SDC4185_D65.icm, an ICC v4 display profile for the Samsung SDC4185 panel
    (Galaxy Book3 Pro 16").

.DESCRIPTION
    The profile is generated from numbers only:
      - primaries : the panel's EDID chromaticity (base block bytes 0x19-0x22)
      - white     : D65, assuming the panel is factory-calibrated to D65 (not measured)
      - tone curve: gamma 2.2 (EDID byte 0x17)
      - luminance : 400 cd/m2

    Following ICC.1:2010 (v4.3), the colorants are adapted to the D50 PCS with Bradford,
    'wtpt' is D50 and the adaptation is stored in 'chad'.

    The output is deterministic: running this script again produces the same bytes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build-icc.ps1
#>
[CmdletBinding()]
param(
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not available in param defaults on Windows PowerShell 5.1.
if (-not $OutFile) { $OutFile = Join-Path $PSScriptRoot '..\dist\SDC4185_D65.icm' }

# --- Inputs ---------------------------------------------------------------

# EDID base block bytes 0x19-0x22 of the SDC4185 panel (red/green/blue/white chromaticity).
$EdidChromaticity = [byte[]](0x0C, 0xF1, 0xAE, 0x52, 0x3C, 0xB9, 0x23, 0x0C, 0x4E, 0x52)
$WhiteXY          = @(0.3127, 0.3290)   # D65
$Gamma            = 2.2
$Luminance        = 400
$Description      = 'Samsung AMOLED D65 Profile'
$Copyright        = 'Copyright (c) 2026 David Hyunyoo Jang. MIT License.'
$CreationDate     = Get-Date -Year 2026 -Month 10 -Day 26 -Hour 0 -Minute 0 -Second 0

# --- 3x3 matrix helpers (jagged arrays) -----------------------------------

function Get-MatrixProduct($A, $B) {
    $result = @()
    for ($i = 0; $i -lt 3; $i++) {
        $row = @()
        for ($j = 0; $j -lt 3; $j++) {
            $row += $A[$i][0] * $B[0][$j] + $A[$i][1] * $B[1][$j] + $A[$i][2] * $B[2][$j]
        }
        $result += , $row
    }
    return , $result
}

function Get-MatrixVectorProduct($A, $v) {
    return , @(
        ($A[0][0] * $v[0] + $A[0][1] * $v[1] + $A[0][2] * $v[2]),
        ($A[1][0] * $v[0] + $A[1][1] * $v[1] + $A[1][2] * $v[2]),
        ($A[2][0] * $v[0] + $A[2][1] * $v[1] + $A[2][2] * $v[2]))
}

function Get-MatrixInverse($m) {
    $a = $m[0][0]; $b = $m[0][1]; $c = $m[0][2]
    $d = $m[1][0]; $e = $m[1][1]; $f = $m[1][2]
    $g = $m[2][0]; $h = $m[2][1]; $k = $m[2][2]
    $det = $a * ($e * $k - $f * $h) - $b * ($d * $k - $f * $g) + $c * ($d * $h - $e * $g)
    return , @(
        @((($e * $k - $f * $h) / $det), (($c * $h - $b * $k) / $det), (($b * $f - $c * $e) / $det)),
        @((($f * $g - $d * $k) / $det), (($a * $k - $c * $g) / $det), (($c * $d - $a * $f) / $det)),
        @((($d * $h - $e * $g) / $det), (($b * $g - $a * $h) / $det), (($a * $e - $b * $d) / $det)))
}

function ConvertTo-XYZ($xy) {
    return , @(($xy[0] / $xy[1]), 1.0, ((1 - $xy[0] - $xy[1]) / $xy[1]))
}

# --- Colorimetry ------------------------------------------------------------

function ConvertFrom-EdidChromaticity([byte[]]$bytes) {
    # bytes[0..1] hold the two low bits of each coordinate, bytes[2..9] the high eight bits.
    $low = @(
        (($bytes[0] -shr 6) -band 3), (($bytes[0] -shr 4) -band 3), (($bytes[0] -shr 2) -band 3), ($bytes[0] -band 3),
        (($bytes[1] -shr 6) -band 3), (($bytes[1] -shr 4) -band 3), (($bytes[1] -shr 2) -band 3), ($bytes[1] -band 3))
    $values = for ($i = 0; $i -lt 8; $i++) { ((([int]$bytes[2 + $i]) -shl 2) -bor $low[$i]) / 1024.0 }
    return [pscustomobject]@{
        Red   = @($values[0], $values[1])
        Green = @($values[2], $values[3])
        Blue  = @($values[4], $values[5])
        White = @($values[6], $values[7])
    }
}

function Get-RgbToXyzMatrix($red, $green, $blue, $white) {
    $p = @((ConvertTo-XYZ $red), (ConvertTo-XYZ $green), (ConvertTo-XYZ $blue))
    $primaries = @(
        @($p[0][0], $p[1][0], $p[2][0]),
        @($p[0][1], $p[1][1], $p[2][1]),
        @($p[0][2], $p[1][2], $p[2][2]))
    $scale = Get-MatrixVectorProduct (Get-MatrixInverse $primaries) (ConvertTo-XYZ $white)
    $result = @()
    for ($i = 0; $i -lt 3; $i++) {
        $result += , @(($primaries[$i][0] * $scale[0]), ($primaries[$i][1] * $scale[1]), ($primaries[$i][2] * $scale[2]))
    }
    return , $result
}

function Get-BradfordMatrix($sourceWhite, $destinationWhite) {
    $cone = @(
        @(0.8951, 0.2664, -0.1614),
        @(-0.7502, 1.7135, 0.0367),
        @(0.0389, -0.0685, 1.0296))
    $src = Get-MatrixVectorProduct $cone $sourceWhite
    $dst = Get-MatrixVectorProduct $cone $destinationWhite
    $gain = @(@(($dst[0] / $src[0]), 0, 0), @(0, ($dst[1] / $src[1]), 0), @(0, 0, ($dst[2] / $src[2])))
    return , (Get-MatrixProduct (Get-MatrixInverse $cone) (Get-MatrixProduct $gain $cone))
}

# --- ICC encoding (big-endian) ----------------------------------------------

function Get-UInt32Bytes([uint32]$value) {
    $b = [BitConverter]::GetBytes($value); [Array]::Reverse($b); return , $b
}

function Get-S15Fixed16Bytes([double]$value) {
    $b = [BitConverter]::GetBytes([int][Math]::Round($value * 65536)); [Array]::Reverse($b); return , $b
}

function Get-SignatureBytes([string]$signature) {
    return , [Text.Encoding]::ASCII.GetBytes($signature)
}

function New-XyzTag([double[]]$xyz) {
    $s = New-Object System.Collections.Generic.List[byte]
    $s.AddRange((Get-SignatureBytes 'XYZ ')); $s.AddRange([byte[]]::new(4))
    foreach ($v in $xyz) { $s.AddRange((Get-S15Fixed16Bytes $v)) }
    return , $s.ToArray()
}

function New-GammaCurveTag([double]$gamma) {
    $s = New-Object System.Collections.Generic.List[byte]
    $s.AddRange((Get-SignatureBytes 'curv')); $s.AddRange([byte[]]::new(4))
    $s.AddRange((Get-UInt32Bytes 1))
    $u8f8 = [uint16][Math]::Round($gamma * 256)
    $s.Add([byte]($u8f8 -shr 8)); $s.Add([byte]($u8f8 -band 0xFF))
    return , $s.ToArray()
}

function New-S15Fixed16ArrayTag($matrix) {
    $s = New-Object System.Collections.Generic.List[byte]
    $s.AddRange((Get-SignatureBytes 'sf32')); $s.AddRange([byte[]]::new(4))
    foreach ($row in $matrix) { foreach ($v in $row) { $s.AddRange((Get-S15Fixed16Bytes $v)) } }
    return , $s.ToArray()
}

function New-MultiLocalizedTextTag([string]$text) {
    $utf16 = [Text.Encoding]::BigEndianUnicode.GetBytes($text)
    $s = New-Object System.Collections.Generic.List[byte]
    $s.AddRange((Get-SignatureBytes 'mluc')); $s.AddRange([byte[]]::new(4))
    $s.AddRange((Get-UInt32Bytes 1))                  # one record
    $s.AddRange((Get-UInt32Bytes 12))                 # record size
    $s.AddRange((Get-SignatureBytes 'enUS'))
    $s.AddRange((Get-UInt32Bytes $utf16.Length))
    $s.AddRange((Get-UInt32Bytes 28))                 # string offset from tag start
    $s.AddRange($utf16)
    return , $s.ToArray()
}

# --- Build -------------------------------------------------------------------

$edid = ConvertFrom-EdidChromaticity $EdidChromaticity
$d50 = @(0.9642, 1.0, 0.8249)                         # ICC PCS illuminant
$rgbToXyz = Get-RgbToXyzMatrix $edid.Red $edid.Green $edid.Blue $WhiteXY
$chad = Get-BradfordMatrix (ConvertTo-XYZ $WhiteXY) $d50
$colorants = Get-MatrixProduct $chad $rgbToXyz        # columns = rXYZ, gXYZ, bXYZ in D50 PCS

$trc = New-GammaCurveTag $Gamma
$tags = @(
    @('desc', (New-MultiLocalizedTextTag $Description)),
    @('cprt', (New-MultiLocalizedTextTag $Copyright)),
    @('wtpt', (New-XyzTag $d50)),
    @('lumi', (New-XyzTag @(0, $Luminance, 0))),
    @('rXYZ', (New-XyzTag @($colorants[0][0], $colorants[1][0], $colorants[2][0]))),
    @('gXYZ', (New-XyzTag @($colorants[0][1], $colorants[1][1], $colorants[2][1]))),
    @('bXYZ', (New-XyzTag @($colorants[0][2], $colorants[1][2], $colorants[2][2]))),
    @('rTRC', $trc),
    @('gTRC', $trc),
    @('bTRC', $trc),
    @('chad', (New-S15Fixed16ArrayTag $chad)))

# Lay out tag data after the tag table; identical data (the three TRCs) is stored once.
$offset = 128 + 4 + 12 * $tags.Count
$data = New-Object System.Collections.Generic.List[byte]
$table = New-Object System.Collections.Generic.List[byte]
$table.AddRange((Get-UInt32Bytes $tags.Count))
$written = @{}
foreach ($tag in $tags) {
    $bytes = [byte[]]$tag[1]
    $key = [Convert]::ToBase64String($bytes)
    if (-not $written.ContainsKey($key)) {
        $written[$key] = $offset + $data.Count
        $data.AddRange($bytes)
        while ($data.Count % 4) { $data.Add(0) }
    }
    $table.AddRange((Get-SignatureBytes $tag[0]))
    $table.AddRange((Get-UInt32Bytes $written[$key]))
    $table.AddRange((Get-UInt32Bytes $bytes.Length))
}

$header = New-Object byte[] 128
$size = 128 + $table.Count + $data.Count
[Array]::Copy((Get-UInt32Bytes $size), 0, $header, 0, 4)
[Array]::Copy((Get-UInt32Bytes 0x04300000), 0, $header, 8, 4)        # version 4.3
[Array]::Copy((Get-SignatureBytes 'mntrRGB XYZ '), 0, $header, 12, 12)
$dateFields = @($CreationDate.Year, $CreationDate.Month, $CreationDate.Day, $CreationDate.Hour, $CreationDate.Minute, $CreationDate.Second)
for ($i = 0; $i -lt 6; $i++) { $header[24 + 2 * $i] = [byte]($dateFields[$i] -shr 8); $header[25 + 2 * $i] = [byte]($dateFields[$i] -band 0xFF) }
[Array]::Copy((Get-SignatureBytes 'acspMSFT'), 0, $header, 36, 8)
[Array]::Copy([byte[]](0x00, 0x00, 0xF6, 0xD6, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xD3, 0x2D), 0, $header, 68, 12)

$profile = New-Object byte[] $size
[Array]::Copy($header, $profile, 128)
$table.ToArray().CopyTo($profile, 128)
$data.ToArray().CopyTo($profile, 128 + $table.Count)

# Profile ID: MD5 of the profile with flags, rendering intent and profile ID zeroed (all zero here).
$md5 = [Security.Cryptography.MD5]::Create()
try { $id = $md5.ComputeHash($profile) } finally { $md5.Dispose() }
[Array]::Copy($id, 0, $profile, 84, 16)

$OutFile = [IO.Path]::GetFullPath($OutFile)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutFile))
[IO.File]::WriteAllBytes($OutFile, $profile)

'Wrote {0} ({1} bytes)' -f $OutFile, $profile.Length
'  primaries  R({0:N4}, {1:N4})  G({2:N4}, {3:N4})  B({4:N4}, {5:N4})' -f $edid.Red[0], $edid.Red[1], $edid.Green[0], $edid.Green[1], $edid.Blue[0], $edid.Blue[1]
'  white      D65 ({0}, {1}), gamma {2}, {3} cd/m2' -f $WhiteXY[0], $WhiteXY[1], $Gamma, $Luminance
'  profile ID {0}' -f (($id | ForEach-Object { $_.ToString('x2') }) -join '')
