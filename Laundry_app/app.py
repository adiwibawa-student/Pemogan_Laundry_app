import os
import secrets
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation

import mysql.connector
from flask import Flask, render_template, request, redirect, url_for, session, flash

import db

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY") or secrets.token_hex(32)

AKUN_DIIZINKAN = ("petugas", "owner")
KONEKSI = {}  # token -> koneksi MySQL yang sedang login
BATAS_PELANGGAN = 5  # pelanggan = lebih dari 5 nota dalam satu bulan


def koneksi_aktif():
    return KONEKSI.get(session.get("token"))

@app.before_request
def wajib_login():
    if request.endpoint in ("login", "static"):
        return None
    if koneksi_aktif() is None:
        return redirect(url_for("login"))
    if request.path.startswith(("/pelanggan", "/nota", "/pembayaran", "/cucian")) and (
        session.get("user") != "petugas"
    ):
        return redirect(url_for("laporan"))
    return None


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        if username not in AKUN_DIIZINKAN:
            error = "Username atau password salah."
        else:
            try:
                conn = db.koneksi(username, password)
            except mysql.connector.Error:
                error = "Username atau password salah."
            else:
                token = secrets.token_hex(16)
                KONEKSI[token] = conn
                session["token"] = token
                session["user"] = username
                return redirect(url_for("beranda"))
    return render_template("login.html", error=error)


@app.route("/keluar")
def keluar():
    conn = KONEKSI.pop(session.get("token"), None)
    if conn is not None:
        conn.close()
    session.clear()
    return redirect(url_for("login"))

@app.template_filter("rp")
def format_rupiah(nilai):
    return "Rp " + f"{int(nilai):,}".replace(",", ".")


@app.template_filter("tgl")
def format_tanggal(nilai):
    if not nilai:
        return "-"
    return nilai.strftime("%d-%m-%Y %H:%M")
NAMA_BULAN = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
              "Agustus", "September", "Oktober", "November", "Desember"]
SINGKAT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep",
           "Okt", "Nov", "Des"]

@app.template_filter("rb")
def format_ribuan(nilai):
    n = int(nilai)
    if n >= 1_000_000:
        return "Rp " + f"{n / 1_000_000:.1f}".replace(".", ",") + " jt"
    if n >= 1000:
        return "Rp " + f"{n / 1000:.0f}" + " rb"
    return "Rp " + str(n)

@app.template_filter("nama_bulan")
def format_nama_bulan(nilai):
    tahun, bln = nilai.split("-")
    return NAMA_BULAN[int(bln) - 1] + " " + tahun

@app.template_filter("tglp")
def format_tanggal_pendek(nilai):
    if not nilai:
        return "-"
    return f"{nilai.day} {SINGKAT[nilai.month - 1]}"

@app.route("/")
def beranda():
    if session.get("user") == "owner":
        return redirect(url_for("laporan"))
    conn = koneksi_aktif()

    def hitung(syarat):
        sql = "SELECT COUNT(*) AS n FROM v_nota_ringkas WHERE " + syarat
        return db.query(conn, sql)[0]["n"]

    stat = {
        "belum_lunas": hitung("status_pembayaran = 'Belum lunas'"),
        "siap_diambil": hitung("status_cucian = 'Siap diambil'"),
        "lewat_batas": hitung("status_cucian = 'Siap diambil' AND batas_ambil < NOW()"),
        "tagihan": db.query(
            conn,
            "SELECT COALESCE(SUM(sisa_tagihan), 0) AS total FROM v_nota_ringkas",
        )[0]["total"],
    }

    nota = db.query(
        conn,
        """
        SELECT no_nota, pelanggan, layanan, tanggal_terima, status_cucian,
               total_biaya, total_bayar, sisa_tagihan, status_pembayaran
        FROM v_nota_ringkas
        ORDER BY order_id DESC
        LIMIT 10
        """,
    )
    return render_template("dashboard.html", halaman="dashboard", stat=stat, nota=nota)

@app.route("/laporan")
def laporan():
    conn = koneksi_aktif()

    # Daftar bulan yang punya data, format "2026-11"
    daftar_bulan = [
        f"{r['th']}-{int(r['bl']):02d}"
        for r in db.query(
            conn,
            "SELECT DISTINCT YEAR(tanggal_terima) AS th, MONTH(tanggal_terima) AS bl "
            "FROM ORDERS ORDER BY th DESC, bl DESC",
        )
    ]
    sekarang = datetime.now().strftime("%Y-%m")
    bulan = request.args.get("bulan", "")
    if bulan not in daftar_bulan:
        if sekarang in daftar_bulan or not daftar_bulan:
            bulan = sekarang
        else:
            bulan = daftar_bulan[0]
    tahun, bln = (int(x) for x in bulan.split("-"))

    ringkas = db.query(
        conn,
        """
        SELECT COALESCE(SUM(total_biaya), 0)  AS nilai,
               COALESCE(SUM(total_bayar), 0)  AS diterima,
               COALESCE(SUM(sisa_tagihan), 0) AS belum
        FROM v_nota_ringkas
        WHERE YEAR(tanggal_terima) = %s AND MONTH(tanggal_terima) = %s
        """,
        (tahun, bln),
    )[0]

    per_minggu = {
        int(r["minggu"]): int(r["nilai"])
        for r in db.query(
            conn,
            """
            SELECT (DAY(tanggal_terima) - 1) DIV 7 + 1 AS minggu,
                   SUM(total_biaya) AS nilai
            FROM v_nota_ringkas
            WHERE YEAR(tanggal_terima) = %s AND MONTH(tanggal_terima) = %s
            GROUP BY minggu
            """,
            (tahun, bln),
        )
    }
    nilai_minggu = [per_minggu.get(n, 0) for n in range(1, 6)]
    puncak = max(nilai_minggu)
    grafik = [
        {
            "no": n,
            "rb": round(v / 1000),
            "px": round(v / puncak * 160) if puncak else 0,
            "tertinggi": puncak > 0 and v == puncak,
        }
        for n, v in enumerate(nilai_minggu, start=1)
    ]

    belum_lunas = db.query(
        conn,
        """
        SELECT no_nota, pelanggan, sisa_tagihan
        FROM v_nota_ringkas
        WHERE status_pembayaran = 'Belum lunas'
          AND YEAR(tanggal_terima) = %s AND MONTH(tanggal_terima) = %s
        ORDER BY sisa_tagihan DESC
        LIMIT 5
        """,
        (tahun, bln),
    )

    lewat_batas = db.query(
        conn,
        """
        SELECT no_nota, pelanggan, tanggal_selesai, batas_ambil,
               DATEDIFF(NOW(), batas_ambil) AS lewat_hari
        FROM v_nota_ringkas
        WHERE status_cucian = 'Siap diambil' AND batas_ambil < NOW()
        ORDER BY batas_ambil
        LIMIT 5
        """,
    )

    audit = db.query(
        conn,
        """
        SELECT CONCAT('N-', LPAD(order_id, 4, '0')) AS no_nota,
               status_cucian, dibuat_pada, dimodifikasi_pada, dimodifikasi_oleh
        FROM ORDERS
        ORDER BY dimodifikasi_pada DESC
        LIMIT 15
        """,
    )
    # Statistik jumlah pelanggan yang datang: AVG, MIN, MAX per bulan dan per minggu
    stat_bulan = db.query(
        conn,
        """
        SELECT COALESCE(AVG(jml), 0) AS rata_rata,
               COALESCE(MIN(jml), 0) AS minimum,
               COALESCE(MAX(jml), 0) AS maksimum
        FROM (
            SELECT COUNT(DISTINCT customer_id) AS jml
            FROM ORDERS
            GROUP BY YEAR(tanggal_terima), MONTH(tanggal_terima)
        ) AS per_bulan
        """,
    )[0]

    stat_minggu = db.query(
        conn,
        """
        SELECT COALESCE(AVG(jml), 0) AS rata_rata,
               COALESCE(MIN(jml), 0) AS minimum,
               COALESCE(MAX(jml), 0) AS maksimum
        FROM (
            SELECT COUNT(DISTINCT customer_id) AS jml
            FROM ORDERS
            GROUP BY YEAR(tanggal_terima), WEEK(tanggal_terima, 1)
        ) AS per_minggu
        """,
    )[0]

    # Pelanggan: customer dengan nota lebih dari batas pada bulan yang dipilih (HAVING)
    pelanggan_tetap = db.query(
        conn,
        """
        SELECT c.nama, COUNT(*) AS jumlah_nota
        FROM CUSTOMER c
        JOIN ORDERS o ON o.customer_id = c.customer_id
        WHERE YEAR(o.tanggal_terima) = %s AND MONTH(o.tanggal_terima) = %s
        GROUP BY c.customer_id, c.nama
        HAVING COUNT(*) > %s
        ORDER BY jumlah_nota DESC, c.nama
        """,
        (tahun, bln, BATAS_PELANGGAN),
    )

    return render_template(
        "laporan.html",
        halaman="laporan",
        bulan=bulan,
        daftar_bulan=daftar_bulan,
        batas_pelanggan=BATAS_PELANGGAN,
        ringkas=ringkas,
        grafik=grafik,
        belum_lunas=belum_lunas,
        lewat_batas=lewat_batas,
        audit=audit,
        stat_bulan=stat_bulan,
        stat_minggu=stat_minggu,
        pelanggan_tetap=pelanggan_tetap,
    )

@app.route("/pelanggan")
def pelanggan():
    if session.get("user") != "petugas":
        return redirect(url_for("laporan"))

    conn = koneksi_aktif()
    data = db.query(conn, "SELECT * FROM CUSTOMER ORDER BY 1")
    kolom = list(data[0].keys()) if data else []

    return render_template(
        "pelanggan.html", halaman="pelanggan", data=data, kolom=kolom
    )

@app.route("/pelanggan/tambah", methods=["GET", "POST"])
@app.route("/pelanggan/<int:customer_id>/ubah", methods=["GET", "POST"])
def form_pelanggan(customer_id=None):
    conn = koneksi_aktif()
    error = None
    data = {"nama": "", "telepon": "", "alamat": ""}

    if customer_id is not None:
        baris = db.query(
            conn, "SELECT * FROM CUSTOMER WHERE customer_id = %s", (customer_id,)
        )
        if not baris:
            return redirect(url_for("pelanggan"))
        data = baris[0]

    if request.method == "POST":
        data = {
            "nama": request.form["nama"].strip(),
            "telepon": request.form["telepon"].strip(),
            "alamat": request.form["alamat"].strip() or None,
        }
        try:
            if customer_id is None:
                db.execute(
                    conn,
                    "INSERT INTO CUSTOMER (nama, telepon, alamat) VALUES (%s, %s, %s)",
                    (data["nama"], data["telepon"], data["alamat"]),
                )
            else:
                db.execute(
                    conn,
                    "UPDATE CUSTOMER SET nama = %s, telepon = %s, alamat = %s "
                    "WHERE customer_id = %s",
                    (data["nama"], data["telepon"], data["alamat"], customer_id),
                )
            return redirect(url_for("pelanggan"))
        except mysql.connector.Error as e:
            if e.errno == 1062:
                error = "Nomor telepon sudah dipakai pelanggan lain."
            else:
                error = "Data tidak valid: " + str(e.msg)

    return render_template(
        "form_pelanggan.html",
        halaman="pelanggan",
        data=data,
        error=error,
        ubah=customer_id is not None,
    )

@app.route("/pelanggan/<int:customer_id>/hapus", methods=["POST"])
def hapus_pelanggan(customer_id):
    conn = koneksi_aktif()
    try:
        jumlah = db.execute(
            conn, "DELETE FROM CUSTOMER WHERE customer_id = %s", (customer_id,)
        )
        if jumlah:
            flash("Pelanggan berhasil dihapus.", "sukses")
    except mysql.connector.Error as e:
        if e.errno in (1451, 1217) or "foreign key" in str(e.msg).lower():
            flash("Pelanggan tidak bisa dihapus karena sudah memiliki nota.", "galat")
        else:
            flash("Gagal menghapus: " + str(e.msg), "galat")
    return redirect(url_for("pelanggan"))

JUMLAH_BARIS = 5  # banyaknya baris barang pada form nota

def simpan_nota(conn, form, rincian):
    """Simpan nota + rincian dalam satu transaksi. Kembalikan order_id."""
    terima = datetime.now().replace(microsecond=0)

    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT durasi_jam FROM SPEED WHERE speed_id = %s", (form["speed_id"],)
        )
        speed = cur.fetchone()
        if speed is None:
            raise ValueError("Layanan tidak ditemukan.")
        estimasi = terima + timedelta(hours=speed[0])

        conn.start_transaction()
        cur.execute(
            "INSERT INTO ORDERS (customer_id, speed_id, tanggal_terima, estimasi_selesai) "
            "VALUES (%s, %s, %s, %s)",
            (form["customer_id"], form["speed_id"], terima, estimasi),
        )
        order_id = cur.lastrowid

        for b in rincian:
            cur.execute(
                "SELECT harga FROM TARIFF WHERE item_id = %s AND speed_id = %s",
                (b["item_id"], form["speed_id"]),
            )
            tarif = cur.fetchone()
            if tarif is None:
                raise ValueError("Tarif untuk salah satu barang pada layanan ini belum tersedia.")
            cur.execute(
                "INSERT INTO ORDER_DETAIL (order_id, item_id, jumlah, harga_satuan) "
                "VALUES (%s, %s, %s, %s)",
                (order_id, b["item_id"], b["jumlah"], tarif[0]),
            )

        conn.commit()
        return order_id
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()


@app.route("/nota/baru", methods=["GET", "POST"])
def nota_baru():
    conn = koneksi_aktif()
    pelanggan = db.query(
        conn, "SELECT customer_id, nama, telepon FROM CUSTOMER ORDER BY nama"
    )
    layanan = db.query(
        conn, "SELECT speed_id, jenis_layanan, durasi_jam FROM SPEED ORDER BY speed_id"
    )
    for s in layanan:
        jam = int(s["durasi_jam"])
        s["teks"] = f"{jam // 24} hari" if jam % 24 == 0 else f"{jam} jam"

    barang = db.query(
        conn,
        """
        SELECT i.item_id,
               CONCAT(c.nama_kategori,
                      IF(i.ukuran = '-', '', CONCAT(' ', i.ukuran))) AS nama_item,
               c.tipe_satuan
        FROM ITEM i
        JOIN ITEM_CATEGORY c ON c.category_id = i.category_id
        ORDER BY c.nama_kategori, i.ukuran
        """,
    )

    # Data untuk pratinjau harga di browser (harga asli tetap dibaca server saat simpan)
    tarif = {}
    for t in db.query(conn, "SELECT item_id, speed_id, harga FROM TARIFF"):
        tarif.setdefault(str(t["speed_id"]), {})[str(t["item_id"])] = int(t["harga"])
    durasi = {str(s["speed_id"]): int(s["durasi_jam"]) for s in layanan}

    error = None
    form = {"customer_id": "", "speed_id": ""}
    baris = [{"item_id": "", "jumlah": ""}]

    if request.method == "POST":
        form["customer_id"] = request.form.get("customer_id", "")
        form["speed_id"] = request.form.get("speed_id", "")
        baris = [
            {"item_id": i, "jumlah": j.strip()}
            for i, j in zip(
                request.form.getlist("item_id"), request.form.getlist("jumlah")
            )
        ]

        rincian = []
        sudah = set()
        for n, b in enumerate(baris, start=1):
            if not b["item_id"] and not b["jumlah"]:
                continue
            if not b["item_id"] or not b["jumlah"]:
                error = f"Baris {n}: barang dan jumlah harus diisi keduanya."
                break
            try:
                jumlah = Decimal(b["jumlah"].replace(",", "."))
            except InvalidOperation:
                error = f"Baris {n}: jumlah harus berupa angka."
                break
            if jumlah <= 0:
                error = f"Baris {n}: jumlah harus lebih dari 0."
                break
            if b["item_id"] in sudah:
                error = f"Baris {n}: barang yang sama sudah ada di nota ini."
                break
            sudah.add(b["item_id"])
            rincian.append({"item_id": int(b["item_id"]), "jumlah": jumlah})

        if error is None and not (form["customer_id"] and form["speed_id"]):
            error = "Pelanggan dan layanan harus dipilih."
        if error is None and not rincian:
            error = "Nota harus memiliki minimal satu barang."

        if error is None:
            try:
                order_id = simpan_nota(conn, form, rincian)
            except ValueError as e:
                error = str(e)
            except mysql.connector.Error as e:
                error = "Gagal menyimpan nota: " + str(e.msg)
            else:
                flash(f"Nota N-{order_id:04d} berhasil dibuat.", "sukses")
                return redirect(url_for("beranda"))

        if not baris:
            baris = [{"item_id": "", "jumlah": ""}]

    return render_template(
        "nota_baru.html",
        halaman="nota",
        error=error,
        form=form,
        baris=baris,
        pelanggan=pelanggan,
        layanan=layanan,
        barang=barang,
        tarif=tarif,
        durasi=durasi,
    )

@app.route("/pembayaran", methods=["GET", "POST"])
def pembayaran():
    conn = koneksi_aktif()

    daftar = db.query(
        conn,
        """
        SELECT order_id, no_nota, pelanggan, status_pembayaran
        FROM v_nota_ringkas
        ORDER BY (status_pembayaran = 'Lunas'), order_id DESC
        """,
    )
    metode = db.query(
        conn, "SELECT method_id, nama_metode FROM PAYMENT_METHOD ORDER BY method_id"
    )

    nota_id = request.args.get("nota", type=int)
    if nota_id is None and daftar:
        nota_id = daftar[0]["order_id"]

    nota = None
    riwayat = []
    if nota_id is not None:
        hasil = db.query(
            conn,
            """
            SELECT order_id, no_nota, pelanggan, total_biaya, total_bayar,
                   sisa_tagihan, status_pembayaran
            FROM v_nota_ringkas WHERE order_id = %s
            """,
            (nota_id,),
        )
        if not hasil:
            flash("Nota tidak ditemukan.", "galat")
            return redirect(url_for("pembayaran"))
        nota = hasil[0]
        riwayat = db.query(
            conn,
            """
            SELECT p.payment_id, p.tanggal_bayar, m.nama_metode,
                   p.jumlah_bayar, p.jenis_bayar
            FROM PAYMENT p
            JOIN PAYMENT_METHOD m ON m.method_id = p.method_id
            WHERE p.order_id = %s
            ORDER BY p.tanggal_bayar, p.payment_id
            """,
            (nota_id,),
        )

    error = None
    form = {"method_id": "", "jumlah_bayar": ""}

    if request.method == "POST" and nota is not None:
        form["method_id"] = request.form.get("method_id", "").strip()
        form["jumlah_bayar"] = request.form.get("jumlah_bayar", "").strip()
        teks = form["jumlah_bayar"].replace(".", "").replace(",", "")

        if nota["sisa_tagihan"] <= 0:
            error = "Nota ini sudah lunas."
        elif not form["method_id"]:
            error = "Metode pembayaran harus dipilih."
        elif not teks.isdigit() or int(teks) <= 0:
            error = "Jumlah bayar harus berupa angka lebih dari 0."
        elif Decimal(int(teks)) > nota["sisa_tagihan"]:
            error = (
                "Jumlah bayar melebihi sisa tagihan ("
                + format_rupiah(nota["sisa_tagihan"])
                + ")."
            )
        else:
            jumlah = int(teks)
            jenis = "Pelunasan" if Decimal(jumlah) >= nota["sisa_tagihan"] else "Uang Muka"
            try:
                db.execute(
                    conn,
                    "INSERT INTO PAYMENT (order_id, method_id, tanggal_bayar, jumlah_bayar, jenis_bayar) "
                    "VALUES (%s, %s, NOW(), %s, %s)",
                    (nota_id, form["method_id"], jumlah, jenis),
                )
            except mysql.connector.Error as e:
                error = "Gagal menyimpan pembayaran: " + str(e.msg)
            else:
                flash(
                    f"Pembayaran {format_rupiah(jumlah)} untuk nota {nota['no_nota']} "
                    f"tercatat sebagai {jenis}.",
                    "sukses",
                )
                return redirect(url_for("pembayaran", nota=nota_id))

    return render_template(
        "pembayaran.html",
        halaman="pembayaran",
        daftar=daftar,
        nota=nota,
        riwayat=riwayat,
        metode=metode,
        form=form,
        error=error,
    )



@app.route("/cucian")
def cucian():
    conn = koneksi_aktif()
    nota = db.query(
        conn,
        """
        SELECT order_id, no_nota, pelanggan, layanan, tanggal_terima,
               status_cucian, tanggal_selesai, batas_ambil, status_pembayaran
        FROM v_nota_ringkas
        WHERE status_cucian <> 'Sudah diambil'
        ORDER BY order_id
        """,
    )
    return render_template(
        "cucian.html", halaman="cucian", nota=nota, sekarang=datetime.now()
    )


@app.route("/cucian/<int:order_id>/<aksi>", methods=["POST"])
def ubah_status(order_id, aksi):
    conn = koneksi_aktif()
    if aksi == "selesai":
        sql = (
            "UPDATE ORDERS SET status_cucian = 'Siap diambil', tanggal_selesai = NOW() "
            "WHERE order_id = %s AND status_cucian = 'Sedang diproses'"
        )
        hasil = "ditandai Siap diambil."
    elif aksi == "diambil":
        sql = (
            "UPDATE ORDERS SET status_cucian = 'Sudah diambil', tanggal_ambil = NOW() "
            "WHERE order_id = %s AND status_cucian = 'Siap diambil'"
        )
        hasil = "ditandai Sudah diambil."
    else:
        return redirect(url_for("cucian"))

    nomor = f"N-{order_id:04d}"
    try:
        jumlah = db.execute(conn, sql, (order_id,))
        if jumlah:
            flash(f"Nota {nomor} {hasil}", "sukses")
        else:
            flash(f"Status nota {nomor} tidak bisa diubah.", "galat")
    except mysql.connector.Error as e:
        flash("Gagal mengubah status: " + str(e.msg), "galat")
    return redirect(url_for("cucian"))

if __name__ == "__main__":
    app.run(debug=True)