# Builds the Workday face, loads it in the Connect IQ simulator and saves a zoomed screenshot.
param([string]$Shot = "$env:TEMP\workday-sim.png")
$ErrorActionPreference = 'Stop'
$proj = (Resolve-Path "$PSScriptRoot\..\workday").Path
$env:PATH = "C:\Program Files\Eclipse Adoptium\jdk-21.0.13.10002-hotspot\bin;$env:PATH"
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
Push-Location $proj
try {
    $out = & "$sdk\bin\monkeyc.bat" -f monkey.jungle -d instinct2x -y "$env:USERPROFILE\.garmin\developer_key.der" -o bin\Workday.prg -w -l 2 2>&1 | ForEach-Object { "$_" }
    $out
    if (-not ($out -match 'BUILD SUCCESSFUL')) { exit 1 }
    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) { Start-Process "$sdk\bin\simulator.exe"; Start-Sleep 6 }
    Start-Process -WindowStyle Hidden -FilePath "$sdk\bin\monkeydo.bat" -ArgumentList "bin\Workday.prg", "instinct2x"
    Start-Sleep 12
} finally { Pop-Location }

Add-Type -AssemblyName System.Drawing
if (-not ('SimCap' -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SimCap { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
public struct RECT { public int L, T, R, B; } }
"@ }
$p = Get-Process simulator | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
[SimCap]::ShowWindow($p.MainWindowHandle, 9) | Out-Null; Start-Sleep 1
$r = New-Object SimCap+RECT; [SimCap]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[SimCap]::PrintWindow($p.MainWindowHandle, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc)
$crop = New-Object System.Drawing.Bitmap 440, 480
$cg = [System.Drawing.Graphics]::FromImage($crop)
$cg.InterpolationMode = 'NearestNeighbor'
$cg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, 440, 480), (New-Object System.Drawing.Rectangle 100, 170, 220, 240), [System.Drawing.GraphicsUnit]::Pixel)
$crop.Save($Shot)
"screenshot -> $Shot"
