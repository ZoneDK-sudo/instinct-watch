# Renders digits and a colon from a Windows font into a 1-bit bitmap font (BMFont .fnt + .png)
# that Connect IQ can use as a custom font on the Instinct's black-and-white screen.
#
#   .\make-font.ps1 -FontFile C:\path\BarlowCondensed-Bold.ttf -DigitHeight 56   (a .ttf file)
#   .\make-font.ps1 -Family "Bahnschrift SemiBold Condensed"                       (an installed font)
param(
    [string]$Family = "",
    [string]$FontFile = "",
    [int]$DigitHeight = 56,          # target height of the digits in pixels
    [string]$OutDir = "$PSScriptRoot\..\workday\resources\fonts",
    [string]$Name = "timefont"
)
Add-Type -AssemblyName System.Drawing
$chars = "0123456789:"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

if ($FontFile) {
    $script:collection = New-Object System.Drawing.Text.PrivateFontCollection
    $script:collection.AddFontFile((Resolve-Path $FontFile).Path)
    $fontFamily = $script:collection.Families[0]
} elseif ($Family) {
    $fontFamily = New-Object System.Drawing.FontFamily($Family)
} else {
    throw "Pass -FontFile (a .ttf) or -Family (an installed font name)."
}
$style = if ($fontFamily.IsStyleAvailable([System.Drawing.FontStyle]::Bold)) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
$Family = $fontFamily.Name

function Render([float]$size) {
    $font = New-Object System.Drawing.Font($fontFamily, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $glyphs = @()
    foreach ($c in $chars.ToCharArray()) {
        $bmp = New-Object System.Drawing.Bitmap 200, 200
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::White)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        $g.DrawString([string]$c, $font, [System.Drawing.Brushes]::Black, 20, 20)
        $g.Dispose()
        $minX = 999; $maxX = -1; $minY = 999; $maxY = -1
        for ($y = 0; $y -lt 200; $y++) { for ($x = 0; $x -lt 200; $x++) {
            if ($bmp.GetPixel($x, $y).R -lt 128) { if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }; if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y } } } }
        $glyphs += [pscustomobject]@{ c = $c; bmp = $bmp; minX = $minX; maxX = $maxX; minY = $minY; maxY = $maxY }
    }
    $font.Dispose()
    return ,$glyphs
}

# Find the font size whose "0" is $DigitHeight pixels tall.
$size = [float]$DigitHeight * 1.3
for ($i = 0; $i -lt 6; $i++) {
    $g0 = (Render $size)[0]
    $h = $g0.maxY - $g0.minY + 1
    if ($h -eq $DigitHeight) { break }
    $size = $size * $DigitHeight / $h
}
$glyphs = Render $size
$top = ($glyphs | Measure-Object minY -Minimum).Minimum
$bottom = ($glyphs | Measure-Object maxY -Maximum).Maximum
$lineH = $bottom - $top + 1
$gapPx = 4   # space between characters on screen

$atlasW = 0; foreach ($g in $glyphs) { $atlasW += ($g.maxX - $g.minX + 1) + 2 }
$atlas = New-Object System.Drawing.Bitmap $atlasW, $lineH
$ag = [System.Drawing.Graphics]::FromImage($atlas)
$ag.Clear([System.Drawing.Color]::White)
$lines = @()
$x = 0
foreach ($g in $glyphs) {
    $gw = $g.maxX - $g.minX + 1
    $src = New-Object System.Drawing.Rectangle $g.minX, $top, $gw, $lineH
    $ag.DrawImage($g.bmp, (New-Object System.Drawing.Rectangle $x, 0, $gw, $lineH), $src, [System.Drawing.GraphicsUnit]::Pixel)
    $adv = if ($g.c -eq ':') { $gw + $gapPx + 2 } else { $gw + $gapPx }
    $xoff = if ($g.c -eq ':') { 2 } else { 0 }
    $lines += "char id=$([int][char]$g.c) x=$x y=0 width=$gw height=$lineH xoffset=$xoff yoffset=0 xadvance=$adv page=0 chnl=15"
    $x += $gw + 2
}
$ag.Dispose()
# Force pure black and white for the 1-bit display
for ($yy = 0; $yy -lt $atlas.Height; $yy++) { for ($xx = 0; $xx -lt $atlas.Width; $xx++) {
    $p = $atlas.GetPixel($xx, $yy); $atlas.SetPixel($xx, $yy, $(if ($p.R -lt 128) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White })) } }
# Connect IQ fonts are drawn as alpha masks: glyph pixels white on transparent black
$mask = New-Object System.Drawing.Bitmap $atlas.Width, $atlas.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($yy = 0; $yy -lt $atlas.Height; $yy++) { for ($xx = 0; $xx -lt $atlas.Width; $xx++) {
    $on = $atlas.GetPixel($xx, $yy).R -lt 128
    $mask.SetPixel($xx, $yy, $(if ($on) { [System.Drawing.Color]::FromArgb(255, 255, 255, 255) } else { [System.Drawing.Color]::FromArgb(0, 0, 0, 0) })) } }
$mask.Save("$OutDir\$Name.png", [System.Drawing.Imaging.ImageFormat]::Png)

$fnt = @(
    "info face=`"$Family`" size=$lineH bold=1 italic=0 charset=`"`" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0",
    "common lineHeight=$lineH base=$lineH scaleW=$($atlas.Width) scaleH=$($atlas.Height) pages=1 packed=0",
    "page id=0 file=`"$Name.png`"",
    "chars count=$($glyphs.Count)"
) + $lines
Set-Content -Path "$OutDir\$Name.fnt" -Value $fnt -Encoding ascii
"font size $([math]::Round($size,1))px -> line height $lineH, atlas $($atlas.Width)x$($atlas.Height)"
"widths: " + (($glyphs | ForEach-Object { "$($_.c)=$($_.maxX - $_.minX + 1)" }) -join ' ')
