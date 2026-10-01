# Jalanin kedua tes (masing-masing dengan salinan vault BARU, karena tes
# nulis ke vault itu). Pemakaian: powershell -File tests\run-tests.ps1 [<vault-asli>]
param([string]$Vault = 'C:\Users\ThinkPad\Documents\Obsidian-Vault')
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$work = Join-Path $env:TEMP 'qm-expense-tests'
$sh = 'C:\Program Files\Git\bin\sh.exe'
$fail = 0
foreach ($t in 'expense_test', 'expense_popup_test') {
    $dst = Join-Path $work $t
    if ((Test-Path $dst) -and -not (Test-Path (Join-Path $dst '.qm-test-vault'))) { throw "$dst bukan folder tes" }
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $work | Out-Null
    & $sh (Join-Path $PSScriptRoot 'make-test-vault.sh') $Vault.Replace([string][char]92, '/') $dst.Replace([string][char]92, '/')
    $out = Join-Path $work "$t.out.txt"
    $p = Start-Process $ahk -ArgumentList @('/ErrorStdOut=UTF-8', (Join-Path $PSScriptRoot "$t.ahk"), $dst, (Join-Path $PSScriptRoot 'rows.tsv')) -PassThru -NoNewWindow -RedirectStandardOutput $out
    if (-not $p.WaitForExit(60000)) { $p.Kill(); "== $t TIMEOUT"; $fail++; continue }
    $p.WaitForExit()
    "== $t"
    Get-Content $out -Encoding UTF8
    if ((Get-Content $out -Encoding UTF8 | Select-Object -Last 1) -notmatch ' 0 gagal$') { $fail++ }
}
if (Get-Command node -ErrorAction SilentlyContinue) {
    "== dashboard_test (node)"
    node (Join-Path $PSScriptRoot 'dashboard_test.js')
    if ($LASTEXITCODE -ne 0) { $fail++ }
} else { "== dashboard_test dilewati (node tidak ada)" }
exit $fail
