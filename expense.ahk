#Requires AutoHotkey v2.0

; expense.ahk -- logika pencatatan pengeluaran KOHA, TANPA GUI:
; parse input satu baris ("kopi susu 8k, ketoprak 15000"), pilah kategori/
; type dari rules.md di vault, lalu tulis ke daily note Obsidian. Popup
; input-nya sendiri (tahap berikutnya) cuma manggil RecordExpenses() di
; bawah. Sengaja dipisah dari koha.ahk supaya bisa dites lewat
; console (tests/expense_test.ahk) tanpa nyentuh vault asli.
;
; Semua fungsi nerima path vault sebagai parameter -- EXPENSE_VAULT cuma
; default buat popup; hardcoded, alasannya sama kayak $ObsidianVaultRoot di
; scripts/lib.ps1 (tool pribadi satu user).

EXPENSE_VAULT := "C:\Users\ThinkPad\Documents\Obsidian-Vault"
EXPENSE_RULES_REL := "Z0014-finance\rules.md"
EXPENSE_DAILY_REL := "Z0010-daily"
EXPENSE_TEMPLATE_REL := "Z0005-templates\Template Daily New.md"

; Harus sama persis dengan daftar kategori di rules.md. Baris aturan yang
; kategorinya gak ada di sini DIABAIKAN -- inilah yang bikin baris
; penjelasan di rules.md (yang kebetulan mengandung "=>") gak kebaca aturan.
EXPENSE_CATEGORIES := Map(
    "pangan", 1, "papan", 1, "sandang", 1, "transportasi", 1, "kesehatan", 1,
    "hiburan", 1, "sosial", 1, "infaq", 1, "investasi", 1, "hutang", 1, "lainnya", 1,
)
; Nama hari bahasa Inggris, bukan FormatTime "dddd" -- itu ikut locale
; Windows, sedangkan Obsidian nulis "Thursday" di judul daily note.
EXPENSE_WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

; "8k"/"8rb"/"8ribu" -> 8000, "1.5jt" -> 1500000, "15.000" (titik ribuan) ->
; 15000, "Rp 15000" -> 15000. Return 0 kalau bukan nominal valid -- angka
; di bawah 100 dianggap bukan nominal (kemungkinan besar bagian dari nama,
; misal "telur omega 3").
ParseAmount(s) {
    s := StrLower(Trim(s))
    s := RegExReplace(s, "^rp\.?\s*")
    if RegExMatch(s, "^\d{1,3}(\.\d{3})+$")
        return Integer(StrReplace(s, "."))
    if RegExMatch(s, "^(\d+(?:[.,]\d+)?)\s*(rb|ribu|k|jt|juta)?$", &m) {
        mult := (m[2] = "") ? 1 : (m[2] = "jt" || m[2] = "juta") ? 1000000 : 1000
        amt := Round(Float(StrReplace(m[1], ",", ".")) * mult)
        return amt >= 100 ? amt : 0
    }
    return 0
}

; Satu entri = "nama nominal" (nominal di belakang) atau "nominal nama"
; (nominal di depan). Belakang dicoba duluan supaya "telur omg 3 29000"
; kebaca nominalnya 29000, bukan 3.
ParseExpenseEntry(text) {
    text := Trim(RegExReplace(text, "\s+", " "))
    if RegExMatch(text, "^(.*\S) (\S+)$", &m) && (amt := ParseAmount(m[2]))
        return { ok: true, name: m[1], amount: amt }
    if RegExMatch(text, "^(\S+) (.*\S)$", &m) && (amt := ParseAmount(m[1]))
        return { ok: true, name: m[2], amount: amt }
    return { ok: false, name: text, amount: 0 }
}

; Pisah beberapa item sekaligus: koma+spasi, titik koma, atau baris baru
; ("1,5jt" gak kepotong karena gak ada spasi sesudah koma). Potongan yang
; belum punya nominal digabung ke potongan berikutnya, jadi nama yang
; mengandung koma ("hutang ke budi, bayar ketoprak 40000") tetap utuh.
; Return { entries: [{name, amount}], errors: [teks yang gagal di-parse] }.
ParseExpenseInput(text) {
    entries := [], errors := []
    pending := ""
    pieces := StrSplit(StrReplace(RegExReplace(text, ",\s+", "`n"), ";", "`n"), "`n", "`r")
    for piece in pieces {
        piece := Trim(piece)
        if piece = ""
            continue
        candidate := (pending = "") ? piece : pending ", " piece
        e := ParseExpenseEntry(candidate)
        if e.ok {
            entries.Push(e)
            pending := ""
        } else {
            pending := candidate
        }
    }
    if pending != ""
        errors.Push(pending)
    return { entries: entries, errors: errors }
}

; Tanggal dari ketikan user: kosong/"hari ini" = hari ini, "kemarin" = -1,
; "-N" = N hari lalu, "YYYY-MM-DD", "DD-MM-YYYY" (gaya catatan user, mis.
; 31-08-2026), "DD-MM" (tahun ini). Return "YYYY-MM-DD", atau "" kalau
; gak valid. now diparameterin biar bisa dites.
ResolveExpenseDate(input, now := "") {
    if now = ""
        now := A_Now
    input := StrLower(Trim(input))
    y := "", mo := "", d := ""
    if input = "" || input = "hari ini" || input = "today"
        return FormatTime(now, "yyyy-MM-dd")
    if input = "kemarin" || input = "yesterday"
        return FormatTime(DateAdd(now, -1, "Days"), "yyyy-MM-dd")
    if RegExMatch(input, "^-(\d{1,3})$", &m)
        return FormatTime(DateAdd(now, -Integer(m[1]), "Days"), "yyyy-MM-dd")
    if RegExMatch(input, "^(\d{4})-(\d{1,2})-(\d{1,2})$", &m)
        y := m[1], mo := m[2], d := m[3]
    else if RegExMatch(input, "^(\d{1,2})-(\d{1,2})-(\d{4})$", &m)
        d := m[1], mo := m[2], y := m[3]
    else if RegExMatch(input, "^(\d{1,2})-(\d{1,2})$", &m)
        d := m[1], mo := m[2], y := FormatTime(now, "yyyy")
    else
        return ""
    ds := Format("{:04}-{:02}-{:02}", y, mo, d)
    return IsValidDateStr(ds) ? ds : ""
}

; "2026-02-30" lolos regex tapi bukan tanggal -- DateAdd ngelempar
; ValueError buat tanggal yang gak ada, dipakai sebagai validator.
IsValidDateStr(ds) {
    if !RegExMatch(ds, "^\d{4}-\d{2}-\d{2}$")
        return false
    try {
        t := StrReplace(ds, "-") "000000"
        DateAdd(t, 0, "Days")
        return FormatTime(t, "yyyy-MM-dd") = ds
    } catch
        return false
}

; ---- Aturan kategori (rules.md) ----------------------------------------

; Satu aturan per baris: "kata, kata => kategori | type". Return array
; { kw, cat, type }, kata kunci sudah lowercase.
LoadExpenseRules(path) {
    rules := []
    if !FileExist(path)
        return rules
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if line = "" || SubStr(line, 1, 1) = "#" || !InStr(line, "=>")
            continue
        halves := StrSplit(line, "=>", , 2)
        parts := StrSplit(halves[2], "|")
        if parts.Length != 2
            continue
        cat := StrLower(Trim(parts[1])), typ := StrLower(Trim(parts[2]))
        if !EXPENSE_CATEGORIES.Has(cat) || !(typ = "need" || typ = "want" || typ = "-")
            continue
        for rawKw in StrSplit(halves[1], ",") {
            kw := StrLower(Trim(rawKw))
            if kw != ""
                rules.Push({ kw: kw, cat: cat, type: typ })
        }
    }
    return rules
}

; Kata kunci cocok kalau muncul di AWAL kata (jadi "kopi" kena "kopinya",
; tapi "tol" gak kena "tolak angin"); kata kunci pendek (<=4 huruf: sei,
; kos, tol, krl) harus cocok SATU KATA PENUH, soalnya awalan 3-4 huruf
; terlalu sering nabrak kata lain. Beberapa aturan cocok -> kata kunci
; terpanjang menang ("kopi nako" > "kopi"), KECUALI kategori hutang yang
; selalu menang -- "hutang ke budi, bayar ketoprak" itu hutang, bukan
; pangan, walau "ketoprak" lebih panjang. Gak ada yang cocok -> known:
; false, category "lainnya"/"want" (popup yang nentuin mau nanya atau
; nyimpen dengan tag #review).
ClassifyExpense(rules, name) {
    lower := StrLower(name)
    best := ""
    for r in rules {
        tail := (StrLen(r.kw) <= 4) ? "(?![a-z0-9])" : ""
        if RegExMatch(lower, "(?<![a-z0-9])\Q" r.kw "\E" tail)
            && (best = "" || (r.cat = "hutang" && best.cat != "hutang")
                || (best.cat != "hutang" && StrLen(r.kw) > StrLen(best.kw)))
            best := r
    }
    if best = ""
        return { cat: "lainnya", type: "want", known: false, kw: "" }
    return { cat: best.cat, type: best.type, known: true, kw: best.kw }
}

; Tebakan type dari kategori, buat kasus user milih kategori manual di
; popup tapi belum milih type. "" = kategori ambigu (pangan/sandang/
; lainnya) -- jangan ditebak, tanya.
DefaultExpenseType(cat) {
    switch cat {
        case "papan", "kesehatan", "transportasi", "infaq", "investasi": return "need"
        case "hiburan", "sosial": return "want"
        case "hutang": return "-"
    }
    return ""
}

; Tambah aturan hasil "belajar" dari pilihan user di popup, di bawah
; heading "Dipelajari otomatis" (dibuat kalau belum ada). Pakai EOL file
; yang sudah ada biar gak nyampur CRLF/LF.
AppendExpenseRule(rulesPath, kw, cat, typ) {
    kw := Trim(StrLower(RegExReplace(RegExReplace(kw, "[,|]|=>", " "), "\s+", " ")))
    if kw = "" || !EXPENSE_CATEGORIES.Has(cat) || !(typ = "need" || typ = "want" || typ = "-")
        throw ValueError("aturan gak valid", -1, kw " => " cat " | " typ)
    text := FileExist(rulesPath) ? FileRead(rulesPath, "UTF-8") : ""
    eol := InStr(text, "`r`n") ? "`r`n" : "`n"
    if text != "" && SubStr(text, -1) != "`n"
        text .= eol
    if !InStr(text, "## Dipelajari otomatis")
        text .= eol "## Dipelajari otomatis" eol
    text .= kw " => " cat " | " typ eol
    WriteTextAtomic(rulesPath, text)
}

; ---- Format & tulis ke daily note --------------------------------------

; Satu transaksi = satu baris, field di dalam kurung siku (inline field
; Dataview) -- beda dari format lama 5-baris yang dicocokkan lewat indeks
; array dan bergeser kalau satu field hilang.
FormatExpenseLine(name, amount, cat, typ, payment, review := false) {
    name := RegExReplace(name, "\s+", " ")
    name := StrReplace(StrReplace(StrReplace(name, "[", "("), "]", ")"), "::", ":")
    payment := Trim(StrLower(RegExReplace(payment, "[\[\]\r\n]", "")))
    line := "- [expense] " name " [amount:: " amount "] [category:: " cat "] [type:: " typ "] [payment:: " payment "]"
    return review ? line " #review" : line
}

; Parse -> klasifikasi -> tulis, semua-atau-tidak-sama-sekali: kalau ada
; potongan input yang gagal di-parse, gak ada yang ditulis dan errors-nya
; dikembalikan, jadi user gak perlu nebak mana yang sudah masuk.
; Return { saved, lines, unknown: [nama yang gak dikenal], errors }.
; Tanggal invalid / template hilang dilempar sebagai exception.
RecordExpenses(vault, dateStr, payment, text) {
    parsed := ParseExpenseInput(text)
    if parsed.errors.Length || !parsed.entries.Length
        return { saved: 0, lines: [], unknown: [], errors: parsed.errors, learned: [] }
    return RecordParsedExpenses(vault, dateStr, payment, parsed.entries)
}

; Versi yang nerima entries hasil ParseExpenseInput + pilihan manual user
; dari popup. overrides = Map index-entri -> { cat, type, learn }: entri
; yang ada di sini TIDAK diklasifikasi dari rules.md (pilihan user menang);
; learn=true (item yang tadinya gak dikenal) = pilihan itu juga ditambah ke
; rules.md SETELAH daftar transaksinya sukses ditulis, jadi gagal nulis
; gak ninggalin aturan yatim. learn=false = koreksi sekali pakai buat
; transaksi itu saja. Gagal nulis aturan gak membatalkan transaksi yang
; sudah masuk -- dilaporkan di result.learnError.
RecordParsedExpenses(vault, dateStr, payment, entries, overrides := "") {
    rules := LoadExpenseRules(vault "\" EXPENSE_RULES_REL)
    result := { saved: 0, lines: [], unknown: [], errors: [], learned: [], learnError: "" }
    toLearn := Map()
    for i, e in entries {
        if IsObject(overrides) && overrides.Has(i) {
            o := overrides[i]
            cat := o.cat, typ := o.type, known := true
            if o.learn
                toLearn[ExpenseLearnKeyword(e.name)] := o
        } else {
            c := ClassifyExpense(rules, e.name)
            cat := c.cat, typ := c.type, known := c.known
        }
        if !known
            result.unknown.Push(e.name)
        result.lines.Push(FormatExpenseLine(e.name, e.amount, cat, typ, payment, !known))
    }
    AddExpenseLines(vault, dateStr, result.lines)
    result.saved := result.lines.Length
    for kw, o in toLearn {
        try {
            AppendExpenseRule(vault "\" EXPENSE_RULES_REL, kw, o.cat, o.type)
            result.learned.Push(kw)
        } catch as err
            result.learnError := err.Message
    }
    return result
}

AddExpenseLines(vault, dateStr, lines) {
    if !IsValidDateStr(dateStr)
        throw ValueError("tanggal gak valid", -1, dateStr)
    path := vault "\" EXPENSE_DAILY_REL "\" dateStr ".md"
    text := FileExist(path) ? FileRead(path, "UTF-8") : NewDailyNoteText(vault, dateStr)
    ; EOL dikembalikan ke aslinya (330 dari 430 daily note user CRLF, sisanya
    ; LF) -- biar Obsidian/git gak melihat seluruh file berubah.
    eol := InStr(text, "`r`n") ? "`r`n" : "`n"
    text := InsertIntoFinanceSection(StrReplace(text, "`r`n", "`n"), lines)
    WriteTextAtomic(path, StrReplace(text, "`n", eol))
}

; Daily note belum ada (mis. catat pengeluaran kemarin/tanggal lampau yang
; gak pernah dibuka di Obsidian) -> bikin dari Template Daily New, ganti
; {{date:...}} jadi "YYYY-MM-DD Weekday" persis format template-nya.
NewDailyNoteText(vault, dateStr) {
    tpl := vault "\" EXPENSE_TEMPLATE_REL
    if !FileExist(tpl)
        throw OSError("template daily gak ketemu", -1, tpl)
    wday := FormatTime(StrReplace(dateStr, "-") "120000", "WDay")
    stamp := dateStr " " EXPENSE_WEEKDAYS[Integer(wday)]
    text := FileRead(tpl, "UTF-8")
    text := RegExReplace(text, "\{\{date:[^}]*\}\}", stamp)
    return StrReplace(StrReplace(text, "{{date}}", dateStr), "{{title}}", dateStr)
}

; text sudah dinormalisasi ke LF. Cari section "## <emoji> Finance":
;  - ada: buang placeholder template (expense:: null dkk) HANYA kalau gak
;    ada transaksi lama yang berisi di section itu (kalau ada, "payment::
;    null" bisa jadi milik transaksi asli yang lupa isi payment -- jangan
;    disentuh); baris baru ditaruh sesudah isi terakhir section.
;  - gak ada (daily note lama sebelum ada section Finance): section dibuat
;    sebelum "What i Eat", atau "Notes", atau di akhir file.
InsertIntoFinanceSection(text, newLines) {
    all := StrSplit(text, "`n")
    fi := 0, wi := 0, ni := 0
    for i, l in all {
        if !fi && RegExMatch(l, "^##\s+\S+\s*Finance\s*$")
            fi := i
        else if !wi && RegExMatch(l, "^##\s+\S+\s*What i Eat")
            wi := i
        else if !ni && RegExMatch(l, "^#\s+\S+\s*Notes")
            ni := i
    }
    out := []
    if !fi {
        at := wi ? wi : ni ? ni : all.Length + 1
        for i, l in all {
            if i = at
                AppendNewSection(out, newLines)
            out.Push(l)
        }
        if at > all.Length
            AppendNewSection(out, newLines)
        return JoinLines(out)
    }
    ; akhir section = pemisah (--- / ___) atau heading berikutnya
    endAt := all.Length + 1
    loop all.Length - fi {
        if RegExMatch(all[fi + A_Index], "^(-{3,}|_{3,}|#{1,6}\s)") {
            endAt := fi + A_Index
            break
        }
    }
    body := []
    hasReal := false
    loop endAt - fi - 1 {
        l := all[fi + A_Index]
        if RegExMatch(l, "i)^expense::\s*\S") && !RegExMatch(l, "i)^expense::\s*null\s*$")
            hasReal := true
        if RegExMatch(l, "^- \[expense\]")
            hasReal := true
        body.Push(l)
    }
    if !hasReal {
        kept := []
        for l in body
            if !RegExMatch(l, "i)^(expense|amount|category|type|payment)::\s*(null|0)?\s*$")
                kept.Push(l)
        body := kept
    }
    while body.Length && Trim(body[1]) = ""
        body.RemoveAt(1)
    while body.Length && Trim(body[body.Length]) = ""
        body.Pop()
    ; blok lama 5-baris + baris baru nempel tanpa jarak = payment:: dan
    ; "- [expense]" kebaca satu paragraf, jadi kasih satu baris kosong.
    if body.Length && !RegExMatch(body[body.Length], "^- \[expense\]")
        body.Push("")
    for l in newLines
        body.Push(l)
    for i, l in all {
        if i < fi
            out.Push(l)
        else if i = fi {
            out.Push(l)
            out.Push("")
            for b in body
                out.Push(b)
            out.Push("")
        } else if i >= endAt
            out.Push(l)
    }
    return JoinLines(out)
}

AppendNewSection(out, newLines) {
    out.Push("## " Chr(0x1F4B8) " Finance")
    out.Push("")
    for l in newLines
        out.Push(l)
    out.Push("")
    out.Push("---")
    out.Push("")
}

JoinLines(arr) {
    s := ""
    for i, l in arr
        s .= (i = 1 ? "" : "`n") l
    return s
}

; UTF-8 tanpa BOM (file Obsidian gak pakai BOM) lewat file temp di folder
; yang sama lalu rename, jadi crash di tengah nulis gak ninggalin daily
; note terpotong.
WriteTextAtomic(path, text) {
    tmp := path ".qm-tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
    FileMove(tmp, path, 1)
}

; ---- Bantuan buat popup -------------------------------------------------

; 9 kategori yang bisa dipilih lewat tombol angka 1-9 buat item yang belum
; dikenal. Sengaja TANPA "hutang" (otomatis dari kata hutang/utang/pinjam)
; dan "lainnya" (hasil bawaan kalau user cuma tekan Enter).
EXPENSE_PICK_CATEGORIES := ["pangan", "papan", "sandang", "transportasi", "kesehatan",
    "hiburan", "sosial", "infaq", "investasi"]

; 15000 -> "Rp 15.000"
FormatRupiah(n) {
    s := String(n), out := ""
    while StrLen(s) > 3 {
        out := "." SubStr(s, -3) out
        s := SubStr(s, 1, StrLen(s) - 3)
    }
    return "Rp " s out
}

; Kata kunci yang dipelajari dari nama item yang baru dikenalkan: kata
; yang mengandung angka dibuang ("frisian flag uht 946ml" -> "frisian flag
; uht", "seblak (3)" -> "seblak") supaya ukuran/jumlah gak ikut jadi syarat
; cocok. Semua kata dibuang (nama isinya angka doang) -> pakai nama utuh.
ExpenseLearnKeyword(name) {
    kept := ""
    for tok in StrSplit(Trim(RegExReplace(StrLower(name), "[^\p{L}\p{N} ]", " ")), " ") {
        if tok != "" && !RegExMatch(tok, "\d")
            kept .= (kept = "" ? "" : " ") tok
    }
    return kept != "" ? kept : Trim(RegExReplace(StrLower(name), "\s+", " "))
}

; Baris pratinjau live di popup, satu per transaksi: "nama  Rp  kategori/
; type" atau "? belum dikenal"; potongan yang gagal di-parse ditandai "!".
; Maksimal 4 baris biar tinggi popup tetap.
ExpensePreviewLines(rules, parsed) {
    lines := []
    for e in parsed.entries {
        c := ClassifyExpense(rules, e.name)
        name := StrLen(e.name) > 22 ? SubStr(e.name, 1, 21) "~" : e.name
        lines.Push(Format("{:-22} {:11}  {}", name, FormatRupiah(e.amount), c.known ? c.cat "/" c.type : "? belum dikenal"))
    }
    for t in parsed.errors
        lines.Push('! nominal gak terbaca: "' (StrLen(t) > 30 ? SubStr(t, 1, 29) "~" : t) '"')
    if lines.Length > 4 {
        extra := lines.Length - 3
        lines.RemoveAt(4, extra)
        lines.Push("... +" extra " lagi")
    }
    return lines
}
