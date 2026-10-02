#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\expense.ahk
#Include ..\expense_popup.ahk

; Tes state machine popup Pengeluaran. Window-nya beneran dibuat (sebentar
; muncul di layar), tapi TIDAK ada tombol yang dikirim ke keyboard -- tes
; manggil handler (ui.Enter(), ui.Key("1"), ...) langsung, jadi gak ada
; risiko ngetik nyasar ke aplikasi lain. Artinya tombol fisik/hotkey scope
; TIDAK ikut teruji di sini.
;   sh tests/make-test-vault.sh <vault-asli> <folder-salinan>
;   AutoHotkey64.exe tests/expense_popup_test.ahk <folder-salinan> | cat

OnError((e, *) => (FileAppend("ERROR: " e.Message " (" e.What ") baris " e.Line "`n", "*", "UTF-8"), ExitApp(2)))

passed := 0, failed := 0
vault := A_Args[1]
SETTINGS_FILE := A_Temp "\qm-expense-popup-test.ini"
if FileExist(SETTINGS_FILE)
    FileDelete(SETTINGS_FILE)
theme := { bg: "141415", fg: "CDCDCD", selBg: "6E94B2", selFg: "141415", bezel: "1C1C24" }
daily := vault "\" EXPENSE_DAILY_REL "\"
rulesPath := vault "\" EXPENSE_RULES_REL

Out(s) => FileAppend(s "`n", "*", "UTF-8")
Check(name, ok, detail := "") {
    global passed, failed
    if ok
        passed++
    else {
        failed++
        Out("FAIL: " name (detail != "" ? "  -> " detail : ""))
    }
}
ReadRaw(path) => FileRead(path, "UTF-8-RAW")

closed := 0
Open(extra := "") {
    global closed
    closed := 0
    opts := { vault: vault, settingsFile: SETTINGS_FILE, onClose: (*) => closed++ }
    return ShowExpensePopup(theme, opts)
}
; Habis simpan popup TIDAK menutup: kembali ke tahap input dengan kotak
; teks kosong, edit aktif lagi, dan pesan "Tersimpan" di pratinjau.
Saved(ui) => ui.state.stage = "input" && ui.input.Value = "" && ui.input.Enabled && InStr(ui.preview.Text, "Tersimpan")
Fill(ui, text, date := "2026-08-31", pay := "gopay") {
    ui.input.Value := text
    ui.date.Value := date
    ui.pay.Value := pay
}

; ---- helper murni ----
Check("FormatRupiah", FormatRupiah(15000) = "Rp 15.000" && FormatRupiah(1500000) = "Rp 1.500.000" && FormatRupiah(800) = "Rp 800")
Check("learn keyword buang ukuran", ExpenseLearnKeyword("Frisian Flag UHT 946ml") = "frisian flag uht"
    && ExpenseLearnKeyword("seblak (3)") = "seblak" && ExpenseLearnKeyword("decathlon : Bottle 500 1L CN") = "decathlon bottle cn"
    && ExpenseLearnKeyword("123") = "123")
rules := LoadExpenseRules(rulesPath)
pv := ExpensePreviewLines(rules, ParseExpenseInput("kopi susu jago 8000, seblak mang ujang 15000, tolong"))
Check("preview 3 baris (2 entri + 1 error)", pv.Length = 3 && InStr(pv[1], "pangan/want") && InStr(pv[2], "? belum dikenal") && SubStr(pv[3], 1, 1) = "!", JoinLines(pv))
Check("preview alignment Format", InStr(pv[1], "kopi susu jago            Rp 8.000"), pv[1])
pv := ExpensePreviewLines(rules, ParseExpenseInput("a 1000, b 1000, c 1000, d 1000, e 1000"))
Check("preview dipotong 4 baris", pv.Length = 4 && InStr(pv[4], "+2 lagi"), JoinLines(pv))

; ---- 1. item belum dikenal -> pick 1 (pangan, ambigu) -> W; dipelajari ----
ui := Open()
ui.preview.GetPos(, , &pw, &ph), ui.gui.GetPos(, , &gw, &gh)
Out("info: preview " pw "x" ph " px, window " gw "x" gh " px, layar " A_ScreenWidth "x" A_ScreenHeight)
Fill(ui, "kopi susu jago 8000, seblak mang ujang 15000")
ui.Enter()
Check("belum dikenal -> pick-cat", ui.state.stage = "pick-cat" && InStr(ui.preview.Text, "[1/1] seblak mang ujang"), ui.preview.Text)
Check("pick-cat menampilkan 9 kategori", InStr(ui.preview.Text, "1 pangan") && InStr(ui.preview.Text, "9 investasi") && InStr(ui.preview.Text, "Enter = lewati"), ui.preview.Text)
Check("edit dinonaktifkan di tahap pick", !ui.input.Enabled)
ui.Key("1")
Check("pangan ambigu -> minta type", ui.state.stage = "pick-type" && InStr(ui.preview.Text, "N = need"))
ui.Key("Backspace")
Check("backspace balik ke pick-cat", ui.state.stage = "pick-cat")
ui.Key("1"), ui.Key("w")
Check("selesai -> tersimpan & form di-reset", Saved(ui) && InStr(ui.preview.Text, "Tersimpan 2 transaksi -> 2026-08-31.md") && InStr(ui.preview.Text, "aturan baru: 1"), ui.preview.Text)
note := ReadRaw(daily "2026-08-31.md")
Check("tertulis: kopi dari rules", InStr(note, "- [expense] kopi susu jago [amount:: 8000] [category:: pangan] [type:: want] [payment:: gopay]"))
Check("tertulis: seblak hasil pilihan, tanpa #review", InStr(note, "- [expense] seblak mang ujang [amount:: 15000] [category:: pangan] [type:: want] [payment:: gopay]`n") && !InStr(note, "seblak mang ujang [amount:: 15000] [category:: pangan] [type:: want] [payment:: gopay] #review"))
Check("aturan dipelajari", InStr(ReadRaw(rulesPath), "seblak mang ujang => pangan | want"))
Check("payment diingat", IniRead(SETTINGS_FILE, "Settings", "ExpensePayment", "") = "gopay")
ui.gui.Destroy()

; ---- 2. item yang sama berikutnya: langsung tersimpan tanpa tanya ----
ui := Open()
Check("payment default = terakhir dipakai", ui.pay.Value = "gopay")
Fill(ui, "seblak mang ujang pedas 17000")
ui.Enter()
Check("sudah dikenal -> langsung tersimpan", Saved(ui))
ui.gui.Destroy()

; ---- 3. Enter di pick-cat = lewati -> lainnya + #review, tanpa aturan ----
ui := Open()
rulesBefore := ReadRaw(rulesPath)
Fill(ui, "barang misterius 5000")
ui.Enter(), ui.Enter()
Check("lewati -> tersimpan", Saved(ui) && InStr(ui.preview.Text, "#review: 1"), ui.preview.Text)
Check("lewati: tag #review", InStr(ReadRaw(daily "2026-08-31.md"), "barang misterius [amount:: 5000] [category:: lainnya] [type:: want] [payment:: gopay] #review"))
Check("lewati: aturan gak berubah", ReadRaw(rulesPath) = rulesBefore)
ui.gui.Destroy()

; ---- 4. kategori tak ambigu (papan) -> gak minta type ----
ui := Open()
Fill(ui, "keset kamar mandi 25000")
ui.Enter(), ui.Key("2")
Check("papan -> langsung tersimpan, need", Saved(ui) && InStr(ReadRaw(daily "2026-08-31.md"), "keset kamar mandi [amount:: 25000] [category:: papan] [type:: need]"))
ui.gui.Destroy()

; ---- 5. Esc di pick = batal, belum ada yang ditulis ----
ui := Open()
snap := ReadRaw(daily "2026-08-31.md")
Fill(ui, "item batal 9000")
ui.Enter()
ui.Esc()
Check("esc di pick -> balik ke input", ui.state.stage = "input" && ui.input.Enabled && ui.input.Value = "item batal 9000")
Check("batal: file gak berubah", ReadRaw(daily "2026-08-31.md") = snap)
ui.Esc()
Check("esc di input -> onClose", closed = 1)
ui.gui.Destroy()

; ---- 6. Ctrl+Enter: koreksi sekali pakai, gak dipelajari ----
ui := Open()
rulesBefore := ReadRaw(rulesPath)
Fill(ui, "kopi susu jago 9000")
ui.CtrlEnter()
Check("ctrl+enter -> pick-cat meski sudah dikenal", ui.state.stage = "pick-cat" && InStr(ui.preview.Text, "pakai tebakan (pangan/want)"), ui.preview.Text)
ui.Key("6")
Check("hiburan -> want, tersimpan", Saved(ui) && InStr(ReadRaw(daily "2026-08-31.md"), "kopi susu jago [amount:: 9000] [category:: hiburan] [type:: want]"))
Check("koreksi sekali pakai: rules.md gak berubah", ReadRaw(rulesPath) = rulesBefore)
ui.gui.Destroy()

; ---- 7. ctrl+enter lalu Enter = pakai tebakan ----
ui := Open()
Fill(ui, "le mineral 6000")
ui.CtrlEnter(), ui.Enter()
Check("forced + Enter = pakai tebakan", Saved(ui) && InStr(ReadRaw(daily "2026-08-31.md"), "le mineral [amount:: 6000] [category:: pangan] [type:: need]"))
ui.gui.Destroy()

; ---- 8. nama yang sama dua kali ditanya sekali ----
ui := Open()
Fill(ui, "cilok bandung 3000, cilok bandung 4000")
ui.Enter()
Check("dedupe: 1 pertanyaan", ui.state.stage = "pick-cat" && ui.state.groups.Length = 1 && ui.state.groups[1].idxs.Length = 2)
ui.Key("3"), ui.Key("n")
note := ReadRaw(daily "2026-08-31.md")
Check("dedupe: dua-duanya sandang/need", InStr(note, "cilok bandung [amount:: 3000] [category:: sandang] [type:: need]") && InStr(note, "cilok bandung [amount:: 4000] [category:: sandang] [type:: need]"))
ui.gui.Destroy()

; ---- 9. validasi form ----
ui := Open()
snap := ReadRaw(daily "2026-08-31.md")
Fill(ui, "kopi 8000", "bukan-tanggal")
ui.Enter()
Check("tanggal invalid ditolak", ui.state.stage = "input" && InStr(ui.preview.Text, "tanggal gak valid"))
Fill(ui, "kopi", "2026-08-31")
ui.Enter()
Check("tanpa nominal ditolak", ui.state.stage = "input" && InStr(ui.preview.Text, "nominal gak terbaca"), ui.preview.Text)
Fill(ui, "kopi 8000", "2026-08-31", "  ")
ui.Enter()
Check("payment kosong ditolak", ui.state.stage = "input" && InStr(ui.preview.Text, "metode bayar kosong"))
Fill(ui, "", "2026-08-31")
ui.Enter()
Check("input kosong ditolak", ui.state.stage = "input")
Check("validasi: file gak berubah", ReadRaw(daily "2026-08-31.md") = snap)
ui.gui.Destroy()

; ---- 10. tanggal relatif ----
ui := Open()
Fill(ui, "parkir 2000", "kemarin")
ui.Enter()
yesterday := FormatTime(DateAdd(A_Now, -1, "Days"), "yyyy-MM-dd")
Check("kemarin -> file kemarin dibuat dari template", Saved(ui) && InStr(ui.preview.Text, yesterday ".md"), ui.preview.Text)
Check("note kemarin ada transaksinya", FileExist(daily yesterday ".md") && InStr(ReadRaw(daily yesterday ".md"), "[expense] parkir [amount:: 2000] [category:: transportasi]"))
ui.gui.Destroy()

; ---- 11. input berulang: habis simpan popup tetap terbuka & ke-reset ----
ui := Open()
today := FormatTime(A_Now, "yyyy-MM-dd")
Fill(ui, "le mineral 20000", "kemarin", "cash")
ui.Enter()
Check("reset: tetap terbuka, tidak ada onClose", Saved(ui) && closed = 0)
Check("reset: tanggal balik ke hari ini", ui.date.Value = today, ui.date.Value)
Check("reset: metode bayar tetap yang terakhir", ui.pay.Value = "cash")
Check("reset: pesan siap input berikutnya", InStr(ui.preview.Text, "Siap input berikutnya") && InStr(ui.preview.Text, "Esc tutup"), ui.preview.Text)
Sleep(1200)   ; dulu popup menutup sendiri ~0,9 dtk setelah simpan -- sekarang gak boleh
Check("reset: gak menutup sendiri", closed = 0)
ui.input.Value := "kopi 5000"
ui.Changed()   ; di AHK v2 mengisi Value lewat kode TIDAK memicu event Change -- ketikan asli memicunya
Check("reset: mulai mengetik -> pratinjau normal", ui.state.stage = "input" && !InStr(ui.preview.Text, "Tersimpan") && InStr(ui.preview.Text, "kopi"), ui.preview.Text)
ui.date.Value := "2026-08-31"
ui.Enter()
Check("input kedua juga tersimpan & ke-reset", Saved(ui) && closed = 0)
ui.Esc()
Check("Esc setelah simpan menutup", closed = 1)
ui.gui.Destroy()
Check("dua input berurutan masuk ke note masing-masing", InStr(ReadRaw(daily FormatTime(DateAdd(A_Now, -1, "Days"), "yyyy-MM-dd") ".md"), "[expense] le mineral [amount:: 20000]") && InStr(ReadRaw(daily "2026-08-31.md"), "[expense] kopi [amount:: 5000]"))

; ---- 12. input berulang lewat jalur pilih kategori (item belum dikenal) ----
ui := Open()
Fill(ui, "gado gado 12000")
ui.Enter(), ui.Key("1"), ui.Key("n")
Check("setelah pick -> tersimpan, form aktif lagi", Saved(ui) && closed = 0)
Fill(ui, "gado gado 13000")
ui.Enter()
Check("item yang baru dipelajari tidak ditanya lagi saat input berulang", Saved(ui) && InStr(ReadRaw(daily "2026-08-31.md"), "gado gado [amount:: 13000] [category:: pangan] [type:: need]"))
ui.gui.Destroy()

Out(passed " lulus, " failed " gagal")
ExitApp(failed ? 1 : 0)
