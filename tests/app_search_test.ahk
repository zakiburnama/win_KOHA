#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\app_search.ahk

; Tes Search Apps: pemindai Start Menu (folder palsu berisi shortcut
; buatan), pencocokan/urutan, dan state popup. Tidak ada tombol yang
; dikirim -- handler dipanggil langsung (lihat expense_popup_test.ahk).
;   AutoHotkey64.exe tests/app_search_test.ahk | cat

OnError((e, *) => (FileAppend("ERROR: " e.Message " (" e.What ") baris " e.Line "`n", "*", "UTF-8"), ExitApp(2)))

passed := 0, failed := 0
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
Names(arr) {
    s := ""
    for a in arr
        s .= (s = "" ? "" : ", ") a.name
    return s
}

root := A_Temp "\koha-appsearch-test"
if DirExist(root)
    DirDelete(root, true)
userDir := root "\user", sysDir := root "\sys"
DirCreate(userDir "\Sub")
DirCreate(sysDir)
for n in ["Visual Studio Code", "Obsidian", "WezTerm", "Notepad", "Notepad++"]
    FileCreateShortcut(A_ComSpec, sysDir "\" n ".lnk")
FileCreateShortcut(A_ComSpec, userDir "\Sub\Google Chrome.lnk")
FileCreateShortcut(A_ComSpec, userDir "\Obsidian.lnk")        ; kembar dengan sys -> user menang
FileCreateShortcut(A_ComSpec, sysDir "\Uninstall Foo.lnk")    ; dibuang
FileAppend("[InternetShortcut]`nURL=https://example.com`n", sysDir "\Some Web App.url")
FileAppend("bukan shortcut", sysDir "\readme.txt")

apps := ScanStartMenuApps([userDir, sysDir])
Check("scan: 7 app (txt, uninstall, duplikat dibuang)", apps.Length = 7, apps.Length " -> " Names(apps))
obs := 0
for a in apps
    if a.lower = "obsidian"
        obs := a
Check("scan: duplikat -> versi user", IsObject(obs) && InStr(obs.path, "\user\"), IsObject(obs) ? obs.path : "tidak ada")
Check("scan: folder tidak ada diabaikan", ScanStartMenuApps([root "\nope"]).Length = 0)
real := ScanStartMenuApps()
Check("scan: Start Menu asli ada isinya", real.Length > 0, real.Length)

; ---- pencocokan ----
Check("query kosong -> []", SearchApps(apps, "").Length = 0 && SearchApps(apps, "   ").Length = 0)
Check("prefix", SearchApps(apps, "obs")[1].name = "Obsidian")
Check("tidak peka huruf besar", SearchApps(apps, "OBSID")[1].name = "Obsidian")
Check("awal kata", SearchApps(apps, "studio")[1].name = "Visual Studio Code")
Check("singkatan huruf awal", SearchApps(apps, "vsc")[1].name = "Visual Studio Code")
Check("subsequence", SearchApps(apps, "wzt")[1].name = "WezTerm")
Check("beberapa kata, semua harus cocok", SearchApps(apps, "google chr")[1].name = "Google Chrome" && SearchApps(apps, "google zzz").Length = 0)
Check("tidak ada yang cocok", SearchApps(apps, "qqq").Length = 0)
r := SearchApps(apps, "notepad")
Check("urutan: lebih pendek dulu", r.Length = 2 && r[1].name = "Notepad" && r[2].name = "Notepad++", Names(r))
Check("limit", SearchApps(apps, "o", 2).Length = 2)
Check("1 huruf: tidak ada subsequence", SearchApps(apps, "x").Length = 0)

; ---- popup ----
box := { closed: 0, launched: "" }
theme := { bg: "141415", fg: "CDCDCD", selBg: "6E94B2", selFg: "141415", bezel: "1C1C24" }
ui := ShowAppSearchPopup(theme, { dirs: [userDir, sysDir], onClose: (*) => box.closed++, onLaunch: (p) => box.launched := p })
Check("popup: awal kosong + hint", ui.state.hits.Length = 0 && InStr(ui.rows[1].Text, "ketik"))
ui.input.Value := "note"
ui.Changed()
Check("popup: hasil muncul, baris 1 terpilih", ui.state.hits.Length = 2 && ui.rows[1].Text = "> Notepad" && ui.rows[2].Text = "  Notepad++", ui.rows[1].Text "|" ui.rows[2].Text)
ui.Move(1)
Check("popup: Down pindah seleksi", ui.state.selected = 2 && ui.rows[2].Text = "> Notepad++")
ui.Move(1)
Check("popup: Down dari bawah -> atas", ui.state.selected = 1)
ui.Move(-1)
Check("popup: Up dari atas -> bawah", ui.state.selected = 2)
ui.input.Value := "zzzz"
ui.Changed()
Check("popup: tidak cocok", InStr(ui.rows[1].Text, "tidak ada yang cocok") && ui.state.hits.Length = 0)
ui.Enter()
Check("popup: Enter tanpa hasil tidak melakukan apa-apa", box.launched = "" && box.closed = 0)
ui.input.Value := "obs"
ui.Changed()
ui.Enter()
Check("popup: Enter menjalankan app terpilih lalu menutup", InStr(box.launched, "\user\Obsidian.lnk") && box.closed = 1, box.launched " closed=" box.closed)

ui2 := ShowAppSearchPopup(theme, { dirs: [userDir, sysDir], onClose: (*) => box.closed++, onLaunch: (p) => box.launched := p })
ui2.Esc()
Check("popup: Esc menutup tanpa menjalankan", box.closed = 2)

; ---- kecepatan ----
t0 := A_TickCount
loop 20
    ScanStartMenuApps()
ms := (A_TickCount - t0) / 20
Check("scan Start Menu asli < 100 ms", ms < 100, ms " ms")
Out("scan rata-rata: " Round(ms, 1) " ms untuk " real.Length " app")

DirDelete(root, true)
Out(passed " lulus, " failed " gagal")
ExitApp(failed ? 1 : 0)
