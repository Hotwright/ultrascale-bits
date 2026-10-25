#!/bin/bash
# Look at the KV260's Pmod LEDs through the bench webcam: grab N stills on
# Windows (MediaCapture, no install needed) and tile the LED crop into one
# image. Diagnosis aid only; the crop is for the camera as it sits today.
#
# Usage: env/kv260_webcam.sh <out.png> [count] [crop w:h:x:y]
set -eu
OUT="${1:?usage: kv260_webcam.sh <out.png> [count] [crop]}"
N="${2:-6}"
CROP="${3:-90:50:250:185}"
W=/mnt/c/temp/cam
mkdir -p "$W"
cat > "$W/snap.ps1" <<PS
Add-Type -AssemblyName System.Runtime.WindowsRuntime
\$m = [System.WindowsRuntimeSystemExtensions].GetMethods()
\$asTask = (\$m | ? { \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation\`1' })[0]
\$asTaskA = (\$m | ? { \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Await(\$op, \$t) { \$k = \$asTask.MakeGenericMethod(\$t).Invoke(\$null, @(\$op)); \$k.Wait() | Out-Null; \$k.Result }
function AwaitA(\$op) { \$asTaskA.Invoke(\$null, @(\$op)).Wait() | Out-Null }
[Windows.Media.Capture.MediaCapture,Windows.Media.Capture,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.StorageFolder,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.ImageEncodingProperties,Windows.Media.MediaProperties,ContentType=WindowsRuntime] | Out-Null
\$mc = New-Object Windows.Media.Capture.MediaCapture
AwaitA (\$mc.InitializeAsync())
Start-Sleep -Milliseconds 1500
\$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync('C:\temp\cam')) ([Windows.Storage.StorageFolder])
\$fmt = [Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg()
for (\$i = 0; \$i -lt $N; \$i++) {
  \$f = Await (\$folder.CreateFileAsync("snap\$i.jpg", [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
  AwaitA (\$mc.CapturePhotoToStorageFileAsync(\$fmt, \$f))
  Start-Sleep -Milliseconds 120
}
\$mc.Dispose()
PS
timeout 120 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\temp\cam\snap.ps1' >/dev/null
args=(); f=""
for i in $(seq 0 $((N-1))); do
    ffmpeg -loglevel error -y -i "$W/snap$i.jpg" -vf "crop=$CROP,scale=360:200:flags=neighbor" "$W/c$i.png"
    args+=(-i "$W/c$i.png"); f="$f[$i]"
done
ffmpeg -loglevel error -y "${args[@]}" -filter_complex "${f}hstack=$N" "$OUT"
echo "$OUT"
