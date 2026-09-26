# Check-NOAB-Install.ps1
$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=== NewOutlookPatcher-NOAB diagnostic ===" -ForegroundColor Cyan
Write-Host ""

$dll = Join-Path $env:SystemRoot "System32\NewOutlookPatcher.dll"
$ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\olk.exe"
$log = Join-Path $env:LOCALAPPDATA "NewOutlookAdBlocker\NewOutlookPatcher-NOAB.log"

Write-Host "[1] Installed worker" -ForegroundColor Yellow
if (Test-Path -LiteralPath $dll) {
    $item = Get-Item -LiteralPath $dll
    Write-Host "FOUND: $($item.FullName)"
    Write-Host "Size : $($item.Length)"
    Write-Host "SHA256: $((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash)"
    try {
        $bytes = [System.IO.File]::ReadAllBytes($dll)
        $unicode = [System.Text.Encoding]::Unicode.GetString($bytes)
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        foreach ($marker in @(
            "MessageAdKeyOutlookUpSell",
            "WebView2 MinHook enabled successfully",
            "AddScriptToExecuteOnDocumentCreated",
            "Environment10 exists"
        )) {
            $found = $unicode.Contains($marker) -or $ascii.Contains($marker)
            Write-Host ("Marker {0}: {1}" -f $marker, $found)
        }
    } catch {}
} else {
    Write-Host "NOT FOUND: $dll" -ForegroundColor Red
}

Write-Host ""
Write-Host "[2] IFEO / AppVerifier registration" -ForegroundColor Yellow
if (Test-Path $ifeo) {
    $p = Get-ItemProperty $ifeo
    Write-Host "GlobalFlag  : $($p.GlobalFlag)"
    Write-Host "VerifierDlls: $($p.VerifierDlls)"
} else {
    Write-Host "olk.exe IFEO key not found." -ForegroundColor Red
}

Write-Host ""
Write-Host "[3] Outlook process" -ForegroundColor Yellow
$olk = Get-Process olk -ErrorAction SilentlyContinue
if ($olk) {
    foreach ($p in $olk) {
        Write-Host "olk.exe PID: $($p.Id)"
        try { Write-Host "Version    : $($p.MainModule.FileVersionInfo.FileVersion)" } catch {}
        try {
            $loaded = $p.Modules | Where-Object { $_.ModuleName -ieq "NewOutlookPatcher.dll" }
            Write-Host "NewOutlookPatcher.dll loaded in olk.exe: $([bool]$loaded)"
        } catch {
            Write-Host "Could not enumerate modules. Run PowerShell as Administrator." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "olk.exe is not running." -ForegroundColor Red
}

Write-Host ""
Write-Host "[4] Runtime trace log" -ForegroundColor Yellow
if (Test-Path $log) {
    Write-Host "LOG: $log"
    Write-Host ""
    Get-Content -LiteralPath $log -Tail 200
} else {
    Write-Host "NO LOG FOUND: $log" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== End diagnostic ===" -ForegroundColor Cyan
