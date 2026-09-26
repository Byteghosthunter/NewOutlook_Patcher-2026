param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Uninstall")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$HostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$WorkerScript = Join-Path $PSScriptRoot "NOAB-Hosts.ps1"
$LogPath = Join-Path $PSScriptRoot "NOAB-Hosts-Admin.log"

function Write-AdminLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    }
    catch {}
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-HostsWriteAccess {
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $HostsPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
        return $true
    }
    catch {
        Write-AdminLog "Write preflight failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Host "This helper must run as Administrator." -ForegroundColor Red
    Write-AdminLog "Not elevated."
    exit 10
}

if (-not (Test-Path -LiteralPath $HostsPath)) {
    Write-Host "HOSTS file not found: $HostsPath" -ForegroundColor Red
    Write-AdminLog "HOSTS file missing."
    exit 11
}

if (-not (Test-Path -LiteralPath $WorkerScript)) {
    Write-Host "NOAB-Hosts.ps1 not found: $WorkerScript" -ForegroundColor Red
    Write-AdminLog "Worker script missing."
    exit 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " NewOutlookPatcher NOAB - Elevated HOSTS permission helper" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Action: $Action"
Write-Host "HOSTS : $HostsPath"
Write-Host ""

$originalReadOnly = $false
$originalAccessSddl = $null
$aclChanged = $false
$patchExitCode = 1
$restoreFailed = $false

try {
    $item = Get-Item -LiteralPath $HostsPath -Force
    $originalReadOnly = $item.IsReadOnly

    $originalAcl = Get-Acl -LiteralPath $HostsPath
    $originalAccessSddl = $originalAcl.GetSecurityDescriptorSddlForm(
        [System.Security.AccessControl.AccessControlSections]::Access
    )

    if ($originalReadOnly) {
        Write-Host "Removing ReadOnly attribute temporarily..." -ForegroundColor Yellow
        Write-AdminLog "Removing ReadOnly attribute temporarily."
        $item.IsReadOnly = $false
    }

    if (-not (Test-HostsWriteAccess)) {
        Write-Host "Granting the local Administrators group temporary Modify access..." -ForegroundColor Yellow
        Write-AdminLog "Adding temporary Administrators Modify ACE."

        $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $adminSid,
            [System.Security.AccessControl.FileSystemRights]::Modify,
            [System.Security.AccessControl.AccessControlType]::Allow
        )

        $workingAcl = Get-Acl -LiteralPath $HostsPath
        [void]$workingAcl.AddAccessRule($rule)
        Set-Acl -LiteralPath $HostsPath -AclObject $workingAcl
        $aclChanged = $true
    }

    if (-not (Test-HostsWriteAccess)) {
        Write-Host "The file is still not writable after the temporary ACL grant." -ForegroundColor Red
        Write-Host "Security software may be actively protecting the HOSTS file." -ForegroundColor Red
        Write-AdminLog "Still not writable after temporary ACL grant."
        exit 13
    }

    Write-Host "HOSTS write access confirmed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Running the proven NOAB HOSTS patch..." -ForegroundColor Cyan
    Write-AdminLog "Starting proven HOSTS worker. Action=$Action"

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $WorkerScript),
        "-Action", $Action
    ) -join " "

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -NoNewWindow

    $patchExitCode = $process.ExitCode
    Write-AdminLog "HOSTS worker exit code=$patchExitCode"

    if ($patchExitCode -ne 0) {
        Write-Host ""
        Write-Host "The HOSTS patch returned exit code $patchExitCode." -ForegroundColor Red
    }
}
catch {
    Write-Host ""
    Write-Host "HOSTS permission helper failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-AdminLog "ERROR: $($_.Exception.ToString())"
    $patchExitCode = 14
}
finally {
    if ($aclChanged -and $originalAccessSddl) {
        try {
            Write-Host ""
            Write-Host "Restoring the original HOSTS access permissions..." -ForegroundColor DarkGray

            $restoreAcl = Get-Acl -LiteralPath $HostsPath
            $restoreAcl.SetSecurityDescriptorSddlForm(
                $originalAccessSddl,
                [System.Security.AccessControl.AccessControlSections]::Access
            )
            Set-Acl -LiteralPath $HostsPath -AclObject $restoreAcl
            Write-AdminLog "Original DACL restored."
        }
        catch {
            $restoreFailed = $true
            Write-Host "WARNING: Could not restore the original HOSTS permissions." -ForegroundColor Yellow
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            Write-AdminLog "DACL restore failed: $($_.Exception.Message)"
        }
    }

    if ($originalReadOnly) {
        try {
            $item = Get-Item -LiteralPath $HostsPath -Force
            $item.IsReadOnly = $true
            Write-AdminLog "ReadOnly attribute restored."
        }
        catch {
            $restoreFailed = $true
            Write-Host "WARNING: Could not restore the ReadOnly attribute." -ForegroundColor Yellow
            Write-AdminLog "ReadOnly restore failed: $($_.Exception.Message)"
        }
    }
}

Write-Host ""

if ($patchExitCode -eq 0 -and -not $restoreFailed) {
    Write-Host "HOSTS $Action completed successfully." -ForegroundColor Green
    Write-AdminLog "Completed successfully."
    exit 0
}

if ($patchExitCode -eq 0 -and $restoreFailed) {
    Write-Host "HOSTS was changed, but the original file permissions could not be fully restored." -ForegroundColor Yellow
    Write-AdminLog "Patch succeeded, restore had warnings."
    exit 15
}

Write-AdminLog "Finished with error code=$patchExitCode"
exit $patchExitCode
