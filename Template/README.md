# Launcher template

`New-PortableApp.ps1` puts a copy of the stock PortableApps.com Launcher stub
here, as `PortableAppsLauncher.exe`, the first time it needs one.

It takes the stub from an application you already have installed under
`PortableApps\`, preferring the newest PAL version whose
`App\AppInfo\Launcher\` folder contains nothing but its own `.ini` (no
`Custom.nsh`, whose compiled code would be application-specific).

The binary is deliberately **not** committed to this repository: it is
PortableApps.com's build, not ours to redistribute. If you would rather supply
it yourself, drop any `<Name>Portable.exe` from a portableapps.com application
here under that name.
