# Notes on the PortableApps.com Format, as observed

Everything below was checked against a live PortableApps.com Platform 30.5
installation and PAL (PortableApps.com Launcher) builds 2.2.1 through 2.2.9.
Where something was verified by experiment rather than read in a spec, it says
so and describes the experiment.

## 1. How the menu discovers apps

The platform scans `PortableApps\` **one level deep**. A folder is listed if and
only if it contains:

```
<Folder>\App\AppInfo\appinfo.ini
```

Everything the user sees comes from that file. There is no registry, no
database, no install step — dropping a folder in adds an entry, deleting it
removes one.

Menu settings live in `PortableApps.com\Data\PortableAppsMenu.ini`, which is
UTF-16LE. It also stores launch counters:

```ini
[TimesRun]
wiztreeportable\wiztreeportable.exe=8
firefoxportable\firefoxportable.exe=104
```

The key is `<app folder>\<Start value>`, lowercased — which is a useful hint
that `Start=` is simply joined to the app folder, so a nested path like
`App\Foo\foo.exe` is a valid `Start` value.

## 2. Package layout

```
NamePortable\
├── NamePortable.exe                 launcher (optional, see §3)
├── App\
│   ├── AppInfo\
│   │   ├── appinfo.ini
│   │   ├── appicon.ico
│   │   ├── appicon_16.png           also _32, _75, _128, _256
│   │   └── Launcher\
│   │       ├── NamePortable.ini     PAL configuration
│   │       ├── Custom.nsh           optional, compiled into the launcher
│   │       └── splash.jpg           optional
│   ├── Name\                        the application
│   └── DefaultData\                 copied into Data\ when Data\ is empty
├── Data\
├── Other\Source\
└── help.html
```

Convention: folder name = launcher name = `AppID`.

## 3. The launcher is generic — verified

`NamePortable.exe` is a compiled NSIS stub. It is *not* tied to the application
it ships with.

**Experiment.** `WinDjViewPortable` was copied to `ZZTestPortable`, its
`WinDjViewPortable.exe` renamed to `ZZTestPortable.exe`, its
`App\AppInfo\Launcher\WinDjViewPortable.ini` renamed to `ZZTestPortable.ini`,
`Data\` emptied, `AppID`/`Name`/`Start` in `appinfo.ini` changed. Running
`ZZTestPortable.exe` started
`D:\...\ZZTestPortable\App\WinDjView\WinDjView.exe` and created
`Data\settings\ZZTestPortableSettings.ini`.

Conclusion: the stub takes the app id from **its own file name**, reads
`App\AppInfo\Launcher\<own name>.ini`, and writes
`Data\settings\<own name>Settings.ini`. Any stub can be reused by copying and
renaming it.

Two things do *not* travel with a reused stub:

- **The icon.** It lives in the stub's PE resources, so in Explorer the new
  launcher shows the donor's icon. The menu is unaffected — it reads
  `App\AppInfo\appicon*`. It cannot be replaced: official launcher builds are
  Authenticode-signed by `CN="RARE IDEAS, LLC"`, and any edit invalidates the
  signature, after which the stub no longer runs its program. Measured, with a
  cloned package where only the launcher exe was swapped: `UpdateResource`
  leaves the file 19 KB shorter with the NSIS overlay gone; appending the
  overlay back is not enough either; and even flipping a single byte inside the
  icon pixel data, with the file layout untouched, is enough to break it, while
  the same stub unmodified works. For a launcher carrying the application's own
  icon, build one with the official PortableApps.com Launcher Generator — its
  output is unsigned and correct by construction.
- **`Custom.nsh`.** If the donor had one, its compiled code is inside the stub
  and will run for your app too. Only pick donors whose
  `App\AppInfo\Launcher\` contains nothing but its own `.ini`.

Stub version and identity are readable from the version resource:
`InternalName = "PortableApps.com Launcher"`, `FileVersion = 2.2.9.0`.

## 4. `appinfo.ini`

Minimum that the menu is happy with:

```ini
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=WizTree Portable
AppID=WizTreePortable
Publisher=...
Category=Utilities
Description=Disk space analyser
Language=Multilingual

[Version]
PackageVersion=4.2.1.0      ; exactly four dot-separated numbers
DisplayVersion=4.21

[Control]
Icons=1
Start=WizTreePortable.exe
```

`Type=` is written both as `PortableApps.comFormat` and `PortableAppsFormat` by
real packages; both are accepted.

Categories: `Accessibility`, `Development`, `Education`, `Games`,
`Graphics & Pictures`, `Internet`, `Music & Video`, `Office`, `Security`,
`Utilities`. Anything else lands in "Other".

Several entries from one package (LibreOffice does this):

```ini
[Control]
Icons=7
Start=LibreOfficePortable.exe
Start1=LibreOfficeBasePortable.exe
Name1=LibreOffice Portable Base
Description1=Database
...
```

with matching `appicon1.ico`, `appicon1_32.png`, … per entry.

Optional sections seen in the wild: `[License]`, `[Dependencies]`
(`UsesJava=optional`), `[Associations]` (`FileTypes=`, `FileTypeCommandLine=`),
`[FileTypeIcons]`, and in `[Control]` a `BaseAppID` used for taskbar grouping,
sometimes written as `%BASELAUNCHERPATH%\App\vlc\vlc.exe`.

## 5. Launcher ini (`App\AppInfo\Launcher\<AppID>.ini`)

```ini
[Launch]
ProgramExecutable=Name\program.exe        ; relative to App\
ProgramExecutable64=Name\program64.exe
ProgramExecutableARM64=Name\programA64.exe
CommandLineArguments=--portable
WorkingDirectory=...
DirectoryMoveOK=yes
SupportsUNC=yes
SingleAppInstance=true
WaitForProgram=true
RunAsAdmin=force

[Activate]
Registry=true

[RegistryKeys]
Key1=HKCU\Software\Vendor\App

[RegistryValueWrite]
HKCU\Software\Vendor\App\Settings\Something=REG_SZ:value

[RegistryCleanupIfEmpty]
1=HKCU\Software\Vendor

[DirectoriesMove]
settings1=%APPDATA%\Vendor\App

[FileWrite1]
Type=Replace
File=%PAL:DataDir%\settings\app.reg
Find=%PAL:LastDrive%\\
Replace=%PAL:Drive%\\
```

Paths containing spaces must be quoted:
`ProgramExecutable="Hetman Partition Recovery\Hetman Partition Recovery.exe"`.

For a program that keeps its settings next to itself — most genuinely portable
ones — `[Launch]` alone is enough.

## 6. INI encoding — the non-obvious part

The platform and the launcher are NSIS programs; they read ini files through
`GetPrivateProfileString`. Tested by writing the same content with a Cyrillic
value in four encodings and reading it back through `GetPrivateProfileStringW`:

| Encoding | Result |
|---|---|
| ASCII / system ANSI (cp1251 here) | correct |
| UTF-16LE with BOM | correct |
| UTF-8 **with** BOM | section not found — the BOM becomes part of the first section name |
| UTF-8 without BOM | mojibake (bytes reinterpreted as ANSI) |

So: keep ini files ASCII, or save them as UTF-16LE with BOM. This is the usual
reason a hand-written `appinfo.ini` with a non-English name "does not show up".

## 7. Refreshing

The menu does not watch the folder. After adding a package, refresh the app list
from the platform's tray/menu, or restart `PortableAppsPlatform.exe`.
