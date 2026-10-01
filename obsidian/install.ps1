# Salin dashboard ke vault Obsidian: view.js SELALU ditimpa (itu kodenya),
# catatan dashboard cuma disalin kalau belum ada (properti bulan:/tahun:
# yang sudah Anda ubah tidak ikut tertimpa).
#   powershell -File obsidian\install.ps1 [-Vault <path>]
param([string]$Vault = 'C:\Users\ThinkPad\Documents\Obsidian-Vault')
$dst = Join-Path $Vault 'Z0014-finance'
if (-not (Test-Path $dst)) { throw "$dst tidak ada -- vault path salah?" }
New-Item -ItemType Directory -Force (Join-Path $dst 'expense-dashboard') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'expense-dashboard\view.js') (Join-Path $dst 'expense-dashboard\view.js') -Force
"view.js disalin"
foreach ($n in 'Dashboard Pengeluaran Bulanan.md', 'Dashboard Pengeluaran Tahunan.md') {
    $target = Join-Path $dst $n
    if (Test-Path $target) { "$n sudah ada -- dibiarkan" }
    else { Copy-Item (Join-Path $PSScriptRoot $n) $target; "$n disalin" }
}
