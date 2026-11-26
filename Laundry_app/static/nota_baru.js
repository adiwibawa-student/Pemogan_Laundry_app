(function () {
  const form = document.getElementById("form-nota");
  const BARANG = JSON.parse(form.dataset.barang);
  const TARIF = JSON.parse(form.dataset.tarif);
  const DURASI = JSON.parse(form.dataset.durasi);
  const BARIS = JSON.parse(form.dataset.baris);

  const tbody = document.getElementById("rincian");
  const elTotal = document.getElementById("total");
  const elEstimasi = document.getElementById("estimasi");
  const BULAN = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

  function rupiah(n) {
    return "Rp " + Math.round(n).toLocaleString("id-ID");
  }

  function angka(teks) {
    const n = parseFloat(String(teks).replace(",", "."));
    return isNaN(n) ? 0 : n;
  }

  function layananTerpilih() {
    const r = form.querySelector("input[name='speed_id']:checked");
    return r ? r.value : null;
  }

  function hitung() {
    const speed = layananTerpilih();
    let total = 0;
    tbody.querySelectorAll("tr").forEach(function (tr) {
      const item = tr.querySelector("select").value;
      const jumlah = angka(tr.querySelector("input").value);
      let harga = null;
      if (speed && item && TARIF[speed] && TARIF[speed][item] !== undefined) {
        harga = TARIF[speed][item];
      }
      tr.querySelector(".harga").textContent = harga === null ? "-" : rupiah(harga);
      const sub = harga === null ? 0 : harga * jumlah;
      tr.querySelector(".subtotal").textContent = rupiah(sub);
      total += sub;
    });
    elTotal.textContent = rupiah(total);
  }

  function estimasi() {
    const speed = layananTerpilih();
    if (!speed) {
      elEstimasi.textContent = "Estimasi selesai: pilih jenis layanan";
      return;
    }
    const d = new Date(Date.now() + DURASI[speed] * 3600 * 1000);
    const jam = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    elEstimasi.textContent =
      "Estimasi selesai: " + d.getDate() + " " + BULAN[d.getMonth()] + " " + d.getFullYear() + ", " + jam;
  }

  function sel(nilai) {
    const s = document.createElement("select");
    s.name = "item_id";
    s.add(new Option("- pilih barang -", ""));
    BARANG.forEach(function (b) {
      s.add(new Option(b.nama_item + " (" + b.tipe_satuan + ")", b.item_id));
    });
    s.value = nilai || "";
    s.addEventListener("change", hitung);
    return s;
  }

  function tambahBaris(item, jumlah) {
    const tr = document.createElement("tr");

    const tdItem = document.createElement("td");
    tdItem.appendChild(sel(item));

    const tdJumlah = document.createElement("td");
    const inp = document.createElement("input");
    inp.type = "text";
    inp.name = "jumlah";
    inp.placeholder = "0";
    inp.setAttribute("inputmode", "decimal");
    inp.value = jumlah || "";
    inp.addEventListener("input", hitung);
    tdJumlah.appendChild(inp);

    const tdHarga = document.createElement("td");
    tdHarga.className = "rata-kanan harga";
    tdHarga.textContent = "-";

    const tdSub = document.createElement("td");
    tdSub.className = "rata-kanan subtotal";
    tdSub.textContent = "Rp 0";

    const tdHapus = document.createElement("td");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "hapus-baris";
    btn.title = "Hapus baris";
    btn.textContent = "×";
    btn.addEventListener("click", function () {
      if (tbody.querySelectorAll("tr").length > 1) {
        tr.remove();
        hitung();
      }
    });
    tdHapus.appendChild(btn);

    [tdItem, tdJumlah, tdHarga, tdSub, tdHapus].forEach(function (td) {
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  }

  form.querySelectorAll("input[name='speed_id']").forEach(function (r) {
    r.addEventListener("change", function () {
      hitung();
      estimasi();
    });
  });
  document.getElementById("tambah-baris").addEventListener("click", function () {
    tambahBaris("", "");
  });

  (BARIS.length ? BARIS : [{ item_id: "", jumlah: "" }]).forEach(function (b) {
    tambahBaris(b.item_id, b.jumlah);
  });
  hitung();
  estimasi();
})();