# windhawk-backup

**Одна команда сохраняет [Windhawk](https://windhawk.net) — все моды, их
настройки и данные — в один ZIP. Вторая команда возвращает всё обратно.**

Кнопки экспорта в Windhawk нет. Его состояние лежит в двух местах:
`C:\ProgramData\Windhawk` и `HKLM\SOFTWARE\Windhawk`. Скрипт забирает оба и
умеет восстанавливать их, даже когда моды загружены в процессы.

[English version](README.md)

## Быстрый старт

1. Скачай `windhawk-backup.ps1` и `windhawk-backup.cmd` в одну папку,
   например `C:\Tools\windhawk-backup`.
2. Запусти `windhawk-backup.cmd` двойным кликом, подтверди UAC, нажми `1` —
   бэкап.
3. ZIP появится рядом со скриптом.

На новой машине или после переустановки: поставь Windhawk, снова запусти
`.cmd`, нажми `2`.

## Примеры

Запускать из PowerShell в папке скрипта. Без прав администратора скрипт сам
перезапустится через UAC.

```powershell
# Бэкап; рядом со скриптом хранятся последние 10
.\windhawk-backup.ps1 Backup

# Бэкап в другую папку, старые не удалять
.\windhawk-backup.ps1 Backup -BackupDir D:\Backups\Windhawk -Keep 0

# Восстановить из последнего бэкапа; моды, поставленные позже, остаются
.\windhawk-backup.ps1 Restore

# Восстановить из конкретного файла
.\windhawk-backup.ps1 Restore -Path D:\Backups\Windhawk\windhawk-backup_20260926_180525.zip

# Точно как в бэкапе: сначала удалить текущие моды
.\windhawk-backup.ps1 Restore -Clean

# Портативный Windhawk: путь из AppDataPath в windhawk.ini
.\windhawk-backup.ps1 Backup -WindhawkRoot D:\Tools\Windhawk\AppData

# Если скрипты запрещены политикой выполнения
powershell -ExecutionPolicy Bypass -File .\windhawk-backup.ps1 Backup

# Полная справка
.\windhawk-backup.ps1 --help
```

Так выглядит восстановление (пути условные, вывод настоящий):

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

## Что лежит в ZIP

| Часть | Содержимое |
|---|---|
| `Data\ModsSource` | исходники модов |
| `Data\Engine\Mods` | скомпилированные моды, 32 и 64 бита |
| `Data\Engine\ModsWritable\mod-storage` | файлы, которые мод хранит сам, например темы иконок |
| `Windhawk.reg` | какие моды включены, настройки каждого мода (`Engine\Mods\<mod>\Settings`), их локальное хранилище, настройки Windhawk |

Не копируются кэши редактора (`UIData`, `EditorWorkspace`) и временное
состояние процессов (`mod-status`, `mod-task`): Windhawk создаёт их заново.

## Параметры

| Параметр | По умолчанию | Что делает |
|---|---|---|
| `Backup` / `Restore` | спросит | что делать |
| `-Path` | последний бэкап | восстановление: из какого ZIP |
| `-Clean` | выключен | восстановление: сначала удалить текущие моды |
| `-BackupDir` | папка скрипта | куда класть бэкапы и лог |
| `-WindhawkRoot` | `C:\ProgramData\Windhawk` | папка данных Windhawk |
| `-Keep` | `10` | сколько бэкапов хранить; `0` — все |
| `-Help`, `--help` | | полная справка с примерами |

## Защита от потерь

- **Перед каждым восстановлением** текущее состояние сохраняется в
  `windhawk-backup_<время>_pre-restore.zip`. `-Keep` такие файлы не удаляет.
- **Каждый запуск пишется в лог** `windhawk-backup.log` рядом с бэкапами,
  вместе с ошибками.
- **Загруженные DLL модов не перезаписываются.** После остановки службы моды
  остаются загруженными в `explorer.exe` и другие процессы. Файлы, совпадающие
  с бэкапом по SHA256, пропускаются, поэтому обычное восстановление их не
  трогает.

## Если что-то пошло не так

**`robocopy ... failed with exit code 8+` и `ERROR 32`.** DLL мода в бэкапе
отличается от загруженной. Перезагрузись и запусти восстановление сразу после
входа.

**Лог через `> log` пустой.** Он и не нужен: скрипт сам пишет
`windhawk-backup.log`, в том числе после перезапуска через UAC в другом окне.

## Требования

Windows 10 или 11, Windows PowerShell 5.1 (встроен), права администратора.
Проверено на установленном Windhawk 1.7.3. Портативный должен работать с
`-WindhawkRoot`, но не проверялся.

## Лицензия

[MIT](LICENSE)
