#!/bin/sh
# Bikin salinan mini vault (rules + template + beberapa daily note asli)
# buat tests/expense_test.ahk. Pemakaian: make-test-vault.sh <vault-asli> <tujuan>
set -e
SRC="$1"; DST="$2"
# rm -rf cuma boleh nimpa folder yang dulu dibikin skrip ini (ada penandanya)
# -- jangan pernah menghapus folder lain kalau path-nya salah ketik.
if [ -e "$DST" ] && [ ! -f "$DST/.qm-test-vault" ]; then
  echo "tolak: $DST sudah ada dan bukan hasil skrip ini" >&2; exit 1
fi
rm -rf "$DST"
mkdir -p "$DST"; touch "$DST/.qm-test-vault"
mkdir -p "$DST/Z0010-daily" "$DST/Z0005-templates" "$DST/Z0014-finance"
cp "$SRC/Z0014-finance/rules.md" "$DST/Z0014-finance/"
cp "$SRC/Z0005-templates/Template Daily New.md" "$DST/Z0005-templates/"
# 05-10: CRLF + blok 5-baris asli; 04-30: CRLF tanpa section Finance;
# 06-13: CRLF + transaksi asli; 2026-09-30 / 08-31: LF dengan placeholder null
for d in 2026-05-10 2026-04-30 2026-06-13 2026-09-30 2026-08-31; do
  cp "$SRC/Z0010-daily/$d.md" "$DST/Z0010-daily/"
done
