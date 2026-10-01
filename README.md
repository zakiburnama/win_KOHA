# QuickMenu Light

A rofi-style quick action popup for Windows, built entirely in native AutoHotkey v2 — no external dependencies. Press a hotkey, pick an action with the arrow keys, hit Enter — done.

> A second implementation, **QuickMenu** (WebView2-based, custom HTML/CSS UI), is still under active development on the [`development`](https://github.com/zakiburnama/win_QuickMenu/tree/development) branch and isn't shipped here yet.

## How it works

- **AutoHotkey v2** creates a small, borderless, always-on-top window and draws the menu itself out of native `Text` controls — no ListBox, no browser engine, nothing else running in the background.
- Retro pixel-art look: reverse-video selection (inverted background/text) plus a `>` cursor, like an old game or terminal menu. Colors are switchable — see [Color themes](#color-themes) below.
- Up/Down/Enter are caught directly via `Hotkey`/`HotIfWinActive`, scoped to just this window.
- **Launched fresh on demand, with no persistent background process or hotkey listener.** `QuickMenuLight.exe` is launched by Lenovo Vantage's "User Defined Key" feature whenever the assigned key is pressed, shows the popup, runs the chosen action, and exits — nothing lingers in the background between presses.
- Dismisses like a mobile/web popup: **only Up/Down/Enter are "accepted" input** — any other key or clicking outside the popup closes it without running an action. Escape is the one exception: inside the Color Scheme submenu it steps back to the main menu instead of closing outright; pressed again from the main menu, it closes like everything else.

## Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/) — to run/edit [quickmenu_light.ahk](quickmenu_light.ahk) or recompile it

That's it — no runtime, no vendored library, no extra font files.

## Project structure

```
quickmenu/
├── quickmenu_light.ahk        # the whole app: GUI, theming, keyboard handling, actions
├── expense.ahk                # Pengeluaran logic, no GUI: parse input, categorize, write to the daily note
├── expense_popup.ahk          # Pengeluaran input window (separate Gui, not a menu mode)
├── tests/                     # console tests for expense*.ahk — see Pengeluaran below
├── QuickMenuLight.exe         # compiled build (see Running it below) — a genuine single file
├── quickmenu_settings.ini     # remembers your chosen color scheme — created on first use, gitignored
├── .gitignore
└── scripts/                   # everything quickmenu_light.ahk shells out to (Run(..., "Hide"))
    ├── lib.ps1                     # shared helpers (wallpaper P/Invoke, notifications, logging)
    ├── apply-theme.ps1             # fan-out script for "global" themes — see Color themes below
    ├── rotate-wallpaper.ps1        # advances the wallpaper on a timer — see Wallpaper slideshow below
    ├── install-wallpaper-rotation.ps1 # one-time setup: registers the Task Scheduler task that runs it
    ├── set-reminder.ps1            # registers a one-time reminder — see Reminders below
    ├── show-reminder.ps1           # fires a reminder's notification, then unregisters its own task
    ├── list-reminders.ps1          # prints pending reminders — backs the Cancel Reminder submenu
    ├── cancel-reminder.ps1         # unregisters one pending reminder by task name
    ├── toggle-wallpaper-slideshow.ps1 # enables/disables the 30-min auto-rotation task
    ├── get-prayer-times.ps1        # fetches today's prayer times — backs the Waktu Sholat submenu display
    ├── sync-prayer-reminders.ps1   # reconciles today's prayer-reminder tasks with settings — see Prayer times below
    ├── show-prayer-reminder.ps1    # fires a prayer reminder's notification, then unregisters its own task
    ├── install-prayer-schedule.ps1 # one-time setup: registers the daily Scheduled Task that runs the sync
    └── run-hidden.vbs              # launches a sibling .ps1 with zero console-window flash — see Gotchas
```

## Actions

Most items are defined in `RunAction()` in [quickmenu_light.ahk](quickmenu_light.ahk:392) — Color Scheme, Reminder, Wallpaper Slideshow, and Next Wallpaper are handled separately (they stay open or need extra state instead of firing once and closing):

| Menu item | Action |
|---|---|
| Open Terminal (Admin) | Launches Windows Terminal elevated (`Run("*RunAs wt.exe")`) — triggers a UAC prompt since QuickMenu Light itself runs unelevated. Always elevated (no non-admin option) — label says so |
| Open WezTerm | Launches WezTerm unelevated (`Run("wezterm-gui")` — not `wezterm.exe`, see [Gotchas](#gotchas) below) |
| Open WezTerm (Admin) | Same, elevated (`Run("*RunAs wezterm-gui")`) — triggers a UAC prompt |
| Obsidian | Launches Obsidian via its full path under `%LOCALAPPDATA%\Programs\Obsidian\` — it's a per-user Electron install, not on PATH (see [Gotchas](#gotchas)) |
| Pengeluaran | Opens a small input window to log an expense into the Obsidian daily note — see [Pengeluaran](#pengeluaran-expense-logging) below |
| Color Scheme | Opens the theme picker described below |
| Next Wallpaper | Advances the wallpaper by one image, on demand — see [Wallpaper slideshow](#wallpaper-slideshow) below. Works regardless of the Wallpaper Slideshow toggle's state. Stays open (like Color Scheme) so you can press it repeatedly to cycle through several — no in-popup feedback, the wallpaper change itself (visible on the desktop around the popup) is the confirmation |
| Wallpaper Slideshow (ON/OFF) | Toggles the automatic 30-min rotation on or off — see [Wallpaper slideshow](#wallpaper-slideshow) below. Label reflects current state; picking it flips and stays open, like Color Scheme |
| Reminder | Opens the duration picker, plus Cancel Reminder and Waktu Sholat — see [Reminders](#reminders) and [Prayer times](#prayer-times-waktu-sholat) below |
| Lock PC | Locks the workstation (`LockWorkStation`) |
| Sleep | Suspends the machine (`SetSuspendState`) |
| Close All Windows | Closes every open window (`WinClose` over `WinGetList()`) |
| Menu Settings | Always the last row, and can't be hidden itself. Opens a list of every item above with an `(ON)`/`(OFF)` label. Enter flips an item (the submenu stays open); `(OFF)` items disappear from the main menu. Escape goes back to the main menu with the changes applied. Stored as `HiddenMenus=` (item names joined by `\|`) in `quickmenu_settings.ini`. Empty or missing means everything is shown |

To add or change an item, edit the `baseItems` array and the matching `case` in `RunAction()`.

## Pengeluaran (expense logging)

Logs an expense with minimal typing and files it into the Obsidian vault's daily note (`Z0010-daily\YYYY-MM-DD.md`), so the data stays plain markdown that Obsidian dashboards can query. Category / need-vs-want sorting happens in the background.

**Input:** one line, `name amount` — e.g. `kopi susu jago 8k`. Several items at once: separate with a comma and a space (`ketoprak 15000, es teh 5000`). Amounts accept `8000`, `8k`, `8rb`, `15.000`, `1.5jt`, `Rp 15000`; the amount can also come first. Below it, **Tgl** defaults to today (type `kemarin`, `-2`, `2026-09-30`, `30-09-2026` or `30-09` for another day) and **Bayar** (payment method) defaults to whatever you used last (remembered as `ExpensePayment=` in `quickmenu_settings.ini`). A live preview shows how each item will be filed.

| Key | Action |
|---|---|
| Enter | Save. If an item isn't recognized, ask for its category first (below) |
| Ctrl+Enter | Review/change the category of **every** item first — a one-off correction, not learned |
| Esc | Close (or, while picking a category, go back to the input without saving) |

**Unknown items.** Rules live in the vault at `Z0014-financeules.md` (`keyword, keyword => category | need/want`, editable in Obsidian; longest keyword wins, except `hutang` rules which always win). When nothing matches, the window asks for a category: **1–9** = pangan, papan, sandang, transportasi, kesehatan, hiburan, sosial, infaq, investasi. Ambiguous categories (pangan, sandang) then ask **N**eed / **W**ant; the others imply it. The answer is appended to `rules.md` under "Dipelajari otomatis" (size/quantity words like `946ml` are dropped from the keyword), so the same item is never asked twice. **Enter** instead skips: the line is saved as `lainnya | want` with a `#review` tag and nothing is learned.

**What gets written** — one line per transaction under `## 💸 Finance`, in Dataview inline-field form:

```md
- [expense] kopi susu jago [amount:: 8000] [category:: pangan] [type:: want] [payment:: shopeepay]
```

The older 5-lines-per-expense blocks are left untouched (the new line goes after them, separated by a blank line); the template's `expense:: null` placeholder is removed when there are no real expenses yet. A missing daily note is created from `Template Daily New`, and a note without a Finance section gets one before "What i Eat". Line endings (CRLF/LF) are preserved per file, and the write goes through a temp file + rename. If any part of the input can't be parsed, nothing is written. `hutang` (debt) is its own category with type `-` — it isn't counted as need or want.

The vault path is hardcoded (`EXPENSE_VAULT` in [expense.ahk](expense.ahk)) — same single-user reasoning as the other hardcoded paths.

**Tests.** `powershell -File testsun-tests.ps1` runs `expense_test.ahk` (parser, rules, writer) and `expense_popup_test.ahk` (the popup's state machine) against a throwaway copy of a few real daily notes — never the real vault. The popup test calls the handlers directly rather than sending keystrokes, so the physical hotkeys aren't covered; check those by hand. An optional `testsows.tsv` (name, category, type per line, gitignored since it's personal data) enables a regression check of `rules.md` against past expenses.

### Dashboards (Obsidian)

[obsidian/](obsidian/) holds the Dataview side: `expense-dashboard/view.js` plus two notes, *Dashboard Pengeluaran Bulanan* and *…Tahunan* (month picked via the `bulan:` property, year via `tahun:`; empty = current). They show total, need/want share, per category and payment method, per day/month, and an "efficiency" block (want share, small repeated purchases, costliest keywords, biggest transactions, items still needing `#review`; `hutang` is reported separately). The view reads the daily notes' text directly, so both the new one-line format and the old 5-line blocks work, and a block with a missing field can't shift the ones after it. `powershell -File obsidian\install.ps1` copies it into the vault (the notes are copied only if missing, so your `bulan:` edits survive); the repo copy is the source of truth. Requires Dataview with JavaScript queries enabled. `tests\dashboard_test.js` (Node, mock `dv`) tests it on synthetic notes.

## Color themes

Selecting **Color Scheme** from the menu opens a submenu of the available themes. Pick one with Up/Down + Enter and it applies **immediately, live** — the submenu stays open so you can flip through a few before settling on one — and is written to `quickmenu_settings.ini` next to the exe, so it's remembered the next time QuickMenu Light opens. Press Escape to step back to the main menu, or Escape again (or any other key, or clicking outside) to close.

Every theme here is **global** — see [below](#global-themes-nvim--wezterm--starship--wallpaper) — there's no QuickMenu-only tier anymore.

| Theme | Look |
|---|---|
| `game_boy` | Classic DMG Game Boy 4-shade green |
| `amber` | Amber CRT terminal (black bg, amber text) |
| `green_term` | Phosphor-green CRT terminal |
| `catppuccin-mocha` | Catppuccin Mocha |
| `gruvbox` | Gruvbox Dark |
| `vague` | [vague.nvim](https://github.com/vague2k/vague.nvim)'s own palette, ported 1:1. The one theme where WezTerm also runs **transparent** (`window_background_opacity = 0.85`) — see below |
| `tokyonight` | [tokyonight.nvim](https://github.com/folke/tokyonight.nvim)'s "night" style — picked over the plugin's own default ("moon") because the installed Obsidian "Tokyo Night" theme hardcodes exactly the night/storm RGB values, keeping all five fan-out targets pixel-consistent with zero manual color conversion |

To add a new theme, add an entry to the `THEMES` map and its name to `THEME_NAMES` at the top of [quickmenu_light.ahk](quickmenu_light.ahk:13) — it'll show up in the picker automatically. Each theme is `{ bg, fg, selBg, selFg, bezel }`: normal background/text, selected-item background/text (reverse-video, like an old terminal menu highlight), and the window's own background color (shows as a thin border/bezel around the item list) — all hex, no `#` prefix. To make it global too, add a matching entry to `GLOBAL_THEMES` right below `THEMES`, and a registry entry in `scripts/apply-theme.ps1` (see the next section).

The font is the classic Windows raster font `Terminal`, chosen specifically because it renders as blocky pixels at small sizes with zero extra files — change the font name/size in `Render()` if you want something else.

### Global themes (nvim / WezTerm / Starship / wallpaper / Obsidian)

All seven entries are **global**: picking one restyles the QuickMenu Light popup like any other theme *and* fans out to the rest of the terminal/editor setup (plus the desktop wallpaper and an Obsidian vault) in one shot. There used to be a QuickMenu-only tier (retro CRT looks with "no natural editor/terminal equivalent") and an eighth theme, `vintage` — both retired once `game_boy`/`amber`/`green_term` got hand-written Neovim colorschemes (see the Neovim row below) and matching WezTerm/Starship palettes, closing that gap.

The fan-out is [apply-theme.ps1](scripts/apply-theme.ps1), launched hidden and non-blocking (`Run(..., "Hide")`) from `OnEnter()` whenever the chosen theme is in the `GLOBAL_THEMES` set. It touches five things, all hardcoded machine-specific paths (this is a personal single-user tool, not a portable one):

| Tool | File | How |
|---|---|---|
| Neovim | `%LOCALAPPDATA%\Temp\nvim\theme.txt` | Whole-file overwrite with the colorscheme name — the same file `theme.lua` (in the [dotfiles](https://github.com/zakiburnama/dotfiles) repo, `nvim/.config/nvim/lua/config/theme.lua`) reads on startup and writes on every `:colorscheme` change, so this is just "pretend the user ran `:colorscheme x`". Takes effect on next nvim launch, **not** in an already-running session. `catppuccin-mocha`/`gruvbox`/`vague`/`tokyonight` use the already-installed plugins of the same name (`vague`'s own palette is ported 1:1 into Starship/WezTerm too, pulled from its actual source rather than guessed; `tokyonight` explicitly pins the **"night"** style — `:colorscheme tokyonight-night` — rather than the plugin's own default "moon", chosen because the installed Obsidian theme hardcodes night/storm's exact RGB values, see the Obsidian row); `game_boy`/`amber`/`green_term` are hand-written `colors/*.lua` files in the dotfiles nvim config — no existing plugin matched these retro-monochrome looks closely enough, and writing them avoids adding new plugin dependencies for just 3 of 7 themes. Each sets ~60 highlight groups (classic + Treesitter `@` captures) from a small palette (bg/bg_alt/fg/fg_dim/fg_bright) with bold/italic/dim standing in for the hue variety a monochrome palette can't provide — `game_boy` is the one **light**-background theme in the set (the real DMG screen is light with dark pixels), so its `fg0`/`fg1` polarity (see the Starship row) is inverted relative to the rest. |
| Starship | `dotfiles/starship/.config/starship.toml` | Replaces the contents between `# BEGIN THEME PALETTE` / `# END THEME PALETTE` markers. The palette table is permanently named `[palettes.active]` (`palette = 'active'` never changes) specifically so the script never has to hunt for a varying table name — it only ever swaps what's *inside* those markers. Static TOML, no live reload: the new prompt appears on the next shell/tab, not the current one. |
| WezTerm | `dotfiles/wezterm/.config/wezterm/wezterm.lua` | Replaces the contents between `-- BEGIN THEME COLORS` / `-- END THEME COLORS` markers with a full new `config.colors = { ... }` block **and** `config.window_background_opacity` — both live inside the marked region together, so transparency is just another per-theme value, not a separate mechanism. Every theme sets `1.0` (opaque) except `vague`, which sets `0.85`. `tokyonight`'s colors are ported 1:1 from the plugin's own official `extras/wezterm/tokyonight_night.toml` (shipped by the `tokyonight.nvim` author), not reinvented. WezTerm auto-reloads its config on file change, so this one *does* apply live to already-open windows. |
| Desktop wallpaper | `dotfiles/wallpapers/<theme>/` | Sets the desktop wallpaper (Fill style) to the alphabetically-first `.jpg`/`.jpeg`/`.png`/`.bmp` found in that theme's folder, via the `SystemParametersInfo` Win32 API (shared with `rotate-wallpaper.ps1`, see below). Applies live immediately. Drop your own image(s) in `dotfiles/wallpapers/<theme>/` for any of the 7 — an empty or missing folder is treated as "not set up yet" and silently skipped, not an error. With more than one image in a folder, prefix filenames (e.g. `01-foo.jpg`) to control which one shows first — the pick is always deterministic (alphabetical), never random. |
| Obsidian | `Obsidian-Vault\.obsidian\appearance.json` + `snippets\quickmenu-theme.css` | Sets `"cssTheme"` to one of the **real, already-installed community themes** in the vault (`Catppuccin`, `Terminal`, `Obsidian gruvbox`, `Minimal`, or `Tokyo Night` — not a from-scratch reskin) for the bulk of the styling, plus `"theme"`: `"obsidian"` (dark) or `"moonstone"` (light, for `game_boy`), and ensures `"quickmenu-theme"` is in `"enabledCssSnippets"`. A small CSS snippet (marker-swapped between `/* BEGIN THEME COLORS */` / `/* END THEME COLORS */`, same pattern as everywhere else here) only overrides the handful of variables each theme leaves as a flavor/accent knob: `game_boy`/`amber`/`green_term` share the **Terminal** theme and just set its `--the-color`/`--the-background-color` (it's designed for exactly this, 2 variables total); `catppuccin-mocha` pins `--ctp-accent` to mauve (Catppuccin's own `.theme-dark` selector already gives full Mocha colors with zero config — accent is the one thing normally picked by a class the uninstalled "Style Settings" plugin would add); `vague` uses **Minimal** and pins its `--accent-h`/`-s`/`-l` (computed from vague's own `#7e98e8` hint-blue via a precise RGB→HSL conversion, not eyeballed) — Minimal's own neutral, zero-saturation dark-gray base is left alone, already close enough to vague's near-black bg that repainting it would be pure effort for no visible gain; `gruvbox` and `tokyonight` need no overrides at all (`Obsidian gruvbox` and `Tokyo Night` are complete, self-contained palettes — the latter's hardcoded RGB triplets were checked line-by-line and match `tokyonight.nvim`'s real "night" style exactly) so their snippet blocks are just empty. Snippets always load after the active theme, so these small overrides reliably win the cascade without ever touching the installed theme files themselves — safe even if one gets updated later. Like Starship, static config — Obsidian needs a reload (Ctrl+R) or re-toggling the snippet to pick up a change, it doesn't watch the file live; if Obsidian is left *open* while a theme is applied, it may also re-save its own stale in-memory appearance state over the change, so a full restart is the more reliable test. |

Adding another global theme: add an entry to the `$Themes` registry and the `ValidateSet` in `scripts/apply-theme.ps1` (remember the closing `config.window_background_opacity = 1.0` line inside `WeztermColors`, unless the new theme should be transparent too; and `ObsidianCssTheme`/`ObsidianSnippet`/`ObsidianMode` if you want Obsidian sync too — leave `ObsidianCssTheme` out entirely to skip that step (logged, not an error, same idea as an empty wallpaper folder)), a matching `THEMES`/`GLOBAL_THEMES` entry in `quickmenu_light.ahk`, a `dotfiles/wallpapers/<theme>/` folder, and either an installed Neovim colorscheme plugin or a hand-written `colors/<theme>.lua` (copy one of the existing three as a starting point — swap its 6 palette values, everything else stays the same shape). The marker-delimited approach means these files only ever get a wholesale block swap — never partial line edits — so a bad/missing marker fails loudly (`Set-MarkedBlock` throws if it doesn't find exactly one match) instead of silently corrupting the file.

Failures aren't shown anywhere (the script runs with no window) — check `%TEMP%\quickmenu-apply-theme.log` if a global theme pick didn't seem to take effect somewhere.

### Wallpaper slideshow

`apply-theme.ps1` only ever shows the *first* image in a theme's folder. [rotate-wallpaper.ps1](scripts/rotate-wallpaper.ps1) is what cycles through the rest, two ways:
- **Automatically**, every 30 min, via a Windows Scheduled Task (`QuickMenu Light - Wallpaper Rotation`, registered once via [install-wallpaper-rotation.ps1](scripts/install-wallpaper-rotation.ps1)) — it keeps advancing in the background without any process sitting idle in memory between ticks: Task Scheduler briefly spawns `powershell.exe`, it runs for well under a second, and exits.
- **On demand**, via the **Next Wallpaper** menu item — same script, same one-shot run, just triggered by `Run(..., "Hide")` from `quickmenu_light.ahk` instead of Task Scheduler. Picking it doesn't reset or interfere with the 30-min timer; it's the same rotation state (`quickmenu-wallpaper-rotation.json`) either way, so a manual "next" just makes the following scheduled tick advance from wherever you left it.

How it knows what to rotate:
- **Which theme**: `apply-theme.ps1` writes the active theme's name to `%TEMP%\quickmenu-active-theme.txt` every time a global theme is picked. `rotate-wallpaper.ps1` just reads that — it has no idea about `quickmenu_light.ahk` or the `$Themes` registry at all.
- **Which image**: `%TEMP%\quickmenu-wallpaper-rotation.json` remembers `{theme, lastFile}`. Each tick, if the saved theme still matches the active one, it advances to the next file alphabetically (wrapping around at the end); if the theme changed (or the saved filename no longer exists), it restarts at image #1 for the new folder instead of guessing.

Setup (already done once on this machine — only needed again after moving the repo, since the task's action hardcodes the script's path), run from the repo root:
```powershell
.\scripts\install-wallpaper-rotation.ps1
```
To stop it: `Unregister-ScheduledTask -TaskName 'QuickMenu Light - Wallpaper Rotation'`. To check on it: `Get-ScheduledTask -TaskName 'QuickMenu Light - Wallpaper Rotation' | Get-ScheduledTaskInfo` (see `LastTaskResult` — `0` means success) or tail `%TEMP%\quickmenu-apply-theme.log`, which both scripts write to.

The task runs as the current user, not SYSTEM — SYSTEM runs in session 0 and can't touch the interactive desktop's wallpaper, so `Register-ScheduledTask` deliberately leaves `-User`/`-Principal` at its default (current user, standard rights, no elevation needed).

**Turning the automatic rotation on/off**: the **Wallpaper Slideshow (ON/OFF)** menu item toggles just the 30-min Scheduled Task — [toggle-wallpaper-slideshow.ps1](scripts/toggle-wallpaper-slideshow.ps1) calls `Enable-ScheduledTask`/`Disable-ScheduledTask` on `QuickMenu Light - Wallpaper Rotation` to match. It has **no effect** on wallpaper changes from switching themes or from **Next Wallpaper** — both call `Set-DesktopWallpaper`/`rotate-wallpaper.ps1` directly, entirely separate code paths from the scheduled task. Picking it stays open and updates its own label immediately (same "flip and see the result" pattern as Color Scheme), while `quickmenu_settings.ini`'s `WallpaperSlideshow` key is what `quickmenu_light.ahk` reads at startup to show the right label without needing to query Task Scheduler (slow) just to draw the menu.

### Reminders

Selecting **Reminder** opens a submenu of fixed durations — `5 min`, `10 min`, `15 min`, `30 min`, `60 min` — plus a **Cancel Reminder** entry at the bottom. Picking a duration closes the popup right away instead of staying open, unlike Color Scheme — there's no "try a few" use case for a timer. Press Escape to step back to the main menu without setting anything.

Durations are a fixed list, not free text — this app has no text-input control anywhere (no `Edit` box, nothing to type into), and a reminder timer didn't seem worth being the first thing that breaks that. Want a different set of durations? Edit `REMINDER_OPTIONS` in [quickmenu_light.ahk](quickmenu_light.ahk:50) *and* the matching `[ValidateSet(...)]` in [set-reminder.ps1](scripts/set-reminder.ps1) — they have to stay in sync, since the AHK side just strips `" min"` off the chosen label and passes the number straight through.

Picking a duration runs [set-reminder.ps1](scripts/set-reminder.ps1) (hidden, non-blocking, same `Run(..., "Hide")` pattern as everything else here), which:
1. Registers a **one-time** Task Scheduler task (unique name, timestamped, so overlapping reminders don't collide) that fires [show-reminder.ps1](scripts/show-reminder.ps1) at the target time — same "nothing idle in memory while waiting" reasoning as the wallpaper rotation task.
2. Shows an immediate confirmation balloon ("Reminder set for 3:45 PM (10 min)") so you know it actually took, since the popup itself gives no feedback before closing.

When the task fires, `show-reminder.ps1` shows a balloon + beep ("Reminder: 10 minute(s) is up.") and then **unregisters its own task** — Task Scheduler doesn't clean up one-time tasks on its own, so without this step you'd accumulate a stale task per reminder forever.

Reminders survive a restart or sleep — Task Scheduler tasks are stored on disk, not in memory, and `-StartWhenAvailable` (set when the task is registered) means a reminder that should've fired while the machine was off/asleep fires as soon as it's back, instead of being silently skipped.

**Checking what's pending, or cancelling one**: inside the Reminder submenu, picking **Cancel Reminder** runs [list-reminders.ps1](scripts/list-reminders.ps1) and shows each pending reminder as `"10 min -> 3:45 PM"` (or `(no reminders set)` if there's nothing pending — picking that does nothing, only Escape backs out, which from here goes back to the Reminder submenu specifically, not all the way to the main menu). Picking one runs [cancel-reminder.ps1](scripts/cancel-reminder.ps1) with that reminder's exact task name, which `Unregister-ScheduledTask`s it and confirms with a notification.

This is one of **two places in the app that wait on PowerShell** instead of firing it hidden/non-blocking (the other is Waktu Sholat, below) — `list-reminders.ps1` has to actually run and return its output *before* the submenu can be sized and drawn, so opening Cancel Reminder has a brief (~0.2–0.4s) delay where the rest of QuickMenu Light is instant. `quickmenu_light.ahk`'s `GetPendingReminders()` gets that output via `RunWait(cmd, , "Hide")` + `FileRead()` on a file `list-reminders.ps1` writes to (`%TEMP%\quickmenu-pending-reminders.txt`) — see [Gotchas](#gotchas) for why it's not `WScript.Shell.Exec` + `StdOut.ReadAll()` (the original implementation, which broke the popup).

You can check the same thing manually any time without opening QuickMenu Light: `Get-ScheduledTask | Where-Object { $_.TaskName -like 'QuickMenu Light - Reminder *' }`.

Both scripts log to `%TEMP%\quickmenu-apply-theme.log`, same file every other script here uses.

### Prayer times (Waktu Sholat)

Inside the Reminder submenu, **Waktu Sholat** opens a settings submenu: a master **Waktu Sholat (ON/OFF)** toggle, then one row per daily prayer — **Subuh**, **Dzuhur**, **Ashar**, **Maghrib**, **Isya** — each showing today's actual time (e.g. `Dzuhur 11:50 (ON)`) and independently toggleable. Every row flips and stays open, same pattern as Wallpaper Slideshow and Color Scheme. Escape backs out to the Reminder submenu, not all the way to main (same as Cancel Reminder).

Like Cancel Reminder, opening this submenu **waits on PowerShell** ([get-prayer-times.ps1](scripts/get-prayer-times.ps1), via the same `RunWait(..., "Hide")` + `FileRead()` pattern) to fetch today's times before it can draw rows with times in them — same brief delay, same reason. If the fetch fails (offline, API down), the rows still show without a time rather than the submenu failing to open.

**Data source**: the free [myQuran API](https://api.myquran.com/doc) (`api.myquran.com`, sourced from Kementerian Agama RI / Kemenag), no API key needed. City is hardcoded in `lib.ps1` (`$PrayerCityId`/`$PrayerCityName`, currently Jakarta) rather than a setting — same "personal single-user tool, hardcoding beats config indirection" reasoning as `$WallpapersRoot`. To change cities, look up the new id and edit both values together:
```powershell
curl "https://api.myquran.com/v3/sholat/kabkota/cari/<city-keyword>"
```

**Why this needed its own scheduling mechanism**, separate from the fixed-duration Reminder system: prayer times are a *different time every day* (and drift gradually through the year), so a reminder can't just be "N minutes from now" — it has to be "whatever Dzuhur's time is today." [sync-prayer-reminders.ps1](scripts/sync-prayer-reminders.ps1) is the core of this:
1. It's **idempotent** — always starts by cancelling every `QuickMenu Light - Sholat * <today>` task, then re-registers one-time tasks (same self-unregistering pattern as regular reminders, firing [show-prayer-reminder.ps1](scripts/show-prayer-reminder.ps1)) only for prayers that are master-enabled, individually enabled, *and* haven't already happened today — flipping Subuh off after it already fired this morning doesn't try to un-fire it, and toggling something on at 2pm doesn't try to schedule this morning's Subuh for today.
2. It's called from **two places**: a recurring Scheduled Task (`QuickMenu Light - Sholat Daily Refresh`, daily at 00:05, registered once via [install-prayer-schedule.ps1](scripts/install-prayer-schedule.ps1)) that sets up each new day, and directly (hidden, non-blocking) from `quickmenu_light.ahk` every time a Waktu Sholat toggle is flipped, so a change takes effect for the rest of *today* instead of waiting until tomorrow's refresh.

Toggle state lives in `quickmenu_settings.ini` (`SholatEnabled` for the master, `SholatSubuh`/`SholatDzuhur`/`SholatAshar`/`SholatMaghrib`/`SholatIsya` individually — default missing = off for the master, on for each prayer) — read by both `quickmenu_light.ahk` (`IniRead`, for the menu) and, for the first time in this codebase, by a PowerShell script (`Get-IniValue` in `lib.ps1`, for the scheduler). AHK's `IniWrite` saves this file as **UTF-16LE with a BOM** (confirmed via hex dump) — `Get-IniValue` reads with `-Encoding Unicode` (Windows PowerShell 5.1's name for that) specifically because of this; the default encoding produces null-byte garbage that matches nothing. PowerShell only ever *reads* this file — AHK remains the sole writer.

## Running it

**As a script** (for development/testing) — requires AutoHotkey v2 installed, menu shows immediately on launch:
```
quickmenu_light.ahk
```

**As a compiled exe:**
```
Ahk2Exe.exe /in quickmenu_light.ahk /out QuickMenuLight.exe /base "<path to AutoHotkey64.exe>"
```
Note: Ahk2Exe's argument parser breaks on spaces in `/base` — use the 8.3 short path (e.g. `C:\PROGRA~1\AUTOHO~1\v2\AUTOHO~2.EXE`) if your AutoHotkey install lives under `Program Files`.

`QuickMenuLight.exe` is a genuine single file with no other dependencies — copy it anywhere.

## Wiring it to a hotkey (Lenovo Vantage)

Since the exe has no hotkey listener of its own:

1. Open **Lenovo Vantage** → **Device settings** → **Input** → **User defined key**.
2. Pick the key (e.g. F12), set the action to **Open applications and files**.
3. In the picker, only Start Menu-registered apps are browsable — the exe's real path won't show up directly. Create a shortcut to it inside `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` first, then it will appear in the list.
4. Select it, save. Pressing the key now launches QuickMenu Light directly — no AHK process runs in between key presses.

## Gotchas

A few non-obvious fixes that shaped this file, in case you're extending it:

- **Centering**: get the window size from `Gui.Show(...)` with explicit `w`/`h`/`x`/`y` computed up front, not from `Show("AutoSize")` followed by `GetPos()`/`Move()` — reading the size back out after an AutoSize show and repositioning afterward isn't reliable (it renders once at the wrong spot first).
- **"Close All Windows" closing nothing**: the popup's own Gui window is itself in `WinGetList()` while it's still open. If it gets `WinClose()`d as part of the loop, that fires the `Close` event and calls `ExitApp()` immediately, cutting the loop short before any *other* window closes. Fix: call `myGui.Destroy()` first — `Destroy()`, unlike `WinClose()`, doesn't fire the `Close` event.
- **`wezterm.exe` is a console-subsystem launcher**, not the GUI app — running it directly leaves a visible console window behind `wezterm-gui.exe` that closes together with the terminal. Launch `wezterm-gui.exe` directly instead.
- **Dismiss-on-blur reentrancy**: our own `guiObj.Destroy()` (called before running the chosen action) synchronously re-triggers `WM_ACTIVATE(inactive)` on that same window, which reenters the very deactivate-handler that's supposed to close the popup on focus loss — and calls `ExitApp()` *before* the actual action (`Run()`, `DllCall()`, ...) executes. Symptom: selecting any item just closed the popup and did nothing else. Fixed with a plain guard: `myGui.Closing := true` right before our own deliberate `Destroy()`, checked by the `WM_ACTIVATE`/`WM_KEYDOWN` handlers before they call `ExitApp()`.
- **Resizing/repositioning an already-visible window with `Gui.Move(x, y, w, h)` (raw numbers) drifted further off-center each time** — needed when switching between the main menu and the Color Scheme submenu, since they have different row counts and therefore different heights. `Gui.Move()` didn't agree with the coordinates `Gui.Show("x# y# w# h#")` (string options) uses for the same window. Fix: call `Show(...)` again instead of `Move()` to reposition — pass `NoActivate` too, so re-showing an already-active window doesn't fire a spurious `WM_ACTIVATE` that the dismiss-on-blur handler above could mistake for real focus loss.
- **`Run("Obsidian.exe")` (bare name) failed silently** — unlike `wt.exe`/`wezterm-gui`, Obsidian isn't a registered PATH alias; as a per-user Electron install it lives under `%LOCALAPPDATA%\Programs\Obsidian\Obsidian.exe` and nowhere Windows' default search order looks. General rule when adding a new app to the menu: first try `where <name>.exe` in a terminal — if that finds nothing, get the exe's real path either from Task Manager (right-click the running process → *Open file location*) or its Start Menu shortcut (*More → Open file location*, or check the shortcut's *Target*), then `Run()` that full path instead of a bare name.
- **A console window briefly flashed on screen every 30 min** (whenever the wallpaper rotation task fired) even though its action passed `-WindowStyle Hidden` to `powershell.exe`. Root cause: `powershell.exe` is a *console-subsystem* app — Windows creates the console host window (`conhost.exe`) as part of process startup, before PowerShell's own code gets a chance to read `-WindowStyle Hidden` and hide it. That window-creation-then-hide sequencing is what flashes; it's a known PowerShell behavior; see [PowerShell/PowerShell#3028](https://github.com/PowerShell/PowerShell/issues/3028). `-Hidden` on `New-ScheduledTaskSettingsSet` does **not** fix this — that setting only controls the task's visibility inside Task Scheduler's own UI, unrelated to the launched process's window. Fix: [run-hidden.vbs](scripts/run-hidden.vbs) — launched via `wscript.exe` (a *GUI-subsystem* app, so no console window is ever created at all) instead of calling `powershell.exe` directly, it re-launches the target script as a genuinely invisible detached process (`WScript.Shell.Run(cmd, 0, False)`). Used by both Task Scheduler-triggered scripts ([install-wallpaper-rotation.ps1](scripts/install-wallpaper-rotation.ps1), and the one-time task [set-reminder.ps1](scripts/set-reminder.ps1) registers) — not needed for anything QuickMenu Light launches directly via AHK's `Run(..., "Hide")`, since that wasn't where the reported flashing was coming from.
- **Cancel Reminder closed the whole popup instead of opening**: `GetPendingReminders()` originally used `ComObject("WScript.Shell").Exec(...)` + `StdOut.ReadAll()` to run `list-reminders.ps1` synchronously and capture its output. Unlike `.Run()`, WSH's `.Exec()` method has **no window-hiding option at all** — the spawned `powershell.exe` console was always visible, if briefly. That window stealing the foreground fired `WM_ACTIVATE(inactive)` on the QuickMenu popup, which the dismiss-on-blur handler (`CloseOnDeactivate`, see above) correctly-but-unhelpfully read as "user clicked away" and closed the popup with `ExitApp()` — before `GetPendingReminders()` even returned. Symptom: click Cancel Reminder, a `powershell.exe` window flashes, the whole popup vanishes instead of showing the list. Fix: `list-reminders.ps1` now writes its output to a file (`%TEMP%\quickmenu-pending-reminders.txt`) instead of stdout, and `GetPendingReminders()` reads it back via `RunWait(cmd, , "Hide")` + `FileRead()` — the same `Run()`/`RunWait()` `"Hide"` mechanism already proven to work everywhere else in this app, which `.Exec()` simply doesn't offer.
