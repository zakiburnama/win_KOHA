#Requires AutoHotkey v2.0
#SingleInstance Force
#Include expense.ahk
#Include expense_popup.ahk
#Include app_search.ahk

; KOHA -- versi native AHK murni, tanpa WebView2/HTML sama sekali.
; Tampil instan (tidak perlu nyalain proses browser terpisah). Tampilan retro
; pixel-art dengan font raster "Terminal" (bawaan Windows, tanpa file
; tambahan) dan seleksi warna terbalik + kursor ">" ala menu game jadul.
; (Versi WebView2 yang lebih berat ada di branch development, dengan nama
; lamanya, QuickMenu.)

; bg/fg = warna normal (background/teks); selBg/selFg = warna item terpilih
; (biasanya kebalikan dari bg/fg -- "reverse video" ala terminal jadul);
; bezel = warna window di sekeliling item (lihat myGui.BackColor di ShowMenu).
THEMES := Map(
    "game_boy", { bg: "9BBC0F", fg: "0F380F", selBg: "0F380F", selFg: "9BBC0F", bezel: "0F380F" },
    "amber",    { bg: "1A0F00", fg: "FFB000", selBg: "FFB000", selFg: "1A0F00", bezel: "FFB000" },
    "green_term", { bg: "0A0A0A", fg: "33FF33", selBg: "33FF33", selFg: "0A0A0A", bezel: "33FF33" },
    "catppuccin-mocha", { bg: "1E1E2E", fg: "CDD6F4", selBg: "CBA6F7", selFg: "1E1E2E", bezel: "11111B" },
    "gruvbox",  { bg: "282828", fg: "EBDBB2", selBg: "FE8019", selFg: "282828", bezel: "1D2021" },
    "vague",    { bg: "141415", fg: "CDCDCD", selBg: "6E94B2", selFg: "141415", bezel: "1C1C24" },
    "tokyonight", { bg: "1A1B26", fg: "C0CAF5", selBg: "7AA2F7", selFg: "1A1B26", bezel: "0C0E14" },
)
THEME_NAMES := ["game_boy", "amber", "green_term", "catppuccin-mocha", "gruvbox", "vague", "tokyonight"]

; Every theme is "global" now -- picking any of them, besides restyling
; KOHA's own popup, also fans out via apply-theme.ps1 to
; Neovim/WezTerm/Starship/wallpaper (see README.md). Custom minimal
; colorschemes were hand-written for game_boy/amber/green_term (no ready-
; made Neovim plugin matches these retro-monochrome looks closely enough,
; and this avoids adding a new plugin dependency to the dotfiles repo just
; for 1 of the 3) -- see dotfiles/nvim/.config/nvim/colors/. vague uses
; the already-installed vague.nvim plugin as-is, and is the one theme
; that also makes WezTerm transparent (window_background_opacity in
; apply-theme.ps1's WeztermColors for it).
GLOBAL_THEMES := Map("game_boy", true, "amber", true, "green_term", true, "catppuccin-mocha", true, "gruvbox", true, "vague", true, "tokyonight", true)

; Tema aktif dibaca dari file settings (dibuat/diupdate otomatis lewat menu
; "Color Scheme" di bawah) -- kalau belum ada / rusak, fallback ke "amber".
SETTINGS_FILE := A_ScriptDir "\koha_settings.ini"
ACTIVE_THEME := IniRead(SETTINGS_FILE, "Settings", "Theme", "amber")
if !THEMES.Has(ACTIVE_THEME)
    ACTIVE_THEME := "amber"

; On/off buat rotasi wallpaper OTOMATIS tiap 30 menit doang (Scheduled
; Task-nya sendiri) -- gak ngaruh ke wallpaper pas ganti tema atau pas klik
; "Next Wallpaper" manual, dua-duanya jalur kode terpisah. Baca dari INI
; biar render menu instan (gak perlu query Task Scheduler yang lebih
; lambat tiap buka KOHA) -- lihat ToggleWallpaperSlideshow().
WALLPAPER_SLIDESHOW_ENABLED := IniRead(SETTINGS_FILE, "Settings", "WallpaperSlideshow", "1") = "1"

; Durasi tetap (bukan input teks bebas) -- konsisten sama gaya keyboard-only
; (Up/Down/Enter) yang dipakai di seluruh app ini, gak ada Edit control sama
; sekali. Lihat set-reminder.ps1 buat ValidateSet yang sama persis.
; "Waktu Sholat" & "Cancel Reminder" digabung ke sini (bukan menu utama
; lagi) -- munculnya di submenu Reminder, di bawah pilihan durasi.
REMINDER_OPTIONS := ["5 min", "10 min", "15 min", "30 min", "60 min", "Waktu Sholat", "Cancel Reminder"]

; Urutan tampilan/toggle 5 waktu sholat -- harus sama persis sama urutan
; key $PrayerDisplayNames di lib.ps1 (PowerShell), walau di sini cuma
; dipakai buat index row (1=master, 2=Subuh, ..., 6=Isya), bukan buat
; nyocokin nama field API.
PRAYER_NAMES := ["Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"]

baseItems := [
  "Search Apps",
  "Open Terminal (Admin)",
  "Open WezTerm",
  "Open WezTerm (Admin)",
  "Obsidian",
  "Claude Code",
  "Pengeluaran",
  "Color Scheme",
  "Next Wallpaper",
  "Wallpaper Slideshow",
  "Reminder",
  "Lock PC",
  "Sleep",
  "Close All Windows",
]

; Item terakhir menu utama, SELALU tampil (gak ikut daftar toggle-nya
; sendiri) -- kalau bisa di-OFF-in juga, sekali semua item disembunyiin
; gak ada jalan balik lagi dari dalam KOHA selain edit INI manual.
MENU_SETTINGS_ITEM := "Menu Settings"

; Item baseItems yang disembunyiin dari menu utama, disimpan sebagai satu
; key "HiddenMenus" (nama item dipisah "|", misal "Obsidian|Sleep") --
; cukup 1 IniRead pas startup (bukan 11), dan default kosong = semua
; tampil, jadi INI lama yang belum punya key ini tetap jalan apa adanya.
HIDDEN_MENUS := Map()
for name in StrSplit(IniRead(SETTINGS_FILE, "Settings", "HiddenMenus", ""), "|")
    if name != ""
        HIDDEN_MENUS[name] := true

; "KOHA.exe search" langsung buka pencarian app tanpa lewat menu utama
; (buat dipasang di tombol/shortcut terpisah).
if A_Args.Length && A_Args[1] = "search"
    ShowAppSearchPopup(THEMES[ACTIVE_THEME])
else
    ShowMenu()

ShowMenu() {
    global baseItems, THEMES, THEME_NAMES, GLOBAL_THEMES, REMINDER_OPTIONS, PRAYER_NAMES, ACTIVE_THEME, SETTINGS_FILE, WALLPAPER_SLIDESHOW_ENABLED, MENU_SETTINGS_ITEM, HIDDEN_MENUS

    margin := 6
    itemH := 26
    w := 300
    x := (A_ScreenWidth - w) / 2
    contentW := w - margin * 2
    ; +1 = baris "Menu Settings" di bawah baseItems (lihat CurrentList()).
    maxRows := Max(baseItems.Length + 1, THEME_NAMES.Length, REMINDER_OPTIONS.Length)

    myGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "KOHA")
    myGui.OnEvent("Close", (*) => ExitApp())

    ; state.mode "main" = menu utama, "theme" = submenu Color Scheme,
    ; "reminder" = submenu Reminder, "cancel" = submenu Cancel Reminder
    ; (anak "reminder"), "sholat" = submenu Waktu Sholat (anak "reminder"
    ; juga), "menus" = submenu Menu Settings (toggle tampil/sembunyi item
    ; menu utama). state.theme (bukan variabel lokal biasa) supaya bisa diganti
    ; dari dalam OnEnter() saat pilih tema baru -- closure AHK aman nulis
    ; property object, tapi tidak dijamin aman nulis-ulang variabel lokal
    ; biasa dari nested func. state.cancelList/sholatTimes sama alasannya
    ; -- diisi SwitchToCancelMode()/SwitchToSholatMode() sebelum
    ; SwitchMode() dipanggil. ctrls dibuat sebanyak baris TERBANYAK dari
    ; baseItems/THEME_NAMES/REMINDER_OPTIONS (state.cancelList dan submenu
    ; sholat -- 6 baris, 5 sholat + master -- gak ikut dihitung eksplisit,
    ; tapi baseItems udah lebih panjang dari keduanya jadi aman). Baris
    ; yang gak dipakai di-nonaktifkan (Visible=false) tergantung mode aktif.
    state := {
        selected: 1, mode: "main", theme: THEMES[ACTIVE_THEME],
        cancelList: [], slideshowEnabled: WALLPAPER_SLIDESHOW_ENABLED,
        sholatTimes: Map(), sholatMaster: false, sholatToggles: Map()
    }
    ; BackColor dipakai sebagai "bezel" di sekeliling item -- Text control di
    ; bawah cuma nutup area x/y=margin..w/h-margin, sisanya nampilin ini.
    myGui.BackColor := state.theme.bezel
    ctrls := []
    loop maxRows {
        y := margin + (A_Index - 1) * itemH
        ; 0x200 = SS_CENTERIMAGE, biar teks center vertikal di baris masing-masing.
        ctrl := myGui.Add("Text", "x" margin " y" y " w" contentW " h" itemH " 0x200")
        ctrl.OnEvent("Click", OnItemClick)
        ctrls.Push(ctrl)
    }

    CurrentList() {
        if state.mode = "main" {
            ; Cuma "Wallpaper Slideshow" yang butuh label dinamis -- item
            ; lain di baseItems dilewatin apa adanya.
            ; Item yang di-OFF-in di Menu Settings dilewatin total (bukan
            ; cuma disembunyiin barisnya) -- jadi tinggi window, navigasi
            ; Up/Down, dan index state.selected semua otomatis ngikut.
            list := []
            for item in baseItems {
                if HIDDEN_MENUS.Has(item)
                    continue
                list.Push(item = "Wallpaper Slideshow" ? item (state.slideshowEnabled ? " (ON)" : " (OFF)") : item)
            }
            list.Push(MENU_SETTINGS_ITEM)
            return list
        }
        if state.mode = "menus" {
            ; Selalu semua baseItems (urutan asli), index baris = index di
            ; baseItems -- ToggleMenuVisibility() ngandelin ini.
            list := []
            for item in baseItems
                list.Push(item (HIDDEN_MENUS.Has(item) ? " (OFF)" : " (ON)"))
            return list
        }
        if state.mode = "reminder"
            return REMINDER_OPTIONS
        if state.mode = "cancel" {
            if state.cancelList.Length = 0
                return ["(no reminders set)"]
            list := []
            for r in state.cancelList
                list.Push(r.label)
            return list
        }
        if state.mode = "sholat" {
            ; Baris 1 = master, baris 2..6 = PRAYER_NAMES -- urutan INDEX
            ; ini yang dipakai OnEnter() buat nentuin mana yang di-toggle,
            ; bukan parsing ulang teks label (labelnya dinamis, ada jam-nya).
            list := ["Waktu Sholat" (state.sholatMaster ? " (ON)" : " (OFF)")]
            for name in PRAYER_NAMES {
                time := state.sholatTimes.Has(name) ? state.sholatTimes[name] " " : ""
                on := state.sholatToggles.Has(name) ? state.sholatToggles[name] : true
                list.Push(name " " time (on ? "(ON)" : "(OFF)"))
            }
            return list
        }
        list := []
        for name in THEME_NAMES
            list.Push(name = ACTIVE_THEME ? name " (current)" : name)
        return list
    }

    Render() {
        list := CurrentList()
        for i, ctrl in ctrls {
            if i > list.Length {
                ctrl.Visible := false
                continue
            }
            ctrl.Visible := true
            if i = state.selected {
                ctrl.SetFont("s10 c" state.theme.selFg, "Terminal")
                ctrl.Opt("Background" state.theme.selBg)
                ctrl.Text := "> " list[i]
            } else {
                ctrl.SetFont("s10 c" state.theme.fg, "Terminal")
                ctrl.Opt("Background" state.theme.bg)
                ctrl.Text := "  " list[i]
            }
        }
    }

    ; Ganti mode (main <-> theme) berarti jumlah baris ikut berubah, jadi
    ; window di-resize ulang (tinggi menyesuaikan + tetap center) sebelum render.
    ; PENTING: pakai Show() lagi (bukan Move()) -- Move() dengan angka mentah
    ; ternyata tidak konsisten dengan koordinat yang dipakai Show("x# y#..."),
    ; bikin window malah geser (kemungkinan mismatch DPI antara method call
    ; langsung vs string options, sama seperti kasus di versi WebView2).
    ; NoActivate supaya reposisi ini tidak memicu WM_ACTIVATE yang bisa
    ; disalahartikan CloseOnDeactivate sebagai window kehilangan fokus.
    SwitchMode(newMode) {
        state.mode := newMode
        state.selected := 1
        newH := CurrentList().Length * itemH + margin * 2
        newY := (A_ScreenHeight - newH) / 2
        myGui.Show("w" w " h" newH " x" x " y" newY " NoActivate")
        Render()
    }

    ; Dua submenu di app ini yang NUNGGU PowerShell selesai dulu (RunWait,
    ; bukan Run() async kayak di tempat lain): Cancel Reminder di sini, dan
    ; SwitchToSholatMode() di bawah. Keduanya butuh data yang BENERAN
    ; akurat (daftar reminder pending / jam sholat hari ini) SEBELUM bisa
    ; nentuin tinggi window & isi baris-barisnya, jadi gak bisa async kayak
    ; fan-out tema/wallpaper. Konsekuensinya: buka submenu ini ada jeda
    ; kecil (proses powershell.exe baru nyala), beda dari bagian lain
    ; KOHA yang instan.
    SwitchToCancelMode() {
        state.cancelList := GetPendingReminders()
        SwitchMode("cancel")
    }

    ; Sinkron juga (lihat komentar SwitchToCancelMode) -- ambil jam sholat
    ; hari ini dari get-prayer-times.ps1 (biar labelnya nampilin jam,
    ; misal "Dzuhur 11:50"), plus baca status toggle master + 5 individual
    ; langsung dari INI (IniRead native AHK, instan, gak perlu subprocess
    ; kedua). Kalau fetch API gagal (offline dll), state.sholatTimes tetap
    ; kosong -- CurrentList() udah nangani itu, baris-nya tampil tanpa jam.
    SwitchToSholatMode() {
        state.sholatTimes := GetPrayerTimesForDisplay()
        state.sholatMaster := IniRead(SETTINGS_FILE, "Settings", "SholatEnabled", "0") = "1"
        state.sholatToggles := Map()
        for name in PRAYER_NAMES
            state.sholatToggles[name] := IniRead(SETTINGS_FILE, "Settings", "Sholat" name, "1") = "1"
        SwitchMode("sholat")
    }

    ; Sama pola kayak ToggleWallpaperSlideshow -- flip + tetap kebuka, INI
    ; ditulis dulu (sumber kebenaran buat render berikutnya), baru
    ; fire-and-forget sync-prayer-reminders.ps1 buat nyocokin Scheduled
    ; Task hari ini sama toggle yang baru. idx 1 = baris master, idx 2..6
    ; = PRAYER_NAMES[idx-1] -- lihat CurrentList() soal urutan barisnya.
    ToggleSholatSetting(idx) {
        if idx = 1 {
            state.sholatMaster := !state.sholatMaster
            IniWrite(state.sholatMaster ? "1" : "0", SETTINGS_FILE, "Settings", "SholatEnabled")
        } else {
            name := PRAYER_NAMES[idx - 1]
            state.sholatToggles[name] := !state.sholatToggles[name]
            IniWrite(state.sholatToggles[name] ? "1" : "0", SETTINGS_FILE, "Settings", "Sholat" name)
        }
        Render()
        scriptPath := A_ScriptDir "\scripts\sync-prayer-reminders.ps1"
        Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '"', , "Hide")
    }

    ; Flip + tetap kebuka, sama pola kayak ToggleSholatSetting -- tapi
    ; murni lokal (cuma INI), gak ada PowerShell yang perlu dijalanin.
    ; Perubahannya baru keliatan di menu utama pas Escape balik ke sana
    ; (SwitchMode("main") ngitung ulang tinggi window dari list baru).
    ToggleMenuVisibility(idx) {
        item := baseItems[idx]
        if HIDDEN_MENUS.Has(item)
            HIDDEN_MENUS.Delete(item)
        else
            HIDDEN_MENUS[item] := true
        ; Tulis ulang dalam urutan baseItems (bukan urutan Map) biar isi
        ; INI stabil & gampang dibaca kalau dibuka manual.
        hidden := ""
        for name in baseItems
            if HIDDEN_MENUS.Has(name)
                hidden .= (hidden = "" ? "" : "|") name
        IniWrite(hidden, SETTINGS_FILE, "Settings", "HiddenMenus")
        Render()
    }

    ; Flip + tetap kebuka (kayak Color Scheme) -- bukan RunAction, biar
    ; kamu bisa langsung lihat label-nya berubah tanpa harus buka-tutup
    ; KOHA ulang buat konfirmasi tersimpan. Nulis ke INI dulu (sumber
    ; kebenaran buat render menu berikutnya, instan) baru fire-and-forget
    ; toggle-wallpaper-slideshow.ps1 buat Enable/Disable Scheduled Task-nya
    ; yang beneran -- INI dan Scheduled Task jadi 2 hal yang disinkronkan
    ; setiap toggle, bukan satu sumber tunggal.
    ToggleWallpaperSlideshow() {
        global WALLPAPER_SLIDESHOW_ENABLED
        state.slideshowEnabled := !state.slideshowEnabled
        WALLPAPER_SLIDESHOW_ENABLED := state.slideshowEnabled
        IniWrite(state.slideshowEnabled ? "1" : "0", SETTINGS_FILE, "Settings", "WallpaperSlideshow")
        Render()
        scriptPath := A_ScriptDir "\scripts\toggle-wallpaper-slideshow.ps1"
        Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '" -Enabled ' (state.slideshowEnabled ? "1" : "0"), , "Hide")
    }

    ; Tetap kebuka (bukan RunAction) -- biar bisa dipencet berkali-kali buat
    ; "scroll" ganti-ganti wallpaper tanpa harus buka-tutup KOHA tiap
    ; kali. Gak ada state di popup ini sendiri yang perlu di-Render() ulang
    ; -- feedback-nya keliatan langsung di wallpaper desktop di belakang
    ; popup, bukan di dalam popup-nya.
    AdvanceWallpaper() {
        Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' A_ScriptDir '\scripts\rotate-wallpaper.ps1"', , "Hide")
    }

    OnItemClick(ctrlObj, *) {
        for i, c in ctrls {
            if c = ctrlObj && ctrlObj.Visible {
                state.selected := i
                Render()
                return
            }
        }
    }

    MoveSelection(delta) {
        len := CurrentList().Length
        state.selected := Mod(state.selected - 1 + delta + len, len) + 1
        Render()
    }

    OnEnter() {
        global ACTIVE_THEME
        choice := CurrentList()[state.selected]
        if state.mode = "main" {
            if choice = "Color Scheme"
                SwitchMode("theme")
            else if choice = "Reminder"
                SwitchMode("reminder")
            else if choice = "Search Apps" {
                ; Window input terpisah (app_search.ahk), pola sama dengan
                ; Pengeluaran di bawah -- popup menu ini tidak bisa dipakai ngetik.
                myGui.Closing := true
                myGui.Destroy()
                ShowAppSearchPopup(state.theme)
            }
            else if choice = MENU_SETTINGS_ITEM
                SwitchMode("menus")
            else if choice = "Pengeluaran" {
                ; Window input terpisah (expense_popup.ahk) -- popup menu ini
                ; nutup pada tombol apapun selain panah/Enter, gak bisa dipakai
                ; ngetik. Destroy dulu dengan pola yang sama kayak RunAction()
                ; (Closing := true dulu biar CloseOnDeactivate gak ExitApp()).
                myGui.Closing := true
                myGui.Destroy()
                ShowExpensePopup(state.theme)
            } else if InStr(choice, "Wallpaper Slideshow") = 1
                ToggleWallpaperSlideshow()
            else if choice = "Next Wallpaper"
                AdvanceWallpaper()
            else
                RunAction(myGui, choice)
        } else if state.mode = "reminder" {
            if choice = "Cancel Reminder" {
                SwitchToCancelMode()
            } else if choice = "Waktu Sholat" {
                SwitchToSholatMode()
            } else {
                ; Beda dari submenu tema -- pilih durasi langsung nutup
                ; popup (kayak RunAction), bukan tetap kebuka. Gak ada
                ; alasan buat "coba-coba beberapa durasi" kayak ganti tema.
                SetReminder(myGui, choice)
            }
        } else if state.mode = "cancel" {
            ; Placeholder "(no reminders set)" -- Enter gak ngapa-ngapain,
            ; cuma Escape yang bisa keluar dari sini.
            if state.cancelList.Length = 0
                return
            CancelReminder(myGui, state.cancelList[state.selected].taskName)
        } else if state.mode = "sholat" {
            ; Toggle + tetap kebuka -- lihat ToggleSholatSetting soal
            ; index 1=master, 2..6=PRAYER_NAMES.
            ToggleSholatSetting(state.selected)
        } else if state.mode = "menus" {
            ToggleMenuVisibility(state.selected)
        } else {
            ; Terapkan tema langsung (live) & tetap di submenu -- biar bisa
            ; coba-coba beberapa tema dulu sebelum keluar, bukan langsung exit.
            ; buang label " (current)" -- itu cuma penanda visual, bukan nama tema asli.
            chosen := StrReplace(choice, " (current)", "")
            IniWrite(chosen, SETTINGS_FILE, "Settings", "Theme")
            ACTIVE_THEME := chosen
            state.theme := THEMES[chosen]
            myGui.BackColor := state.theme.bezel
            Render()
            ; Tema "global" (lihat GLOBAL_THEMES di atas) juga fan-out ke
            ; nvim/WezTerm/Starship lewat apply-theme.ps1. Run() non-blocking
            ; & Hide, biar submenu ini tetap responsif -- script jalan di
            ; belakang, gagal-nya (kalau ada) dicatat ke log sendiri, bukan
            ; ditampilkan di sini.
            if GLOBAL_THEMES.Has(chosen) {
                scriptPath := A_ScriptDir "\scripts\apply-theme.ps1"
                Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '" -Theme ' chosen, , "Hide")
            }
        }
    }

    ; Up/Down/Tab/Enter ditangkap manual (Text control bukan ListBox, tidak
    ; ada navigasi bawaan) -- discope ke window ini saja lewat
    ; HotIfWinActive supaya tidak mengganggu tombol yang sama di aplikasi
    ; lain. Tab = item berikutnya, persis Down (termasuk lompat ke item
    ; pertama dari item terakhir); Shift+Tab = item sebelumnya, persis Up.
    HotIfWinActive("ahk_id " myGui.Hwnd)
    Hotkey("Up", (*) => MoveSelection(-1))
    Hotkey("Down", (*) => MoveSelection(1))
    Hotkey("Tab", (*) => MoveSelection(1))
    Hotkey("+Tab", (*) => MoveSelection(-1))
    Hotkey("Enter", (*) => OnEnter())
    Hotkey("NumpadEnter", (*) => OnEnter())
    HotIfWinActive()

    ; Popup ala mobile/web: cuma Arrow Up/Down, Tab (+Shift) & Enter yang "diterima" input --
    ; tombol lain apapun (Esc, tombol Windows, dll) atau klik/pindah fokus ke
    ; luar window langsung menutup menu. Berlaku di mode manapun.
    myGui.Closing := false
    readyTick := A_TickCount
    OnMessage(0x0100, CloseOnOtherKey)   ; WM_KEYDOWN
    OnMessage(0x0006, CloseOnDeactivate) ; WM_ACTIVATE

    CloseOnOtherKey(wParam, lParam, msg, hwnd) {
        ; VK_SHIFT (16) ikut diterima: menekan Shift SENDIRI (sebelum Tab pada
        ; Shift+Tab) juga mengirim WM_KEYDOWN, dan tanpa ini menu tertutup
        ; sebelum Tab sempat ditekan.
        static allowed := Map(38, 1, 40, 1, 13, 1, 9, 1, 16, 1)  ; UP, DOWN, RETURN, TAB, SHIFT
        if myGui.Closing || allowed.Has(wParam)
            return
        ; Escape (27) di submenu manapun (mode != "main") = mundur satu
        ; halaman ke PARENT-nya dulu, bukan langsung nutup -- "cancel" dan
        ; "sholat" anaknya "reminder" (Cancel Reminder & Waktu Sholat
        ; ada di dalam submenu Reminder), submenu lain semua anak langsung
        ; "main". Escape di menu utama, atau tombol lain apapun di mode
        ; manapun, tetap langsung nutup seperti biasa.
        if wParam = 27 && (state.mode = "cancel" || state.mode = "sholat") {
            SwitchMode("reminder")
            return
        }
        if wParam = 27 && state.mode != "main" {
            SwitchMode("main")
            return
        }
        ExitApp()
    }

    CloseOnDeactivate(wParam, lParam, msg, hwnd) {
        ; abaikan sesaat pas baru muncul -- hindari WM_ACTIVATE awal yang keburu
        ; nembak inactive sebelum window benar-benar settle jadi foreground.
        ; myGui.Closing juga dicek -- Destroy() di RunAction()/OnEnter() memicu
        ; WM_ACTIVATE(inactive) balik ke sini secara reentrant; tanpa guard ini,
        ; ExitApp() kepanggil duluan SEBELUM aksi (Run/DllCall/IniWrite dsb) sempat
        ; jalan -- gejalanya: pilih menu, langsung ke-close, tanpa aksi apapun terjadi.
        if !myGui.Closing && (wParam & 0xFFFF) = 0 && (A_TickCount - readyTick > 200)
            ExitApp()
    }

    Render()
    h := CurrentList().Length * itemH + margin * 2
    y := (A_ScreenHeight - h) / 2
    myGui.Show("w" w " h" h " x" x " y" y)
}

RunAction(myGui, item) {
    ; PENTING: destroy window kita SENDIRI dulu sebelum "Close All Windows"
    ; jalan. WinClose() sendiri (bukan Destroy()) di bawah triggers event
    ; "Close" yang kita daftarkan di atas -- kalau window kita masih ada saat
    ; WinGetList() dipanggil, dia bisa ikut ke-WinClose duluan, memicu
    ; ExitApp() instan, dan motong loop sebelum sempat nutup window lain.
    myGui.Closing := true
    myGui.Destroy()
    switch item {
        case "Close All Windows":
            for win in WinGetList()
                WinClose(win)
        case "Open Terminal (Admin)":
            Run("*RunAs wt.exe")
        case "Open WezTerm":
            Run("wezterm-gui")
        case "Open WezTerm (Admin)":
            ; Sama "*RunAs" verb yang udah kebukti jalan buat wt.exe di
            ; atas -- wezterm-gui (bukan wezterm.exe, lihat Gotchas) tetap
            ; dipanggil bare-name lewat PATH, cuma ditambah elevasi.
            Run("*RunAs wezterm-gui")
        case "Lock PC":
            DllCall("LockWorkStation")
        case "Sleep":
            DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
        case "Obsidian":
            Run(EnvGet("LOCALAPPDATA") "\Programs\Obsidian\Obsidian.exe")
        case "Claude Code":
            ; Aplikasi desktop Claude (Claude Code ada di tab "Code"-nya),
            ; bukan CLI -- CLI `claude` gak terpasang di PATH. claude.exe di
            ; root AnthropicClaude\ itu launcher Squirrel (sama kayak
            ; Discord/Slack): path-nya tetap walau app update ke folder
            ; app-x.y.z baru, jadi aman di-hardcode.
            Run(EnvGet("LOCALAPPDATA") "\AnthropicClaude\claude.exe")
    }
    ExitApp()
}

SetReminder(myGui, choice) {
    ; Sama pola kayak RunAction() (destroy sendiri dulu, baru ExitApp) --
    ; lihat komentar RunAction() soal kenapa urutannya begini.
    myGui.Closing := true
    myGui.Destroy()
    ; "5 min" -> "5" -- set-reminder.ps1 punya ValidateSet yang sama persis
    ; jadi angka ini selalu valid selama REMINDER_OPTIONS gak diubah tanpa
    ; ikut ubah ValidateSet-nya juga.
    minutes := StrReplace(choice, " min", "")
    scriptPath := A_ScriptDir "\scripts\set-reminder.ps1"
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '" -Minutes ' minutes, , "Hide")
    ExitApp()
}

; Sinkron (lihat komentar SwitchToCancelMode) -- RunWait dengan "Hide", sama
; persis mekanisme yang udah kebukti jalan aman di 4 tempat lain (Next
; Wallpaper, Color Scheme, Reminder, Cancel Reminder sendiri pas eksekusi
; cancel-nya). list-reminders.ps1 nulis ke file (bukan stdout) -- versi awal
; fungsi ini pakai WScript.Shell.Exec buat baca StdOut langsung, TAPI Exec()
; gak punya opsi buat nyembunyiin window sama sekali (beda dari Run()/
; RunWait() yang punya parameter "Hide"). Window PowerShell yang kelihatan
; itu curi fokus dari popup KOHA, mancing logic dismiss-on-blur
; (CloseOnDeactivate) nutup popup-nya duluan sebelum daftar reminder-nya
; sempat kebaca -- gejalanya: klik Cancel Reminder, window pwsh kekilat
; sebentar, terus KOHA-nya ilang. Baca file lewat RunWait+FileRead
; menghindari masalah ini total karena window-nya emang gak pernah muncul.
GetPendingReminders() {
    scriptPath := A_ScriptDir "\scripts\list-reminders.ps1"
    outFile := A_Temp "\koha-pending-reminders.txt"
    if FileExist(outFile)
        FileDelete(outFile)
    RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' scriptPath '"', , "Hide")
    output := FileExist(outFile) ? FileRead(outFile) : ""
    reminders := []
    for line in StrSplit(Trim(output, "`r`n"), "`n") {
        line := Trim(line, "`r")
        if line = ""
            continue
        parts := StrSplit(line, "|")
        if parts.Length = 2
            reminders.Push({ taskName: parts[1], label: parts[2] })
    }
    return reminders
}

CancelReminder(myGui, taskName) {
    myGui.Closing := true
    myGui.Destroy()
    scriptPath := A_ScriptDir "\scripts\cancel-reminder.ps1"
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' scriptPath '" -TaskName "' taskName '"', , "Hide")
    ExitApp()
}

; Sinkron (lihat komentar SwitchToCancelMode) -- sama pola persis
; GetPendingReminders(): RunWait+FileRead, bukan WScript.Shell.Exec.
; get-prayer-times.ps1 nulis "key|DisplayName|HH:MM" per baris (key-nya
; gak dipakai di sini, DisplayName-nya yang jadi key Map biar match
; langsung sama PRAYER_NAMES). File kosong (fetch API gagal) -> Map
; kosong, dan CurrentList() nangani itu dengan nampilin baris tanpa jam.
GetPrayerTimesForDisplay() {
    scriptPath := A_ScriptDir "\scripts\get-prayer-times.ps1"
    outFile := A_Temp "\koha-prayer-times.txt"
    if FileExist(outFile)
        FileDelete(outFile)
    RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' scriptPath '"', , "Hide")
    output := FileExist(outFile) ? FileRead(outFile) : ""
    times := Map()
    for line in StrSplit(Trim(output, "`r`n"), "`n") {
        line := Trim(line, "`r")
        if line = ""
            continue
        parts := StrSplit(line, "|")
        if parts.Length = 3
            times[parts[2]] := parts[3]
    }
    return times
}
