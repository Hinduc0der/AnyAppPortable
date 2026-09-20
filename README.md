# AnyAppPortable

Turn any portable Windows program — a folder or a single `.exe` — into a
[PortableApps.com](https://portableapps.com) menu entry.

One PowerShell script. No compiler, no NSIS, no PortableApps.com Launcher
Generator, nothing to install.

```powershell
.\New-PortableApp.ps1 "D:\Papps\Victoria537"
```

```
  main executable: Victoria.exe
  copying the program -> App\Victoria
  building icons
  launcher: VictoriaPortable.exe

  Done: D:\Papps\PortableApps\VictoriaPortable
```

…and the app shows up in the PortableApps.com menu with its own icon, name and
category after a menu refresh.

> Messages come in English or Russian, following the Windows UI language.
> Override with `-Language en|ru`.

## What it does

Given a folder (or one `.exe`), it builds a complete PortableApps.com Format
(PAF) package:

- **finds the main executable** — skips `setup` / `unins` / `update` / `crash` /
  `vcredist` / ARM64 builds, then scores the rest by name match with the folder,
  GUI vs console subsystem (read from the PE header), presence of version info,
  and nesting depth. If it is not sure, it shows the candidates and asks;
- **detects 32/64-bit pairs** (`Foo32.exe` + `Foo64.exe`) and wires them up as
  `ProgramExecutable` / `ProgramExecutable64`;
- **extracts the icon** straight from the executable's `RT_GROUP_ICON` resources
  and renders `appicon.ico` plus `appicon_16/32/75/128/256.png`. Falls back to a
  generated letter tile if the exe carries no icon;
- **writes `appinfo.ini` and the launcher ini** in an encoding the menu can
  actually read (see [Encoding](#encoding-matters), it is not obvious);
- **supplies the launcher** — through the official PortableApps.com Launcher
  Generator when it is installed, otherwise by cloning a stock launcher stub
  from an app you already have — see [How the launcher works](#how-the-launcher-works);
- **fills in metadata** (name, version, publisher, description) from the exe's
  version resource, and asks for whatever is missing.

It can also tell you what is *not* in the menu yet:

```powershell
.\New-PortableApp.ps1 -Scan
```

```
  type    what                             main exe
  folder  Calibre Portable                 calibre-portable.exe
  folder  fan control                      FanControl.exe
  folder  hwinfo                           HWiNFO64.exe
  exe     keyviz-v1.0.6-portable.exe       keyviz-v1.0.6-portable.exe
```

## Requirements

- Windows with the PortableApps.com Platform installed
- Windows PowerShell 5.1 (ships with Windows) or PowerShell 7+
- For the launcher, one of:
  - [PortableApps.com Launcher](https://portableapps.com/apps/development/portableapps.com_launcher)
    installed into `PortableApps\` — the best result, the launcher gets the app's own icon;
  - or simply any app installed from portableapps.com, whose launcher stub gets cloned;
  - or neither, with `-Launcher None`.

## Install

Drop the repo next to your `PortableApps` folder:

```
X:\YourPortableDrive\
├── PortableApps\            <- the platform and its apps
│   ├── PortableApps.com\
│   ├── FirefoxPortable\
│   └── ...
└── Tools\                   <- this repo
    ├── New-PortableApp.ps1
    ├── Rebuild-Launchers.ps1
    ├── add-to-menu.cmd
    └── scan.cmd
```

The default destination is `..\PortableApps` relative to the script. Anywhere
else works too — just pass `-Destination`.

## Usage

Drag a folder or an `.exe` onto **`add-to-menu.cmd`**, or:

```powershell
# simplest — everything else is detected or asked for
.\New-PortableApp.ps1 "D:\Papps\Victoria537"

# full metadata
.\New-PortableApp.ps1 "D:\Papps\hwinfo" `
    -Name "HWiNFO" -Category Utilities `
    -Description "Hardware monitoring" -Publisher "Martin Malik"

# a single exe, needs elevation, move the original instead of copying
.\New-PortableApp.ps1 "D:\Papps\Win 10 Tweaker.exe" -Name "Win 10 Tweaker" -RunAsAdmin -Move

# the app keeps settings in the registry and in %APPDATA% — pull them into Data\
.\New-PortableApp.ps1 "D:\Papps\fan control" -Name "FanControl" `
    -RegistryKey 'HKCU\Software\FanControl' -AppDataDir '%APPDATA%\FanControl'

# what is still missing from the menu
.\New-PortableApp.ps1 -Scan
```

| Option | Purpose |
|---|---|
| `-Name`, `-AppId`, `-Category`, `-Description`, `-Publisher`, `-Version` | menu card fields; anything omitted is taken from the exe's version info or asked for |
| `-Exe`, `-Exe64` | override main-executable detection |
| `-Arguments` | command line arguments for the program |
| `-Icon` | take the icon from another file (`.ico` / `.png` / `.exe`) |
| `-RegistryKey`, `-AppDataDir` | move the app's settings into `Data\` while it runs |
| `-RunAsAdmin` | launch elevated |
| `-Move` | move the source instead of copying it |
| `-Launcher` | `Auto` (default: official generator if present, else a cloned stub), `Generate`, `Clone`, `None` |
| `-Generator` | explicit path to `PortableApps.comLauncherGenerator.exe` |
| `-NoLauncher` | same as `-Launcher None` |
| `-Force` | overwrite an existing app folder |
| `-Destination` | target folder (default `..\PortableApps`) |
| `-IniEncoding` | `Auto` (default), `Ansi`, `Unicode` |
| `-Language` | `Auto` (follows the Windows UI language), `en`, `ru` |
| `-Scan` | list programs that are not in the menu yet |

`Rebuild-Launchers.ps1` is a companion for the case where you added packages
before installing the generator: it finds the ones whose launcher was cloned
from another application, and rebuilds them so each carries its own icon.
Packages installed from portableapps.com are left alone. It prints what it would
do and changes nothing until you pass `-Apply`.

Categories accepted by the menu: `Accessibility`, `Development`, `Education`,
`Games`, `Graphics & Pictures`, `Internet`, `Music & Video`, `Office`,
`Security`, `Utilities`.

## What gets generated

```
NamePortable\
├── NamePortable.exe                 PortableApps.com Launcher stub
├── App\
│   ├── AppInfo\
│   │   ├── appinfo.ini              the menu card
│   │   ├── appicon.ico              + appicon_16/32/75/128/256.png
│   │   └── Launcher\
│   │       └── NamePortable.ini     what to run and how
│   ├── Name\                        the program itself
│   └── DefaultData\                 seed settings, copied into Data\ on first run
├── Data\                            user settings, travel with the drive
└── Other\Source\
```

The menu scans `PortableApps\` one level deep and lists every folder that
contains `App\AppInfo\appinfo.ini`. No registration, no database: drop the
folder in and it appears; delete it and it is gone.

## How the launcher works

`NamePortable.exe` is the stock PortableApps.com Launcher (PAL). **It is not
compiled per application** — verified by cloning `WinDjViewPortable` under a
different name: the stub derives the app id from its own file name and reads
`App\AppInfo\Launcher\<own-exe-name>.ini`, then writes
`Data\settings\<own-exe-name>Settings.ini`.

That is why a launcher can simply be copied. With no generator installed, the
script looks through your apps for a "clean" stub — one whose
`App\AppInfo\Launcher\` folder holds nothing but its own `.ini` (no
`Custom.nsh`, which would carry application-specific compiled code) — prefers the
newest PAL version, and caches it in `Template\PortableAppsLauncher.exe`.

A cloned stub has one cosmetic flaw: **in Explorer it wears the donor's icon**,
which lives in its PE resources. The menu is unaffected, it reads
`App\AppInfo\appicon*`. And that icon cannot be swapped out, because official
launcher builds are Authenticode-signed:

```
Status            : Valid
SignerCertificate : CN="RARE IDEAS, LLC", O="RARE IDEAS, LLC", L=New York
```

Any modification invalidates the signature and the stub stops working. Measured
on one test bed — a cloned app package where only the launcher exe is swapped:

| Edit | Result |
|---|---|
| `UpdateResource` (the documented Windows API) | 19 KB smaller, NSIS overlay gone, program never starts |
| same, with the overlay appended back | launcher runs and exits, program never starts |
| one byte flipped inside the icon pixel data, file layout untouched | program never starts |
| control: the same stub, unmodified | works |

**So for a correct icon, install the official
[PortableApps.com Launcher](https://portableapps.com/apps/development/portableapps.com_launcher).**
It is an ordinary portable app and is only needed while building a package. When
the script finds
`PortableApps\PortableApps.comLauncher\PortableApps.comLauncherGenerator.exe`,
it hands the finished package to it and gets back a launcher compiled around
`App\AppInfo\appicon.ico` — the icon the script has already extracted from the
program. Freshly built launchers are unsigned, so nothing is being tampered with.

`-Launcher` picks the strategy:

| Value | Behaviour |
|---|---|
| `Auto` | the generator if it is installed, otherwise a cloned stub (default) |
| `Generate` | require the generator, fail early if it is missing |
| `Clone` | always clone a stub, never call the generator |
| `None` | no launcher at all: `Start=` points at `App\Name\program.exe`. You lose PAL's settings redirection and path rewriting, but the folder is clean and nothing is borrowed |

## Encoding matters

The menu and the launcher read their `.ini` files through Win32
`GetPrivateProfileString`. Tested with non-ASCII values:

| File encoding | Result |
|---|---|
| ASCII / system ANSI | read correctly |
| UTF-16LE with BOM | read correctly |
| UTF-8 with BOM | section not found at all |
| UTF-8 without BOM | mojibake |

So the script writes ASCII when every value is ASCII, and UTF-16LE otherwise.
Force it with `-IniEncoding Ansi|Unicode`.

This is the trap that silently breaks hand-written `appinfo.ini` files with
non-English names — most editors default to UTF-8.

More notes on the format, including everything that was verified by experiment
rather than read in a spec: [`docs/paf-format.md`](docs/paf-format.md).

## Prior art

This is not the first tool in this space, but the others are GUI wizards built
around the official Launcher Generator, and all of them stopped moving around
2016:

| Tool | Notes |
|---|---|
| [PortableApps.com Launcher](https://portableapps.com/apps/development/portableapps.com_launcher) | official, actively maintained. Compiles a real launcher `.exe` from ini files **you** write. It does not build the package, gather metadata or extract icons. |
| [PortableApps App Creation Wizard](https://github.com/EmilyLove26/PortableApps-App-Creation-Wizard) | AutoIt GUI wizard, closest analogue. Last commit June 2016. Requires the Launcher Generator and manual file moving. |
| [PAF Assistant](https://sourceforge.net/projects/pafassistant/) | VB.NET GUI, generates structure + ini + icons. Last release July 2016. |
| [PAF Template Maker](https://portableapps.com/node/38626) | forum utility, drops an empty template on the desktop. |

What is different here: one script, no GUI, CLI plus drag-and-drop, and the
generator is optional rather than required — without it you still get a working
package. It also does the parts the others leave to you: picking the main
executable from PE headers, pairing 32/64-bit builds, extracting the icon
without external tools, writing the ini files in an encoding the menu can read,
and `-Scan` for what you have not added yet.

## Caveats

- `-NoLauncher` mode is verified structurally; the platform treats `Start=` as a
  path relative to the app folder (its own `[TimesRun]` counters are stored as
  `folder\file.exe`), but I have not clicked through every menu build with it.
  The default launcher path is the well-trodden one.
- The script copies the program by default. Large apps mean large copies — use
  `-Move` if you want the original gone.
- Repacked "portable" builds that are really installers in disguise will be
  detected as `*setup.exe` and skipped; point `-Exe` at the real binary.

## Authorship

The idea is Hinduc0der's, and so is everything around it: the requirements, the calls on
what the tool should and should not do, and the testing against a live
PortableApps.com installation.

The implementation is not. Every line of code here, the experiments the design
rests on — that the launcher stub is generic, that it is signed and therefore
cannot be re-iconed, which ini encodings the menu can actually read — and this
documentation were written by Claude (Claude Opus 5, Anthropic) working in
Claude Code. No human wrote code in this repository.

## License

MIT — see [LICENSE](LICENSE).

PortableApps.com, the PortableApps.com Launcher and the PortableApps.com Format
are the work of Rare Ideas, LLC and contributors. This project only generates
files for that format; the launcher itself is either built by their own
generator or copied from a stub already present on your machine. Nothing of
theirs is redistributed here. It is not affiliated with or endorsed by
PortableApps.com.
