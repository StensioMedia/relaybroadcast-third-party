# ===========================================================================
# KONTROLLEN AV WINDOWS-APPENS FFMPEG (2026-10-13, licensbyggplanen uppgift 3)
# ---------------------------------------------------------------------------
# Körs i Windows-jobbet i build-ffmpeg-windows.yml, på binärerna som build.sh
# korskompilerat. Allt appen använder ska finnas (listan är tagen ur koden,
# svaret 2026-10-11 §A2 och en grep 2026-10-13), licensen ska vara GPL
# version 2 eller senare, och SRT med lösenfras ska fungera på riktigt.
# Ett enda fel stoppar jobbet.
#
#   pwsh -NoProfile -File check.ps1 -Mapp <mapp med ffmpeg.exe och ffprobe.exe>
#   pwsh -NoProfile -File check.ps1 -BaraSyntax      (läser bara in skriptet)
#
# Utskriften läses in HEL innan den söks: med en rörledning till ett filter
# slutar läsningen vid första träffen och ffmpeg kan dö av det (samma fälla som
# scripts/mac-ffmpeg/build.sh beskriver för SIGPIPE).
# Skriptet är skrivet så att det går även i Windows PowerShell 5.1.
# ===========================================================================
param(
  [string]$Mapp = (Join-Path $PSScriptRoot 'ut'),
  [switch]$BaraSyntax
)
$ErrorActionPreference = 'Stop'
if ($BaraSyntax) { Write-Output 'ok  check.ps1 går att läsa in'; return }

$ffmpeg = Join-Path $Mapp 'ffmpeg.exe'
$ffprobe = Join-Path $Mapp 'ffprobe.exe'
$fel = New-Object System.Collections.Generic.List[string]
function Fel([string]$text) { $script:fel.Add($text); Write-Output "FEL $text" }
function Ok([string]$text) { Write-Output "ok  $text" }

foreach ($f in @($ffmpeg, $ffprobe)) { if (-not (Test-Path $f)) { throw "saknas: $f" } }

# Hela utskriften som en sträng (stdout och stderr).
function Kor([string[]]$argument) {
  $ut = & $ffmpeg -hide_banner @argument 2>&1 | Out-String
  return $ut
}

# --- Licensen -------------------------------------------------------------------
$conf = Kor @('-buildconf')
if ($conf -notmatch '--enable-gpl') { Fel '-buildconf saknar --enable-gpl' } else { Ok '-buildconf har --enable-gpl' }
if ($conf -match '--enable-nonfree') { Fel '-buildconf har --enable-nonfree' } else { Ok 'inte --enable-nonfree' }
if ($conf -match '--enable-version3') { Fel '-buildconf har --enable-version3' } else { Ok 'inte --enable-version3' }
$konfFil = Join-Path $Mapp 'CONFIGURE.txt'
if (Test-Path $konfFil) {
  $rad = (Get-Content -Raw $konfFil).Trim()
  if ($conf.Contains($rad)) { Ok 'CONFIGURE.txt är samma rad som -buildconf' } else { Fel 'CONFIGURE.txt skiljer sig från -buildconf' }
}
$lic = Kor @('-L')
if ($lic -notmatch 'GNU General Public License') { Fel '-L nämner inte GNU General Public License' } else { Ok '-L: GNU General Public License' }
if ($lic -notmatch 'version 2 of the License, or') { Fel '-L säger inte version 2 eller senare' } else { Ok '-L: version 2 eller senare' }

# --- Det appen använder ----------------------------------------------------------
# Raderna i ffmpegs listor: "<flaggor> <namn> <beskrivning>". Namnet söks som ett
# helt ord efter flaggorna.
function Har([string]$lista, [string]$utskrift, [string[]]$namn, [string]$monster) {
  foreach ($n in $namn) {
    $m = $monster -f [regex]::Escape($n)
    if ($utskrift -match $m) { Ok "$lista`: $n" } else { Fel "$lista saknar $n" }
  }
}
$rad = '(?m)^\s*\S+\s+{0}\s'          # -encoders, -decoders, -filters, -muxers, -demuxers, -devices
$ensam = '(?m)^\s*{0}\s*$'            # -protocols, -hwaccels: ett namn per rad

Har 'kodare' (Kor @('-encoders')) @('libx264', 'h264_nvenc', 'hevc_nvenc', 'h264_qsv', 'h264_amf', 'h264_mf', 'aac', 'libopus', 'prores_ks', 'dnxhd', 'mpeg2video', 'pcm_s16le', 'pcm_s24le') $rad
Har 'avkodare' (Kor @('-decoders')) @('libdav1d', 'h264', 'hevc', 'vp9') $rad
# rtsp och hls är format (demuxer/muxer) i ffmpeg, inte protokoll — de prövas nedan.
Har 'protokoll' (Kor @('-protocols')) @('srt', 'https', 'tls', 'rtmps', 'rtmp', 'rtp') $ensam
Har 'filter' (Kor @('-filters')) @('yadif', 'yadif_cuda', 'bwdif', 'scale_cuda', 'hwupload', 'hwdownload', 'hwupload_cuda', 'xstack', 'overlay', 'ebur128', 'astats', 'blackdetect', 'freezedetect', 'silencedetect', 'amix', 'ddagrab', 'testsrc2') $rad
Har 'enheter' (Kor @('-devices')) @('dshow', 'gdigrab') $rad
Har 'hårdvaruaccelerationer' (Kor @('-hwaccels')) @('cuda', 'qsv', 'd3d11va', 'dxva2') $ensam
Har 'muxrar' (Kor @('-muxers')) @('mpegts', 'flv', 'segment', 'hls', 'rtsp', 'mp4', 'matroska', 'tee') $rad
Har 'demuxrar' (Kor @('-demuxers')) @('dash', 'hls', 'rtsp') $rad

# --- SRT med lösenfras, på riktigt -----------------------------------------------------
# Sändaren lyssnar (mode=listener) och kodar testsrc2 med libx264; en andra ffmpeg
# ansluter med samma lösenfras och skriver till en fil. Utan kryptering i SRT
# vägrar lösenfrasen, och filen blir tom.
$port = Get-Random -Minimum 47000 -Maximum 47999
$fras = 'relaybroadcast-prov-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$fil = Join-Path ([IO.Path]::GetTempPath()) ("srt-prov-$port.ts")
if (Test-Path $fil) { Remove-Item $fil -Force }
$sandare = Start-Process -FilePath $ffmpeg -PassThru -WindowStyle Hidden -ArgumentList @(
  '-hide_banner', '-loglevel', 'error', '-re', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=25', '-t', '8',
  '-c:v', 'libx264', '-f', 'mpegts', "`"srt://127.0.0.1:$port`?mode=listener&passphrase=$fras&pbkeylen=16`"")
Start-Sleep -Seconds 1
$mottagare = Start-Process -FilePath $ffmpeg -PassThru -WindowStyle Hidden -ArgumentList @(
  '-hide_banner', '-loglevel', 'error', '-y', '-i', "`"srt://127.0.0.1:$port`?mode=caller&passphrase=$fras&pbkeylen=16`"",
  '-c', 'copy', '-f', 'mpegts', "`"$fil`"")
if (-not $mottagare.WaitForExit(20000)) { $mottagare.Kill() }
if (-not $sandare.WaitForExit(5000)) { $sandare.Kill() }
$langd = 0
if (Test-Path $fil) {
  $p = & $ffprobe -v error -show_entries format=duration -of csv=p=0 $fil 2>&1 | Out-String
  [double]::TryParse(($p.Trim() -split "`r?`n")[0], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$langd) | Out-Null
  Remove-Item $fil -Force -ErrorAction SilentlyContinue
}
if ($langd -ge 2) { Ok ("SRT med lösenfras: {0:N1} s avkodat över krypterad förbindelse" -f $langd) } else { Fel ("SRT med lösenfras: bara {0:N1} s kom fram" -f $langd) }

# --- Resultatet ------------------------------------------------------------------
if ($fel.Count -gt 0) {
  Write-Output ''
  Write-Output "$($fel.Count) kontroller föll:"
  $fel | ForEach-Object { Write-Output "  $_" }
  exit 1
}
Write-Output ''
Write-Output 'Alla kontroller gröna.'
