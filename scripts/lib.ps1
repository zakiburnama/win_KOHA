<#
    Shared helpers for QuickMenu Light's global-theme and reminder scripts
    (apply-theme.ps1, rotate-wallpaper.ps1, set-reminder.ps1,
    show-reminder.ps1). Dot-source this, don't run it directly:
        . "$PSScriptRoot\lib.ps1"
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$LogFile = Join-Path $env:TEMP 'quickmenu-apply-theme.log'
$WallpapersRoot = 'C:\PERSONAL-PROJECTS\linux\dotfiles\wallpapers'
$ActiveThemeFile = Join-Path $env:TEMP 'quickmenu-active-theme.txt'
$ImageExtensionPattern = '^\.(jpg|jpeg|png|bmp)$'
# Written by list-reminders.ps1, read by quickmenu_light.ahk's
# GetPendingReminders() after a RunWait(..., "Hide") -- see that script's
# header for why this is a file and not stdout.
$PendingRemindersFile = Join-Path $env:TEMP 'quickmenu-pending-reminders.txt'

# The same quickmenu_settings.ini quickmenu_light.ahk reads/writes via
# IniRead/IniWrite -- see Get-IniValue below for why PowerShell can't use
# those same builtins. Never write to this file from PowerShell; AHK owns
# it, these scripts only ever read.
$SettingsFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'quickmenu_settings.ini'

# Prayer-time (waktu sholat) reminders -- Jakarta, via the myQuran API
# (api.myquran.com, sourced from Kemenag RI). City is hardcoded rather than
# a setting: same "personal single-user tool, hardcoding beats config
# indirection" reasoning as $WallpapersRoot. Change both values together if
# you move cities -- look up the new id with:
#   curl "https://api.myquran.com/v3/sholat/kabkota/cari/<city-keyword>"
$PrayerCityId = '58a2fc6ed39fd083f55d4182bf88826d'
$PrayerCityName = 'Jakarta'
# Order matters -- this is display/scheduling order (Subuh through Isya).
# Keys match the myQuran API's own field names exactly.
$PrayerDisplayNames = [ordered]@{
    subuh   = 'Subuh'
    dzuhur  = 'Dzuhur'
    ashar   = 'Ashar'
    maghrib = 'Maghrib'
    isya    = 'Isya'
}
$PrayerTimesFile = Join-Path $env:TEMP 'quickmenu-prayer-times.txt'

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'u') $Message" | Add-Content -LiteralPath $LogFile -Encoding utf8
}

function Set-FileContent {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# Reads one key from quickmenu_settings.ini's [Settings] section. AHK's
# IniWrite saves .ini files as UTF-16LE with a BOM (confirmed via hex
# dump), so this reads with -Encoding Unicode (Windows PowerShell 5.1's
# name for UTF-16LE) rather than the default -- otherwise every line comes
# back as null-byte-interleaved garbage and nothing matches. A plain
# regex line match, not a real INI parser: this file only ever has one
# flat [Settings] section, so that's deliberately all this needs to be.
function Get-IniValue {
    param([string]$Key, [string]$Default = '')

    if (-not (Test-Path -LiteralPath $SettingsFile)) {
        return $Default
    }
    $line = Get-Content -LiteralPath $SettingsFile -Encoding Unicode |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" } |
        Select-Object -First 1
    if (-not $line) {
        return $Default
    }
    return ($line -split '=', 2)[1].Trim()
}

# Today's 5 prayer times from the myQuran API, as an ordered hashtable
# keyed the same as $PrayerDisplayNames (subuh/dzuhur/ashar/maghrib/isya)
# with "HH:mm" string values. Throws on any failure (network, unexpected
# shape) -- callers decide how to degrade, this doesn't guess.
function Get-PrayerTimesToday {
    $url = "https://api.myquran.com/v3/sholat/jadwal/$PrayerCityId/today?tz=Asia%2FJakarta"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 10
    if (-not $response.status) {
        throw "myQuran API returned status=false: $($response.message)"
    }
    # data.jadwal is a single-key object keyed by today's date
    # ("2026-09-19") whose value has subuh/dzuhur/ashar/maghrib/isya
    # (plus imsak/terbit/dhuha, which nothing here uses) -- grab the one
    # value without needing to know or format that date key ourselves.
    $todayJadwal = @($response.data.jadwal.PSObject.Properties.Value)[0]

    $times = [ordered]@{}
    foreach ($key in $PrayerDisplayNames.Keys) {
        $times[$key] = $todayJadwal.$key
    }
    return $times
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class QuickMenuWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@

# Sets the desktop wallpaper (Fill style) to the given image path -- the one
# primitive both apply-theme.ps1 (immediate feedback on theme switch) and
# rotate-wallpaper.ps1 (periodic advance) build on.
function Set-DesktopWallpaper {
    param([string]$Path)

    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02

    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' # 10 = Fill
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
    [QuickMenuWallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Path, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) | Out-Null
}

# All jpg/jpeg/png/bmp files directly inside $WallpapersRoot\<theme>\,
# sorted alphabetically -- the one deterministic ordering apply-theme.ps1
# (picks the first) and rotate-wallpaper.ps1 (walks all of them) both rely
# on. Always returns an array (never a bare single object), even for 0 or 1
# matches -- avoids PowerShell's single-item-unwraps-to-scalar gotcha.
function Get-ThemeWallpapers {
    param([string]$Theme)

    $dir = Join-Path $WallpapersRoot $Theme
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }
    @(Get-ChildItem -LiteralPath $dir -File |
        Where-Object { $_.Extension -match $ImageExtensionPattern } |
        Sort-Object Name)
}

# Balloon-tip notification, optionally with a beep. Used both for the
# reminder itself (show-reminder.ps1) and the "ok, timer's running"
# confirmation shown the moment a reminder is set (set-reminder.ps1). The
# NotifyIcon has to stay alive a few seconds after ShowBalloonTip for
# Windows to actually render it -- Dispose()ing immediately can beat the
# balloon to the screen.
function Show-Notification {
    param([string]$Title, [string]$Text, [switch]$Beep)

    $notify = New-Object System.Windows.Forms.NotifyIcon
    try {
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText = $Text
        $notify.ShowBalloonTip(10000)
        if ($Beep) {
            [System.Media.SystemSounds]::Exclamation.Play()
        }
        Start-Sleep -Seconds 5
    } finally {
        $notify.Dispose()
    }
}
