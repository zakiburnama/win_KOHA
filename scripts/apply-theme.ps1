<#
    Applies a canonical global color theme across the tools QuickMenu Light's
    "Color Scheme" submenu can reach beyond its own popup: Neovim, WezTerm,
    Starship, the desktop wallpaper, and an Obsidian vault. Triggered by
    quickmenu_light.ahk (Run(), hidden window) when the chosen theme is one
    of the "global" entries in GLOBAL_THEMES -- see README.md for the full
    picture.

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
    [ValidateSet('game_boy', 'amber', 'green_term', 'catppuccin-mocha', 'gruvbox', 'vague', 'tokyonight')]
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

# Obsidian vault theme sync -- uses the REAL installed community theme
# (ObsidianCssTheme: which folder under .obsidian/themes/) for the bulk of
# the styling, not a full from-scratch reskin. A small CSS snippet this
# script fully owns (see $ObsidianSnippetFile in lib.ps1) only overrides
# the handful of variables each installed theme leaves as a flavor/accent
# knob -- Catppuccin's own ".theme-dark" selector already gives full Mocha
# colors with zero configuration, for instance, it's only --ctp-accent
# (normally picked via a class the "Style Settings" plugin would add,
# which isn't installed) that needs pinning. Snippets always load after
# the active theme, so these overrides reliably win the CSS cascade
# without ever touching the installed theme's own file -- safe even if
# that theme gets updated later. gruvbox and tokyonight need no overrides
# at all (ObsidianSnippet is just '') since "Obsidian gruvbox" and
# "Tokyo Night" are complete, self-contained palettes already. A theme
# with no ObsidianCssTheme entry in the registry (no good match installed)
# would skip entirely, same idea as an empty wallpaper folder -- not
# currently the case for any of the 7 global themes below.
function Set-ObsidianTheme {
    param([string]$Theme, [string]$CssTheme, [string]$CssBlock, [string]$Mode)

    if (-not $CssTheme) {
        Write-Log "obsidian: no theme mapping for '$Theme', skipping"
        return
    }

    $snippetDir = Split-Path $ObsidianSnippetFile -Parent
    if (-not (Test-Path -LiteralPath $snippetDir)) {
        New-Item -ItemType Directory -Path $snippetDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $ObsidianSnippetFile)) {
        Set-FileContent -Path $ObsidianSnippetFile -Content "/* BEGIN THEME COLORS */`n`n/* END THEME COLORS */"
    }
    Set-MarkedBlock -Path $ObsidianSnippetFile -BeginMarker '/* BEGIN THEME COLORS */' -EndMarker '/* END THEME COLORS */' -NewBlock $CssBlock

    $json = Get-Content -LiteralPath $ObsidianAppearanceFile -Raw | ConvertFrom-Json
    $json.theme = $Mode
    if ($json.PSObject.Properties.Name -contains 'cssTheme') {
        $json.cssTheme = $CssTheme
    } else {
        $json | Add-Member -NotePropertyName cssTheme -NotePropertyValue $CssTheme -Force
    }
    $snippets = @()
    if ($json.PSObject.Properties.Name -contains 'enabledCssSnippets') {
        $snippets = @($json.enabledCssSnippets)
    }
    if ($snippets -notcontains 'quickmenu-theme') {
        $snippets += 'quickmenu-theme'
    }
    if ($json.PSObject.Properties.Name -contains 'enabledCssSnippets') {
        $json.enabledCssSnippets = $snippets
    } else {
        $json | Add-Member -NotePropertyName enabledCssSnippets -NotePropertyValue $snippets -Force
    }
    Set-FileContent -Path $ObsidianAppearanceFile -Content ($json | ConvertTo-Json -Depth 5)

    Write-Log "obsidian: applied '$Theme' (cssTheme=$CssTheme, mode=$Mode)"
}

# ---------------------------------------------------------------------------
# Theme registry -- one source of truth for all 7 global themes. Adding a
# new one: add an entry here, add it to the ValidateSet above, and add a
# matching entry to GLOBAL_THEMES in quickmenu_light.ahk (plus its own
# popup bg/fg/selBg/selFg/bezel there).
# ---------------------------------------------------------------------------
$Themes = @{
    'game_boy'          = @{
        NvimColorscheme = 'game_boy'
        StarshipPalette = @'
# Classic DMG Game Boy 4-shade green -- matches QuickMenu Light's own
# game_boy theme and colors/game_boy.lua 1:1. Unlike the other themes
# here this is a LIGHT palette (the real DMG screen is light with dark
# pixels), so color_fg0/color_fg1 are swapped relative to the dark themes:
# color_fg0 is LIGHT (for the dark accent chips below), color_fg1 is DARK
# (for the light bg1/bg3 "fade toward terminal background" chips).
[palettes.active]
color_fg0 = '#9bbc0f'   # lightest -- text on the dark accent chips
color_fg1 = '#0f380f'   # darkest -- text on the light bg1/bg3 chips
color_bg1 = '#9bbc0f'   # lightest -- matches the (light!) terminal background
color_bg3 = '#8bac0f'   # light
color_blue = '#0f380f'
color_aqua = '#306230'
color_green = '#0f380f'
color_orange = '#306230'
color_purple = '#0f380f'
color_red = '#306230'
color_yellow = '#0f380f'
'@
        WeztermColors   = @'
-- Classic DMG Game Boy 4-shade green. LIGHT background on purpose -- the
-- real DMG screen is light/yellow-green with dark pixels, not the other
-- way around.
config.colors = {
	foreground = "#0F380F",
	background = "#9BBC0F",

	cursor_bg = "#0F380F",
	cursor_fg = "#9BBC0F",
	cursor_border = "#0F380F",

	selection_fg = "#9BBC0F",
	selection_bg = "#0F380F",

	split = "#306230",
	visual_bell = "#0F380F",

	ansi = {
		"#0F380F", -- black
		"#306230", -- red
		"#306230", -- green
		"#306230", -- yellow
		"#0F380F", -- blue
		"#0F380F", -- magenta
		"#306230", -- cyan
		"#306230", -- white
	},
	brights = {
		"#306230", -- bright black
		"#0F380F", -- bright red
		"#0F380F", -- bright green
		"#0F380F", -- bright yellow
		"#306230", -- bright blue
		"#306230", -- bright magenta
		"#0F380F", -- bright cyan
		"#0F380F", -- bright white
	},

	tab_bar = {
		background = "#8BAC0F",
		active_tab = {
			bg_color = "#0F380F",
			fg_color = "#9BBC0F",
		},
		inactive_tab = {
			bg_color = "#9BBC0F",
			fg_color = "#0F380F",
		},
		inactive_tab_hover = {
			bg_color = "#8BAC0F",
			fg_color = "#0F380F",
		},
		new_tab = {
			bg_color = "#8BAC0F",
			fg_color = "#0F380F",
		},
	},
}
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Terminal'
        ObsidianSnippet = @'
body {
	--the-color: #0F380F;
	--the-background-color: #9BBC0F;
}
'@
        ObsidianMode    = 'moonstone'
    }
    'amber'             = @{
        NvimColorscheme = 'amber'
        StarshipPalette = @'
# Amber CRT terminal -- matches QuickMenu Light's own amber theme and
# colors/amber.lua 1:1. Standard dark-theme polarity: color_fg0 is dark
# (for the bright amber accent chips), color_fg1 is light amber (for the
# dark bg1/bg3 "fade toward terminal background" chips).
[palettes.active]
color_fg0 = '#1a0f00'
color_fg1 = '#ffd480'
color_bg1 = '#1a0f00'
color_bg3 = '#2a1a00'
color_blue = '#ffb000'
color_aqua = '#ffd480'
color_green = '#ffb000'
color_orange = '#ffd480'
color_purple = '#ffb000'
color_red = '#ffd480'
color_yellow = '#ffb000'
'@
        WeztermColors   = @'
-- Amber CRT terminal, single-hue monochrome
config.colors = {
	foreground = "#FFB000",
	background = "#1A0F00",

	cursor_bg = "#FFB000",
	cursor_fg = "#1A0F00",
	cursor_border = "#FFB000",

	selection_fg = "#1A0F00",
	selection_bg = "#FFB000",

	split = "#FFD480",
	visual_bell = "#FFB000",

	ansi = {
		"#1A0F00", -- black
		"#805800", -- red
		"#805800", -- green
		"#FFB000", -- yellow
		"#805800", -- blue
		"#805800", -- magenta
		"#FFB000", -- cyan
		"#FFB000", -- white
	},
	brights = {
		"#805800", -- bright black
		"#FFB000", -- bright red
		"#FFB000", -- bright green
		"#FFD480", -- bright yellow
		"#FFB000", -- bright blue
		"#FFB000", -- bright magenta
		"#FFD480", -- bright cyan
		"#FFD480", -- bright white
	},

	tab_bar = {
		background = "#1A0F00",
		active_tab = {
			bg_color = "#FFB000",
			fg_color = "#1A0F00",
		},
		inactive_tab = {
			bg_color = "#805800",
			fg_color = "#1A0F00",
		},
		inactive_tab_hover = {
			bg_color = "#FFD480",
			fg_color = "#1A0F00",
		},
		new_tab = {
			bg_color = "#1A0F00",
			fg_color = "#FFB000",
		},
	},
}
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Terminal'
        ObsidianSnippet = @'
body {
	--the-color: #FFB000;
	--the-background-color: #1A0F00;
}
'@
        ObsidianMode    = 'obsidian'
    }
    'green_term'        = @{
        NvimColorscheme = 'green_term'
        StarshipPalette = @'
# Phosphor-green CRT terminal -- matches QuickMenu Light's own green_term
# theme and colors/green_term.lua 1:1. Standard dark-theme polarity:
# color_fg0 is dark (for the bright green accent chips), color_fg1 is
# light green (for the dark bg1/bg3 "fade toward terminal background"
# chips).
[palettes.active]
color_fg0 = '#0a0a0a'
color_fg1 = '#99ff99'
color_bg1 = '#0a0a0a'
color_bg3 = '#1a1a1a'
color_blue = '#33ff33'
color_aqua = '#99ff99'
color_green = '#33ff33'
color_orange = '#99ff99'
color_purple = '#33ff33'
color_red = '#99ff99'
color_yellow = '#33ff33'
'@
        WeztermColors   = @'
-- Phosphor-green CRT terminal, single-hue monochrome
config.colors = {
	foreground = "#33FF33",
	background = "#0A0A0A",

	cursor_bg = "#33FF33",
	cursor_fg = "#0A0A0A",
	cursor_border = "#33FF33",

	selection_fg = "#0A0A0A",
	selection_bg = "#33FF33",

	split = "#99FF99",
	visual_bell = "#33FF33",

	ansi = {
		"#0A0A0A", -- black
		"#1A661A", -- red
		"#1A661A", -- green
		"#33FF33", -- yellow
		"#1A661A", -- blue
		"#1A661A", -- magenta
		"#33FF33", -- cyan
		"#33FF33", -- white
	},
	brights = {
		"#1A661A", -- bright black
		"#33FF33", -- bright red
		"#33FF33", -- bright green
		"#99FF99", -- bright yellow
		"#33FF33", -- bright blue
		"#33FF33", -- bright magenta
		"#99FF99", -- bright cyan
		"#99FF99", -- bright white
	},

	tab_bar = {
		background = "#0A0A0A",
		active_tab = {
			bg_color = "#33FF33",
			fg_color = "#0A0A0A",
		},
		inactive_tab = {
			bg_color = "#1A661A",
			fg_color = "#0A0A0A",
		},
		inactive_tab_hover = {
			bg_color = "#99FF99",
			fg_color = "#0A0A0A",
		},
		new_tab = {
			bg_color = "#0A0A0A",
			fg_color = "#33FF33",
		},
	},
}
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Terminal'
        ObsidianSnippet = @'
body {
	--the-color: #33FF33;
	--the-background-color: #0A0A0A;
}
'@
        ObsidianMode    = 'obsidian'
    }
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
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Catppuccin'
        ObsidianSnippet = @'
body {
	/* The real Catppuccin theme's ".theme-dark" selector alone already
	   gives full Mocha base colors, no class/plugin needed. --ctp-accent
	   is the one exception: it only gets set by an accent-picker class
	   (".ctp-accent-mauve" etc.), which needs the Style Settings plugin
	   to ever apply -- not installed, so pin it here directly instead.
	   Mauve rgb triplet is Catppuccin's own value, straight from
	   theme.css, not invented. */
	--ctp-accent: 203, 166, 247;
}
'@
        ObsidianMode    = 'obsidian'
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
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Obsidian gruvbox'
        # Empty -- this theme is a complete, self-contained dark palette
        # with no class/plugin-gated bits (unlike Catppuccin/Terminal), so
        # there's nothing to override. Still needs to be a real Set-
        # MarkedBlock call (not skipped) so the markers in the snippet
        # file stay valid for the next theme that swaps back in.
        ObsidianSnippet = ''
        ObsidianMode    = 'obsidian'
    }
    'vague'             = @{
        NvimColorscheme = 'vague'
        StarshipPalette = @'
# Vague (vague2k/vague.nvim, already installed -- uses its real palette
# 1:1, pulled from lua/vague/config/internal.lua, not invented). Standard
# dark-theme polarity: color_fg0 is dark bg (for the pastel accent chips
# below), color_fg1 is light fg (for the dark bg1/bg3 chips).
[palettes.active]
color_fg0 = '#141415'   # bg
color_fg1 = '#cdcdcd'   # fg
color_bg1 = '#141415'   # bg: matches the terminal background
color_bg3 = '#252530'   # line
color_blue = '#7e98e8'  # hint
color_aqua = '#9bb4bc'  # type
color_green = '#7fa563' # plus (git diff add)
color_orange = '#e0a363' # number
color_purple = '#aeaed1' # constant
color_red = '#d8647e'   # error
color_yellow = '#f3be7c' # warning
'@
        WeztermColors   = @'
-- Vague (vague2k/vague.nvim palette, ported 1:1) -- the one theme here
-- that runs transparent (window_background_opacity below), so the
-- wallpaper shows through.
config.colors = {
	foreground = "#CDCDCD",
	background = "#141415",

	cursor_bg = "#7E98E8",
	cursor_fg = "#141415",
	cursor_border = "#7E98E8",

	selection_fg = "#CDCDCD",
	selection_bg = "#333738",

	split = "#878787",
	visual_bell = "#F3BE7C",

	ansi = {
		"#141415", -- black
		"#D8647E", -- red
		"#7FA563", -- green
		"#F3BE7C", -- yellow
		"#6E94B2", -- blue
		"#BB9DBD", -- magenta
		"#9BB4BC", -- cyan
		"#CDCDCD", -- white
	},
	brights = {
		"#606079", -- bright black
		"#D8647E", -- bright red
		"#7FA563", -- bright green
		"#F3BE7C", -- bright yellow
		"#7E98E8", -- bright blue
		"#AEAED1", -- bright magenta
		"#B4D4CF", -- bright cyan
		"#CDCDCD", -- bright white
	},

	tab_bar = {
		background = "#1C1C24",
		active_tab = {
			bg_color = "#7E98E8",
			fg_color = "#141415",
		},
		inactive_tab = {
			bg_color = "#252530",
			fg_color = "#606079",
		},
		inactive_tab_hover = {
			bg_color = "#333738",
			fg_color = "#CDCDCD",
		},
		new_tab = {
			bg_color = "#1C1C24",
			fg_color = "#606079",
		},
	},
}
config.window_background_opacity = 0.85
'@
        ObsidianCssTheme = 'Minimal'
        ObsidianSnippet = @'
body {
	/* Minimal's own ".theme-dark" default is a neutral (zero-saturation)
	   dark gray -- close enough to vague's own near-black neutral bg
	   (#141415) that it's not worth overriding (Minimal's whole ethos is
	   "plain and gets out of your way" anyway). Only the accent needs
	   pinning: Minimal computes it from --accent-h/-s/-l (hsl()), default
	   is a blue-gray (h:201 s:17% l:50%) -- converted from vague's real
	   "hint" color #7e98e8 (precise RGB->HSL, not eyeballed: h=225.3
	   s=69.7% l=70.2%, rounded) so Obsidian's accent matches the editor/
	   terminal's.
	*/
	--accent-h: 225;
	--accent-s: 70%;
	--accent-l: 70%;
}
'@
        ObsidianMode    = 'obsidian'
    }
    'tokyonight'        = @{
        NvimColorscheme = 'tokyonight-night'
        StarshipPalette = @'
# Tokyo Night, "night" style (folke/tokyonight.nvim's own real palette --
# colors/tokyonight-night.lua on top of colors/tokyonight-storm.lua for
# the non-bg colors -- not invented). "night" chosen over the plugin's
# own default "moon" style specifically because the already-installed
# "Tokyo Night" Obsidian theme (themes/Tokyo Night/theme.css) hardcodes
# exactly this variant's RGB triplets -- picking it keeps nvim/WezTerm/
# Starship/Obsidian all pixel-consistent with zero manual color-math.
[palettes.active]
color_fg0 = '#0c0e14'   # bg_dark1 -- darkest, for the bright accent chips
color_fg1 = '#c0caf5'   # fg
color_bg1 = '#1a1b26'   # bg: matches the terminal background
color_bg3 = '#292e42'   # bg_highlight
color_blue = '#7aa2f7'
color_aqua = '#7dcfff'  # cyan
color_green = '#9ece6a'
color_orange = '#ff9e64'
color_purple = '#bb9af7' # magenta
color_red = '#f7768e'
color_yellow = '#e0af68'
'@
        WeztermColors   = @'
-- Tokyo Night, "night" style -- ported 1:1 from tokyonight.nvim's own
-- official extras/wezterm/tokyonight_night.toml (shipped by the plugin
-- author, not reinvented).
config.colors = {
	foreground = "#c0caf5",
	background = "#1a1b26",

	cursor_bg = "#c0caf5",
	cursor_fg = "#1a1b26",
	cursor_border = "#c0caf5",

	selection_fg = "#c0caf5",
	selection_bg = "#283457",

	split = "#7aa2f7",
	visual_bell = "#e0af68",

	ansi = {
		"#15161e", -- black
		"#f7768e", -- red
		"#9ece6a", -- green
		"#e0af68", -- yellow
		"#7aa2f7", -- blue
		"#bb9af7", -- magenta
		"#7dcfff", -- cyan
		"#a9b1d6", -- white
	},
	brights = {
		"#414868", -- bright black
		"#ff899d", -- bright red
		"#9fe044", -- bright green
		"#faba4a", -- bright yellow
		"#8db0ff", -- bright blue
		"#c7a9ff", -- bright magenta
		"#a4daff", -- bright cyan
		"#c0caf5", -- bright white
	},

	tab_bar = {
		background = "#1a1b26",
		active_tab = {
			bg_color = "#7aa2f7",
			fg_color = "#16161e",
		},
		inactive_tab = {
			bg_color = "#292e42",
			fg_color = "#545c7e",
		},
		inactive_tab_hover = {
			bg_color = "#292e42",
			fg_color = "#7aa2f7",
		},
		new_tab = {
			bg_color = "#1a1b26",
			fg_color = "#7aa2f7",
		},
	},
}
config.window_background_opacity = 1.0
'@
        ObsidianCssTheme = 'Tokyo Night'
        # Empty -- the installed "Tokyo Night" theme's own ".theme-dark"
        # block is a complete, self-contained palette with no class/
        # plugin-gated bits, and its hardcoded RGB triplets already match
        # tokyonight.nvim's real "night" style exactly (verified line by
        # line against colors/tokyonight-storm.lua + -night.lua), so
        # there's nothing left to override. Same pattern as gruvbox.
        ObsidianSnippet = ''
        ObsidianMode    = 'obsidian'
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

try {
    Set-ObsidianTheme -Theme $Theme -CssTheme $def.ObsidianCssTheme -CssBlock $def.ObsidianSnippet -Mode $def.ObsidianMode
} catch {
    Write-Log "obsidian update FAILED: $_"
}

Write-Log "done"
