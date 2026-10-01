// Tes obsidian/expense-dashboard/view.js di Node dengan dv palsu (Dataview
// asli cuma ada di dalam Obsidian). Daily note-nya sintetis -- dibangun di
// folder temp, bukan vault asli:
//   node tests/dashboard_test.js
// Opsional: node tests/dashboard_test.js --vault <path> <mode> <periode>
// menjalankan view terhadap vault beneran (hanya BACA) dan mencetak hasil
// render-nya, buat dicocokkan manual dengan Obsidian.
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert");

const VIEW = fs.readFileSync(path.join(__dirname, "..", "obsidian", "expense-dashboard", "view.js"), "utf8");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

// dv minimal: pages().array(), io.load(), current(), header/paragraph/table.
async function runView(vaultDir, input, current) {
    const out = [];
    const dir = path.join(vaultDir, "Z0010-daily");
    const dv = {
        pages: () => ({
            array: () => fs.readdirSync(dir).filter(f => f.endsWith(".md")).sort()
                .map(f => ({ file: { name: f.slice(0, -3), path: "Z0010-daily/" + f } })),
        }),
        io: { load: async p => fs.readFileSync(path.join(vaultDir, p), "utf8") },
        current: () => current || {},
        header: (n, t) => out.push({ kind: "h" + n, text: t }),
        paragraph: t => out.push({ kind: "p", text: t }),
        table: (head, rows) => out.push({ kind: "table", head, rows }),
    };
    await new AsyncFunction("dv", "input", VIEW)(dv, input);
    return out;
}
const text = out => out.map(o => o.kind === "table"
    ? o.head.join(" | ") + "\n" + o.rows.map(r => r.join(" | ")).join("\n")
    : o.text).join("\n");
const tableAfter = (out, header) => {
    const i = out.findIndex(o => o.kind.startsWith("h") && o.text.includes(header));
    return out.slice(i + 1).find(o => o.kind === "table");
};

function financeSection(body) {
    return "---\n\n# note\n\n___\n\n## 💸 Finance\n\n" + body + "\n---\n\n## 🍖 What i Eat\n\nbreakfast::\n";
}

async function main() {
    if (process.argv[2] === "--vault") {
        const out = await runView(process.argv[3], { mode: process.argv[4] }, process.argv[4] === "year" ? { tahun: process.argv[5] } : { bulan: process.argv[5] });
        console.log(text(out));
        return;
    }

    const vault = fs.mkdtempSync(path.join(os.tmpdir(), "qm-dash-"));
    const daily = path.join(vault, "Z0010-daily");
    fs.mkdirSync(daily);
    const w = (name, body, crlf) => fs.writeFileSync(path.join(daily, name + ".md"), crlf ? financeSection(body).replace(/\n/g, "\r\n") : financeSection(body));

    // 05-01: format lama (CRLF), blok kedua TANPA payment -- format lama yang
    // dicocokkan lewat indeks array bakal menggeser blok sesudahnya.
    w("2026-05-01", [
        "expense:: nasi goreng", "amount:: 25000", "category:: pangan", "type:: need", "payment:: shopeepay", "",
        "expense:: kopi susu", "amount:: 8000", "category:: pangan", "type:: want", "", // payment hilang
        "expense:: ayam", "amount:: 12000", "category:: Pangan", "type:: need", "payment:: gopay", "",
        "expense:: hutang ke budi, bayar ketoprak", "amount:: 40000", "category:: pangan", "type:: need", "payment:: bca", "",
    ].join("\n"), true);
    // 05-02: format baru, #review, hutang, campur dengan blok lama
    w("2026-05-02", [
        "expense:: telur", "amount:: 29000", "category:: pangan", "type:: need", "payment:: cash", "",
        "- [expense] kopi nako + donat [amount:: 63000] [category:: pangan] [type:: want] [payment:: shopeepay]",
        "- [expense] seblak [amount:: 15000] [category:: lainnya] [type:: want] [payment:: shopeepay] #review",
        "- [expense] hutang ke budi [amount:: 40000] [category:: hutang] [type:: -] [payment:: bca]",
    ].join("\n"));
    // 05-03: placeholder template (null) -> tidak boleh jadi transaksi
    w("2026-05-03", ["expense:: null", "amount:: 0", "category:: null", "type:: null", "payment:: null", ""].join("\n"));
    // 04-30: bulan sebelumnya (buat delta) ; 06-01: bulan lain (buat tahunan)
    w("2026-04-30", "- [expense] kopi [amount:: 20000] [category:: pangan] [type:: want] [payment:: cash]");
    w("2026-06-01", "- [expense] kopi susu [amount:: 10000] [category:: pangan] [type:: want] [payment:: cash]\n- [expense] gojek [amount:: 22500] [category:: transportasi] [type:: need] [payment:: gopay]");
    // note tanpa section Finance sama sekali
    fs.writeFileSync(path.join(daily, "2026-05-04.md"), "# hari tanpa finance\n");

    // ---- bulanan ----
    const m = await runView(vault, { mode: "month" }, { bulan: "2026-05" });
    const t = text(m);
    // total = 25000+8000+12000+29000+63000+15000 = 152000 (hutang 40000 terpisah)
    assert(t.includes("Total: Rp 152.000"), "total bulan: " + t.split("\n").slice(0, 4).join(" / "));
    assert(t.includes("▲ 660% dari 2026-04: Rp 20.000"), "delta vs bulan lalu");
    const need = 25000 + 12000 + 29000, want = 8000 + 63000 + 15000;
    assert(t.includes("✅ Need | Rp " + String(need).replace(/\B(?=(\d{3})+$)/g, ".")), "need " + need);
    assert(t.includes("🛍️ Want | Rp " + String(want).replace(/\B(?=(\d{3})+$)/g, ".")), "want " + want);
    // blok tanpa payment tidak menggeser blok sesudahnya: ayam tetap gopay, 12000
    const detail = tableAfter(m, "Detail").rows;
    const ayam = detail.find(r => r[1] === "ayam");
    assert(ayam && ayam[2] === "Rp 12.000" && ayam[3] === "pangan" && ayam[5] === "gopay", "ayam: " + JSON.stringify(ayam));
    const kopi = detail.find(r => r[1] === "kopi susu");
    assert(kopi && kopi[5] === "?", "payment hilang -> '?': " + JSON.stringify(kopi));
    assert(detail.length === 8, "8 baris detail (6 + 2 hutang), dapat " + detail.length);
    assert(!detail.some(r => r[1] === "null"), "placeholder null bukan transaksi");
    const review = tableAfter(m, "Perlu direview").rows;
    assert(review.length === 1 && review[0][1] === "seblak", "review: " + JSON.stringify(review));
    const hutang = tableAfter(m, "Hutang").rows;
    assert(hutang.length === 2 && hutang.every(r => r[2] === "Rp 40.000"), "hutang terpisah, termasuk catatan lama berlabel pangan: " + JSON.stringify(hutang));
    const cats = tableAfter(m, "Per kategori").rows;
    assert(cats.map(r => r[0] + " " + r[1]).join() === "pangan Rp 137.000,lainnya Rp 15.000", "hutang bukan kategori pengeluaran: " + JSON.stringify(cats));
    const words = tableAfter(m, "Terboros").rows;
    assert(words[0][0] === "kopi" && words[0][1] === 2 && words[0][2] === "Rp 71.000", "grup kata pertama: " + JSON.stringify(words[0]));
    // shopeepay = 25000 + 63000 + 15000
    const pays = Object.fromEntries(tableAfter(m, "metode").rows.map(r => [r[0], r[1]]));
    assert(pays["shopeepay"] === "Rp 103.000" && pays["gopay"] === "Rp 12.000" && pays["cash"] === "Rp 29.000" && pays["?"] === "Rp 8.000", "per metode: " + JSON.stringify(pays));

    // ---- bulan kosong & input salah ----
    assert(text(await runView(vault, { mode: "month" }, { bulan: "2025-01" })).includes("Tidak ada transaksi di 2025-01"));
    assert(text(await runView(vault, { mode: "month" }, { bulan: "mei" })).includes("harus berbentuk"));
    assert(text(await runView(vault, { mode: "year" }, { tahun: "26" })).includes("harus berbentuk"));
    // default = bulan berjalan kalau frontmatter kosong (tidak boleh error)
    await runView(vault, { mode: "month" }, {});

    // ---- tahunan ----
    const y = await runView(vault, { mode: "year" }, { tahun: 2026 });
    const yt = text(y);
    // 152000 (Mei) + 20000 (Apr) + 32500 (Jun) = 204500
    assert(yt.includes("Total: Rp 204.500"), "total tahun: " + yt.split("\n")[0]);
    const months = tableAfter(y, "Per bulan").rows;
    assert(months.map(r => r[0]).join() === "April,Mei,Juni", "urutan bulan: " + months.map(r => r[0]));
    assert(months[1][2].startsWith("▲"), "Mei naik dari April");
    assert(months[2][2].startsWith("▼"), "Juni turun dari Mei");
    const matrix = tableAfter(y, "Kategori × bulan");
    assert(matrix.head.join() === "Bulan,pangan,transportasi,lainnya", "kolom matriks: " + matrix.head);

    console.log("dashboard_test: semua lulus");
}
main().catch(e => { console.error("GAGAL:", e.message); process.exit(1); });
