@echo off
rem Double-click: asks Backup/Restore. Arguments are passed through: windhawk-backup.cmd Restore -Clean
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windhawk-backup.ps1" %*
