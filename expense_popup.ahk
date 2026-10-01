#Requires AutoHotkey v2.0

; expense_popup.ahk -- popup input "Pengeluaran" QuickMenu Light. Window
; sendiri (bukan mode baru di ShowMenu), soalnya popup menu utama sengaja
; nutup pada tombol APAPUN selain panah/Enter (CloseOnOtherKey) -- gak
; mungkin dipakai ngetik. Dipanggil dari OnEnter() setelah window menu
; di-Destroy(); semua logika parse/klasifikasi/tulis ada di expense.ahk.
;
; Tahap (state.stage):
;   "input"     ketik "nama nominal" (+ tanggal & metode bayar). Enter =
;               simpan; kalau ada item yang belum dikenal lanjut ke pick-cat.
;               Ctrl+Enter = ubah kategori SEMUA item dulu (sekali pakai).
;   "pick-cat"  tombol 1-9 pilih kategori (Enter = lewati, simpan #review).
;   "pick-type" cuma buat kategori yang ambigu (pangan/sandang): N / W.
;   "done"      sebentar nampilin "tersimpan", lalu tutup sendiri.
; Esc di tahap pick = balik ke input (batal, belum ada yang ditulis);
; Esc di input = tutup. Gak nutup pas klik di luar window (beda dari menu
; utama) -- teks yang sudah diketik gak hilang kalau pindah window buat
; ngecek harga.
;
; opts (opsional, dipakai tes): { vault, settingsFile, onClose, onSaved }.
; Return object berisi kontrol & handler supaya tes bisa nyetir popup ini
; tanpa keyboard beneran (handler dibungkus lambda (this) => ..., karena
; Func yang disimpan sebagai property objek dipanggil dengan obj sebagai
; parameter pertama).
ShowExpensePopup(theme, opts := "") {
    vault := (IsObject(opts) && opts.HasProp("vault")) ? opts.vault : EXPENSE_VAULT
    settingsFile := (IsObject(opts) && opts.HasProp("settingsFile")) ? opts.settingsFile : SETTINGS_FILE
    onClose := (IsObject(opts) && opts.HasProp("onClose")) ? opts.onClose : (*) => ExitApp()
    onSaved := (IsObject(opts) && opts.HasProp("onSaved")) ? opts.onSaved : ""

    margin := 10
    gap := 8
    pad := 8
    w := 560
    innerW := w - margin * 2
    rules := LoadExpenseRules(vault "\" EXPENSE_RULES_REL)

    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "QuickMenu Pengeluaran")
    g.BackColor := theme.bezel
    g.SetFont("s10 c" theme.fg, "Terminal")

    ; Edit satu baris menaruh teksnya mepet ATAS kotaknya (beda dari Text +
    ; SS_CENTERIMAGE yang menengahkan), jadi kalau Edit-nya setinggi
    ; auto-size-nya, teks isian tampak lebih tinggi dari label di sebelahnya.
    ; Solusi: tiap kolom = "kartu" (Text berlatar theme.bg) + Edit yang
    ; tingginya cuma sebesar SATU BARIS TEKS (th, diukur dari Text "Ag"
    ; auto-size -- bukan angka tebakan, tinggi font raster "Terminal" beda
    ; antar DPI), diletakkan persis di tengah kartu: baris teksnya jadi
    ; sejajar dengan label yang di-center. -E0x200 = tanpa border sunken,
    ; biar flat ala menu retro.
    Card(x, y, cw, ch) => g.Add("Text", "x" x " y" y " w" cw " h" ch " Background" theme.bg)
    y1 := margin
    probe := g.Add("Text", "x0 y0 w100", "Ag")
    probe.GetPos(, , , &th)
    probe.Visible := false   ; kontrol gak punya Destroy() -- cukup disembunyikan
    boxH := th + 2           ; +2 = napas biar descender (g, y, p) gak terpotong
    cardH := Max(th + 20, 32)
    editY := (cy) => cy + (cardH - th) // 2

    Card(margin, y1, innerW, cardH)
    inputCtl := g.Add("Edit", "x" margin + pad " y" editY(y1) " w" innerW - pad * 2 " h" boxH " -E0x200 Background" theme.bg)

    y2 := y1 + cardH + gap
    dateW := 240
    payX := margin + dateW + gap
    payW := innerW - dateW - gap
    Card(margin, y2, dateW, cardH)
    g.Add("Text", "x" margin + pad " y" y2 " w44 h" cardH " 0x200 Background" theme.bg, "Tgl")
    dateCtl := g.Add("Edit", "x" margin + pad + 48 " y" editY(y2) " w" dateW - pad * 2 - 48 " h" boxH " -E0x200 Background" theme.bg,
        FormatTime(A_Now, "yyyy-MM-dd"))
    Card(payX, y2, payW, cardH)
    g.Add("Text", "x" payX + pad " y" y2 " w60 h" cardH " 0x200 Background" theme.bg, "Bayar")
    payCtl := g.Add("Edit", "x" payX + pad + 64 " y" editY(y2) " w" payW - pad * 2 - 64 " h" boxH " -E0x200 Background" theme.bg,
        IniRead(settingsFile, "Settings", "ExpensePayment", "shopeepay"))

    ; Tinggi pratinjau diukur dari 7 baris teks BENERAN (Text tanpa "h"
    ; auto-size ke isinya, lebar yang sama dengan teks aslinya biar baris
    ; panjang ikut membungkus), lalu kartunya dikasih jarak pad di semua
    ; sisi supaya teks gak nempel ke pinggir. Kartu dibuat DULU baru teksnya
    ; (kontrol yang dibuat belakangan tampil di atas).
    y3 := y2 + cardH + gap
    textW := innerW - pad * 2
    measure := g.Add("Text", "x0 y0 w" textW, "x`nx`nx`nx`nx`nx`nx")
    measure.GetPos(, , , &previewH)
    measure.Visible := false
    Card(margin, y3, innerW, previewH + pad * 2)
    previewCtl := g.Add("Text", "x" margin + pad " y" y3 + pad " w" textW " h" previewH " Background" theme.bg, "")
    winH := y3 + previewH + pad * 2 + margin

    state := {
        stage: "input", entries: [], groups: [], pos: 1, forced: false,
        overrides: Map(), dateStr: "", payment: "", chosenCat: ""
    }

    SetPreview(lines) {
        previewCtl.Text := lines is Array ? JoinLines(lines) : lines
    }

    ShowInputPreview() {
        parsed := ParseExpenseInput(inputCtl.Value)
        if inputCtl.Value = "" {
            SetPreview(["ketik: nama nominal   (kopi susu 8k, nasi 15000)", "",
                "beberapa item: pisah koma",
                "", "Enter simpan   Ctrl+Enter ubah kategori   Esc tutup"])
            return
        }
        lines := ExpensePreviewLines(rules, parsed)
        total := 0
        for e in parsed.entries
            total += e.amount
        ds := ResolveExpenseDate(dateCtl.Value)
        lines.Push("")
        lines.Push((ds = "" ? "! tanggal gak valid" : ds) " | " Trim(payCtl.Value) " | " FormatRupiah(total))
        lines.Push("Enter simpan   Ctrl+Enter ubah kategori   Esc tutup")
        SetPreview(lines)
    }

    OnChange(*) {
        if state.stage = "input"
            ShowInputPreview()
    }
    inputCtl.OnEvent("Change", OnChange)
    dateCtl.OnEvent("Change", OnChange)
    payCtl.OnEvent("Change", OnChange)

    SetEditsEnabled(on) {
        inputCtl.Enabled := on
        dateCtl.Enabled := on
        payCtl.Enabled := on
    }

    ; Validasi form + parse; return true kalau siap dilanjutkan.
    ReadForm() {
        state.dateStr := ResolveExpenseDate(dateCtl.Value)
        if state.dateStr = "" {
            SetPreview("! tanggal gak valid: " dateCtl.Value "`n`nformat: kosong = hari ini, kemarin, -2,`n2026-09-30, 30-09-2026, 30-09")
            dateCtl.Focus()
            return false
        }
        state.payment := Trim(payCtl.Value)
        if state.payment = "" {
            SetPreview("! metode bayar kosong (mis. shopeepay, gopay, cash, bca)")
            payCtl.Focus()
            return false
        }
        parsed := ParseExpenseInput(inputCtl.Value)
        if !parsed.entries.Length || parsed.errors.Length {
            ShowInputPreview()
            if !parsed.entries.Length && !parsed.errors.Length
                SetPreview("! belum ada yang diketik")
            inputCtl.Focus()
            return false
        }
        state.entries := parsed.entries
        state.overrides := Map()
        return true
    }

    ; groups = daftar yang ditanyakan satu per satu. Mode normal: nama
    ; unik yang belum dikenal (ditanya sekali walau muncul dua kali, dan
    ; pilihannya dipelajari). Mode forced (Ctrl+Enter): tiap entri sendiri,
    ; pilihannya sekali pakai.
    BeginPicking(forced) {
        state.forced := forced
        state.groups := []
        seen := Map()
        for i, e in state.entries {
            if forced {
                state.groups.Push({ name: e.name, amount: e.amount, idxs: [i] })
                continue
            }
            if ClassifyExpense(rules, e.name).known
                continue
            key := StrLower(e.name)
            if seen.Has(key)
                seen[key].idxs.Push(i)
            else {
                grp := { name: e.name, amount: e.amount, idxs: [i] }
                seen[key] := grp
                state.groups.Push(grp)
            }
        }
        state.pos := 1
        if !state.groups.Length
            return DoSave()
        SetEditsEnabled(false)
        ShowPickCat()
    }

    ShowPickCat() {
        state.stage := "pick-cat"
        grp := state.groups[state.pos]
        guess := ClassifyExpense(rules, grp.name)
        lines := ["[" state.pos "/" state.groups.Length "] " grp.name "  " FormatRupiah(grp.amount)]
        row := ""
        for i, c in EXPENSE_PICK_CATEGORIES {
            row .= Format("{:-16}", i " " c)
            if Mod(i, 3) = 0 {
                lines.Push(RTrim(row))
                row := ""
            }
        }
        lines.Push("")
        if state.forced
            lines.Push("Enter = pakai tebakan (" guess.cat "/" guess.type ")   Esc = batal")
        else
            lines.Push("Enter = lewati (simpan #review)   Esc = batal")
        SetPreview(lines)
    }

    ShowPickType() {
        state.stage := "pick-type"
        grp := state.groups[state.pos]
        SetPreview(["[" state.pos "/" state.groups.Length "] " grp.name "  " FormatRupiah(grp.amount) "  -> " state.chosenCat,
            "", "N = need   W = want", "", "Backspace = kembali   Esc = batal"])
    }

    ; Pilihan user buat grup saat ini -> semua entrinya di-override, lalu
    ; lanjut ke grup berikutnya (atau simpan kalau sudah habis).
    ApplyChoice(cat, typ) {
        grp := state.groups[state.pos]
        for idx in grp.idxs
            state.overrides[idx] := { cat: cat, type: typ, learn: !state.forced }
        NextGroup()
    }

    NextGroup() {
        state.pos += 1
        if state.pos > state.groups.Length
            DoSave()
        else
            ShowPickCat()
    }

    BackToInput() {
        state.stage := "input"
        SetEditsEnabled(true)
        inputCtl.Focus()
        ShowInputPreview()
    }

    DoSave() {
        try
            result := RecordParsedExpenses(vault, state.dateStr, state.payment, state.entries, state.overrides)
        catch as err {
            state.stage := "input"
            SetEditsEnabled(true)
            SetPreview("! gagal menyimpan:`n" err.Message "`n`nEsc = tutup")
            return
        }
        try IniWrite(state.payment, settingsFile, "Settings", "ExpensePayment")
        total := 0
        for e in state.entries
            total += e.amount
        state.stage := "done"
        lines := ["Tersimpan " result.saved " transaksi -> " state.dateStr ".md", FormatRupiah(total) " | " state.payment]
        if result.unknown.Length
            lines.Push("#review: " result.unknown.Length " item (cek di Obsidian)")
        if result.learned.Length
            lines.Push("aturan baru: " result.learned.Length " (rules.md)")
        if result.learnError != ""
            lines.Push("! aturan gagal disimpan: " result.learnError)
        SetPreview(lines)
        if IsObject(onSaved)
            onSaved(result)
        SetTimer(Close, -900)
    }

    Close(*) {
        onClose()
    }

    OnEnter() {
        if state.stage = "input" {
            if ReadForm()
                BeginPicking(false)
        } else if state.stage = "pick-cat" {
            ; Lewati: tanpa override -> forced = pakai tebakan, normal =
            ; lainnya/want + #review (aturan ditulis RecordParsedExpenses).
            NextGroup()
        }
    }

    OnCtrlEnter() {
        if state.stage = "input" && ReadForm()
            BeginPicking(true)
        else
            OnEnter()
    }

    OnEscape() {
        if state.stage = "input"
            Close()
        else if state.stage = "pick-cat" || state.stage = "pick-type"
            BackToInput()
    }

    ; k = "1".."9" | "n" | "w" | "Backspace"
    OnKey(k) {
        if state.stage = "pick-cat" && RegExMatch(k, "^[1-9]$") {
            cat := EXPENSE_PICK_CATEGORIES[Integer(k)]
            dt := DefaultExpenseType(cat)
            if dt != ""
                ApplyChoice(cat, dt)
            else {
                state.chosenCat := cat
                ShowPickType()
            }
        } else if state.stage = "pick-type" {
            if k = "n" || k = "w"
                ApplyChoice(state.chosenCat, k = "n" ? "need" : "want")
            else if k = "Backspace"
                ShowPickCat()
        }
    }

    g.OnEvent("Close", Close)

    ; Hotkey di-scope ke window ini (sama pola ShowMenu). "*" = jalan walau
    ; Shift/Ctrl lagi ditekan, jadi huruf kapital tetap kena. Tombol
    ; pilihan (1-9/N/W/Backspace) cuma aktif di tahap pick -- di tahap
    ; input angka & huruf harus tetap bisa diketik ke kotak teks.
    inWin := (*) => state.stage != "done" && WinActive("ahk_id " g.Hwnd)
    inPick := (*) => (state.stage = "pick-cat" || state.stage = "pick-type") && WinActive("ahk_id " g.Hwnd)
    HotIf(inWin)
    Hotkey("*Enter", (*) => GetKeyState("Ctrl") ? OnCtrlEnter() : OnEnter())
    Hotkey("*NumpadEnter", (*) => GetKeyState("Ctrl") ? OnCtrlEnter() : OnEnter())
    Hotkey("*Escape", (*) => OnEscape())
    HotIf(inPick)
    for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "n", "w", "Backspace"]
        Hotkey("*" k, ((key, *) => OnKey(key)).Bind(k))
    HotIf()

    ShowInputPreview()
    x := (A_ScreenWidth - w) / 2
    y := (A_ScreenHeight - winH) / 2
    g.Show("w" w " h" winH " x" x " y" y)
    inputCtl.Focus()

    return { gui: g, state: state, input: inputCtl, date: dateCtl, pay: payCtl, preview: previewCtl,
        Enter: (this) => OnEnter(), CtrlEnter: (this) => OnCtrlEnter(), Esc: (this) => OnEscape(),
        Key: (this, k) => OnKey(k) }
}
