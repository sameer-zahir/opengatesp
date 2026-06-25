#Requires -Version 7.4
<#
.SYNOPSIS
    Generate tools/opengatesp.ico — the app icon used by the .exe launcher, the
    installer, and the Start Menu / desktop shortcuts.
.DESCRIPTION
    Draws a rounded-square mark in the Tokyo Night Moon accent blue with a dark
    console chevron (">_") — the developer-tool identity. Renders each size natively
    and assembles a PNG-backed .ico (crisp at 16-256px). Windows-only (System.Drawing).
#>
[CmdletBinding()]
param([string]$OutPath)

Add-Type -AssemblyName System.Drawing
if (-not $OutPath) { $OutPath = Join-Path $PSScriptRoot 'opengatesp.ico' }

$Blue = [System.Drawing.ColorTranslator]::FromHtml('#82AAFF')   # accent
$Ink  = [System.Drawing.ColorTranslator]::FromHtml('#1B1D2B')   # accent foreground (near-black)

function New-IconPng([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    # rounded-square background
    $pad = [Math]::Max(1, [int]($size * 0.045))
    $rad = [double]($size * 0.225)
    $x = $pad; $y = $pad; $w = $size - 2 * $pad; $h = $size - 2 * $pad; $d = $rad * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush $Blue
    $g.FillPath($bg, $path)

    # console chevron ">"
    $pen = New-Object System.Drawing.Pen $Ink, ([single]([Math]::Max(2.0, $size * 0.092)))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $cx = $size * 0.40; $arm = $size * 0.155; $top = $size * 0.32; $mid = $size * 0.50; $bot = $size * 0.68
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([single]($cx - $arm), [single]$top)),
        (New-Object System.Drawing.PointF ([single]($cx + $arm), [single]$mid)),
        (New-Object System.Drawing.PointF ([single]($cx - $arm), [single]$bot))
    )
    $g.DrawLines($pen, $pts)

    # underscore cursor (skip on the smallest sizes where it muddies)
    if ($size -ge 32) {
        $g.DrawLine($pen, [single]($size * 0.52), [single]$bot, [single]($size * 0.70), [single]$bot)
    }

    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

$sizes = 256, 64, 48, 32, 16
$pngs = @(); foreach ($s in $sizes) { $pngs += , (New-IconPng $s) }

# Assemble an ICO with PNG-compressed entries (Vista+).
$ico = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ico
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $dim = [byte]($(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write($dim); $bw.Write($dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($OutPath, $ico.ToArray())
$bw.Dispose()
Write-Host "Wrote $OutPath ($([Math]::Round((Get-Item $OutPath).Length/1kb,1)) KB, sizes: $($sizes -join ', '))"
