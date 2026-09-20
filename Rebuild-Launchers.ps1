<#
.SYNOPSIS
    Rebuilds cloned launcher stubs with the official PortableApps.com Launcher
    Generator, so each launcher carries its own application's icon.

.DESCRIPTION
    New-PortableApp.ps1 falls back to cloning a launcher stub when the official
    generator is not installed. Such a stub works, but in Explorer it wears the
    icon of the application it was copied from.

    This script finds those packages - the ones whose launcher was built for a
    different application - and rebuilds them. Packages whose launcher already
    matches, including everything installed from portableapps.com, are left
    alone.

    It lists what it would do and changes nothing until you pass -Apply.

.EXAMPLE
    .\Rebuild-Launchers.ps1

.EXAMPLE
    .\Rebuild-Launchers.ps1 -Apply

.NOTES
    Idea and direction: Hinduc0der.
    Code and documentation: written by Claude (Claude Opus 5, Anthropic)
    in Claude Code. See LICENSE for authorship and terms.
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [string]$Generator,
    [switch]$Apply,

    [ValidateSet('Auto', 'en', 'ru')]
    [string]$Language = 'Auto'
)

$ErrorActionPreference = 'Stop'

$ToolRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$PappsRoot = Split-Path -Parent $ToolRoot
if (-not $Destination) { $Destination = Join-Path $PappsRoot 'PortableApps' }

$Lang = if ($Language -ne 'Auto') { $Language }
else {
    $c = try { (Get-UICulture).TwoLetterISOLanguageName } catch { 'en' }
    if ($c -eq 'ru') { 'ru' } else { 'en' }
}

$Strings = @{
    en = @{
        title    = 'PortableApps: rebuilding cloned launchers'
        noGen    = 'PortableApps.com Launcher Generator not found. Install "PortableApps.com Launcher" from portableapps.com into {0}, or pass -Generator <path>.'
        using    = 'generator: {0}'
        scanning = 'looking through {0}'
        none     = 'Nothing to rebuild - every launcher already matches its application.'
        found    = 'Launchers built for a different application ({0}):'
        col      = '{0,-34} {1}'
        colHead  = '{0,-34} {1}'
        appCol   = 'package'
        iconCol  = 'launcher was built for'
        dryRun   = 'This was a dry run. Add -Apply to rebuild them.'
        rebuild  = 'rebuilding {0} ...'
        okOne    = '  done'
        failOne  = '  the generator produced no exe - left as it was'
        summary  = 'Rebuilt: {0} of {1}. Refresh the app list in the menu to see the new icons.'
    }
    ru = @{
        title    = 'PortableApps: пересборка клонированных лаунчеров'
        noGen    = 'Не найден PortableApps.com Launcher Generator. Поставьте "PortableApps.com Launcher" с portableapps.com в {0} или укажите путь ключом -Generator <путь>.'
        using    = 'генератор: {0}'
        scanning = 'смотрю {0}'
        none     = 'Пересобирать нечего - у всех лаунчеров иконка своей программы.'
        found    = 'Лаунчеры, собранные для другой программы ({0}):'
        col      = '{0,-34} {1}'
        colHead  = '{0,-34} {1}'
        appCol   = 'пакет'
        iconCol  = 'лаунчер собран для'
        dryRun   = 'Это был холостой прогон. Добавьте -Apply, чтобы пересобрать.'
        rebuild  = 'пересобираю {0} ...'
        okOne    = '  готово'
        failOne  = '  генератор не создал exe - оставил как было'
        summary  = 'Пересобрано: {0} из {1}. Обновите список в меню, чтобы увидеть новые иконки.'
    }
}

function T {
    param([string]$Key)
    $t = $Strings[$Lang][$Key]
    if ($null -eq $t) { $t = $Strings['en'][$Key] }
    if ($args.Count -gt 0) { return ($t -f $args) }
    return $t
}

# appinfo.ini may be ASCII/ANSI or UTF-16LE, so read it the way the menu does
if (-not ('PappsIniRead' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PappsIniRead {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern uint GetPrivateProfileStringW(string section, string key, string def,
                                                StringBuilder ret, uint size, string file);
    public static string Get(string file, string section, string key) {
        var sb = new StringBuilder(1024);
        GetPrivateProfileStringW(section, key, "", sb, 1024, file);
        return sb.ToString();
    }
}
'@
}

function Resolve-LauncherGenerator {
    $rel = 'PortableApps.comLauncher\PortableApps.comLauncherGenerator.exe'
    if ($Generator) {
        if (Test-Path -LiteralPath $Generator -PathType Leaf) { return (Resolve-Path -LiteralPath $Generator).Path }
        $nested = Join-Path $Generator 'PortableApps.comLauncherGenerator.exe'
        if (Test-Path -LiteralPath $nested) { return $nested }
        return $null
    }
    foreach ($root in @($Destination, $PappsRoot, $ToolRoot)) {
        $c = Join-Path $root $rel
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

Write-Host ''
Write-Host (T 'title') -ForegroundColor Cyan

$gen = Resolve-LauncherGenerator
if (-not $gen) { throw (T 'noGen' $Destination) }
Write-Host ('  ' + (T 'using' $gen)) -ForegroundColor DarkGray
Write-Host ('  ' + (T 'scanning' $Destination)) -ForegroundColor DarkGray

$candidates = @()
foreach ($dir in (Get-ChildItem -LiteralPath $Destination -Directory)) {
    $exe = Join-Path $dir.FullName "$($dir.Name).exe"
    $ini = Join-Path $dir.FullName "App\AppInfo\Launcher\$($dir.Name).ini"
    $appinfo = Join-Path $dir.FullName 'App\AppInfo\appinfo.ini'
    if (-not (Test-Path -LiteralPath $exe)) { continue }
    if (-not (Test-Path -LiteralPath $ini)) { continue }      # nothing to rebuild from
    if (-not (Test-Path -LiteralPath $appinfo)) { continue }

    $vi = (Get-Item -LiteralPath $exe).VersionInfo
    if ($vi.InternalName -ne 'PortableApps.com Launcher') { continue }

    # "WizTree Portable (PortableApps.com Launcher)" -> "WizTree Portable"
    $builtFor = ($vi.FileDescription -replace '\s*\(PortableApps\.com Launcher\)\s*$', '').Trim()
    $appName = [PappsIniRead]::Get($appinfo, 'Details', 'Name').Trim()
    if (-not $appName) { continue }
    if ($builtFor -eq $appName) { continue }                  # already its own launcher

    $candidates += [pscustomobject]@{
        Path     = $dir.FullName
        App      = $appName
        BuiltFor = if ($builtFor) { $builtFor } else { '?' }
        Exe      = "$($dir.Name).exe"
    }
}

Write-Host ''
if (-not $candidates) {
    Write-Host ('  ' + (T 'none')) -ForegroundColor Green
    Write-Host ''
    return
}

Write-Host ('  ' + (T 'found' $candidates.Count)) -ForegroundColor Yellow
Write-Host ('  ' + (T 'colHead' (T 'appCol') (T 'iconCol'))) -ForegroundColor DarkGray
foreach ($c in $candidates) { Write-Host ('  ' + (T 'col' $c.App $c.BuiltFor)) }
Write-Host ''

if (-not $Apply) {
    Write-Host ('  ' + (T 'dryRun')) -ForegroundColor DarkGray
    Write-Host ''
    return
}

$done = 0
foreach ($c in $candidates) {
    Write-Host ('  ' + (T 'rebuild' $c.App)) -ForegroundColor DarkGray
    $target = Join-Path $c.Path $c.Exe
    $backup = "$target.bak"
    Move-Item -LiteralPath $target -Destination $backup -Force
    $proc = Start-Process -FilePath $gen -ArgumentList "`"$($c.Path)`"" -PassThru
    if (-not $proc.WaitForExit(180000)) { try { $proc.Kill() } catch { } }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $backup -Force
        Write-Host (T 'okOne') -ForegroundColor Green
        $done++
    }
    else {
        Move-Item -LiteralPath $backup -Destination $target -Force
        Write-Host (T 'failOne') -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ('  ' + (T 'summary' $done $candidates.Count)) -ForegroundColor Green
Write-Host ''
