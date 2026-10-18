$log="C:\Users\MECHREVO\Downloads\HMA-OSS-oss-173\HMA-OSS-oss-173\build-8.log"
$out="C:\Users\MECHREVO\Downloads\HMA-OSS-oss-173\HMA-OSS-oss-173\build-status.txt"
$deadline=(Get-Date).AddMinutes(40)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 10
  $txt = Get-Content $log -Raw -ErrorAction SilentlyContinue
  if ($txt -match "BUILD (SUCCESSFUL|FAILED)") {
    ("finish=" + (Get-Date -Format HH:mm:ss)) | Out-File -Encoding utf8 $out
    $txt | Out-File -Append -Encoding utf8 $out
    break
  }
}