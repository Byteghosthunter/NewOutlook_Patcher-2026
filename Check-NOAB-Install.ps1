# Check-NOAB-Install.ps1
$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=== NewOutlookPatcher NOAB diagnostic ===" -ForegroundColor Cyan
Write-Host ""

$dll = Join-Path $env:SystemRoot "System32\NewOutlookPatcher.dll"
$ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\olk.exe"
$hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$log = Join-Path $env:LOCALAPPDATA "NewOutlookAdBlocker\NewOutlookPatcher-NOAB.log"

$domains = @(
    "msft-ssp.adnxs.com",
    "msft-ssp-fra1.adnxs.com",
    "eb2.3lift.com",
    "b1t-dubdc2.outbrain.com"
)

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
Write-Host "[3] HOSTS ad blocking" -ForegroundColor Yellow
if (Test-Path $hostsPath) {
    $hostsText = Get-Content -LiteralPath $hostsPath -Raw
    $begin = $hostsText.Contains("# BEGIN NewOutlookAdBlocker-2026")
    $end = $hostsText.Contains("# END NewOutlookAdBlocker-2026")
    Write-Host "Managed block markers: $($begin -and $end)"
    foreach ($domain in $domains) {
        $escaped = [regex]::Escape($domain)
        $blocked = [regex]::IsMatch(
            $hostsText,
            "(?im)^\s*0\.0\.0\.0\s+$escaped\s*(?:#.*)?$"
        )
        Write-Host ("{0}: {1}" -f $domain, $(if ($blocked) { "BLOCKED" } else { "NOT BLOCKED" }))
    }

    $coreBlocked = [regex]::IsMatch(
        $hostsText,
        "(?im)^\s*(?:0\.0\.0\.0|127\.0\.0\.1)\s+outlook\.office\.com\s*(?:#.*)?$"
    )
    Write-Host "outlook.office.com blocked: $coreBlocked"
} else {
    Write-Host "HOSTS file not found." -ForegroundColor Red
}

Write-Host ""
Write-Host "[4] Outlook process" -ForegroundColor Yellow
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
Write-Host "[5] Runtime trace log" -ForegroundColor Yellow
if (Test-Path $log) {
    Write-Host "LOG: $log"
    Write-Host ""
    Get-Content -LiteralPath $log -Tail 100
} else {
    Write-Host "No runtime trace log found."
}

Write-Host ""
Write-Host "=== End diagnostic ===" -ForegroundColor Cyan
