# OutlookAdBlocker.ps1
# NewOutlookAdBlocker-2026 - v0.6
#
# Purpose:
#   Manage a dedicated block in the Windows hosts file using domains.txt
#
# Usage:
#   .\OutlookAdBlocker.ps1 -Action Install
#   .\OutlookAdBlocker.ps1 -Action Uninstall
#   .\OutlookAdBlocker.ps1 -Action Status
#   .\OutlookAdBlocker.ps1 -Action Verify
#   .\OutlookAdBlocker.ps1 -Action Install -DryRun
#   .\OutlookAdBlocker.ps1 -Action Uninstall -DryRun
#
# Notes:
#   - Install/Uninstall require administrator rights.
#   - Elevation reuses the currently running PowerShell host.
#   - A backup of the hosts file is created before changes.
#   - Only the managed block between the markers below is modified.
#   - Legacy duplicate entries for domains in domains.txt are removed before
#     the managed block is written.
#   - DNS resolution is verified after installation.

[CmdletBinding()]
param(
    [ValidateSet("Install", "Uninstall", "Status", "Verify")]
    [string]$Action = "Status",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ScriptVersion = "0.6"
$HostsPath     = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$DomainsPath   = Join-Path $PSScriptRoot "domains.txt"

$BeginMarker = "# BEGIN NewOutlookAdBlocker-2026"
$EndMarker   = "# END NewOutlookAdBlocker-2026"

$LogDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$LogPath = Join-Path $LogDir ("OutlookAdBlocker-" + (Get-Date -Format "yyyyMMdd") + ".log")

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    param([string]$RequestedAction, [switch]$RequestedDryRun)

    # Re-launch with the same PowerShell host that is currently running
    # (Windows PowerShell or PowerShell 7). This avoids switching from
    # pwsh.exe to powershell.exe during elevation.
    $currentHostExe = (Get-Process -Id $PID -ErrorAction Stop).Path

    if (-not $currentHostExe -or -not (Test-Path -LiteralPath $currentHostExe)) {
        throw "Could not determine the current PowerShell executable."
    }

    $argList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$PSCommandPath`""
        "-Action", $RequestedAction
    )

    if ($RequestedDryRun) {
        $argList += "-DryRun"
    }

    Write-Host "Elevating with: $currentHostExe" -ForegroundColor DarkGray

    $process = Start-Process `
        -FilePath $currentHostExe `
        -Verb RunAs `
        -ArgumentList $argList `
        -PassThru `
        -Wait

    if (-not $process) {
        throw "Could not start the elevated PowerShell process."
    }

    exit $process.ExitCode
}

function Get-DomainList {
    if (-not (Test-Path -LiteralPath $DomainsPath)) {
        throw "domains.txt was not found: $DomainsPath"
    }

    $domains = @(
        Get-Content -LiteralPath $DomainsPath |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object {
            $_ -and
            -not $_.StartsWith("#")
        } |
        Sort-Object -Unique
    )

    if ($domains.Count -eq 0) {
        throw "domains.txt does not contain any domains."
    }

    foreach ($domain in $domains) {
        if ($domain -notmatch '^(?=.{1,253}$)(?!-)(?:[a-z0-9-]{1,63}\.)+[a-z0-9-]{2,63}$') {
            throw "Invalid domain in domains.txt: $domain"
        }
    }

    return $domains
}

function Get-HostsLines {
    if (-not (Test-Path -LiteralPath $HostsPath)) {
        throw "Windows hosts file not found: $HostsPath"
    }

    return @(Get-Content -LiteralPath $HostsPath)
}

function Remove-ManagedBlock {
    param([string[]]$Lines)

    $result = New-Object System.Collections.Generic.List[string]
    $insideBlock = $false

    foreach ($line in $Lines) {
        if ($line.Trim() -eq $BeginMarker) {
            $insideBlock = $true
            continue
        }

        if ($line.Trim() -eq $EndMarker) {
            $insideBlock = $false
            continue
        }

        if (-not $insideBlock) {
            $result.Add($line)
        }
    }

    return @($result)
}

function Remove-LegacyDomainEntries {
    param(
        [string[]]$Lines,
        [string[]]$Domains
    )

    $domainSet = @{}
    foreach ($domain in $Domains) {
        $domainSet[$domain] = $true
    }

    $result = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()

        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            $result.Add($line)
            continue
        }

        # Strip inline comment for parsing only.
        $content = ($trimmed -split '\s+#', 2)[0].Trim()
        $parts = @($content -split '\s+' | Where-Object { $_ })

        if ($parts.Count -ge 2) {
            $hostnames = @($parts[1..($parts.Count - 1)] | ForEach-Object { $_.ToLowerInvariant() })

            $containsManagedDomain = $false
            foreach ($hostname in $hostnames) {
                if ($domainSet.ContainsKey($hostname)) {
                    $containsManagedDomain = $true
                    break
                }
            }

            if ($containsManagedDomain) {
                continue
            }
        }

        $result.Add($line)
    }

    return @($result)
}

function Backup-HostsFile {
    $backupDir = Join-Path $PSScriptRoot "backups"

    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupDir "hosts-$timestamp.bak"

    Copy-Item -LiteralPath $HostsPath -Destination $backupPath -Force
    return $backupPath
}

function Test-HostsWriteAccess {
    $stream = $null

    try {
        # Match the manual test that succeeded on this system:
        # open the existing hosts file for write access while allowing
        # other readers/writers to keep their handles open.
        $stream = [System.IO.File]::Open(
            $HostsPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        return $true
    }
    catch {
        Write-Host "Hosts write preflight failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Write-HostsFile {
    param([string[]]$Lines)

    # Do not replace the hosts file itself. Some Windows setups allow
    # administrators to write to the existing file but block file replacement
    # operations such as Copy-Item -Force.
    #
    # Open the existing file for writing, truncate it, then write the new
    # content in place. This preserves the file object and its ACLs.
    $encoding = New-Object System.Text.UTF8Encoding($false)

    $stream = $null
    $writer = $null

    try {
        $stream = New-Object System.IO.FileStream(
            $HostsPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        $stream.SetLength(0)

        $writer = New-Object System.IO.StreamWriter($stream, $encoding)

        foreach ($line in $Lines) {
            $writer.WriteLine($line)
        }

        $writer.Flush()
        $stream.Flush($true)
    }
    catch {
        throw "Could not write the Windows hosts file in place: $($_.Exception.Message)"
    }
    finally {
        if ($writer) {
            $writer.Dispose()
        }
        elseif ($stream) {
            $stream.Dispose()
        }
    }
}

function Test-ManagedBlockWritten {
    param([string[]]$Domains)

    $content = @(Get-Content -LiteralPath $HostsPath)

    if ($content -notcontains $BeginMarker -or $content -notcontains $EndMarker) {
        return $false
    }

    foreach ($domain in $Domains) {
        $pattern = '^\s*0\.0\.0\.0\s+' + [regex]::Escape($domain) + '(?:\s|$)'
        if (-not ($content | Where-Object { $_ -match $pattern })) {
            return $false
        }
    }

    return $true
}

function Flush-DnsCache {
    Write-Host "Flushing DNS cache..."
    ipconfig /flushdns | Out-Null
}


function Test-OutlookRunning {
    return $null -ne (Get-Process olk -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-DesiredManagedBlock {
    param([string[]]$Domains)

    $desired = New-Object System.Collections.Generic.List[string]
    $desired.Add($BeginMarker)
    $desired.Add("# Managed automatically by OutlookAdBlocker.ps1 v$ScriptVersion")

    foreach ($domain in $Domains) {
        $desired.Add("0.0.0.0 $domain")
    }

    $desired.Add($EndMarker)
    return @($desired)
}

function Get-CurrentManagedBlock {
    param([string[]]$Lines)

    $result = New-Object System.Collections.Generic.List[string]
    $inside = $false

    foreach ($line in $Lines) {
        if ($line.Trim() -eq $BeginMarker) {
            $inside = $true
        }

        if ($inside) {
            $result.Add($line)
        }

        if ($line.Trim() -eq $EndMarker) {
            break
        }
    }

    return @($result)
}

function Test-BlocksEqual {
    param(
        [string[]]$Current,
        [string[]]$Desired
    )

    if ($Current.Count -ne $Desired.Count) {
        return $false
    }

    for ($i = 0; $i -lt $Current.Count; $i++) {
        if ($Current[$i].Trim() -ne $Desired[$i].Trim()) {
            return $false
        }
    }

    return $true
}

function Install-Block {
    $domains = Get-DomainList
    $lines = Get-HostsLines
    $desiredBlock = Get-DesiredManagedBlock -Domains $domains
    $currentBlock = Get-CurrentManagedBlock -Lines $lines

    if (Test-BlocksEqual -Current $currentBlock -Desired $desiredBlock) {
        Write-Host "Managed block is already up to date." -ForegroundColor Green
        Write-Log "Install skipped: managed block already up to date."
        return
    }

    if (Test-OutlookRunning) {
        Write-Host "New Outlook is currently running. Restart it after installation." -ForegroundColor Yellow
        Write-Log "Install started while New Outlook was running." "WARN"
    }

    if ($DryRun) {
        Write-Host "Dry run: no changes will be written." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Domains that would be managed:"
        foreach ($domain in $domains) {
            Write-Host "  0.0.0.0 $domain"
        }
        Write-Log "Dry-run install completed for $($domains.Count) domain(s)."
        return
    }

    if (-not (Test-HostsWriteAccess)) {
        throw "The Windows hosts file cannot currently be opened for writing."
    }

    $backupPath = Backup-HostsFile
    Write-Host "Backup created: $backupPath" -ForegroundColor DarkGray

    $lines = Remove-ManagedBlock -Lines $lines
    $lines = Remove-LegacyDomainEntries -Lines $lines -Domains $domains

    $newLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $newLines.Add($line)
    }

    # Keep the managed block visually separated from existing content.
    if ($newLines.Count -gt 0 -and $newLines[$newLines.Count - 1].Trim() -ne "") {
        $newLines.Add("")
    }

    foreach ($line in $desiredBlock) {
        $newLines.Add($line)
    }

    Write-HostsFile -Lines @($newLines)

    if (-not (Test-ManagedBlockWritten -Domains $domains)) {
        throw "The hosts file was written, but verification of the managed block failed."
    }

    Flush-DnsCache

    Write-Host ""
    Write-Host "Installed and verified block for $($domains.Count) domain(s)." -ForegroundColor Green
    Write-Log "Installed and verified block for $($domains.Count) domain(s). Backup: $backupPath"

    foreach ($domain in $domains) {
        Write-Host "  0.0.0.0 $domain"
    }

    Write-Host ""
    Write-Host "DNS verification:" -ForegroundColor Cyan

    foreach ($domain in $domains) {
        try {
            $addresses = @(
                Resolve-DnsName $domain -ErrorAction Stop |
                Where-Object { $_.IPAddress } |
                Select-Object -ExpandProperty IPAddress -Unique
            )

            if ($addresses -contains "0.0.0.0" -or $addresses -contains "::") {
                Write-Host "  [OK] $domain -> $($addresses -join ', ')" -ForegroundColor Green
            }
            elseif ($addresses.Count -gt 0) {
                Write-Host "  [CHECK] $domain -> $($addresses -join ', ')" -ForegroundColor Yellow
            }
            else {
                Write-Host "  [OK] $domain -> no address returned" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  [OK] $domain -> resolution failed/blocked" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "Restart New Outlook before testing." -ForegroundColor Yellow
}

function Uninstall-Block {
    $lines = Get-HostsLines
    $updated = Remove-ManagedBlock -Lines $lines

    if (@($updated).Count -eq @($lines).Count) {
        Write-Host "No managed NewOutlookAdBlocker block was found." -ForegroundColor Yellow
        Write-Log "Uninstall skipped: no managed block found."
        return
    }

    if (Test-OutlookRunning) {
        Write-Host "New Outlook is currently running. Restart it after uninstall." -ForegroundColor Yellow
        Write-Log "Uninstall started while New Outlook was running." "WARN"
    }

    if ($DryRun) {
        Write-Host "Dry run: the managed block would be removed. No changes written." -ForegroundColor Yellow
        Write-Log "Dry-run uninstall completed."
        return
    }

    if (-not (Test-HostsWriteAccess)) {
        throw "The Windows hosts file cannot currently be opened for writing."
    }

    $backupPath = Backup-HostsFile
    Write-Host "Backup created: $backupPath" -ForegroundColor DarkGray

    Write-HostsFile -Lines @($updated)
    Flush-DnsCache

    Write-Host "Managed block removed." -ForegroundColor Green
    Write-Log "Managed block removed. Backup: $backupPath"
}


function Verify-Block {
    $domains = Get-DomainList

    Write-Host "Checking configured domains..." -ForegroundColor Cyan
    Write-Host ""

    $allOk = $true

    foreach ($domain in $domains) {
        try {
            $addresses = @(
                Resolve-DnsName $domain -ErrorAction Stop |
                Where-Object { $_.IPAddress } |
                Select-Object -ExpandProperty IPAddress -Unique
            )

            if ($addresses -contains "0.0.0.0" -or $addresses -contains "::") {
                Write-Host "  [OK]      $domain -> $($addresses -join ', ')" -ForegroundColor Green
            }
            elseif ($addresses.Count -gt 0) {
                Write-Host "  [FAILED]  $domain -> $($addresses -join ', ')" -ForegroundColor Red
                $allOk = $false
            }
            else {
                Write-Host "  [CHECK]   $domain -> no address returned" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  [OK]      $domain -> resolution failed/blocked" -ForegroundColor Green
        }
    }

    Write-Host ""

    if ($allOk) {
        Write-Host "Verification passed." -ForegroundColor Green
    }
    else {
        Write-Host "Verification found one or more domains that are not blocked." -ForegroundColor Red
    }
}

function Show-Status {
    $domains = Get-DomainList
    $lines = Get-HostsLines

    $currentHostExe = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    $isAdmin = Test-IsAdministrator

    Write-Host "Script version: $ScriptVersion"
    Write-Host "PowerShell:     $currentHostExe"
    Write-Host "Administrator:  $isAdmin"
    Write-Host "Hosts file:     $HostsPath"
    Write-Host "Domains file:   $DomainsPath"
    Write-Host "Log file:       $LogPath"
    Write-Host "Dry run:        $DryRun"
    Write-Host ""

    $inManagedBlock = $false
    $managed = @{}

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ($trimmed -eq $BeginMarker) {
            $inManagedBlock = $true
            continue
        }

        if ($trimmed -eq $EndMarker) {
            $inManagedBlock = $false
            continue
        }

        if ($inManagedBlock -and $trimmed -match '^0\.0\.0\.0\s+([^\s#]+)') {
            $managed[$matches[1].ToLowerInvariant()] = $true
        }
    }

    if ($managed.Count -eq 0) {
        Write-Host "Managed block:  not installed" -ForegroundColor Yellow
    }
    else {
        Write-Host "Managed block:  installed" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Domain status:"

    foreach ($domain in $domains) {
        if ($managed.ContainsKey($domain)) {
            Write-Host "  [BLOCKED] $domain" -ForegroundColor Green
        }
        else {
            Write-Host "  [NOT MANAGED] $domain" -ForegroundColor DarkYellow
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " NewOutlookAdBlocker-2026 v$ScriptVersion"
Write-Host "==========================================" -ForegroundColor Cyan

if ($Action -in @("Install", "Uninstall") -and -not $DryRun -and -not (Test-IsAdministrator)) {
    Write-Host ""
    Write-Host "Administrator rights are required for '$Action'." -ForegroundColor Yellow
    Write-Host "Requesting elevation..."
    Restart-Elevated -RequestedAction $Action -RequestedDryRun:$DryRun
}

Write-Log "Action=$Action DryRun=$DryRun ScriptVersion=$ScriptVersion"

switch ($Action) {
    "Install" {
        Write-Section "Install"
        Install-Block
    }

    "Uninstall" {
        Write-Section "Uninstall"
        Uninstall-Block
    }

    "Status" {
        Write-Section "Status"
        Show-Status
    }

    "Verify" {
        Write-Section "Verify"
        Verify-Block
    }
}
