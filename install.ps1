param([string]$GameDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Find-Game {
    $candidates = @(
        'C:\steam\steamapps\common\REPO',
        'C:\Program Files (x86)\Steam\steamapps\common\REPO',
        'C:\Program Files\Steam\steamapps\common\REPO',
        'D:\Steam\steamapps\common\REPO',
        'D:\SteamLibrary\steamapps\common\REPO',
        'E:\SteamLibrary\steamapps\common\REPO'
    )
    try {
        $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($steam) { $candidates += (Join-Path $steam 'steamapps\common\REPO') }
    } catch {}
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'REPO.exe')) { return $c }
    }
    return $null
}

function Expand-ZipTo($zip, $dest, $stripPrefix) {
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    foreach ($e in $z.Entries) {
        $name = $e.FullName
        if ($stripPrefix -and $name.StartsWith($stripPrefix)) { $name = $name.Substring($stripPrefix.Length) }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $target = Join-Path $dest ($name -replace '/', '\')
        if ($e.Name -eq '') { New-Item -ItemType Directory -Force -Path $target | Out-Null; continue }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
    $z.Dispose()
}

function Install-Mod($zip, $dest) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    foreach ($e in $z.Entries) {
        if ($e.Name -eq '') { continue }
        if ($e.FullName -match '^(README|CHANGELOG|icon\.png|manifest\.json)') { continue }
        $target = Join-Path $dest ($e.FullName -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
    $z.Dispose()
}

Write-Host ''
Write-Host '=== R.E.P.O. ModPack 1.1 installer ===' -ForegroundColor Cyan

if (-not $GameDir) { $GameDir = Find-Game }
if (-not $GameDir) {
    Write-Host 'Не нашёл игру автоматически.' -ForegroundColor Yellow
    $GameDir = Read-Host 'Вставь путь к папке с REPO.exe (например C:\steam\steamapps\common\REPO)'
}
$GameDir = $GameDir.Trim('"').TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'REPO.exe'))) {
    Write-Host "В папке '$GameDir' нет REPO.exe. Установка отменена." -ForegroundColor Red
    Read-Host 'Enter для выхода'
    exit 1
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mods = Join-Path $root 'Моды'
if (-not (Test-Path -LiteralPath $mods)) { $mods = Join-Path $root 'Mods' }
if (-not (Test-Path -LiteralPath $mods)) { throw 'Не найдена папка с модами рядом со скриптом' }

$backup = Join-Path $GameDir ('backups\before_modpack_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($f in 'winhttp.dll', 'doorstop_config.ini') {
    $p = Join-Path $GameDir $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $backup -Force }
}

Write-Host '1/3 Ставлю BepInEx...' -ForegroundColor Green
Expand-ZipTo (Join-Path $mods 'BepInExPack.zip') $GameDir 'BepInExPack/'

Write-Host '2/3 Ставлю моды...' -ForegroundColor Green
$plugins = Join-Path $GameDir 'BepInEx\plugins'

$map = @{
    'REPOLib_4.3.0.zip'              = 'REPOLib'
    'MenuLib.zip'                    = 'MenuLib'
    'REPOConfig.zip'                 = 'REPOConfig'
    'REPORoles_Classic.zip'          = 'REPORoles_Classic'
    'Shop_Items_Spawn_in_Level.zip'  = 'Shop_Items_Spawn_in_Level'
    'TruckSell.zip'                  = 'TruckSell'
    'IncreaseDifficultyMod.zip'      = 'IncreaseDifficultyMod'
    'InterestingLevels.zip'          = 'InterestingLevels'
    'TheFacility.zip'                = 'TheFacility'
    'JustOtakus_Valuables.zip'       = 'JustOtakus_Valuables'
    'SusScrapsValuables.zip'         = 'SusScrapsValuables'
    'UsableValuables.zip'            = 'UsableValuables'
    'TextUpgradesUIScale.zip'        = 'TextUpgradesUIScale'
}
foreach ($k in $map.Keys) {
    $zip = Join-Path $mods $k
    if (-not (Test-Path -LiteralPath $zip)) { Write-Host "  пропуск: нет $k" -ForegroundColor Yellow; continue }
    Install-Mod $zip (Join-Path $plugins $map[$k])
    Write-Host "  + $($map[$k])"
}

$fontZip = Join-Path $mods 'Russian_Font_Fix.zip'
if (Test-Path -LiteralPath $fontZip) {
    Expand-ZipTo $fontZip (Join-Path $GameDir 'BepInEx') $null
    Write-Host '  + Russian Font Fix (кириллица + шрифты)'
}

$ruRoles = Join-Path $root 'Русские_роли_REPORoles.cfg'
$rolesCfg = Join-Path $GameDir 'BepInEx\config\R3Labs.Repo_Roles.Classic.cfg'
if ((Test-Path -LiteralPath $ruRoles) -and -not (Test-Path -LiteralPath $rolesCfg)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rolesCfg) | Out-Null
    Copy-Item -LiteralPath $ruRoles -Destination $rolesCfg -Force
    Write-Host '  + русские названия и описания ролей'
}

Write-Host '3/3 Ставлю патчер...' -ForegroundColor Green
Expand-ZipTo (Join-Path $mods 'FixPluginTypesSerialization.zip') $GameDir $null

$guide = Join-Path $root 'Настройки_модов_по-русски.html'
if (Test-Path -LiteralPath $guide) {
    Copy-Item -LiteralPath $guide -Destination $GameDir -Force
    Write-Host '  + шпаргалка "Настройки_модов_по-русски.html" в папке игры'
}

Write-Host ''
Write-Host 'ГОТОВО. Запускай игру через Steam.' -ForegroundColor Cyan
Write-Host "Бэкап старых файлов: $backup"
Write-Host 'Первый запуск создаст конфиги модов (BepInEx\config).'
Read-Host 'Enter для выхода'
