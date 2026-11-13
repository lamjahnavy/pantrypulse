$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $projectRoot '..\.venv-kerasocr-tf210\Scripts\python.exe'
$log = Join-Path $projectRoot 'ocr_backend\demo_backend.log'
$healthUrl = 'http://127.0.0.1:8000/health'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python environment not found: $python"
}

$env:OCR_DEBUG = '0'
$env:OCR_RECOGNIZER_MODE = 'pretrained'
$env:OCR_DATE_RETRY_MODE = 'custom_lightweight'

$existing = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if (-not $existing) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $python
    $startInfo.Arguments = '-m ocr_backend.app'
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) { Add-Content -LiteralPath $using:log -Value $EventArgs.Data }
    } | Out-Null
    Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) { Add-Content -LiteralPath $using:log -Value $EventArgs.Data }
    } | Out-Null
    Write-Host "Started backend PID $($process.Id)"
} else {
    Write-Host "Backend already listening on port 8000"
}

for ($attempt = 1; $attempt -le 60; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ($health.status -eq 'ok') {
            $health | ConvertTo-Json -Compress
            exit 0
        }
    } catch {
        Start-Sleep -Seconds 1
    }
}

throw "Backend did not respond at $healthUrl within 60 seconds."
