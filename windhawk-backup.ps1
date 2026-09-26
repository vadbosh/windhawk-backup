<#
.SYNOPSIS
    Back up and restore Windhawk mods and settings.

.DESCRIPTION
    WHERE BACKUPS GO
      Default folder: the folder where windhawk-backup.ps1 itself is located,
        no matter which folder the console is in.
      File name: windhawk-backup_<yyyyMMdd_HHmmss>.zip
      Safety copy made before every restore: windhawk-backup_<yyyyMMdd_HHmmss>_pre-restore.zip
      Change the folder with -BackupDir. The full path is printed at the end of every run.
      Log of every run, appended: <backup folder>\windhawk-backup.log (errors included).

    WHAT IS IN THE ZIP
      Data\          copy of the Windhawk data folder (default C:\ProgramData\Windhawk):
                     ModsSource, Engine\Mods, Engine\ModsWritable, settings.ini, etc.
                     Editor caches (UIData, EditorWorkspace) are not copied.
                     Runtime state (ModsWritable\mod-status, mod-task) is not copied either.
      Windhawk.reg   export of HKLM\SOFTWARE\Windhawk (enabled mods and their settings).
                     The portable version has no such key; this step is skipped.

    WHAT HAPPENS
      Backup : stop Windhawk -> copy files -> export registry -> ZIP -> delete backups
               beyond -Keep -> start Windhawk.
      Restore: ask for confirmation -> stop Windhawk -> safety backup (_pre-restore) ->
               [-Clean: remove current mods] -> copy files back -> import registry ->
               start Windhawk.

    The script needs administrator rights and relaunches itself through UAC if needed.
    The relaunched window stays open (-NoExit) so the output can be read.

.PARAMETER Action
    Backup, Restore or Help. If omitted, the script asks (1 = Backup, 2 = Restore).

.PARAMETER Path
    Restore only: ZIP to restore from. If omitted, the newest regular backup in -BackupDir
    (_pre-restore files are ignored).

.PARAMETER Clean
    Restore only: remove current mods first (folders ModsSource, Engine\Mods,
    Engine\ModsWritable and registry keys Engine\Mods, Engine\ModsWritable).
    Without -Clean the backup is applied on top: mods installed after the backup stay.

.PARAMETER BackupDir
    Folder for backups. Default: the folder of this script. Created if missing.

.PARAMETER WindhawkRoot
    Windhawk data folder. Default: C:\ProgramData\Windhawk.
    For the portable version: the AppDataPath value from windhawk.ini next to windhawk.exe.

.PARAMETER Keep
    Backup only: how many regular backups to keep in -BackupDir; older ones are deleted.
    _pre-restore files are never deleted. 0 = keep all. Default: 10.

.PARAMETER Help
    Show this help. Same as: -h, --help, help, /?, Get-Help .\windhawk-backup.ps1 -Full

.EXAMPLE
    .\windhawk-backup.ps1 Backup

    Back up to <script folder>\windhawk-backup_<timestamp>.zip, keep the last 10.

.EXAMPLE
    .\windhawk-backup.ps1 Backup -BackupDir D:\Backups\Windhawk -Keep 0

    Back up to D:\Backups\Windhawk and never delete old backups.

.EXAMPLE
    .\windhawk-backup.ps1 Restore

    Restore from the newest backup in the script folder. Mods installed later stay.

.EXAMPLE
    .\windhawk-backup.ps1 Restore -Path D:\Backups\Windhawk\windhawk-backup_20260926_143000.zip

    Restore from a specific file.

.EXAMPLE
    .\windhawk-backup.ps1 Restore -Clean

    Remove all current mods, then restore the newest backup: exact state of the backup.

.EXAMPLE
    .\windhawk-backup.ps1 Backup -WindhawkRoot D:\Tools\Windhawk\AppData

    Back up a portable Windhawk. Take the path from AppDataPath in D:\Tools\Windhawk\windhawk.ini.

.EXAMPLE
    windhawk-backup.cmd Restore -Clean

    The same from cmd.exe or Explorer; the .cmd wrapper bypasses the execution policy.
    Double-click windhawk-backup.cmd to get the Backup/Restore prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windhawk-backup.ps1 Backup

    Run when scripts are blocked by the execution policy.

.EXAMPLE
    Get-ChildItem .\windhawk-backup_*.zip

    List existing backups (run from the script folder).

.NOTES
    If a restore fails with a robocopy error 8+, mod DLLs are locked by running processes:
    reboot and run the restore again right after logon.
#>
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action,

    [string]$Path,

    [switch]$Clean,

    [string]$BackupDir,   # default: script folder, set below

    [string]$WindhawkRoot = (Join-Path $env:ProgramData 'Windhawk'),

    [int]$Keep = 10,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 may pass "--help" or "/?" as a positional value, so check $Action too.
if ($Help -or ($Action -and @('help', '-help', '--help', '-h', '/h', '/?', '?') -contains $Action)) {
    Get-Help -Name $PSCommandPath -Full
    return
}
if ($Action -and @('Backup', 'Restore') -notcontains $Action) {
    throw "Unknown action '$Action'. Use Backup, Restore or -Help."
}

# Script folder, not the current directory: after a UAC relaunch the current directory is System32.
if (-not $BackupDir) { $BackupDir = $PSScriptRoot }

# Make relative paths absolute now, for the same reason; the UAC relaunch gets the absolute ones.
foreach ($name in 'BackupDir', 'Path', 'WindhawkRoot') {
    $value = Get-Variable -Name $name -ValueOnly
    if ($value) {
        $value = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($value)
        Set-Variable -Name $name -Value $value
        if ($PSBoundParameters.ContainsKey($name)) { $PSBoundParameters[$name] = $value }
    }
}

$RegKey      = 'HKLM\SOFTWARE\Windhawk'
$ServiceName = 'Windhawk'                     # ServiceCommon::kName in Windhawk source
$ExcludeDirs = @(
    'UIData', 'EditorWorkspace',  # editor caches, recreated automatically
    'mod-status', 'mod-task'      # Engine\ModsWritable: per-process runtime state, deleted as mods unload
)
$ModDirs     = @('ModsSource', 'Engine\Mods', 'Engine\ModsWritable')
$ModRegKeys  = @('Engine\Mods', 'Engine\ModsWritable')

# --- Elevation --------------------------------------------------------------

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    # Start-Process in PS 5.1 does not quote array items, so quote them here.
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value) { $argList += "-$($kv.Key)" }
        } else {
            $argList += "-$($kv.Key)"
            $argList += "`"$($kv.Value)`""
        }
    }
    Write-Host 'Administrator rights required, relaunching via UAC...'
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

# --- Helpers ----------------------------------------------------------------

function Test-WindhawkRegistry {
    # /reg:64 so that 32-bit PowerShell does not look in WOW6432Node.
    cmd.exe /c "reg query `"$RegKey`" /reg:64 >nul 2>&1"
    $LASTEXITCODE -eq 0
}

function Invoke-Reg {
    param([string[]]$Arguments)
    & reg.exe @Arguments /reg:64 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg $($Arguments[0]) failed with exit code $LASTEXITCODE" }
}

function Invoke-Robocopy {
    param([string]$Source, [string]$Destination, [string[]]$Extra = @())
    $log = [IO.Path]::GetTempFileName()
    try {
        & robocopy.exe $Source $Destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP "/UNILOG:$log" @Extra | Out-Null
        $code = $LASTEXITCODE
        # robocopy exit codes 0-7 mean success, 8+ mean failure.
        if ($code -ge 8) {
            # An error line names the file, the next line gives the reason. Retries repeat them.
            $details = Select-String -LiteralPath $log -Pattern 'ERROR \d+' -Context 0, 1 |
                ForEach-Object { ($_.Line -replace '^.*?(ERROR \d+)', '$1') + ' -- ' + ($_.Context.PostContext -join ' ').Trim() } |
                Select-Object -Unique
            $details = @($details)
            if ($details.Count -gt 20) {
                $details = $details[0..19] + "... and $($details.Count - 20) more"
            }
            throw "robocopy '$Source' -> '$Destination' failed with exit code ${code}:`n$($details -join "`n")"
        }
    } finally {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
}

function Stop-Windhawk {
    $state = [pscustomobject]@{ ServiceWasRunning = $false; ExePath = $null }

    $proc = Get-Process -Name windhawk -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1
    if ($proc) { $state.ExePath = $proc.Path }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $state.ServiceWasRunning = $true
        Write-Host 'Stopping Windhawk service...'
        Stop-Service -Name $ServiceName -Force
    }

    $procs = Get-Process -Name windhawk -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host 'Stopping windhawk.exe processes...'
        $procs | Stop-Process -Force
        $procs | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    }
    $state
}

function Start-Windhawk {
    param($State)
    if ($State.ServiceWasRunning) {
        # The service starts the tray UI (-tray-only) in every session by itself.
        Write-Host 'Starting Windhawk service...'
        Start-Service -Name $ServiceName
    } elseif ($State.ExePath) {
        Write-Host 'Starting Windhawk...'
        Start-Process -FilePath $State.ExePath -ArgumentList '-tray-only'
    }
}

function Remove-OldBackups {
    if ($Keep -le 0) { return }
    Get-ChildItem -Path $BackupDir -Filter 'windhawk-backup_*.zip' |
        Where-Object { $_.Name -notlike '*_pre-restore.zip' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        ForEach-Object {
            Write-Host "Removing old backup: $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

# --- Backup -----------------------------------------------------------------

function New-WindhawkBackup {
    param([string]$Suffix = '')

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip   = Join-Path $BackupDir "windhawk-backup_$stamp$Suffix.zip"
    $stage = Join-Path $env:TEMP "windhawk-backup_$stamp"

    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        Write-Host "Copying $WindhawkRoot ..."
        Invoke-Robocopy -Source $WindhawkRoot -Destination (Join-Path $stage 'Data') -Extra (@('/XD') + $ExcludeDirs)

        if (Test-WindhawkRegistry) {
            Write-Host "Exporting $RegKey ..."
            Invoke-Reg -Arguments @('export', $RegKey, (Join-Path $stage 'Windhawk.reg'), '/y')
        } else {
            Write-Host "Key $RegKey not found (portable version?), registry skipped."
        }

        Write-Host 'Compressing to ZIP...'
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Backup saved: $zip" -ForegroundColor Green
    $zip
}

# --- Restore ----------------------------------------------------------------

function Restore-WindhawkBackup {
    param([string]$Zip)

    $stage = Join-Path $env:TEMP ('windhawk-restore_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-Host "Extracting $Zip ..."
    Expand-Archive -LiteralPath $Zip -DestinationPath $stage -Force
    try {
        $data = Join-Path $stage 'Data'
        $reg  = Join-Path $stage 'Windhawk.reg'
        if (-not (Test-Path $data) -and -not (Test-Path $reg)) {
            throw "$Zip contains neither Data\ nor Windhawk.reg - not a backup made by this script."
        }

        if ($Clean) {
            Write-Host 'Removing current mods (-Clean)...'
            # Mod DLLs stay loaded in running processes (explorer.exe etc.) after the service
            # stops, and a loaded DLL cannot be deleted. Remove what can be removed, report the rest.
            $inUse = @()
            foreach ($rel in $ModDirs) {
                $dir = Join-Path $WindhawkRoot $rel
                if (-not (Test-Path $dir)) { continue }
                foreach ($file in Get-ChildItem -LiteralPath $dir -Recurse -File -Force) {
                    try { Remove-Item -LiteralPath $file.FullName -Force }
                    catch { $inUse += $file.FullName }
                }
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($inUse) {
                Write-Warning "$($inUse.Count) file(s) in use, left in place (gone after a reboot and another -Clean restore):"
                $inUse | ForEach-Object { Write-Host "    $_" }
            }
            if (Test-WindhawkRegistry) {
                foreach ($sub in $ModRegKeys) {
                    cmd.exe /c "reg delete `"$RegKey\$sub`" /f /reg:64 >nul 2>&1"
                }
            }
        }

        if (Test-Path $data) {
            # Files already identical to the backup are not copied: a loaded mod DLL cannot be
            # overwritten, and after the ZIP round trip its timestamp differs, so robocopy would try.
            $skipped = 0
            $dataFull = (Get-Item -LiteralPath $data).FullName
            foreach ($file in Get-ChildItem -LiteralPath $data -Recurse -File -Force) {
                $dst = Join-Path $WindhawkRoot $file.FullName.Substring($dataFull.Length).TrimStart('\', '/')
                if ((Test-Path -LiteralPath $dst -PathType Leaf) -and
                    (Get-Item -LiteralPath $dst -Force).Length -eq $file.Length -and
                    (Get-FileHash -LiteralPath $dst).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $skipped++
                }
            }
            Write-Host "Copying files to $WindhawkRoot ($skipped unchanged file(s) skipped)..."
            Invoke-Robocopy -Source $data -Destination $WindhawkRoot
        }
        if (Test-Path $reg) {
            Write-Host "Importing $RegKey ..."
            Invoke-Reg -Arguments @('import', $reg)
        }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Restore complete.' -ForegroundColor Green
}

# --- Main -------------------------------------------------------------------

# The script writes its own log: a thrown error bypasses "*>" redirection, and after a UAC
# relaunch the output is in another window anyway.
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$LogFile = Join-Path $BackupDir 'windhawk-backup.log'
Start-Transcript -LiteralPath $LogFile -Append | Out-Null

try {
    if (-not $Action) {
        $choice = Read-Host '1 = Backup, 2 = Restore'
        switch ($choice) {
            '1' { $Action = 'Backup' }
            '2' { $Action = 'Restore' }
            default { throw "Unknown choice: $choice" }
        }
    }

    if (-not (Test-Path $WindhawkRoot)) {
        throw "Windhawk data folder not found: $WindhawkRoot. For the portable version pass -WindhawkRoot (AppDataPath from windhawk.ini)."
    }

    if ($Action -eq 'Restore') {
        if (-not $Path) {
            $latest = Get-ChildItem -Path $BackupDir -Filter 'windhawk-backup_*.zip' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike '*_pre-restore.zip' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw "No backups in $BackupDir. Pass -Path." }
            $Path = $latest.FullName
        }
        if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }

        Write-Host "Restoring from: $Path"
        if ($Clean) { Write-Host '-Clean: current mods will be removed before restore.' -ForegroundColor Yellow }
        $answer = Read-Host 'Continue? (y/N)'
        if ($answer -notmatch '^y') { Write-Host 'Cancelled.'; return }
    }

    $state = Stop-Windhawk
    try {
        if ($Action -eq 'Backup') {
            New-WindhawkBackup | Out-Null
            Remove-OldBackups
        } else {
            Write-Host 'Safety backup of the current state...'
            New-WindhawkBackup -Suffix '_pre-restore' | Out-Null
            Restore-WindhawkBackup -Zip $Path
        }
    } finally {
        Start-Windhawk -State $state
    }
} catch {
    # Write-Host reaches the transcript and "*>" redirection; a rethrown error would not.
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "At: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
} finally {
    Write-Host "Log: $LogFile"
    Stop-Transcript | Out-Null
}
