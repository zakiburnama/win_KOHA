#Requires AutoHotkey v2.0

; app_search.ahk -- "Search Apps" KOHA: ketik sebagian nama aplikasi, Enter
; langsung membukanya. Alternatif ringan buat pencarian Start Menu Windows
; yang di laptop ini harus "cold load" dulu di pencarian pertama.
;
; Kenapa ini ringan & instan:
;   - Tidak ada indexer, cache, atau proses latar. Tiap kali dibuka, KOHA
;     cuma menyisir isi 2 folder Start Menu (%APPDATA% dan %ProgramData%,
;     sekitar 150-200 shortcut) pakai Loop Files -- belasan milidetik,
;     jadi hasilnya selalu segar (app baru langsung muncul) tanpa file cache
;     yang bisa basi.
;   - Pencocokan murni teks di memori; tidak ada query ke Windows Search.
;
; Batasan: yang dicari hanya shortcut (.lnk/.url) di Start Menu. App Store/UWP
; (Calculator, Settings, dst) tidak punya shortcut di folder itu, jadi tidak
; ikut -- sengaja, menyisir shell:AppsFolder butuh PowerShell/COM yang lambat.
;
; Dipanggil dari OnEnter() koha.ahk (menu "Search Apps") atau langsung lewat
; argumen: KOHA.exe search.
;
; opts (opsional, dipakai tes): { dirs, onClose, onLaunch }.

APP_SEARCH_ROWS := 8

; Daftar folder Start Menu yang disisir: milik user dulu, baru semua-user --
; kalau namanya kembar, yang milik user menang (lihat ScanStartMenuApps).
StartMenuDirs() => [
    A_AppData "\Microsoft\Windows\Start Menu\Programs",
    A_AppDataCommon "\Microsoft\Windows\Start Menu\Programs",
]

; Return Array of { name, lower, path }. Nama = nama file tanpa ekstensi.
; Dedup per nama (case-insensitive); "Uninstall ..." dibuang karena hampir
; selalu cuma mengganggu hasil.
ScanStartMenuApps(dirs := "") {
    if !IsObject(dirs)
        dirs := StartMenuDirs()
    apps := []
    seen := Map()
    for dir in dirs {
        if !DirExist(dir)
            continue
        loop files dir "\*.*", "R" {
            if A_LoopFileExt != "lnk" && A_LoopFileExt != "url"
                continue
            name := SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName) - StrLen(A_LoopFileExt) - 1)
            low := StrLower(name)
            if seen.Has(low) || InStr(low, "uninstall")
                continue
            seen[low] := true
            apps.Push({ name: name, lower: low, path: A_LoopFileFullPath })
        }
    }
    return apps
}

; Skor satu kata kunci terhadap satu nama (keduanya sudah huruf kecil);
; 0 = tidak cocok. Makin tinggi makin relevan:
;   100 awal nama, 80 awal kata, 70 singkatan huruf awal kata ("vsc" ->
;   Visual Studio Code), 60 ada di tengah, 30 huruf-hurufnya berurutan
;   (subsequence, minimal 2 huruf).
ScoreToken(lower, tok) {
    pos := InStr(lower, tok)
    if pos = 1
        return 100
    if pos > 1 {
        prev := SubStr(lower, pos - 1, 1)
        return RegExMatch(prev, "[a-z0-9]") ? 60 : 80
    }
    if StrLen(tok) < 2
        return 0
    initials := ""
    for word in StrSplit(RegExReplace(lower, "[^a-z0-9]+", " "), " ")
        if word != ""
            initials .= SubStr(word, 1, 1)
    if InStr(initials, tok) = 1
        return 70
    p := 1
    loop parse tok {
        p := InStr(lower, A_LoopField, , p)
        if !p
            return 0
        p += 1
    }
    return 30
}

; Skor query (boleh beberapa kata, semuanya harus cocok) terhadap app.
ScoreApp(app, query) {
    total := 0
    for tok in StrSplit(StrLower(Trim(query)), " ") {
        if tok = ""
            continue
        s := ScoreToken(app.lower, tok)
        if !s
            return 0
        total += s
    }
    return total
}

; Top `limit` app yang cocok, diurutkan skor menurun, lalu nama lebih
; pendek, lalu alfabet. Query kosong -> []. Insertion sort: hasilnya
; paling banyak beberapa ratus entri, jadi tidak perlu yang lebih canggih.
SearchApps(apps, query, limit := 8) {
    hits := []
    if Trim(query) = ""
        return hits
    for app in apps {
        s := ScoreApp(app, query)
        if !s
            continue
        hit := { app: app, score: s }
        i := hits.Length
        hits.Push(hit)
        while i >= 1 && HitBefore(hit, hits[i]) {
            hits[i + 1] := hits[i]
            i -= 1
        }
        hits[i + 1] := hit
    }
    out := []
    for hit in hits {
        if out.Length >= limit
            break
        out.Push(hit.app)
    }
    return out
}

HitBefore(a, b) {
    if a.score != b.score
        return a.score > b.score
    la := StrLen(a.app.name), lb := StrLen(b.app.name)
    if la != lb
        return la < lb
    return StrCompare(a.app.lower, b.app.lower) < 0
}

; Window biasa yang kelihatan (punya judul, bukan tool window) -- dipakai
; LaunchAndFocus buat mengenali window BARU yang muncul setelah Run().
VisibleWindows() {
    set := Map()
    for hwnd in WinGetList() {
        try {
            if WinGetTitle(hwnd) != "" && (WinGetStyle(hwnd) & 0x10000000) && !(WinGetExStyle(hwnd) & 0x80)
                set[hwnd] := true
        }
    }
    return set
}

; Run() lalu angkat window barunya ke depan. Tanpa ini, app yang SUDAH
; berjalan (Brave/Chrome: shortcut-nya membuka window baru di proses yang
; ada) muncul di belakang window lain, karena Windows menolak merebut fokus
; dari proses KOHA yang langsung keluar -- terlihat seperti "tidak terbuka".
; App yang belum jalan biasanya otomatis di depan, jadi tidak terpengaruh.
; Menunggu maksimal ~3 detik dan berhenti begitu window baru ketemu; kalau
; tidak ada window baru (app cuma memfokuskan window lamanya), KOHA tetap
; keluar setelah batas itu.
LaunchAndFocus(path) {
    before := VisibleWindows()
    log := "path=" path
    try Run(path)
    catch as e
        log .= " | Run GAGAL: " e.Message
    deadline := A_TickCount + 3000
    found := 0
    while !found && A_TickCount < deadline {
        Sleep(50)
        for hwnd in VisibleWindows() {
            if !before.Has(hwnd) {
                found := hwnd
                break
            }
        }
    }
    if found {
        ok := ForceForeground(found)
        log .= " | window baru: " WinGetTitle(found) " | di depan: " (ok ? "ya" : "TIDAK")
    } else
        log .= " | tidak ada window baru dalam 3 detik"
    ; Log kecil buat diagnosa kalau app "tidak terbuka" -- ditimpa tiap
    ; peluncuran, jadi tidak menumpuk.
    try FileOpen(A_Temp "\koha-search.log", "w").Write(FormatTime(A_Now, "HH:mm:ss") " " log "`n")
}

; WinActivate biasa sering ditolak Windows (foreground lock) kalau proses
; kita tidak dianggap sedang "dipakai user" -- misalnya KOHA.exe yang
; dijalankan lewat tombol Lenovo Vantage, beda dari script yang dijalankan
; manual. Bertahap: WinActivate dulu; kalau belum di depan, pakai trik
; Alt (menekan Alt memberi proses ini hak ubah foreground), lalu
; SwitchToThisWindow sebagai cadangan terakhir.
ForceForeground(hwnd) {
    try WinActivate(hwnd)
    if WinWaitActive(hwnd, , 0.4)
        return true
    Send("{Alt down}{Alt up}")
    try WinActivate(hwnd)
    if WinWaitActive(hwnd, , 0.4)
        return true
    DllCall("SwitchToThisWindow", "Ptr", hwnd, "Int", 1)
    return !!WinWaitActive(hwnd, , 0.4)
}

ShowAppSearchPopup(theme, opts := "") {
    global APP_SEARCH_ROWS
    dirs := (IsObject(opts) && opts.HasProp("dirs")) ? opts.dirs : ""
    onClose := (IsObject(opts) && opts.HasProp("onClose")) ? opts.onClose : (*) => ExitApp()
    onLaunch := (IsObject(opts) && opts.HasProp("onLaunch")) ? opts.onLaunch : LaunchAndFocus

    apps := ScanStartMenuApps(dirs)

    margin := 10
    gap := 8
    pad := 8
    itemH := 26
    w := 480
    innerW := w - margin * 2

    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "KOHA Search Apps")
    g.BackColor := theme.bezel
    g.SetFont("s10 c" theme.fg, "Terminal")

    ; Kotak input: pola yang sama persis dengan expense_popup.ahk (kartu Text
    ; + Edit setinggi satu baris teks di tengahnya) -- lihat komentar di sana.
    probe := g.Add("Text", "x0 y0 w100", "Ag")
    probe.GetPos(, , , &th)
    probe.Visible := false
    boxH := th + 2
    cardH := Max(th + 20, 32)
    g.Add("Text", "x" margin " y" margin " w" innerW " h" cardH " Background" theme.bg)
    inputCtl := g.Add("Edit", "x" margin + pad " y" margin + (cardH - th) // 2 " w" innerW - pad * 2 " h" boxH " -E0x200 Background" theme.bg)

    ; Baris hasil -- Text per baris, seleksi reverse-video + ">" seperti menu utama.
    rowsY := margin + cardH + gap
    rows := []
    loop APP_SEARCH_ROWS
        rows.Push(g.Add("Text", "x" margin " y" rowsY + (A_Index - 1) * itemH " w" innerW " h" itemH " 0x200 Background" theme.bg))
    winH := rowsY + APP_SEARCH_ROWS * itemH + margin

    state := { hits: [], selected: 1, closing: false }

    Render() {
        if Trim(inputCtl.Value) = ""
            hint := "  ketik nama app...   Enter buka   Esc tutup"
        else if !state.hits.Length
            hint := "  (tidak ada yang cocok)"
        else
            hint := ""
        for i, ctl in rows {
            text := state.hits.Has(i) ? state.hits[i].name : (i = 1 ? hint : "")
            if state.hits.Has(i) && i = state.selected {
                ctl.SetFont("c" theme.selFg)
                ctl.Opt("Background" theme.selBg)
                ctl.Text := "> " text
            } else {
                ctl.SetFont("c" theme.fg)
                ctl.Opt("Background" theme.bg)
                ctl.Text := state.hits.Has(i) ? "  " text : text
            }
        }
    }

    OnChange(*) {
        state.hits := SearchApps(apps, inputCtl.Value, APP_SEARCH_ROWS)
        state.selected := 1
        Render()
    }
    inputCtl.OnEvent("Change", OnChange)

    Move(delta) {
        len := state.hits.Length
        if !len
            return
        state.selected := Mod(state.selected - 1 + delta + len, len) + 1
        Render()
    }

    Close(*) {
        if state.closing
            return
        state.closing := true
        g.Destroy()
        onClose()
    }

    ; Destroy dulu baru Run, sama pola RunAction() di koha.ahk (flag closing
    ; supaya WM_ACTIVATE reentrant dari Destroy() tidak memanggil Close lagi).
    Launch() {
        if state.closing || !state.hits.Has(state.selected)
            return
        path := state.hits[state.selected].path
        state.closing := true
        g.Destroy()
        try onLaunch(path)
        onClose()
    }

    g.OnEvent("Close", Close)
    OnMessage(0x0006, OnActivate)   ; WM_ACTIVATE -- klik di luar = tutup
    readyTick := A_TickCount
    OnActivate(wParam, lParam, msg, hwnd) {
        ; closing dicek PERTAMA: setelah Destroy(), g.Hwnd melempar error.
        if !state.closing && hwnd = g.Hwnd && (wParam & 0xFFFF) = 0 && (A_TickCount - readyTick > 200)
            Close()
    }

    inWin := (*) => !state.closing && WinActive("ahk_id " g.Hwnd)
    HotIf(inWin)
    Hotkey("Up", (*) => Move(-1))
    Hotkey("Down", (*) => Move(1))
    Hotkey("Tab", (*) => Move(1))
    Hotkey("+Tab", (*) => Move(-1))
    Hotkey("Enter", (*) => Launch())
    Hotkey("NumpadEnter", (*) => Launch())
    Hotkey("Escape", (*) => Close())
    HotIf()

    Render()
    g.Show("w" w " h" winH " x" (A_ScreenWidth - w) / 2 " y" (A_ScreenHeight - winH) / 2)
    inputCtl.Focus()

    return { gui: g, state: state, input: inputCtl, rows: rows, apps: apps,
        Changed: (this) => OnChange(), Enter: (this) => Launch(), Esc: (this) => Close(),
        Move: (this, d) => Move(d) }
}
