<#
    Applies a canonical global color theme across the tools QuickMenu Light's
    "Color Scheme" submenu can reach beyond its own popup: Neovim, WezTerm,
    Starship, and the desktop wallpaper. Triggered by quickmenu_light.ahk
    (Run(), hidden window) when the chosen theme is one of the "global"
    entries in GLOBAL_THEMES -- see README.md for the full picture.

    Runs hidden with no console, so failures are logged (not shown) to
    %TEMP%\quickmenu-apply-theme.log rather than swallowed silently.

    Each target file keeps its own line-ending convention (wezterm.lua is
    LF, starship.toml is CRLF) -- Set-MarkedBlock normalizes to LF for the
    regex swap, then restores whichever style the file already used.

    Also records the chosen theme to %TEMP%\quickmenu-active-theme.txt --
    rotate-wallpaper.ps1 (run periodically via Task Scheduler, see
    install-wallpaper-rotation.ps1) reads that to know which theme's
    wallpaper folder to keep cycling through between theme switches.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('catppuccin-mocha', 'gruvbox')]
    [string]$Theme
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

# Replaces everything strictly between a BEGIN/END marker line (the marker
# lines themselves are left untouched) with $NewBlock. Throws if the
# markers aren't found exactly once, rather than silently no-op'ing --
# a moved/renamed marker is a real break, not something to paper over.
function Set-MarkedBlock {
    param([string]$Path, [string]$BeginMarker, [string]$EndMarker, [string]$NewBlock)

    $raw = [System.IO.File]::ReadAllText($Path)
    $usesCRLF = $raw.Contains("`r`n")

    $normalized = $raw -replace "`r`n", "`n"
    $newBlockNormalized = ($NewBlock -replace "`r`n", "`n").Trim("`n")

    $pattern = [regex]::Escape($BeginMarker) + "\n(?s).*?\n" + [regex]::Escape($EndMarker)
    $found = [regex]::Matches($normalized, $pattern)
    if ($found.Count -ne 1) {
        throw "Expected exactly 1 '$BeginMarker' ... '$EndMarker' block in $Path, found $($found.Count)."
    }

    $replacement = "$BeginMarker`n$newBlockNormalized`n$EndMarker"
    $result = $normalized.Substring(0, $found[0].Index) + $replacement + $normalized.Substring($found[0].Index + $found[0].Length)

    if ($usesCRLF) {
        $result = $result -replace "`n", "`r`n"
    }

    Set-FileContent -Path $Path -Content $result
}

# Sets the desktop wallpaper to the alphabetically-first jpg/jpeg/png/bmp
# found in $WallpapersRoot\<theme>\ -- immediate feedback on theme switch.
# rotate-wallpaper.ps1 takes over from there, advancing through the rest of
# the folder every 30 min. Deterministic on purpose -- if you keep more than
# one image per theme, prefix filenames (e.g. "01-foo.jpg") to control which
# one shows first. A missing or empty folder is a normal "haven't put a
# wallpaper there yet" state, not an error -- logged as info and skipped,
# same as every other step here.
function Set-ThemeWallpaper {
    param([string]$Theme)

    $images = Get-ThemeWallpapers -Theme $Theme
    if ($images.Count -eq 0) {
        Write-Log "wallpaper: no jpg/jpeg/png/bmp files for '$Theme', skipping"
        return
    }

    Set-DesktopWallpaper -Path $images[0].FullName
    Write-Log "wallpaper: set to $($images[0].FullName)"
}

# ---------------------------------------------------------------------------
# Theme registry -- one source of truth for the 2 canonical global themes.
# Adding a new global theme later: add an entry here, add it to the
# ValidateSet above, and add a matching entry to GLOBAL_THEMES in
# quickmenu_light.ahk (plus its own popup bg/fg/selBg/selFg/bezel there).
# ---------------------------------------------------------------------------
$Themes = @{
    'catppuccin-mocha' = @{
        NvimColorscheme = 'catppuccin-mocha'
        StarshipPalette = @'
# Catppuccin Mocha (official palette, matches the WezTerm/kitty theme).
# color_fg0: dark text, for the BRIGHT segment backgrounds below.
# color_fg1: light text, for the DARK segments (color_bg1/color_bg3).
[palettes.active]
color_fg0 = '#11111b'   # crust
color_fg1 = '#cdd6f4'   # text
color_bg1 = '#1e1e2e'   # base: matches the terminal background, so the tail fades in seamlessly
color_bg3 = '#313244'   # surface0
color_blue = '#89b4fa'
color_aqua = '#94e2d5'  # teal
color_green = '#a6e3a1'
color_orange = '#fab387' # peach
color_purple = '#cba6f7' # mauve
color_red = '#f38ba8'
color_yellow = '#f9e2af'
'@
        WeztermColors   = @'
-- Catppuccin-Mocha, ported 1:1 from current-theme.conf
config.colors = {
	foreground = "#CDD6F4",
	background = "#1E1E2E",

	cursor_bg = "#F5E0DC",
	cursor_fg = "#1E1E2E",
	cursor_border = "#F5E0DC",

	selection_fg = "#1E1E2E",
	selection_bg = "#F5E0DC",

	split = "#B4BEFE",
	visual_bell = "#F9E2AF",

	ansi = {
		"#45475A", -- black
		"#F38BA8", -- red
		"#A6E3A1", -- green
		"#F9E2AF", -- yellow
		"#89B4FA", -- blue
		"#F5C2E7", -- magenta
		"#94E2D5", -- cyan
		"#BAC2DE", -- white
	},
	brights = {
		"#585B70", -- bright black
		"#F38BA8", -- bright red
		"#A6E3A1", -- bright green
		"#F9E2AF", -- bright yellow
		"#89B4FA", -- bright blue
		"#F5C2E7", -- bright magenta
		"#94E2D5", -- bright cyan
		"#A6ADC8", -- bright white
	},

	tab_bar = {
		background = "#11111B",
		active_tab = {
			bg_color = "#CBA6F7",
			fg_color = "#11111B",
		},
		inactive_tab = {
			bg_color = "#181825",
			fg_color = "#CDD6F4",
		},
		inactive_tab_hover = {
			bg_color = "#313244",
			fg_color = "#CDD6F4",
		},
		new_tab = {
			bg_color = "#11111B",
			fg_color = "#CDD6F4",
		},
	},
}
'@
    }
    'gruvbox'           = @{
        NvimColorscheme = 'gruvbox'
        StarshipPalette = @'
# Gruvbox Dark (medium contrast) -- this repo's original starship palette
# before the Catppuccin migration (recovered from the pre-rename working
# tree). color_fg0 and color_fg1 are the same light tone here: gruvbox's
# accent colors are mid-dark, not pastel like Catppuccin's, so they don't
# need Catppuccin's dark/light split between bright- and dark-segment text.
[palettes.active]
color_fg0 = '#fbf1c7'
color_fg1 = '#fbf1c7'
color_bg1 = '#3c3836'
color_bg3 = '#665c54'
color_blue = '#458588'
color_aqua = '#689d6a'
color_green = '#98971a'
color_orange = '#d65d0e'
color_purple = '#b16286'
color_red = '#cc241d'
color_yellow = '#d79921'
'@
        WeztermColors   = @'
-- Gruvbox Dark (medium contrast), standard 16-color terminal palette
config.colors = {
	foreground = "#EBDBB2",
	background = "#282828",

	cursor_bg = "#FE8019",
	cursor_fg = "#282828",
	cursor_border = "#FE8019",

	selection_fg = "#EBDBB2",
	selection_bg = "#504945",

	split = "#83A598",
	visual_bell = "#FABD2F",

	ansi = {
		"#282828", -- black
		"#CC241D", -- red
		"#98971A", -- green
		"#D79921", -- yellow
		"#458588", -- blue
		"#B16286", -- magenta
		"#689D6A", -- cyan
		"#A89984", -- white
	},
	brights = {
		"#928374", -- bright black
		"#FB4934", -- bright red
		"#B8BB26", -- bright green
		"#FABD2F", -- bright yellow
		"#83A598", -- bright blue
		"#D3869B", -- bright magenta
		"#8EC07C", -- bright cyan
		"#EBDBB2", -- bright white
	},

	tab_bar = {
		background = "#1D2021",
		active_tab = {
			bg_color = "#FE8019",
			fg_color = "#282828",
		},
		inactive_tab = {
			bg_color = "#3C3836",
			fg_color = "#EBDBB2",
		},
		inactive_tab_hover = {
			bg_color = "#504945",
			fg_color = "#EBDBB2",
		},
		new_tab = {
			bg_color = "#1D2021",
			fg_color = "#EBDBB2",
		},
	},
}
'@
    }
}

# ---------------------------------------------------------------------------
# Target files -- machine-specific paths, not portable. This is a personal
# single-user tool, so hardcoding beats config-file indirection here.
# ---------------------------------------------------------------------------
$NvimThemeFile  = Join-Path $env:LOCALAPPDATA 'Temp\nvim\theme.txt'
$StarshipConfig = 'C:\PERSONAL-PROJECTS\linux\dotfiles\starship\.config\starship.toml'
$WeztermConfig  = 'C:\PERSONAL-PROJECTS\linux\dotfiles\wezterm\.config\wezterm\wezterm.lua'

$def = $Themes[$Theme]
Write-Log "applying theme '$Theme'"

try {
    Set-FileContent -Path $ActiveThemeFile -Content $Theme
} catch {
    Write-Log "active-theme.txt update FAILED: $_"
}

try {
    Set-FileContent -Path $NvimThemeFile -Content $def.NvimColorscheme
} catch {
    Write-Log "nvim theme.txt update FAILED: $_"
}

try {
    Set-MarkedBlock -Path $StarshipConfig -BeginMarker '# BEGIN THEME PALETTE' -EndMarker '# END THEME PALETTE' -NewBlock $def.StarshipPalette
} catch {
    Write-Log "starship.toml update FAILED: $_"
}

try {
    Set-MarkedBlock -Path $WeztermConfig -BeginMarker '-- BEGIN THEME COLORS' -EndMarker '-- END THEME COLORS' -NewBlock $def.WeztermColors
} catch {
    Write-Log "wezterm.lua update FAILED: $_"
}

try {
    Set-ThemeWallpaper -Theme $Theme
} catch {
    Write-Log "wallpaper update FAILED: $_"
}

Write-Log "done"
