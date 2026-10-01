#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\expense.ahk

; Tes expense.ahk lewat console -- gak ada GUI, gak nyentuh vault asli.
;   1. sh tests/make-test-vault.sh <vault-asli> <folder-salinan>
;   2. AutoHotkey64.exe tests/expense_test.ahk <folder-salinan> [rows.tsv] | cat
; (| cat perlu karena AHK subsystem GUI -- stdout cuma kebaca kalau di-pipe)
; rows.tsv opsional: "nama<TAB>kategori<TAB>type" per baris, buat uji regresi
; aturan terhadap transaksi asli user.

; Runtime error di AHK v2 = dialog modal yang bikin tes menggantung kalau
; dijalankan tanpa layar -- ubah jadi output + exit code 2.
OnError((e, *) => (FileAppend("ERROR: " e.Message " (" e.What ") baris " e.Line "`n", "*", "UTF-8"), ExitApp(2)))

passed := 0, failed := 0
vault := A_Args[1]

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

; ---- ParseAmount ----
for pair in [["8000", 8000], ["8k", 8000], ["8rb", 8000], ["8 ribu", 8000], ["15.000", 15000],
             ["1.500", 1500], ["1.5jt", 1500000], ["2jt", 2000000], ["Rp 15000", 15000],
             ["Rp. 15.000", 15000], ["3", 0], ["50", 0], ["abc", 0], ["", 0], ["12.34", 0]]
    Check("ParseAmount " pair[1], ParseAmount(pair[1]) = pair[2], ParseAmount(pair[1]))

; ---- ParseExpenseInput ----
p := ParseExpenseInput("kopi susu jago 8000")
Check("parse 1 item", p.entries.Length = 1 && p.entries[1].name = "kopi susu jago" && p.entries[1].amount = 8000)
p := ParseExpenseInput("ketoprak 15000, es teh 5k")
Check("parse 2 item koma", p.entries.Length = 2 && p.entries[2].name = "es teh" && p.entries[2].amount = 5000)
p := ParseExpenseInput("telur omg 3 29000")
Check("angka di nama gak dianggap nominal", p.entries.Length = 1 && p.entries[1].name = "telur omg 3" && p.entries[1].amount = 29000)
p := ParseExpenseInput("8000 kopi susu")
Check("nominal di depan", p.entries.Length = 1 && p.entries[1].name = "kopi susu" && p.entries[1].amount = 8000)
p := ParseExpenseInput("hutang ke budi, bayar ketoprak + sei 40000")
Check("nama berkoma tetap utuh", p.entries.Length = 1 && p.entries[1].amount = 40000 && InStr(p.entries[1].name, "budi, bayar"))
p := ParseExpenseInput("kopi")
Check("tanpa nominal = error", p.entries.Length = 0 && p.errors.Length = 1)
p := ParseExpenseInput("kopi 8000; nasi")
Check("sebagian error", p.entries.Length = 1 && p.errors.Length = 1)
p := ParseExpenseInput("gaji 1,5jt")
Check("koma desimal gak dipecah", p.entries.Length = 1 && p.entries[1].amount = 1500000)
p := ParseExpenseInput("kopi 8000`nnasi 12000`n")
Check("pemisah newline", p.entries.Length = 2)

; ---- ResolveExpenseDate ----
now := "20261001103000"
Check("date kosong", ResolveExpenseDate("", now) = "2026-10-01")
Check("date kemarin", ResolveExpenseDate("kemarin", now) = "2026-09-30")
Check("date -2", ResolveExpenseDate("-2", now) = "2026-09-29")
Check("date -31 lintas bulan", ResolveExpenseDate("-31", now) = "2026-08-31")
Check("date iso", ResolveExpenseDate("2026-05-10", now) = "2026-05-10")
Check("date DD-MM-YYYY", ResolveExpenseDate("31-08-2026", now) = "2026-08-31")
Check("date DD-MM", ResolveExpenseDate("5-9", now) = "2026-09-05")
Check("date gak ada", ResolveExpenseDate("2026-02-30", now) = "")
Check("date sampah", ResolveExpenseDate("besok-lusa", now) = "")

; ---- rules & klasifikasi ----
rules := LoadExpenseRules(vault "\" EXPENSE_RULES_REL)
Check("rules ke-load", rules.Length > 100, rules.Length)
for t in [["kopi nako + donat", "pangan", "want"], ["le mineral galon", "pangan", "need"],
          ["Gojek Pulang + tip 5000", "transportasi", "need"], ["hutang ke budi", "hutang", "-"],
          ["utang kopi", "hutang", "-"], ["Laundry 6 kg", "sandang", "need"], ["tolak angin", "lainnya", "want"],
          ["tol cikampek", "transportasi", "need"], ["ke kosan teman", "lainnya", "want"], ["xyzzy", "lainnya", "want"]] {
    c := ClassifyExpense(rules, t[1])
    Check("classify " t[1], c.cat = t[2] && c.type = t[3], c.cat "|" c.type)
}
Check("unknown known=false", !ClassifyExpense(rules, "xyzzy").known)
Check("kata kunci terpanjang menang", ClassifyExpense(rules, "tisu indomaret wajah 900g").cat = "pangan")
Check("DefaultExpenseType", DefaultExpenseType("papan") = "need" && DefaultExpenseType("hiburan") = "want"
    && DefaultExpenseType("pangan") = "" && DefaultExpenseType("hutang") = "-")

; Regresi terhadap transaksi asli (in-sample): minimal 111 dari 116 tepat
if A_Args.Length >= 2 && FileExist(A_Args[2]) {
    ok := 0, total := 0
    for line in StrSplit(FileRead(A_Args[2], "UTF-8"), "`n", "`r") {
        if line = ""
            continue
        f := StrSplit(line, "`t")
        total++
        c := ClassifyExpense(rules, f[1])
        if c.cat = f[2] && c.type = f[3]
            ok++
        else
            Out("  regresi beda: " f[1] " | user " f[2] "/" f[3] " | rule " c.cat "/" c.type)
    }
    Out("regresi aturan: " ok "/" total " tepat")
    Check("regresi >= 111", ok >= 111, ok "/" total)
}

; ---- FormatExpenseLine ----
Check("format line", FormatExpenseLine("kopi susu", 8000, "pangan", "want", "ShopeePay")
    = "- [expense] kopi susu [amount:: 8000] [category:: pangan] [type:: want] [payment:: shopeepay]")
Check("format sanitasi + review", FormatExpenseLine("a [b] c::d", 100, "lainnya", "want", "cash", true)
    = "- [expense] a (b) c:d [amount:: 100] [category:: lainnya] [type:: want] [payment:: cash] #review")

; ---- penulis: placeholder null (LF) ----
daily := vault "\" EXPENSE_DAILY_REL "\"
before := ReadRaw(daily "2026-09-30.md")
r := RecordExpenses(vault, "2026-09-30", "ShopeePay", "kopi susu jago 8k, ketoprak 15000")
after := ReadRaw(daily "2026-09-30.md")
Check("null: 2 baris tersimpan", r.saved = 2 && r.unknown.Length = 0)
Check("null: placeholder hilang", !InStr(after, "expense:: null") && !InStr(after, "amount:: 0"))
Check("null: baris masuk di bawah Finance", InStr(after, "## " Chr(0x1F4B8) " Finance`n`n- [expense] kopi susu jago [amount:: 8000]")
    && InStr(after, "[payment:: shopeepay]`n- [expense] ketoprak [amount:: 15000]"), after)
Check("null: tetap LF", !InStr(after, "`r"))
Check("null: bagian lain gak berubah", SubStr(before, 1, InStr(before, "## " Chr(0x1F4B8) " Finance") - 1)
    = SubStr(after, 1, InStr(after, "## " Chr(0x1F4B8) " Finance") - 1)
    && SubStr(before, InStr(before, "`n---`n`n## " Chr(0x1F356))) = SubStr(after, InStr(after, "`n---`n`n## " Chr(0x1F356))))
Check("null: tanpa BOM", SubStr(after, 1, 1) = "-")
; tambah lagi -> urut, tanpa baris kosong nyelip
RecordExpenses(vault, "2026-09-30", "cash", "es teh 5000")
after2 := ReadRaw(daily "2026-09-30.md")
Check("append kedua nempel", InStr(after2, "[payment:: shopeepay]`n- [expense] es teh [amount:: 5000]"), after2)

; ---- penulis: blok 5-baris lama (CRLF) ----
before := ReadRaw(daily "2026-05-10.md")
RecordExpenses(vault, "2026-05-10", "gopay", "bakso 20000")
after := ReadRaw(daily "2026-05-10.md")
Check("lama: blok lama utuh", InStr(after, "expense:: Telur OMG 3`r`namount:: 29000`r`ncategory:: pangan`r`ntype:: need`r`npayment:: gopay"))
Check("lama: baris baru dipisah blank dari blok lama", InStr(after, "payment:: gopay`r`n`r`n- [expense] bakso [amount:: 20000]"))
Check("lama: tetap CRLF penuh", !RegExMatch(after, "(?<!\r)\n"))
Check("lama: bagian Notes gak berubah", SubStr(before, InStr(before, "# " Chr(0x1F9E0) " Notes")) = SubStr(after, InStr(after, "# " Chr(0x1F9E0) " Notes")))

; ---- penulis: note tanpa section Finance (CRLF) ----
RecordExpenses(vault, "2026-04-30", "cash", "parkir 2000")
after := ReadRaw(daily "2026-04-30.md")
Check("tanpa section: dibuat sebelum What i Eat", RegExMatch(after, "s)Night.*## \S+ Finance\r\n\r\n- \[expense\] parkir.*---\r\n\r\n## \S+ What i Eat"), after)
Check("tanpa section: tetap CRLF penuh", !RegExMatch(after, "(?<!\r)\n"))

; ---- penulis: note belum ada -> dari template ----
Check("belum ada: file memang gak ada", !FileExist(daily "2026-12-25.md"))
RecordExpenses(vault, "2026-12-25", "cash", "kado 50000")
after := ReadRaw(daily "2026-12-25.md")
Check("belum ada: judul tanggal + hari", InStr(after, "# " Chr(0x1F4C5) " 2026-12-25 Friday"), SubStr(after, 1, 120))
Check("belum ada: transaksi masuk, placeholder hilang", InStr(after, "[expense] kado [amount:: 50000] [category:: sosial] [type:: want]") && !InStr(after, "expense:: null"))

; ---- penulis: hutang & unknown & all-or-nothing & tanggal invalid ----
r := RecordExpenses(vault, "2026-08-31", "bca", "hutang ke budi 40000, xyzzy 3k")
after := ReadRaw(daily "2026-08-31.md")
Check("hutang: type -", InStr(after, "[category:: hutang] [type:: -] [payment:: bca]"))
Check("unknown: #review + dilaporkan", r.unknown.Length = 1 && r.unknown[1] = "xyzzy" && InStr(after, "[category:: lainnya] [type:: want] [payment:: bca] #review"))
snap := ReadRaw(daily "2026-08-31.md")
r := RecordExpenses(vault, "2026-08-31", "cash", "kopi 8000, nasi")
Check("all-or-nothing: error -> gak ada yang ditulis", r.saved = 0 && r.errors.Length = 1 && ReadRaw(daily "2026-08-31.md") = snap)
threw := false
try RecordExpenses(vault, "2026-02-30", "cash", "kopi 8000")
catch
    threw := true
Check("tanggal invalid -> exception", threw)
Check("gak ada file temp tersisa", !FileExist(daily "*.qm-tmp"))

; ---- AppendExpenseRule ----
rp := vault "\" EXPENSE_RULES_REL
n0 := LoadExpenseRules(rp).Length
AppendExpenseRule(rp, "Seblak, Mang Ujang", "pangan", "want")
rules2 := LoadExpenseRules(rp)
Check("rule baru ke-load", rules2.Length = n0 + 1 && ClassifyExpense(rules2, "seblak mang ujang pedas").cat = "pangan")
Check("rule baru di bawah heading", InStr(ReadRaw(rp), "## Dipelajari otomatis"))
AppendExpenseRule(rp, "cilok", "pangan", "want")
Check("heading gak dobel", StrSplit(ReadRaw(rp), "## Dipelajari otomatis").Length = 2)

Out(passed " lulus, " failed " gagal")
ExitApp(failed ? 1 : 0)
