# windhawk-backup

**One command to back up [Windhawk](https://windhawk.net) — every mod, its
settings and its stored data — into a single ZIP, and one command to put it back.**

Windhawk has no export button. Its state is split between
`C:\ProgramData\Windhawk` and `HKLM\SOFTWARE\Windhawk`; this script collects
both, and restores them while the mods are still loaded.

[Русская версия](README.RU.md)

## Quick start

1. Download `windhawk-backup.ps1` and `windhawk-backup.cmd` into one folder,
   for example `C:\Tools\windhawk-backup`.
2. Double-click `windhawk-backup.cmd`, confirm UAC, press `1` for backup.
3. The ZIP appears next to the script.

On a new machine or after a reinstall: install Windhawk, double-click the
`.cmd` again, press `2`.

## Examples

Run from PowerShell in the script folder. Without admin rights the script
relaunches itself through UAC.

```powershell
# Back up; keeps the last 10 backups next to the script
.\windhawk-backup.ps1 Backup

# Back up to another folder and never delete old backups
.\windhawk-backup.ps1 Backup -BackupDir D:\Backups\Windhawk -Keep 0

# Restore the newest backup; mods installed after it stay
.\windhawk-backup.ps1 Restore

# Restore a specific file
.\windhawk-backup.ps1 Restore -Path D:\Backups\Windhawk\windhawk-backup_20260926_180525.zip

# Exact state of the backup: remove current mods first
.\windhawk-backup.ps1 Restore -Clean

# Portable Windhawk: pass AppDataPath from windhawk.ini
.\windhawk-backup.ps1 Backup -WindhawkRoot D:\Tools\Windhawk\AppData

# Scripts blocked by the execution policy
powershell -ExecutionPolicy Bypass -File .\windhawk-backup.ps1 Backup

# Full help
.\windhawk-backup.ps1 --help
```

A restore looks like this (paths are illustrative, output is real):

```text
Restoring from: C:\Tools\windhawk-backup\windhawk-backup_20260926_180525.zip
Continue? (y/N): y
Stopping Windhawk service...
Stopping windhawk.exe processes...
Safety backup of the current state...
Backup saved: C:\Tools\windhawk-backup\windhawk-backup_20260926_181357_pre-restore.zip
Extracting C:\Tools\windhawk-backup\windhawk-backup_20260926_180525.zip ...
Copying files to C:\ProgramData\Windhawk (38 unchanged file(s) skipped)...
Importing HKLM\SOFTWARE\Windhawk ...
Restore complete.
Starting Windhawk service...
Log: C:\Tools\windhawk-backup\windhawk-backup.log
```

## What is in the ZIP

| Part | Content |
|---|---|
| `Data\ModsSource` | mod source code |
| `Data\Engine\Mods` | compiled mods, 32- and 64-bit |
| `Data\Engine\ModsWritable\mod-storage` | files a mod keeps for itself, e.g. icon themes |
| `Windhawk.reg` | which mods are enabled, each mod's settings (`Engine\Mods\<mod>\Settings`), local storage, Windhawk settings |

Not copied: editor caches (`UIData`, `EditorWorkspace`) and per-process runtime
state (`mod-status`, `mod-task`). Windhawk recreates them.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `Backup` / `Restore` | asks | what to do |
| `-Path` | newest backup | restore: ZIP to restore from |
| `-Clean` | off | restore: remove current mods first |
| `-BackupDir` | script folder | where backups and the log go |
| `-WindhawkRoot` | `C:\ProgramData\Windhawk` | Windhawk data folder |
| `-Keep` | `10` | backups to keep; `0` keeps all |
| `-Help`, `--help` | | full help with examples |

## Safety

- **Before every restore** the current state is saved as
  `windhawk-backup_<time>_pre-restore.zip`. `-Keep` never deletes these.
- **Every run is logged** to `windhawk-backup.log` next to the backups,
  errors included.
- **Loaded mod DLLs are not overwritten.** After the service stops, mods stay
  loaded in `explorer.exe` and other processes. Files identical to the backup
  (SHA256) are skipped, so a normal restore does not touch them.

## Troubleshooting

**`robocopy ... failed with exit code 8+` with `ERROR 32`.** A mod DLL in the
backup differs from the loaded one. Reboot and run the restore right after
logon.

**Nothing in the log file after `> log`.** Not needed: the script writes
`windhawk-backup.log` itself, also after a UAC relaunch into another window.

## Requirements

Windows 10 or 11, Windows PowerShell 5.1 (built in), administrator rights.
Tested with installed Windhawk 1.7.3. Portable should work with
`-WindhawkRoot`, untested.

## License

[MIT](LICENSE)
