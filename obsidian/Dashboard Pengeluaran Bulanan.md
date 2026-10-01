---
bulan: "2026-05"
tags: [finance, dashboard]
---
# Dashboard Pengeluaran Bulanan

Ganti **bulan** di Properties (format `2026-05`); kosongkan = bulan berjalan. Data dari baris `- [expense]` yang ditulis menu Pengeluaran QuickMenu, plus catatan format lama. Hutang dilaporkan terpisah dan tidak dihitung di total.

```dataviewjs
await dv.view("Z0014-finance/expense-dashboard", { mode: "month" })
```
