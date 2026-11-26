# Pemogan Laundry

Aplikasi pencatatan transaksi laundry berbasis web untuk **Proyek Basis Data**
(Universitas Pendidikan Ganesha). Studi kasus: Pemogan Laundry.

## Teknologi
- Database: MySQL 8.0.16 atau lebih baru (butuh dukungan CHECK constraint)
- Backend: Python + Flask
- Penghubung: mysql-connector-python
- Tampilan: HTML, CSS, dan sedikit JavaScript (template Jinja)

## Struktur proyek
```
Laundry_app/
├── app.py                  # route dan logika aplikasi
├── db.py                   # koneksi dan helper query MySQL
├── requirements.txt
├── database/
│   └── project_database.sql   # skema, data contoh, view, trigger, akun MySQL
├── templates/              # halaman HTML (Jinja)
└── static/                 # CSS dan JavaScript
```

## Cara menjalankan
1. Pasang Python 3 dan MySQL (8.0.16+).
2. Buka `database/project_database.sql` di MySQL Workbench (koneksi `root`), lalu
   jalankan seluruh script. **Script ini menghapus lalu membuat ulang database
   `pemogan_laundry`.**
3. Pasang paket Python:
   ```
   pip install -r requirements.txt
   ```
4. Jalankan aplikasi:
   ```
   python app.py
   ```
5. Buka `http://127.0.0.1:5000` di browser.

Jika MySQL tidak memakai `localhost:3306`, atur variabel lingkungan `DB_HOST`,
`DB_PORT`, dan `DB_NAME` sebelum menjalankan aplikasi.

## Akun
Login memakai akun MySQL langsung (tidak ada tabel pengguna).

| Peran | Username | Hak akses MySQL | Menu |
|---|---|---|---|
| Petugas | `petugas` | SELECT, INSERT, UPDATE, DELETE | Dashboard, Pelanggan, Nota baru, Pembayaran, Status cucian, Laporan |
| Owner | `owner` | SELECT saja | Laporan |

Password pada script SQL hanyalah **contoh untuk demo**. Ganti dengan:
```sql
ALTER USER 'petugas'@'localhost' IDENTIFIED BY 'password_baru';
ALTER USER 'owner'@'localhost'   IDENTIFIED BY 'password_baru';
```

## Rancangan database
- 9 tabel: CUSTOMER, SPEED, ITEM_CATEGORY, ITEM, TARIFF, PAYMENT_METHOD, ORDERS,
  ORDER_DETAIL, PAYMENT.
- View `v_nota_ringkas` menghitung total biaya, total bayar, sisa tagihan, status
  lunas (R13), dan batas ambil 7 hari (R15). Nilai turunan tidak disimpan.
- Trigger: audit ORDERS (`dibuat_pada`, `dimodifikasi_pada`, `dimodifikasi_oleh`
  diisi dari akun MySQL yang login) dan validasi jumlah barang pcs harus bulat (R10).
- Aturan yang dijaga aplikasi: nota minimal satu rincian lewat transaksi database
  (R3), harga diambil dari TARIFF saat nota disimpan (R11).

## Anggota kelompok
- [I MADE ADI WIBAWA PRATAMA] ([2515101010]) - [ANGGOTA]
- [AHMAD SEPTYAWAN RAMADHAN] ([2515101026]) - [ANGGOTA]
- [I GEDE AGUS ADI PRAMANA] ([2515101099]) - [KETUA]