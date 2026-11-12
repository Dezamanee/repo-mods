param([string]$GameDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Find-Game {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $steamKey = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if ($steamKey -and $steamKey.SteamPath) {
            $steamRoot = $steamKey.SteamPath -replace '/', '\'
            $candidates.Add((Join-Path $steamRoot 'steamapps\common\REPO'))

            $vdfPath = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdfPath) {
                foreach ($line in Get-Content -LiteralPath $vdfPath -ErrorAction SilentlyContinue) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $libPath = $matches[1] -replace '\\\\', '\' -replace '/', '\'
                        $candidates.Add((Join-Path $libPath 'steamapps\common\REPO'))
                    }
                }
            }
        }
    } catch {}

    $defaults = @(
        'C:\Program Files (x86)\Steam\steamapps\common\REPO',
        'C:\Program Files\Steam\steamapps\common\REPO',
        'C:\steam\steamapps\common\REPO',
        'D:\Steam\steamapps\common\REPO',
        'D:\SteamLibrary\steamapps\common\REPO',
        'D:\Games\SteamLibrary\steamapps\common\REPO',
        'E:\SteamLibrary\steamapps\common\REPO',
        'F:\SteamLibrary\steamapps\common\REPO'
    )
    foreach ($p in $defaults) { $candidates.Add($p) }

    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath (Join-Path $c 'REPO.exe'))) {
            return $c
        }
    }
    return $null
}

function Test-WriteAccess($dir) {
    try {
        $probe = Join-Path $dir ('.write_test_' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, 'test')
        [IO.File]::Delete($probe)
        return $true
    } catch { return $false }
}

function Expand-ArchiveFiltered {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestDir,
        [string]$StripPrefix = $null,
        [bool]$SkipDocs = $true
    )

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $z = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($e in $z.Entries) {
            $name = $e.FullName

            if ($SkipDocs -and $e.Name -match '^(README.*|CHANGELOG.*|LICENSE.*|icon\.png|manifest\.json)$') { continue }

            if ($StripPrefix -and $name.StartsWith($StripPrefix)) { $name = $name.Substring($StripPrefix.Length) }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $target = Join-Path $DestDir ($name -replace '/', '\')

            if ($e.Name -eq '') {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }

            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
        }
    } finally {
        $z.Dispose()
    }
}

Write-Host ''
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host '    R.E.P.O. ModPack Installer v1.2      ' -ForegroundColor Cyan
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host ''

if (-not $GameDir) { $GameDir = Find-Game }
if (-not $GameDir) {
    Write-Host 'Не удалось автоматически найти папку игры.' -ForegroundColor Yellow
    $GameDir = Read-Host 'Вставьте путь к папке с REPO.exe (например C:\Program Files (x86)\Steam\steamapps\common\REPO)'
}
$GameDir = $GameDir.Trim('"').TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'REPO.exe'))) {
    Write-Host "В папке '$GameDir' файл REPO.exe не найден. Установка отменена." -ForegroundColor Red
    exit 1
}

if (-not (Test-WriteAccess $GameDir)) {
    Write-Host "Нет прав на запись в '$GameDir'." -ForegroundColor Red
    Write-Host 'Запустите установщик от имени администратора (ПКМ -> Запуск от имени администратора).' -ForegroundColor Yellow
    exit 2
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mods = Join-Path $root 'Моды'
if (-not (Test-Path -LiteralPath $mods)) { $mods = Join-Path $root 'Mods' }
if (-not (Test-Path -LiteralPath $mods)) {
    Write-Host 'Папка с архивами модов (Моды или Mods) не найдена.' -ForegroundColor Red
    exit 3
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$backup = Join-Path $GameDir ('backups\before_modpack_' + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null

foreach ($f in 'winhttp.dll', 'doorstop_config.ini', '.doorstop_version') {
    $p = Join-Path $GameDir $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $backup -Force }
}
foreach ($dirName in 'plugins', 'config') {
    $src = Join-Path $GameDir ("BepInEx\" + $dirName)
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $backup ("BepInEx_" + $dirName)) -Recurse -Force
    }
}
Write-Host "Бэкап: $backup" -ForegroundColor DarkGray

Write-Host '[1/3] Установка BepInEx...' -ForegroundColor Green
$bepZip = Get-ChildItem -LiteralPath $mods -Filter 'BepInExPack*.zip' -File | Select-Object -First 1
if (-not $bepZip) {
    Write-Host 'ОШИБКА: BepInExPack.zip не найден в папке Моды.' -ForegroundColor Red
    exit 4
}
Expand-ArchiveFiltered -ZipPath $bepZip.FullName -DestDir $GameDir -StripPrefix 'BepInExPack/' -SkipDocs $true

Write-Host '[2/3] Установка модов...' -ForegroundColor Green
$plugins = Join-Path $GameDir 'BepInEx\plugins'
New-Item -ItemType Directory -Force -Path $plugins | Out-Null

$modMapping = [ordered]@{
    'REPOLib*.zip'                   = @{ Folder = 'REPOLib';                   Strip = 'plugins/' }
    'MenuLib*.zip'                   = @{ Folder = 'MenuLib';                   Strip = $null }
    'REPOConfig*.zip'                = @{ Folder = 'REPOConfig';                Strip = $null }
    'REPORoles_Classic*.zip'         = @{ Folder = 'REPORoles_Classic';         Strip = $null }
    'Shop_Items_Spawn_in_Level*.zip' = @{ Folder = 'Shop_Items_Spawn_in_Level'; Strip = $null }
    'TruckSell*.zip'                 = @{ Folder = 'TruckSell';                 Strip = $null }
    '*IncreaseDifficultyMod*.zip'    = @{ Folder = 'IncreaseDifficultyMod';     Strip = $null }
    'InterestingLevels*.zip'         = @{ Folder = 'InterestingLevels';         Strip = $null }
    'TheFacility*.zip'               = @{ Folder = 'TheFacility';               Strip = $null }
    'JustOtakus_Valuables*.zip'      = @{ Folder = 'JustOtakus_Valuables';      Strip = $null }
    'SusScrapsValuables*.zip'        = @{ Folder = 'SusScrapsValuables';        Strip = $null }
    'UsableValuables*.zip'           = @{ Folder = 'UsableValuables';           Strip = $null }
    'TextUpgradesUIScale*.zip'       = @{ Folder = 'TextUpgradesUIScale';       Strip = $null }
}

$missing = New-Object System.Collections.Generic.List[string]
foreach ($pattern in $modMapping.Keys) {
    $item = $modMapping[$pattern]
    $zip = Get-ChildItem -LiteralPath $mods -Filter $pattern -File | Select-Object -First 1
    if (-not $zip) {
        Write-Host ("  - пропуск: {0} (архив не найден)" -f $item.Folder) -ForegroundColor Yellow
        $missing.Add($item.Folder)
        continue
    }
    Expand-ArchiveFiltered -ZipPath $zip.FullName -DestDir (Join-Path $plugins $item.Folder) -StripPrefix $item.Strip -SkipDocs $true
    Write-Host ("  + {0}" -f $item.Folder)
}

$fontZip = Get-ChildItem -LiteralPath $mods -Filter '*Russian_Font_Fix*.zip' -File | Select-Object -First 1
if ($fontZip) {
    Expand-ArchiveFiltered -ZipPath $fontZip.FullName -DestDir (Join-Path $GameDir 'BepInEx') -SkipDocs $true
    Write-Host '  + Russian Font Fix (кириллица и шрифты)'
} else {
    $missing.Add('Russian_Font_Fix')
}

$ruRoles = Join-Path $root 'Русские_роли_REPORoles.cfg'
$rolesCfg = Join-Path $GameDir 'BepInEx\config\R3Labs.Repo_Roles.Classic.cfg'
if (Test-Path -LiteralPath $ruRoles) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rolesCfg) | Out-Null
    if (Test-Path -LiteralPath $rolesCfg) {
        Copy-Item -LiteralPath $rolesCfg -Destination ($rolesCfg + '.bak_' + $stamp) -Force
    }
    Copy-Item -LiteralPath $ruRoles -Destination $rolesCfg -Force
    Write-Host '  + русские названия и описания ролей'
}

Write-Host '[3/3] Установка патчера...' -ForegroundColor Green
$patcherZip = Get-ChildItem -LiteralPath $mods -Filter '*FixPluginTypesSerialization*.zip' -File | Select-Object -First 1
if ($patcherZip) {
    Expand-ArchiveFiltered -ZipPath $patcherZip.FullName -DestDir $GameDir -SkipDocs $true
    Write-Host '  + FixPluginTypesSerialization'
} else {
    $missing.Add('FixPluginTypesSerialization')
}

$guide = Join-Path $root 'Настройки_модов_по-русски.html'
if (Test-Path -LiteralPath $guide) {
    Copy-Item -LiteralPath $guide -Destination $GameDir -Force
    Write-Host '  + шпаргалка "Настройки_модов_по-русски.html"'
}

Write-Host ''
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host '   УСТАНОВКА ЗАВЕРШЕНА' -ForegroundColor Green
Write-Host '=========================================' -ForegroundColor Cyan
Write-Host "Бэкап старых файлов и конфигов: $backup"

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host ('Пропущены архивы: ' + ($missing -join ', ')) -ForegroundColor Yellow
    Write-Host 'IncreaseDifficultyMod скачивается отдельно из релиза:' -ForegroundColor Yellow
    Write-Host '  https://github.com/Dezamanee/repo-mods/releases/tag/v1.0'
}
Write-Host 'Запускайте игру через Steam.'
