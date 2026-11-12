param([string]$GameDir)

$ErrorActionPreference = 'Stop'

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
        'E:\SteamLibrary\steamapps\common\REPO'
    )
    foreach ($p in $defaults) { $candidates.Add($p) }

    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath (Join-Path $c 'REPO.exe'))) { return $c }
    }
    return $null
}

if (-not $GameDir) { $GameDir = Find-Game }
if (-not $GameDir) { $GameDir = Read-Host 'Введите путь к папке с REPO.exe' }
$GameDir = $GameDir.Trim('"').TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'REPO.exe'))) {
    Write-Host "В папке '$GameDir' нет REPO.exe. Отмена." -ForegroundColor Red
    exit 1
}

Write-Host "Удаление модов из: $GameDir" -ForegroundColor Yellow

$targets = @('BepInEx', 'winhttp.dll', 'doorstop_config.ini', '.doorstop_version', 'Настройки_модов_по-русски.html')
foreach ($item in $targets) {
    $path = Join-Path $GameDir $item
    if (Test-Path -LiteralPath $path) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force
            Write-Host "  - удалено: $item" -ForegroundColor Green
        } catch {
            Write-Host "  ! не удалось удалить: $item ($($_.Exception.Message))" -ForegroundColor Red
            $failed = $true
        }
    }
}

$backupRoot = Join-Path $GameDir 'backups'
if (Test-Path -LiteralPath $backupRoot) {
    Write-Host ''
    Write-Host 'Резервные копии сохранены здесь:' -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { Write-Host ("  " + $_.FullName) }
    Write-Host 'Чтобы вернуть старые файлы, скопируй их обратно в папку игры.'
}

if ($failed) { exit 2 }
Write-Host ''
Write-Host 'Готово: моды удалены, сейвы и настройки игры не тронуты.' -ForegroundColor Green
