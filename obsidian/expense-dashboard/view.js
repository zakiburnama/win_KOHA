// Dataview view: dashboard pengeluaran (bulanan / tahunan).
// Dipanggil dari catatan dashboard:
//   ```dataviewjs
//   await dv.view("Z0014-finance/expense-dashboard", { mode: "month" })   // atau "year"
//   ```
// Periode dibaca dari frontmatter catatan pemanggil (bulan: "2026-05" /
// tahun: 2026), kosong = bulan/tahun berjalan.
//
// Data dibaca LANGSUNG dari teks daily note (dv.io.load), bukan dari field
// Dataview -- format lama (5 baris expense/amount/category/type/payment)
// dikelompokkan per "expense::" bukan dicocokkan lewat indeks array, jadi
// satu field yang hilang gak menggeser transaksi sesudahnya, dan format
// baru (satu baris "- [expense] ... [amount:: N] ...") terbaca dengan
// aturan yang sama dengan expense.ahk menulisnya.

const SMALL_TXN = 20000;   // "kecil tapi sering": transaksi <= ini
const pad2 = n => String(n).padStart(2, "0");
const rp = n => "Rp " + String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
const pct = (a, b) => (b > 0 ? Math.round((a / b) * 100) : 0) + "%";
const bar = (frac, width) => "█".repeat(Math.max(0, Math.min(width, Math.round(frac * width))));
const sum = (arr, f) => arr.reduce((s, x) => s + f(x), 0);
const MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

// Section "## <emoji> Finance" di satu daily note -> array transaksi.
function parseNote(text, date) {
    const lines = text.replace(/\r\n/g, "\n").split("\n");
    let start = -1;
    for (let i = 0; i < lines.length; i++) {
        if (/^##\s+\S+\s*Finance\s*$/.test(lines[i])) { start = i; break; }
    }
    if (start < 0) return [];

    const norm = (v, dflt) => {
        v = (v || "").trim().toLowerCase();
        return v === "" || v === "null" ? dflt : v;
    };
    // Kata hutang/utang/pinjam di nama = hutang, apa pun kategori yang
    // tertulis (catatan lama, mis. "hutang ke budi, bayar ketoprak" masih
    // berkategori pangan) -- sama dengan aturan hutang di rules.md.
    const make = (name, f, review) => {
        const debt = /(^|[^a-z0-9])(hutang|utang|pinjam)/i.test(name);
        return {
            date: date, ym: date.slice(0, 7), name: name.trim(),
            amount: parseInt(f.amount, 10) || 0,
            cat: debt ? "hutang" : norm(f.category, "lainnya"),
            type: debt ? "-" : norm(f.type, "?"), pay: norm(f.payment, "?"),
            review: review
        };
    };
    const rows = [];
    let cur = null;   // blok format lama yang sedang dikumpulkan
    const flush = () => {
        if (cur && cur.name && cur.name.toLowerCase() !== "null") {
            const r = make(cur.name, cur, false);
            if (r.amount > 0) rows.push(r);
        }
        cur = null;
    };

    for (let i = start + 1; i < lines.length; i++) {
        const l = lines[i];
        if (/^(-{3,}|_{3,}|#{1,6}\s)/.test(l)) break;
        let m = l.match(/^- \[expense\]\s*(.*)$/);
        if (m) {
            flush();
            const rest = m[1], f = {};
            rest.replace(/\[(\w+)::\s*([^\]]*)\]/g, (_, k, v) => { f[k] = v; return ""; });
            const name = rest.replace(/\[\w+::[^\]]*\]/g, "").replace(/#review/g, "");
            const r = make(name, f, /#review/.test(rest));
            if (r.name && r.amount > 0) rows.push(r);
            continue;
        }
        m = l.match(/^(expense|amount|category|type|payment)::\s*(.*?)\s*$/i);
        if (!m) continue;
        const key = m[1].toLowerCase();
        if (key === "expense") {
            flush();
            cur = { name: m[2], amount: "", category: "", type: "", payment: "" };
        } else if (cur) {
            cur[key] = m[2];
        }
    }
    flush();
    return rows;
}

async function loadRows(prefix) {
    const pages = dv.pages('"Z0010-daily"').array().filter(p => p.file.name.startsWith(prefix));
    const rows = [];
    for (const p of pages) {
        const text = await dv.io.load(p.file.path);
        if (!text) continue;
        for (const r of parseNote(text, p.file.name)) rows.push(r);
    }
    return rows;
}

// Nama -> kata pertama yang bermakna (>=3 huruf, tanpa angka), buat
// ngelompokin varian ("kopi susu jago", "kopi nako + donat" -> "kopi").
function firstWord(name) {
    const toks = name.toLowerCase().replace(/[^\p{L}\p{N} ]/gu, " ").split(/\s+/).filter(Boolean);
    const w = toks.find(t => t.length >= 3 && !/\d/.test(t));
    return w || toks[0] || "?";
}

function group(rows, keyFn) {
    const m = new Map();
    for (const r of rows) {
        const k = keyFn(r);
        if (!m.has(k)) m.set(k, { key: k, rows: [], total: 0, count: 0 });
        const g = m.get(k);
        g.rows.push(r); g.total += r.amount; g.count++;
    }
    return [...m.values()].sort((a, b) => b.total - a.total);
}

// hutang gak dihitung sebagai pengeluaran (bukan need/want) -- dilaporkan sendiri.
function summarize(rows) {
    const spend = rows.filter(r => r.cat !== "hutang");
    const total = sum(spend, r => r.amount);
    const need = sum(spend.filter(r => r.type === "need"), r => r.amount);
    const want = sum(spend.filter(r => r.type === "want"), r => r.amount);
    return { spend: spend, total: total, need: need, want: want, other: total - need - want,
        hutang: rows.filter(r => r.cat === "hutang") };
}

function renderEfficiency(spend, total) {
    dv.header(3, "🔍 Peluang efisiensi");
    if (!spend.length) return;
    const wantRows = spend.filter(r => r.type === "want");
    const wantTotal = sum(wantRows, r => r.amount);
    dv.paragraph("Porsi **want**: " + rp(wantTotal) + " (" + pct(wantTotal, total) + " dari total). Ini yang paling mudah dipangkas.");

    const small = spend.filter(r => r.amount <= SMALL_TXN);
    const smallTotal = sum(small, r => r.amount);
    dv.paragraph("Transaksi kecil (≤ " + rp(SMALL_TXN) + "): **" + small.length + "x**, total " + rp(smallTotal) +
        " (" + pct(smallTotal, total) + " dari total) — pengeluaran kecil berulang yang sering tidak terasa.");

    dv.header(4, "Terboros per kata kunci (kasar, kata pertama nama)");
    const byWord = group(spend, r => firstWord(r.name)).filter(g => g.count >= 2).slice(0, 8);
    dv.table(["Kata", "Kali", "Total", "Rata-rata", "Porsi want"],
        byWord.map(g => [g.key, g.count, rp(g.total), rp(g.total / g.count),
            pct(sum(g.rows.filter(r => r.type === "want"), r => r.amount), g.total)]));

    dv.header(4, "Want terbesar");
    const wantByName = group(wantRows, r => r.name.toLowerCase()).slice(0, 8);
    dv.table(["Item", "Kali", "Total"], wantByName.map(g => [g.rows[0].name, g.count, rp(g.total)]));

    dv.header(4, "5 transaksi terbesar");
    dv.table(["Tanggal", "Item", "Jumlah", "Kategori", "Type"],
        spend.slice().sort((a, b) => b.amount - a.amount).slice(0, 5)
            .map(r => [r.date, r.name, rp(r.amount), r.cat, r.type]));
}

function renderReview(rows) {
    const review = rows.filter(r => r.review || (r.cat === "lainnya" && r.type !== "-"));
    if (!review.length) return;
    dv.header(3, "📝 Perlu direview");
    dv.paragraph("Belum dipilah (`#review` / `lainnya`). Rapikan di daily note-nya, atau tambahkan aturan di `rules.md` supaya otomatis lain kali.");
    dv.table(["Tanggal", "Item", "Jumlah", "Kategori", "Type"],
        review.sort((a, b) => b.date.localeCompare(a.date)).map(r => [r.date, r.name, rp(r.amount), r.cat, r.type]));
}

function renderHutang(hutang) {
    if (!hutang.length) return;
    dv.header(3, "🤝 Hutang");
    dv.paragraph("Bukan pengeluaran biasa — tidak dihitung di total, need, maupun want.");
    dv.table(["Tanggal", "Catatan", "Jumlah", "Bayar"],
        hutang.sort((a, b) => b.date.localeCompare(a.date)).map(r => [r.date, r.name, rp(r.amount), r.pay]));
}

function renderCategoryPay(spend, total) {
    dv.header(3, "📂 Per kategori");
    dv.table(["Kategori", "Total", "%", "Need", "Want", ""],
        group(spend, r => r.cat).map(g => [g.key, rp(g.total), pct(g.total, total),
            rp(sum(g.rows.filter(r => r.type === "need"), r => r.amount)),
            rp(sum(g.rows.filter(r => r.type === "want"), r => r.amount)),
            bar(g.total / total, 20)]));
    dv.header(3, "💳 Per metode bayar");
    dv.table(["Metode", "Total", "%", "Transaksi"],
        group(spend, r => r.pay).map(g => [g.key, rp(g.total), pct(g.total, total), g.count]));
}

async function renderMonth(period) {
    const parts = period.split("-").map(Number);
    const y = parts[0], mo = parts[1];
    const prevD = new Date(y, mo - 2, 1);
    const prevPeriod = prevD.getFullYear() + "-" + pad2(prevD.getMonth() + 1);
    const rows = await loadRows(period);
    dv.header(2, "💸 Pengeluaran — " + MONTHS[mo - 1] + " " + y);
    if (!rows.length) { dv.paragraph("Tidak ada transaksi di " + period + ". Ganti `bulan:` di properti catatan ini."); return; }
    const s = summarize(rows);
    const prev = summarize(await loadRows(prevPeriod));
    const days = new Set(s.spend.map(r => r.date)).size;
    const daysInMonth = new Date(y, mo, 0).getDate();
    const delta = prev.total > 0
        ? " (" + (s.total >= prev.total ? "▲ " : "▼ ") + pct(Math.abs(s.total - prev.total), prev.total) + " dari " + prevPeriod + ": " + rp(prev.total) + ")"
        : "";
    dv.paragraph("**Total: " + rp(s.total) + "**" + delta);
    dv.table(["", "Jumlah", "Porsi"], [
        ["✅ Need", rp(s.need), pct(s.need, s.total)],
        ["🛍️ Want", rp(s.want), pct(s.want, s.total)],
        ["❓ Belum dipilah", rp(s.other), pct(s.other, s.total)]]);
    dv.paragraph(s.spend.length + " transaksi di " + days + " hari tercatat · rata-rata " + rp(s.total / Math.max(days, 1)) +
        "/hari tercatat · " + rp(s.total / daysInMonth) + "/hari kalender");

    renderCategoryPay(s.spend, s.total);
    renderEfficiency(s.spend, s.total);
    renderReview(rows);
    renderHutang(s.hutang);

    dv.header(3, "📅 Harian");
    const byDay = group(s.spend, r => r.date).sort((a, b) => a.key.localeCompare(b.key));
    const maxDay = Math.max.apply(null, byDay.map(g => g.total));
    dv.table(["Tanggal", "Total", "Transaksi", ""], byDay.map(g => [g.key, rp(g.total), g.count, bar(g.total / maxDay, 20)]));

    dv.header(3, "📋 Detail");
    dv.table(["Tanggal", "Item", "Jumlah", "Kategori", "Type", "Bayar"],
        rows.slice().sort((a, b) => b.date.localeCompare(a.date) || b.amount - a.amount)
            .map(r => [r.date, r.name, rp(r.amount), r.cat, r.type, r.pay]));
}

async function renderYear(period) {
    const rows = await loadRows(period + "-");
    dv.header(2, "💸 Pengeluaran — Tahun " + period);
    if (!rows.length) { dv.paragraph("Tidak ada transaksi di " + period + ". Ganti `tahun:` di properti catatan ini."); return; }
    const s = summarize(rows);
    dv.paragraph("**Total: " + rp(s.total) + "** · " + s.spend.length + " transaksi · need " + pct(s.need, s.total) + " / want " + pct(s.want, s.total));

    dv.header(3, "📆 Per bulan");
    const byMonth = group(rows, r => r.ym).sort((a, b) => a.key.localeCompare(b.key));
    const maxM = Math.max.apply(null, byMonth.map(g => summarize(g.rows).total));
    let prevTotal = null;
    dv.table(["Bulan", "Total", "vs bulan lalu", "Need", "Want", "% Want", ""],
        byMonth.map(g => {
            const ms = summarize(g.rows);
            const d = prevTotal === null || prevTotal === 0 ? "-"
                : (ms.total >= prevTotal ? "▲ " : "▼ ") + pct(Math.abs(ms.total - prevTotal), prevTotal);
            prevTotal = ms.total;
            return [MONTHS[Number(g.key.slice(5)) - 1], rp(ms.total), d, rp(ms.need), rp(ms.want), pct(ms.want, ms.total), bar(ms.total / maxM, 20)];
        }));
    dv.paragraph("Rata-rata per bulan tercatat: " + rp(s.total / byMonth.length) + " (" + byMonth.length + " bulan ada data)");

    renderCategoryPay(s.spend, s.total);

    dv.header(3, "🗂️ Kategori × bulan");
    const cats = group(s.spend, r => r.cat).map(g => g.key);
    dv.table(["Bulan"].concat(cats), byMonth.map(g => {
        const ms = summarize(g.rows);
        return [MONTHS[Number(g.key.slice(5)) - 1]].concat(cats.map(c => {
            const t = sum(ms.spend.filter(r => r.cat === c), r => r.amount);
            return t ? rp(t) : "-";
        }));
    }));

    renderEfficiency(s.spend, s.total);
    renderReview(rows);
    renderHutang(s.hutang);
}

const cur = dv.current() || {};
const mode = (input && input.mode) || "month";
const now = new Date();
if (mode === "year") {
    const period = String((input && input.year) || cur.tahun || now.getFullYear());
    if (!/^\d{4}$/.test(period)) dv.paragraph("⚠️ `tahun:` harus berbentuk 2026, bukan: " + period);
    else await renderYear(period);
} else {
    const period = String((input && input.month) || cur.bulan || (now.getFullYear() + "-" + pad2(now.getMonth() + 1)));
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) dv.paragraph("⚠️ `bulan:` harus berbentuk \"2026-05\", bukan: " + period);
    else await renderMonth(period);
}
