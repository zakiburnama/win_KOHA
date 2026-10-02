<#
    Advances the desktop wallpaper to the next image (alphabetical order) in
    the currently active global theme's wallpapers folder. Meant to be run
    periodically via Task Scheduler -- see install-wallpaper-rotation.ps1,
    which registers it. Not launched by KOHA directly.

    "Currently active theme" comes from %TEMP%\koha-active-theme.txt,
    written by apply-theme.ps1 every time a global theme (catppuccin-mocha
    or gruvbox) is picked from KOHA's Color Scheme submenu.

    Its own position -- which image was shown last, and for which theme --
    lives in %TEMP%\koha-wallpaper-rotation.json. Keeping the theme
    name alongside the index means switching themes always restarts at
    image #1 for the new theme, instead of carrying over an index that
    belonged to a different folder.
#>

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$RotationStateFile = Join-Path $env:TEMP 'koha-wallpaper-rotation.json'

try {
    if (-not (Test-Path -LiteralPath $ActiveThemeFile)) {
        Write-Log "rotate: no active theme recorded yet, skipping"
        return
    }

    $theme = ([System.IO.File]::ReadAllText($ActiveThemeFile)).Trim()
    $images = Get-ThemeWallpapers -Theme $theme
    if ($images.Count -eq 0) {
        Write-Log "rotate: no images for theme '$theme', skipping"
        return
    }

    $state = $null
    if (Test-Path -LiteralPath $RotationStateFile) {
        try {
            $state = Get-Content -LiteralPath $RotationStateFile -Raw | ConvertFrom-Json
        } catch {
            $state = $null
        }
    }

    # Only resume from the saved index if it was for THIS theme and that
    # filename still exists (folder contents can change between ticks) --
    # otherwise a theme switch, or a renamed/deleted file, just restarts at
    # image #1 rather than erroring or guessing.
    $nextIndex = 0
    if ($state -and $state.theme -eq $theme) {
        $currentPos = [array]::IndexOf(@($images.Name), $state.lastFile)
        if ($currentPos -ge 0) {
            $nextIndex = ($currentPos + 1) % $images.Count
        }
    }

    $chosen = $images[$nextIndex]
    Set-DesktopWallpaper -Path $chosen.FullName

    @{ theme = $theme; lastFile = $chosen.Name } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $RotationStateFile -Encoding utf8

    Write-Log "rotate: theme '$theme' -> $($chosen.Name) ($($nextIndex + 1)/$($images.Count))"
} catch {
    Write-Log "rotate FAILED: $_"
}
