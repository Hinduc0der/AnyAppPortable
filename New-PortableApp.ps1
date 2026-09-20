<#
.SYNOPSIS
    Turns any portable Windows program into a PortableApps.com menu entry.

.DESCRIPTION
    The PortableApps.com Platform scans its PortableApps\ folder one level deep
    and lists every subfolder that contains App\AppInfo\appinfo.ini. Name,
    category, icon and the executable to start all come from there.

    This script builds such a package out of an ordinary portable program —
    a folder or a single .exe.

.EXAMPLE
    .\New-PortableApp.ps1 "D:\Papps\Victoria537"

.EXAMPLE
    .\New-PortableApp.ps1 "D:\Papps\keyviz-v1.0.6-portable.exe" -Name "Keyviz"

.EXAMPLE
    .\New-PortableApp.ps1 -Scan

.LINK
    https://portableapps.com/development/portableapps.com_format

.NOTES
    Idea and direction: Hinduc0der.
    Code and documentation: written by Claude (Claude Opus 5, Anthropic)
    in Claude Code. See LICENSE for authorship and terms.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Source,

    [string]$Name,
    [string]$AppId,
    [string]$Category = 'Utilities',
    [string]$Description,
    [string]$Publisher,
    [string]$Version,

    # Main executable inside Source, when auto-detection gets it wrong
    [string]$Exe,
    # 64-bit build, if there is a separate one
    [string]$Exe64,
    # Command line arguments for the program
    [string]$Arguments,
    # Where to take the icon from: .ico / .png / .exe. Default: the main exe
    [string]$Icon,

    [string]$Destination,

    # Move a registry branch into Data\, e.g. 'HKCU\Software\Vendor\App'
    [string[]]$RegistryKey,
    # Move a settings folder into Data\, e.g. '%APPDATA%\Vendor\App'
    [string[]]$AppDataDir,

    # How to get the launcher exe:
    #   Auto     - the official generator if it is installed, otherwise a cloned stub
    #   Generate - require the official PortableApps.com Launcher Generator
    #   Clone    - copy a stock launcher stub from an installed app
    #   None     - no launcher at all, Start= points straight at the program
    [ValidateSet('Auto', 'Generate', 'Clone', 'None')]
    [string]$Launcher = 'Auto',

    # Explicit path to PortableApps.comLauncherGenerator.exe
    [string]$Generator,

    [switch]$Move,
    [switch]$RunAsAdmin,
    [switch]$NoLauncher,
    [switch]$Force,
    [switch]$Scan,

    [ValidateSet('Auto', 'Ansi', 'Unicode')]
    [string]$IniEncoding = 'Auto',

    # Interface language. Auto follows the Windows UI culture.
    [ValidateSet('Auto', 'en', 'ru')]
    [string]$Language = 'Auto'
)

$ErrorActionPreference = 'Stop'
try { [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance) } catch { }

# --- Interface strings ------------------------------------------------------

$Lang = if ($Language -ne 'Auto') {
    $Language
}
else {
    $culture = try { (Get-UICulture).TwoLetterISOLanguageName } catch { 'en' }
    if ($culture -eq 'ru') { 'ru' } else { 'en' }
}

$Strings = @{
    en = @{
        title         = 'PortableApps: app package generator'
        mainExe       = 'main executable: {0}'
        foundPair     = '32/64-bit pair found: {0} + {1}'
        copying       = 'copying the program -> App\{0}'
        makingIcons   = 'building icons'
        launcher      = 'launcher: {0} (cloned stub)'
        noLauncher    = 'no launcher needed: Start points straight at the exe'
        genRunning    = 'building the launcher with the PortableApps.com Launcher Generator...'
        genOk         = 'launcher: {0} (built by the official generator, with the app icon)'
        genFail       = 'the generator produced no {0} - falling back to a cloned stub'
        genTimeout    = 'the generator did not finish in {0} s - falling back to a cloned stub'
        templateFrom  = 'launcher template taken from {0} (PAL {1})'
        done          = 'Done: {0}'
        treeLauncher  = 'PortableApps.com launcher'
        treeAppInfo   = 'the menu card (name, category, Start)'
        treeIcons     = '+ appicon_16/32/75/128/256.png'
        treeLaunchIni = 'launch settings'
        treeProgram   = 'the program itself'
        treeDefault   = 'seed settings (copied into Data on first run)'
        treeData      = 'user settings'
        refresh1      = 'In the menu: right-click the platform icon -> refresh the app list,'
        refresh2      = 'or restart PortableAppsPlatform.exe.'

        scanTitle     = 'Sitting in {0} and not in the menu yet:'
        scanColType   = 'type'
        scanColWhat   = 'what'
        scanColExe    = 'main exe'
        scanFolder    = 'folder'
        scanExe       = 'exe'
        scanNotFound  = '- none found -'
        scanHint      = 'Add with:  .\New-PortableApp.ps1 "<path>"'

        askName       = '  Name in the menu [{0}]'
        askPath       = '  Path to the program (folder or .exe)'
        askNumber     = '  Number (Enter = 1)'
        ambiguous     = "Can't tell which exe is the main one. Candidates:"
        kindGui       = 'GUI'
        kindConsole   = 'console'

        warnCategory  = "Category '{0}' is not standard. Valid ones: {1}"
        warnNoDrawing = 'System.Drawing is unavailable - no icons were created'
        warnIconFail  = 'Could not take the icon from the file - drew a letter placeholder'
        warnIcon      = 'icon: {0}'

        errNotFound   = 'Not found: {0}'
        errSourceType = 'The source must be an .exe or a folder'
        errNoExe      = 'No .exe found in the folder'
        errNoSuchExe  = 'There is no {0} in {1}'
        errExists     = '{0} already exists. Delete it or run with -Force'
        errNoGenerator = @'
PortableApps.com Launcher Generator not found.
Install "PortableApps.com Launcher" from portableapps.com into
  {0}
(it lands in PortableApps.comLauncher\), point at it with -Generator <path>,
or use -Launcher Clone.
'@
        errNoTemplate = @'
No launcher template found.
Put any <Name>Portable.exe from a PortableApps.com application into
  {0}
or install at least one app from portableapps.com into
  {1}
(any app whose App\AppInfo\Launcher folder has no Custom.nsh will do),
or run with -NoLauncher.
'@
    }

    ru = @{
        title         = 'PortableApps: генератор структуры приложения'
        mainExe       = 'главный exe: {0}'
        foundPair     = 'нашлась пара 32/64: {0} + {1}'
        copying       = 'копирую программу -> App\{0}'
        makingIcons   = 'делаю иконки'
        launcher      = 'лаунчер: {0} (клон стаба)'
        noLauncher    = 'лаунчер не нужен: Start указывает прямо на exe'
        genRunning    = 'собираю лаунчер генератором PortableApps.com Launcher...'
        genOk         = 'лаунчер: {0} (собран официальным генератором, с иконкой программы)'
        genFail       = 'генератор не создал {0} - беру клон стаба'
        genTimeout    = 'генератор не уложился в {0} с - беру клон стаба'
        templateFrom  = 'шаблон лаунчера взят из {0} (PAL {1})'
        done          = 'Готово: {0}'
        treeLauncher  = 'лаунчер PortableApps.com'
        treeAppInfo   = 'карточка для меню (имя, категория, Start)'
        treeIcons     = '+ appicon_16/32/75/128/256.png'
        treeLaunchIni = 'настройки запуска'
        treeProgram   = 'сама программа'
        treeDefault   = 'эталон настроек (копируется в Data при первом старте)'
        treeData      = 'настройки пользователя'
        refresh1      = 'В меню: правый клик по значку платформы -> обновить список,'
        refresh2      = 'либо перезапустить PortableAppsPlatform.exe.'

        scanTitle     = 'Что лежит в {0} и ещё не в меню:'
        scanColType   = 'тип'
        scanColWhat   = 'что'
        scanColExe    = 'главный exe'
        scanFolder    = 'папка'
        scanExe       = 'exe'
        scanNotFound  = '- не найден -'
        scanHint      = 'Добавить:  .\New-PortableApp.ps1 "<путь>"'

        askName       = '  Название в меню [{0}]'
        askPath       = '  Путь к программе (папка или .exe)'
        askNumber     = '  Номер (Enter = 1)'
        ambiguous     = 'Не могу однозначно выбрать главный exe. Варианты:'
        kindGui       = 'GUI'
        kindConsole   = 'консоль'

        warnCategory  = "Категория '{0}' нестандартная. Допустимые: {1}"
        warnNoDrawing = 'System.Drawing недоступен - иконки не созданы'
        warnIconFail  = 'Иконку из файла взять не удалось - нарисована заглушка с буквой'
        warnIcon      = 'иконка: {0}'

        errNotFound   = 'Не найдено: {0}'
        errSourceType = 'Источник должен быть .exe или папкой'
        errNoExe      = 'В папке не найдено ни одного .exe'
        errNoSuchExe  = 'В {1} нет {0}'
        errExists     = '{0} уже существует. Удалите её или запустите с -Force'
        errNoGenerator = @'
Не найден PortableApps.com Launcher Generator.
Поставьте "PortableApps.com Launcher" с portableapps.com в
  {0}
(он встанет папкой PortableApps.comLauncher\), либо укажите путь ключом
-Generator <путь>, либо запускайте с -Launcher Clone.
'@
        errNoTemplate = @'
Не найден шаблон лаунчера.
Положите любой <Имя>Portable.exe от приложения PortableApps.com в
  {0}
или установите хотя бы одно приложение с portableapps.com в
  {1}
(годится любое, у которого в App\AppInfo\Launcher нет Custom.nsh),
либо запускайте с ключом -NoLauncher.
'@
    }
}

# T 'key' arg1 arg2 ... — looks the string up and applies -f formatting
function T {
    param([string]$Key)
    $text = $Strings[$Lang][$Key]
    if ($null -eq $text) { $text = $Strings['en'][$Key] }
    if ($null -eq $text) { return $Key }
    if ($args.Count -gt 0) { return ($text -f $args) }
    return $text
}

# --- Paths ------------------------------------------------------------------

$ToolRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$PappsRoot = Split-Path -Parent $ToolRoot
if (-not $Destination) { $Destination = Join-Path $PappsRoot 'PortableApps' }
$LauncherTemplate = Join-Path $ToolRoot 'Template\PortableAppsLauncher.exe'

$ValidCategories = @(
    'Accessibility', 'Development', 'Education', 'Games', 'Graphics & Pictures',
    'Internet', 'Music & Video', 'Office', 'Operating Systems', 'Security',
    'Utilities'
)

# Names that are almost never the main executable
$JunkAnywhere = '(unins|setup|install|update|upgrade|crash|report|vcredist|redist|dxweb|dotnet|repair|patch|activat|keygen)'
$JunkPrefix   = '^(helper|service|daemon|elevate|register|licen|7z|launcher|config|readme)'

# --- Helpers ----------------------------------------------------------------

function Write-Step { param([string]$Text) Write-Host "  $Text" -ForegroundColor DarkGray }
function Write-Ok   { param([string]$Text) Write-Host "  $Text" -ForegroundColor Green }
function Write-Note { param([string]$Text) Write-Host "  ! $Text" -ForegroundColor Yellow }

function Read-WithDefault {
    # Non-interactive host (called from another script): just take the default
    param([string]$Prompt, [string]$Default)
    try { $a = Read-Host $Prompt } catch { return $Default }
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return $a.Trim()
}

function Write-IniFile {
    # The menu and the launcher read ini files through GetPrivateProfileString,
    # which understands ASCII/ANSI and UTF-16LE with BOM, but not UTF-8.
    param([string]$Path, [string[]]$Lines)
    $text = ($Lines -join "`r`n") + "`r`n"
    $enc = switch ($IniEncoding) {
        'Ansi'    { [Text.Encoding]::GetEncoding(1251) }
        'Unicode' { [Text.Encoding]::Unicode }
        default {
            if ($text -match '[^\x00-\x7F]') { [Text.Encoding]::Unicode } else { [Text.Encoding]::ASCII }
        }
    }
    [IO.File]::WriteAllText($Path, $text, $enc)
}

# Bitness and subsystem (GUI/console) straight from the PE header
function Get-PeInfo {
    param([string]$Path)
    $res = [pscustomobject]@{ Bits = 0; Gui = $false; Arm = $false }
    try {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $br = New-Object IO.BinaryReader($fs)
            if ($br.ReadUInt16() -ne 0x5A4D) { return $res }
            $fs.Position = 0x3C
            $peOff = $br.ReadUInt32()
            $fs.Position = $peOff
            if ($br.ReadUInt32() -ne 0x00004550) { return $res }
            $machine = $br.ReadUInt16()
            $res.Bits = switch ($machine) { 0x8664 { 64 } 0xAA64 { 64 } 0x014C { 32 } default { 0 } }
            $res.Arm = ($machine -eq 0xAA64)
            $fs.Position = $peOff + 24 + 68      # Optional Header + Subsystem
            $res.Gui = ($br.ReadUInt16() -eq 2)  # 2 = Windows GUI
        } finally { $fs.Dispose() }
    } catch { }
    return $res
}

# --- Icon extraction --------------------------------------------------------

if (-not ('PappsIcoExtract' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

public static class PappsIcoExtract
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryExW(string file, IntPtr h, uint flags);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr FindResourceW(IntPtr h, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr h, IntPtr res);
    [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr data);
    [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr h, IntPtr res);
    delegate bool EnumResNameProc(IntPtr h, IntPtr type, IntPtr name, IntPtr lp);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool EnumResourceNamesW(IntPtr h, IntPtr type, EnumResNameProc cb, IntPtr lp);

    const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
    static readonly IntPtr RT_ICON = (IntPtr)3;
    static readonly IntPtr RT_GROUP_ICON = (IntPtr)14;

    static byte[] Res(IntPtr h, IntPtr type, IntPtr name)
    {
        IntPtr r = FindResourceW(h, name, type);
        if (r == IntPtr.Zero) return null;
        uint size = SizeofResource(h, r);
        IntPtr d = LoadResource(h, r);
        if (d == IntPtr.Zero) return null;
        IntPtr p = LockResource(d);
        if (p == IntPtr.Zero || size == 0) return null;
        byte[] buf = new byte[size];
        Marshal.Copy(p, buf, 0, (int)size);
        return buf;
    }

    public static bool Extract(string exePath, string icoPath)
    {
        IntPtr h = LoadLibraryExW(exePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (h == IntPtr.Zero) return false;
        try
        {
            IntPtr group = IntPtr.Zero;
            EnumResourceNamesW(h, RT_GROUP_ICON, delegate(IntPtr hm, IntPtr t, IntPtr n, IntPtr lp)
            {
                group = n; return false;   // the first icon group is the application icon
            }, IntPtr.Zero);
            if (group == IntPtr.Zero) return false;

            byte[] grp = Res(h, RT_GROUP_ICON, group);
            if (grp == null || grp.Length < 6) return false;
            int count = BitConverter.ToUInt16(grp, 4);
            if (count <= 0) return false;

            var images = new List<byte[]>();
            using (var ms = new MemoryStream())
            using (var bw = new BinaryWriter(ms))
            {
                bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)count);
                int offset = 6 + 16 * count;
                for (int i = 0; i < count; i++)
                {
                    int p = 6 + 14 * i;
                    byte w = grp[p], hh = grp[p + 1], cc = grp[p + 2], rr = grp[p + 3];
                    ushort planes = BitConverter.ToUInt16(grp, p + 4);
                    ushort bits = BitConverter.ToUInt16(grp, p + 6);
                    ushort id = BitConverter.ToUInt16(grp, p + 12);
                    byte[] img = Res(h, RT_ICON, (IntPtr)id);
                    if (img == null) img = new byte[0];
                    images.Add(img);
                    bw.Write(w); bw.Write(hh); bw.Write(cc); bw.Write(rr);
                    bw.Write(planes); bw.Write(bits);
                    bw.Write((uint)img.Length); bw.Write((uint)offset);
                    offset += img.Length;
                }
                foreach (var img in images) bw.Write(img);
                bw.Flush();
                File.WriteAllBytes(icoPath, ms.ToArray());
            }
            return true;
        }
        finally { FreeLibrary(h); }
    }
}
'@
}

function Get-MasterBitmap {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -in '.png', '.bmp', '.jpg', '.jpeg', '.gif') {
        return [Drawing.Bitmap]::FromFile($Path)
    }
    if ($ext -eq '.ico') {
        $ico = New-Object Drawing.Icon($Path, 256, 256)
        try { return $ico.ToBitmap() } finally { $ico.Dispose() }
    }
    return $null
}

function New-LetterIcon {
    param([string]$Letter, [int]$Size)
    $bmp = New-Object Drawing.Bitmap($Size, $Size)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $g.FillRectangle((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 60, 90, 140))), 0, 0, $Size, $Size)
        $font = New-Object Drawing.Font('Segoe UI', ($Size * 0.55), [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $g.DrawString($Letter.ToUpper(), $font, [Drawing.Brushes]::White,
            (New-Object Drawing.RectangleF(0, 0, $Size, $Size)), $fmt)
        $font.Dispose(); $fmt.Dispose()
    } finally { $g.Dispose() }
    return $bmp
}

function Save-BitmapAsIco {
    # An .ico holding a single PNG-compressed frame (Windows Vista and later)
    param([Drawing.Bitmap]$Bitmap, [string]$Path)
    $ms = New-Object IO.MemoryStream
    $Bitmap.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $png = $ms.ToArray(); $ms.Dispose()
    $out = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($out)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
    $dim = if ($Bitmap.Width -ge 256) { 0 } else { $Bitmap.Width }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
    $bw.Write($png); $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
    $bw.Dispose(); $out.Dispose()
}

function New-AppIcons {
    param([string]$IconSource, [string]$AppInfoDir, [string]$FallbackLetter)

    try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
    catch { Write-Note (T 'warnNoDrawing'); return }

    $icoPath = Join-Path $AppInfoDir 'appicon.ico'
    $master = $null
    $ext = [IO.Path]::GetExtension($IconSource).ToLowerInvariant()

    if ($ext -in '.exe', '.dll') {
        # rare case: right after copying, the file is still held by an antivirus
        $done = $false
        foreach ($try in 1..3) {
            if ([PappsIcoExtract]::Extract($IconSource, $icoPath)) { $done = $true; break }
            Start-Sleep -Milliseconds 250
        }
        if ($done) {
            try { $master = Get-MasterBitmap $icoPath } catch { Write-Note (T 'warnIcon' $_.Exception.Message); $master = $null }
        }
    }
    elseif ($ext -eq '.ico') {
        Copy-Item -LiteralPath $IconSource -Destination $icoPath -Force
        try { $master = Get-MasterBitmap $icoPath } catch { Write-Note (T 'warnIcon' $_.Exception.Message); $master = $null }
    }
    else {
        try {
            $master = Get-MasterBitmap $IconSource
            Save-BitmapAsIco -Bitmap $master -Path $icoPath
        } catch { Write-Note (T 'warnIcon' $_.Exception.Message); $master = $null }
    }

    if (-not $master) {
        Write-Note (T 'warnIconFail')
        $master = New-LetterIcon -Letter $FallbackLetter -Size 256
        Save-BitmapAsIco -Bitmap $master -Path $icoPath
    }

    foreach ($size in 16, 32, 75, 128, 256) {
        $bmp = New-Object Drawing.Bitmap($size, $size)
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.PixelOffsetMode = 'HighQuality'
            $g.SmoothingMode = 'HighQuality'
            $g.Clear([Drawing.Color]::Transparent)
            $g.DrawImage($master, 0, 0, $size, $size)
        } finally { $g.Dispose() }
        $bmp.Save((Join-Path $AppInfoDir "appicon_$size.png"), [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    $master.Dispose()
}

# The official PortableApps.com Launcher Generator, if it is installed. It
# compiles a real launcher from App\AppInfo\Launcher\<AppID>.ini and embeds
# App\AppInfoppicon.ico, so the exe carries the program's own icon.
function Resolve-LauncherGenerator {
    $exe = 'PortableApps.comLauncher\PortableApps.comLauncherGenerator.exe'
    if ($Generator) {
        if (Test-Path -LiteralPath $Generator -PathType Leaf) { return (Resolve-Path -LiteralPath $Generator).Path }
        $nested = Join-Path $Generator 'PortableApps.comLauncherGenerator.exe'
        if (Test-Path -LiteralPath $nested) { return $nested }
        throw (T 'errNotFound' $Generator)
    }
    foreach ($root in @($Destination, $PappsRoot, $ToolRoot)) {
        $c = Join-Path $root $exe
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Invoke-LauncherGenerator {
    param([string]$GeneratorPath, [string]$AppRoot, [string]$ExeName, [int]$TimeoutSec = 180)
    $target = Join-Path $AppRoot $ExeName
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    Write-Step (T 'genRunning')
    $proc = Start-Process -FilePath $GeneratorPath -ArgumentList "`"$AppRoot`"" -PassThru
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        Write-Note (T 'genTimeout' $TimeoutSec)
        return $false
    }
    if (Test-Path -LiteralPath $target) {
        Write-Step (T 'genOk' $ExeName)
        return $true
    }
    Write-Note (T 'genFail' $ExeName)
    return $false
}

# The PortableApps.com Launcher (PAL) is not tied to the app it ships with: the
# stub takes the app id from its own file name and reads
# App\AppInfo\Launcher\<own name>.ini. So any "clean" stub from an installed app
# will do — one whose Launcher folder has no Custom.nsh, since that would carry
# compiled code specific to the donor application.
function Resolve-LauncherTemplate {
    if (Test-Path -LiteralPath $LauncherTemplate) { return $LauncherTemplate }

    $donors = @()
    foreach ($dir in (Get-ChildItem -LiteralPath $Destination -Directory -ErrorAction SilentlyContinue)) {
        $exe = Join-Path $dir.FullName "$($dir.Name).exe"
        $lDir = Join-Path $dir.FullName 'App\AppInfo\Launcher'
        if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $lDir)) { continue }
        $extra = @(Get-ChildItem -LiteralPath $lDir -File | Where-Object { $_.Name -ine "$($dir.Name).ini" })
        if ($extra.Count -gt 0) { continue }
        $item = Get-Item -LiteralPath $exe
        if ($item.VersionInfo.InternalName -ne 'PortableApps.com Launcher') { continue }
        $donors += [pscustomobject]@{
            Path = $exe
            Ver  = [version]($item.VersionInfo.FileVersion -replace '[^0-9.]', '')
            Size = $item.Length
        }
    }

    # newest PAL, and among those the most compact stub
    $best = $donors |
        Sort-Object @{ Expression = 'Ver'; Descending = $true }, @{ Expression = 'Size'; Descending = $false } |
        Select-Object -First 1

    if (-not $best) { throw (T 'errNoTemplate' $LauncherTemplate $Destination) }

    New-Item -ItemType Directory -Path (Split-Path -Parent $LauncherTemplate) -Force | Out-Null
    Copy-Item -LiteralPath $best.Path -Destination $LauncherTemplate -Force
    Write-Step (T 'templateFrom' (Split-Path -Leaf (Split-Path -Parent $best.Path)) $best.Ver)
    return $LauncherTemplate
}

# --- Finding the main executable --------------------------------------------

function Get-ExeCandidates {
    param([string]$Folder)
    $folderKey = ([IO.Path]::GetFileName($Folder) -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    $list = @()
    Get-ChildItem -LiteralPath $Folder -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Substring($Folder.Length).TrimStart('\')
            ($rel.Split('\').Count -le 3)
        } |
        ForEach-Object {
            $base = ($_.BaseName -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            $pe = Get-PeInfo $_.FullName
            $score = 0
            if ($base -eq $folderKey) { $score += 60 }
            elseif ($folderKey -and ($folderKey.StartsWith($base) -or $base.StartsWith($folderKey))) { $score += 40 }
            $depth = ($_.FullName.Substring($Folder.Length).TrimStart('\').Split('\').Count)
            $score += (4 - $depth) * 8
            if ($pe.Gui) { $score += 25 }
            if ($pe.Bits -eq 64) { $score += 6 }
            if ($_.VersionInfo.FileDescription) { $score += 10 }
            $score += [Math]::Min(12, [int]($_.Length / 1MB))
            if ($_.BaseName -match $JunkAnywhere) { $score -= 120 }
            if ($_.BaseName -match $JunkPrefix) { $score -= 60 }
            if ($pe.Arm -or $_.BaseName -match 'arm') { $score -= 80 }
            $list += [pscustomobject]@{
                File  = $_
                Rel   = $_.FullName.Substring($Folder.Length).TrimStart('\')
                Bits  = $pe.Bits
                Gui   = $pe.Gui
                Arm   = $pe.Arm
                Desc  = $_.VersionInfo.FileDescription
                Score = $score
            }
        }
    return $list | Sort-Object Score -Descending
}

function Select-MainExe {
    param([object[]]$Candidates)
    if (-not $Candidates) { throw (T 'errNoExe') }
    if ($Candidates.Count -eq 1) { return $Candidates[0] }
    $top = $Candidates[0]
    $second = $Candidates[1]
    if ($top.Score - $second.Score -ge 25) { return $top }

    Write-Host ''
    Write-Host ('  ' + (T 'ambiguous')) -ForegroundColor Yellow
    $i = 1
    $show = $Candidates | Select-Object -First 12
    foreach ($c in $show) {
        $bits = if ($c.Bits) { "$($c.Bits)-bit" } else { '?' }
        $kind = if ($c.Gui) { T 'kindGui' } else { T 'kindConsole' }
        Write-Host ("   {0,2}. {1,-45} {2,-8} {3,-8} {4}" -f $i, $c.Rel, $bits, $kind, $c.Desc)
        $i++
    }
    $ans = Read-WithDefault (T 'askNumber') '1'
    $n = 0
    if (-not [int]::TryParse($ans, [ref]$n) -or $n -lt 1 -or $n -gt $show.Count) { $n = 1 }
    return $show[$n - 1]
}

# Looks for a 32-bit / 64-bit pair of the same program (Foo.exe / Foo64.exe)
function Find-BitnessPair {
    param([object]$Pick, [object[]]$Candidates)
    $norm = { param($t) ($t -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() }
    $base = & $norm $Pick.File.BaseName
    $wanted = if ($Pick.Bits -eq 64) {
        @(($base -replace '64$', ''), ($base -replace '64$', '32'))
    } else {
        @("${base}64", ($base -replace '32$', '64'))
    }
    $wanted = $wanted | Where-Object { $_ -and $_ -ne $base } | Select-Object -Unique
    $other = $Candidates | Where-Object {
        $_.Rel -ne $Pick.Rel -and -not $_.Arm -and ($wanted -contains (& $norm $_.File.BaseName))
    } | Select-Object -First 1
    if (-not $other) { return $null }
    if ($Pick.Bits -eq 64) { return [pscustomobject]@{ X86 = $other.Rel; X64 = $Pick.Rel } }
    if ($other.Bits -eq 64) { return [pscustomobject]@{ X86 = $Pick.Rel; X64 = $other.Rel } }
    return $null
}

# --- -Scan mode -------------------------------------------------------------

function Invoke-Scan {
    Write-Host ''
    Write-Host (T 'scanTitle' $PappsRoot) -ForegroundColor Cyan
    Write-Host ''
    $skip = @('PortableApps', 'Tools', 'Documents', 'Backup', 'drv')
    $rows = @()

    Get-ChildItem -LiteralPath $PappsRoot -Directory | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
        $cands = Get-ExeCandidates $_.FullName
        $main = if ($cands) { $cands[0] } else { $null }
        $rows += [pscustomobject]@{
            Kind = T 'scanFolder'
            What = $_.Name
            Exe  = if ($main) { $main.Rel } else { T 'scanNotFound' }
        }
    }
    $skipFiles = @('Start.exe', 'StartPortableApps.exe', 'autorun.exe')
    Get-ChildItem -LiteralPath $PappsRoot -File -Filter *.exe |
        Where-Object { $skipFiles -notcontains $_.Name -and $_.Name -notlike '*.paf.exe' } | ForEach-Object {
        $rows += [pscustomobject]@{ Kind = T 'scanExe'; What = $_.Name; Exe = $_.Name }
    }

    $w = 60
    $kw = [Math]::Max((T 'scanFolder').Length, (T 'scanExe').Length) + 1
    Write-Host ("  {0,-$kw} {1,-$w} {2}" -f (T 'scanColType'), (T 'scanColWhat'), (T 'scanColExe')) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        $what = $r.What
        if ($what.Length -gt $w) { $what = $what.Substring(0, $w - 3) + '...' }
        Write-Host ("  {0,-$kw} {1,-$w} {2}" -f $r.Kind, $what, $r.Exe)
    }
    Write-Host ''
    Write-Host ('  ' + (T 'scanHint')) -ForegroundColor DarkGray
    Write-Host ''
}

# --- Main work --------------------------------------------------------------

function Invoke-Create {
    if (-not (Test-Path -LiteralPath $Source)) { throw (T 'errNotFound' $Source) }

    # Decide how the launcher will be produced before creating anything,
    # so a missing generator fails before half a package is on disk.
    $mode = if ($NoLauncher) { 'None' } else { $Launcher }
    $genPath = $null
    if ($mode -in 'Auto', 'Generate') {
        $genPath = Resolve-LauncherGenerator
        if (-not $genPath -and $mode -eq 'Generate') { throw (T 'errNoGenerator' $Destination) }
    }

    $srcItem = Get-Item -LiteralPath $Source
    $isFile = -not $srcItem.PSIsContainer

    # 1. The main executable
    if ($isFile) {
        if ($srcItem.Extension -ne '.exe') { throw (T 'errSourceType') }
        $mainExeFull = $srcItem.FullName
        $mainRel = $srcItem.Name
        $srcFolder = $null
    }
    else {
        $srcFolder = $srcItem.FullName
        $cands = Get-ExeCandidates $srcFolder
        if ($Exe) {
            $pick = $cands | Where-Object { $_.Rel -ieq $Exe -or $_.File.Name -ieq $Exe } | Select-Object -First 1
            if (-not $pick) { throw (T 'errNoSuchExe' $Exe $srcFolder) }
        }
        else { $pick = Select-MainExe $cands }
        $mainExeFull = $pick.File.FullName
        $mainRel = $pick.Rel
        if (-not $Exe64) {
            $pair = Find-BitnessPair -Pick $pick -Candidates $cands
            if ($pair) {
                $mainRel = $pair.X86
                $exe64Rel = $pair.X64
                $mainExeFull = Join-Path $srcFolder $pair.X64   # take the icon from the 64-bit build
                Write-Step (T 'foundPair' $pair.X86 $pair.X64)
            }
        }
    }
    Write-Step (T 'mainExe' $mainRel)

    # 2. Names and metadata
    $vi = (Get-Item -LiteralPath $mainExeFull).VersionInfo
    if (-not $Name) {
        $guess = if ($isFile) { $srcItem.BaseName } else { $srcItem.Name }
        if ($vi.ProductName -and $vi.ProductName.Trim()) { $guess = $vi.ProductName.Trim() }
        $guess = ($guess -replace '[-_.]+', ' ').Trim()
        $Name = Read-WithDefault (T 'askName' $guess) $guess
    }
    if (-not $AppId) {
        $idBase = ($Name -replace '[^a-zA-Z0-9\-]', '')
        if (-not $idBase) { $idBase = 'App' }
        $AppId = if ($idBase -match 'Portable$') { $idBase } else { "${idBase}Portable" }
    }
    if (-not $Version) {
        $Version = if ($vi.ProductVersion) { $vi.ProductVersion.Trim() } else { '1.0' }
        $Version = ($Version -split '\s')[0]
    }
    if (-not $Publisher) {
        $Publisher = if ($vi.CompanyName) { $vi.CompanyName.Trim() } else { 'Unknown' }
    }
    if (-not $Description) {
        $Description = if ($vi.FileDescription) { $vi.FileDescription.Trim() } else { $Name }
    }
    if ($ValidCategories -notcontains $Category) {
        Write-Note (T 'warnCategory' $Category ($ValidCategories -join ', '))
    }

    # PackageVersion must be exactly four dot-separated numbers
    $pv = ($Version -replace '[^0-9]+', '.').Trim('.')
    $parts = @($pv -split '\.' | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 4) { $parts += '0' }
    $PackageVersion = ($parts[0..3] -join '.')

    # 3. Target folder
    $appRoot = Join-Path $Destination $AppId
    if (Test-Path -LiteralPath $appRoot) {
        if (-not $Force) { throw (T 'errExists' $appRoot) }
        Remove-Item -LiteralPath $appRoot -Recurse -Force
    }

    $innerName = ($AppId -replace 'Portable$', '')
    if (-not $innerName) { $innerName = 'App' }
    $appDir = Join-Path $appRoot 'App'
    $appInfoDir = Join-Path $appDir 'AppInfo'
    $launcherDir = Join-Path $appInfoDir 'Launcher'
    $payloadDir = Join-Path $appDir $innerName

    New-Item -ItemType Directory -Path $appInfoDir -Force | Out-Null
    if ($mode -ne 'None') { New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $appDir 'DefaultData') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $appRoot 'Data') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $appRoot 'Other\Source') -Force | Out-Null

    # 4. The program files
    Write-Step (T 'copying' $innerName)
    if ($isFile) {
        New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
        if ($Move) { Move-Item -LiteralPath $mainExeFull -Destination $payloadDir }
        else { Copy-Item -LiteralPath $mainExeFull -Destination $payloadDir }
        $progRel = Join-Path $innerName ([IO.Path]::GetFileName($mainExeFull))
        $iconSrc = Join-Path $payloadDir ([IO.Path]::GetFileName($mainExeFull))
    }
    else {
        if ($Move) { Move-Item -LiteralPath $srcFolder -Destination $payloadDir }
        else { Copy-Item -LiteralPath $srcFolder -Destination $payloadDir -Recurse }
        $progRel = Join-Path $innerName $mainRel
        $iconSrc = Join-Path $payloadDir $mainRel
    }

    # 5. Icons
    Write-Step (T 'makingIcons')
    $iconFrom = if ($Icon) { (Resolve-Path -LiteralPath $Icon).Path } else { $iconSrc }
    New-AppIcons -IconSource $iconFrom -AppInfoDir $appInfoDir -FallbackLetter $Name.Substring(0, 1)

    # 6. The menu card
    $startEntry = "$AppId.exe"
    if ($mode -eq 'None') {
        $startEntry = "App\$progRel"
        Write-Step (T 'noLauncher')
    }

    $appinfo = @(
        '[Format]',
        'Type=PortableApps.comFormat',
        'Version=3.9',
        '',
        '[Details]',
        "Name=$Name",
        "AppID=$AppId",
        "Publisher=$Publisher",
        "Category=$Category",
        "Description=$Description",
        'Language=Multilingual',
        '',
        '[License]',
        'Shareable=true',
        'OpenSource=false',
        'Freeware=true',
        'CommercialUse=false',
        '',
        '[Version]',
        "PackageVersion=$PackageVersion",
        "DisplayVersion=$Version",
        '',
        '[Control]',
        'Icons=1',
        "Start=$startEntry"
    )
    Write-IniFile -Path (Join-Path $appInfoDir 'appinfo.ini') -Lines $appinfo

    # 7. Launcher configuration, then the launcher itself
    if ($mode -ne 'None') {
        # PAL wants quotes around paths containing spaces
        $q = { param($p) if ($p -match '\s') { '"' + $p + '"' } else { $p } }
        $ini = @('[Launch]', "ProgramExecutable=$(& $q $progRel)")
        $exe64Final = if ($Exe64) { $Exe64 } elseif ($exe64Rel) { Join-Path $innerName $exe64Rel } else { $null }
        if ($exe64Final) { $ini += "ProgramExecutable64=$(& $q $exe64Final)" }
        if ($Arguments) { $ini += "CommandLineArguments=$Arguments" }
        $ini += @('DirectoryMoveOK=yes', 'SupportsUNC=yes', 'SingleAppInstance=true', 'WaitForProgram=true')
        if ($RunAsAdmin) { $ini += 'RunAsAdmin=force' }

        if ($RegistryKey) {
            $ini += @('', '[Activate]', 'Registry=true', '', '[RegistryKeys]')
            $n = 1
            foreach ($k in $RegistryKey) { $ini += "Key$n=$k"; $n++ }
            $ini += @('', '[RegistryCleanupIfEmpty]')
            $n = 1
            foreach ($k in $RegistryKey) { $ini += "$n=$k"; $n++ }
        }
        if ($AppDataDir) {
            $ini += @('', '[DirectoriesMove]')
            $n = 1
            foreach ($d in $AppDataDir) { $ini += "settings$n=$d"; $n++ }
        }
        if (-not $RegistryKey -and -not $AppDataDir) {
            $ini += @(
                '',
                '; If the app keeps settings outside its folder, uncomment what you need:',
                '; [Activate]',
                '; Registry=true',
                '; [RegistryKeys]',
                '; Key1=HKCU\Software\Vendor\App',
                '; [DirectoriesMove]',
                '; settings1=%APPDATA%\Vendor\App'
            )
        }
        Write-IniFile -Path (Join-Path $launcherDir "$AppId.ini") -Lines $ini

        # The official generator builds a launcher carrying the app's own icon.
        # Without it we clone a stock stub, which keeps the donor's icon in
        # Explorer (the menu icon comes from App\AppInfo\appicon* either way):
        # the stub is Authenticode-signed, so its icon cannot be rewritten.
        $built = $false
        if ($genPath) {
            $built = Invoke-LauncherGenerator -GeneratorPath $genPath -AppRoot $appRoot -ExeName "$AppId.exe"
        }
        if (-not $built) {
            $template = Resolve-LauncherTemplate
            Copy-Item -LiteralPath $template -Destination (Join-Path $appRoot "$AppId.exe")
            Write-Step (T 'launcher' "$AppId.exe")
        }
    }

    # 8. Summary
    Write-Host ''
    Write-Ok (T 'done' $appRoot)
    Write-Host ''
    Write-Host "  $AppId\" -ForegroundColor White
    if ($mode -ne 'None') { Write-Host ("  |- {0,-24} {1}" -f "$AppId.exe", (T 'treeLauncher')) }
    Write-Host '  |- App\'
    Write-Host '  |  |- AppInfo\'
    Write-Host ("  |  |  |- {0,-18} {1}" -f 'appinfo.ini', (T 'treeAppInfo'))
    Write-Host ("  |  |  |- {0,-18} {1}" -f 'appicon.ico', (T 'treeIcons'))
    if ($mode -ne 'None') { Write-Host ("  |  |  '- {0,-18} {1}" -f "Launcher\$AppId.ini", (T 'treeLaunchIni')) }
    Write-Host ("  |  |- {0,-21} {1}" -f "$innerName\", (T 'treeProgram'))
    Write-Host ("  |  '- {0,-21} {1}" -f 'DefaultData\', (T 'treeDefault'))
    Write-Host ("  |- {0,-24} {1}" -f 'Data\', (T 'treeData'))
    Write-Host "  '- Other\Source\"
    Write-Host ''
    Write-Host ('  ' + (T 'refresh1')) -ForegroundColor DarkGray
    Write-Host ('  ' + (T 'refresh2')) -ForegroundColor DarkGray
    Write-Host ''
}

# --- Entry point ------------------------------------------------------------

Write-Host ''
Write-Host (T 'title') -ForegroundColor Cyan

if ($Scan) { Invoke-Scan; return }

if (-not $Source) {
    $Source = (Read-WithDefault (T 'askPath') '').Trim('"').Trim()
    if (-not $Source) { Invoke-Scan; return }
}

Invoke-Create
