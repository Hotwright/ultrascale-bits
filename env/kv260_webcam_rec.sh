#!/bin/bash
# Record a short webcam video of the KV260's Pmod LEDs (Windows MediaCapture,
# no install needed), so blink rates can be measured frame by frame. The
# stills in kv260_webcam.sh come ~1.6 s apart, too slow for that.
#
# Usage: env/kv260_webcam_rec.sh [seconds]   -> /mnt/c/temp/cam/rec.mp4
set -eu
SECS="${1:-25}"
W=/mnt/c/temp/cam
mkdir -p "$W"
cat > "$W/rec.ps1" <<'PS'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$m = [System.WindowsRuntimeSystemExtensions].GetMethods()
$asTask = ($m | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskA = ($m | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Await($op, $t) { $k = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $k.Wait() | Out-Null; $k.Result }
function AwaitA($op) { $asTaskA.Invoke($null, @($op)).Wait() | Out-Null }
[Windows.Media.Capture.MediaCapture,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.StorageFolder,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.MediaEncodingProfile,Windows.Media.MediaProperties,ContentType=WindowsRuntime] | Out-Null
$mc = New-Object Windows.Media.Capture.MediaCapture
AwaitA ($mc.InitializeAsync())
Start-Sleep -Milliseconds 1500
$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync('C:\temp\cam')) ([Windows.Storage.StorageFolder])
$f = Await ($folder.CreateFileAsync("rec.mp4", [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
$p = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp4([Windows.Media.MediaProperties.VideoEncodingQuality]::Vga)
AwaitA ($mc.StartRecordToStorageFileAsync($p, $f))
Start-Sleep -Seconds ([int]$args[0])
AwaitA ($mc.StopRecordAsync())
$mc.Dispose()
PS
timeout $((SECS + 60)) powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\temp\cam\rec.ps1' "$SECS" >/dev/null
ffprobe -v error -show_entries stream=width,height,r_frame_rate,nb_frames "$W/rec.mp4"
