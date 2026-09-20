# AnyAppPortable

Добавляет любую портативную программу — папку или одиночный `.exe` — в меню
[PortableApps.com](https://portableapps.com).

Один скрипт на PowerShell. Ни компилятора, ни NSIS, ни генератора лаунчеров,
ничего ставить не нужно.

```powershell
.\New-PortableApp.ps1 "D:\Papps\Victoria537"
```

```
  главный exe: Victoria.exe
  копирую программу -> App\Victoria
  делаю иконки
  лаунчер: VictoriaPortable.exe

  Готово: D:\Papps\PortableApps\VictoriaPortable
```

После обновления списка программа появляется в меню со своей иконкой, именем и
категорией.

Сообщения — на русском или английском, по языку интерфейса Windows;
переключается ключом `-Language en|ru`.

*English version: [README.md](README.md)*

## Как меню находит программы

`PortableApps.com\PortableAppsPlatform.exe` при старте (и при обновлении списка)
сканирует папку `PortableApps\` на один уровень вглубь. Папка попадает в меню
тогда и только тогда, когда в ней есть файл:

```
<ЛюбаяПапка>\App\AppInfo\appinfo.ini
```

Из него берётся всё, что видит пользователь: название, категория, описание,
версия. Иконка — из соседних `appicon*.ico/.png`. Что запускать — из строки
`Start=` в секции `[Control]`.

Никакой регистрации, базы данных или установщика: положил папку правильной
формы — программа в меню, убрал папку — исчезла. Настройки самого меню лежат в
`PortableApps.com\Data\PortableAppsMenu.ini` (там же счётчик запусков
`[TimesRun]` в виде `папка\файл.exe`).

## Структура папки приложения

```
ИмяPortable\
├── ИмяPortable.exe                 лаунчер PortableApps.com (PAL)
├── App\
│   ├── AppInfo\
│   │   ├── appinfo.ini             карточка для меню
│   │   ├── appicon.ico             иконка (многоразмерная)
│   │   ├── appicon_16.png          ... _32, _75, _128, _256 — для меню
│   │   └── Launcher\
│   │       └── ИмяPortable.ini     что и как запускать
│   ├── Имя\                        сама программа
│   └── DefaultData\                эталон настроек: копируется в Data\,
│                                   если Data\ пустая (первый запуск)
├── Data\                           настройки пользователя
└── Other\Source\                   необязательно: исходники, readme
```

Имя папки, имя лаунчера и `AppID` принято делать одинаковыми
(`WizTreePortable\WizTreePortable.exe` + `AppID=WizTreePortable`).

## appinfo.ini — минимум

```ini
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=WizTree Portable          ; что видно в меню
AppID=WizTreePortable          ; без пробелов, совпадает с именем папки
Publisher=...
Category=Utilities             ; см. список ниже
Description=Анализ занятого места
Language=Multilingual

[Version]
PackageVersion=4.2.1.0         ; строго четыре числа через точку
DisplayVersion=4.21            ; как показывать человеку

[Control]
Icons=1
Start=WizTreePortable.exe      ; путь относительно папки приложения
```

Допустимые категории (иначе программа уедет в «Другое»):
`Accessibility`, `Development`, `Education`, `Games`, `Graphics & Pictures`,
`Internet`, `Music & Video`, `Office`, `Security`, `Utilities`.

Несколько пунктов от одной программы (как у LibreOffice) — через `Icons=7`,
`Start1..Start7`, `Name1..`, `Description1..` и иконки `appicon1.ico`,
`appicon2.ico`, …

## Лаунчер (PAL) и его ini

`ИмяPortable.exe` — это универсальный PortableApps.com Launcher. **Проверено:
он не «зашит» под конкретную программу.** Стаб определяет приложение по имени
собственного файла и читает `App\AppInfo\Launcher\<имя_exe>.ini`, а свои
настройки пишет в `Data\settings\<имя_exe>Settings.ini`.

Поэтому скрипт просто копирует стаб от уже установленного приложения: ищет
«чистый» — такой, у которого в папке `App\AppInfo\Launcher` нет ничего, кроме
его собственного `.ini` (то есть нет `Custom.nsh` со скомпилированным кодом под
ту программу), берёт самый свежий PAL и кэширует его в
`Template\PortableAppsLauncher.exe`.

Что умеет ini лаунчера:

```ini
[Launch]
ProgramExecutable=Имя\program.exe        ; путь от папки App\
ProgramExecutable64=Имя\program64.exe    ; если есть 64-битная сборка
CommandLineArguments=--portable
DirectoryMoveOK=yes
SupportsUNC=yes
SingleAppInstance=true
WaitForProgram=true
RunAsAdmin=force                         ; если программе нужны права админа

[Activate]
Registry=true

[RegistryKeys]                           ; ветка уезжает в Data\ и возвращается
Key1=HKCU\Software\Vendor\App            ; в систему только на время работы

[DirectoriesMove]                        ; то же самое для папки настроек
settings1=%APPDATA%\Vendor\App
```

Если программа хранит настройки рядом с собой (большинство портативных) —
хватит одной секции `[Launch]`.

У клонированного стаба один изъян, косметический: **в Проводнике он носит
иконку донора** — она лежит в его ресурсах. На меню это не влияет, оно берёт
картинку из `App\AppInfo\appicon*`. И подменить её внутри стаба нельзя: сборки
лаунчера подписаны цифровой подписью.

```
Status            : Valid
SignerCertificate : CN="RARE IDEAS, LLC", O="RARE IDEAS, LLC", L=New York
```

Любая правка файла ломает подпись, и стаб перестаёт работать. Проверено на
одном стенде — клон готового пакета, где подменяется только exe лаунчера:

| правка | результат |
|---|---|
| `UpdateResource` (штатный API Windows) | файл легче на 19 КБ, оверлей NSIS потерян, программа не стартует |
| то же + возврат оверлея вручную | лаунчер отрабатывает вхолостую, программу не запускает |
| один байт внутри пиксельных данных иконки, раскладка файла нетронута | не стартует |
| контроль: тот же стаб без правок | работает |

**Поэтому ради правильной иконки ставится официальный
[PortableApps.com Launcher](https://portableapps.com/apps/development/portableapps.com_launcher).**
Это обычное портативное приложение, нужное только в момент сборки пакета. Если
скрипт находит
`PortableApps\PortableApps.comLauncher\PortableApps.comLauncherGenerator.exe`,
он отдаёт ему готовый пакет и получает лаунчер, собранный вокруг
`App\AppInfo\appicon.ico` — той самой иконки, которую скрипт уже вытащил из
программы. Свежесобранные лаунчеры не подписаны, ломать нечего.

Ключ `-Launcher` выбирает стратегию:

| значение | поведение |
|---|---|
| `Auto` | генератор, если он установлен, иначе клон стаба (по умолчанию) |
| `Generate` | требовать генератор, падать сразу, если его нет |
| `Clone` | всегда клонировать стаб, генератор не звать |
| `None` | без лаунчера вообще: `Start=` указывает на `App\Имя\program.exe`. Теряется перенос настроек и подстановка путей, зато папка чище и ничего ни у кого не заимствуется |

## Кодировка ini — важно

Меню и лаунчер читают ini через `GetPrivateProfileString` (Win32). Проверено на
значениях с кириллицей:

| кодировка файла | результат |
|---|---|
| ASCII / ANSI (cp1251) | читается |
| UTF-16LE с BOM | читается |
| UTF-8 с BOM | секция вообще не находится |
| UTF-8 без BOM | кракозябры |

Скрипт поэтому пишет ASCII, если весь текст латиницей, и UTF-16LE, если в
названии или описании есть русский. Принудительно: `-IniEncoding Ansi|Unicode`.

Это же и есть причина, по которой руками написанный `appinfo.ini` с русским
названием часто «не подхватывается»: редакторы по умолчанию сохраняют в UTF-8.

## Инструмент

| файл | что делает |
|---|---|
| `New-PortableApp.ps1` | собирает структуру из папки или одиночного `.exe` |
| `add-to-menu.cmd` | перетащить на него папку/exe — и всё |
| `scan.cmd` | показать, что ещё не в меню |
| `Rebuild-Launchers.ps1` | пересобрать лаунчеры пакетов, сделанных до установки генератора |
| `docs/paf-format.md` | подробные заметки по формату (на английском) |

```powershell
# самое простое — остальное спросит/определит само
.\New-PortableApp.ps1 "D:\Papps\Victoria537"

# со всеми полями карточки
.\New-PortableApp.ps1 "D:\Papps\hwinfo" `
    -Name "HWiNFO" -Category Utilities `
    -Description "Мониторинг железа и датчиков" -Publisher "Martin Malik"

# одиночный exe, нужны права админа, оригинал перенести (не копировать)
.\New-PortableApp.ps1 "D:\Papps\Win 10 Tweaker.exe" -Name "Win 10 Tweaker" -RunAsAdmin -Move

# программа держит настройки в реестре и в AppData — забрать их в Data\
.\New-PortableApp.ps1 "D:\Papps\fan control" -Name "FanControl" `
    -RegistryKey 'HKCU\Software\FanControl' -AppDataDir '%APPDATA%\FanControl'

# что лежит рядом и ещё не в меню
.\New-PortableApp.ps1 -Scan
```

| ключ | зачем |
|---|---|
| `-Name`, `-AppId`, `-Category`, `-Description`, `-Publisher`, `-Version` | поля карточки; что не задано — берётся из версии exe или спрашивается |
| `-Exe`, `-Exe64` | если автоопределение главного exe ошиблось |
| `-Arguments` | аргументы командной строки |
| `-Icon` | взять иконку из другого файла (`.ico`/`.png`/`.exe`) |
| `-RegistryKey`, `-AppDataDir` | перенести настройки программы в `Data\` |
| `-RunAsAdmin` | запускать с правами администратора |
| `-Move` | перенести исходник, а не копировать |
| `-Launcher` | `Auto` (по умолчанию), `Generate`, `Clone`, `None` |
| `-Generator` | явный путь к `PortableApps.comLauncherGenerator.exe` |
| `-NoLauncher` | то же, что `-Launcher None` |
| `-Force` | перезаписать уже существующую папку |
| `-Destination` | другая папка назначения (по умолчанию `..\PortableApps`) |
| `-IniEncoding` | `Auto` (по умолчанию), `Ansi`, `Unicode` |
| `-Language` | `Auto` (по языку Windows), `en`, `ru` |
| `-Scan` | список неподключённых программ |

Как выбирается главный exe: сначала отбрасываются `setup/unins/update/crash/
vcredist/…` и ARM64-сборки, потом очки за совпадение имени с папкой, за GUI
(а не консоль — подсистема читается из PE-заголовка), за наличие описания
версии, за меньшую вложенность. Если уверенности нет — показывает список и
спрашивает номер. Пара `Foo32.exe` + `Foo64.exe` распознаётся автоматически и
пишется как `ProgramExecutable` + `ProgramExecutable64`.

## Пакеты, сделанные до установки генератора

У них лаунчер - клон чужого стаба, то есть с чужой иконкой в Проводнике.
`Rebuild-Launchers.ps1` находит именно такие (сравнивает, для какой программы
собран лаунчер, с именем в `appinfo.ini`) и пересобирает их генератором.
Приложения, установленные с portableapps.com, не трогает. Без ключа `-Apply`
только показывает список.

```powershell
.\Rebuild-Launchers.ps1           # посмотреть, что будет пересобрано
.\Rebuild-Launchers.ps1 -Apply    # пересобрать
```

## После добавления

Меню не следит за папкой в реальном времени: нужно либо правый клик по значку
платформы → обновить список, либо перезапустить `PortableAppsPlatform.exe`.

Удалить программу из меню — просто удалить её папку из `PortableApps\`.

## Авторство

Идея — Hinduc0der, и всё вокруг неё тоже: постановка задачи, решения о том, что
инструмент делает, а чего не делает, и проверка на живой установке
PortableApps.com.

Реализация — нет. Весь код здесь, опыты, на которых держится устройство
инструмента (что стаб лаунчера универсален; что он подписан и потому иконку в
нём заменить нельзя; какие кодировки ini меню способно прочитать), и вся
документация написаны Claude (Claude Opus 5, Anthropic) в Claude Code.
Человеческого кода в репозитории нет.

## Лицензия

MIT — см. [LICENSE](LICENSE).

PortableApps.com, PortableApps.com Launcher и формат PortableApps.com Format —
работа Rare Ideas, LLC и участников проекта. Этот скрипт лишь генерирует файлы
этого формата и копирует стаб лаунчера, который уже есть на вашей машине.
С PortableApps.com проект никак не связан.
