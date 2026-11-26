-- =====================================================================
-- project_database.sql
-- Basis data Pemogan Laundry (9 tabel) - MySQL 8.0.16 atau lebih baru
--
-- Cara menjalankan (MySQL Workbench):
--   1. Sambungkan ke Local instance sebagai root.
--   2. File > Open SQL Script, pilih file ini.
--   3. Klik ikon petir pertama (jalankan seluruh script).
-- Script boleh dijalankan berulang: database dan user lama dihapus dulu.
--
-- Isi: tabel + constraint, data contoh, trigger (audit dan aturan R10),
--      view ringkasan nota, user dan hak akses.
-- Password pada CREATE USER hanya password contoh untuk demo.
-- =====================================================================

SET NAMES utf8mb4;

DROP DATABASE IF EXISTS pemogan_laundry;
CREATE DATABASE pemogan_laundry
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE pemogan_laundry;

-- ---------------------------------------------------------------------
-- 1. TABEL MASTER
-- ---------------------------------------------------------------------

-- R6: nama boleh kembar, telepon wajib dan unik, alamat boleh kosong.
CREATE TABLE CUSTOMER (
  customer_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nama        VARCHAR(100)  NOT NULL,
  telepon     VARCHAR(20)   NOT NULL,
  alamat      VARCHAR(200)  NULL,
  CONSTRAINT pk_customer PRIMARY KEY (customer_id),
  CONSTRAINT uq_customer_telepon UNIQUE (telepon),
  CONSTRAINT ck_customer_nama CHECK (CHAR_LENGTH(TRIM(nama)) > 0)
);

-- Jenis layanan: Reguler, One Day, Express (R14: nama tidak boleh kembar).
CREATE TABLE SPEED (
  speed_id      TINYINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  jenis_layanan VARCHAR(20)       NOT NULL,
  durasi_jam    SMALLINT UNSIGNED NOT NULL,
  CONSTRAINT pk_speed PRIMARY KEY (speed_id),
  CONSTRAINT uq_speed_jenis UNIQUE (jenis_layanan),
  CONSTRAINT ck_speed_durasi CHECK (durasi_jam > 0)
);

-- R7: setiap jenis barang punya satu satuan hitung (kg atau pcs).
CREATE TABLE ITEM_CATEGORY (
  category_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nama_kategori VARCHAR(50)  NOT NULL,
  tipe_satuan   VARCHAR(3)   NOT NULL,
  CONSTRAINT pk_item_category PRIMARY KEY (category_id),
  CONSTRAINT uq_item_category_nama UNIQUE (nama_kategori),
  CONSTRAINT ck_item_category_satuan CHECK (tipe_satuan IN ('kg', 'pcs'))
);

-- Item = jenis barang + ukuran. Ukuran '-' bila tidak ada ukuran khusus.
CREATE TABLE ITEM (
  item_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id INT UNSIGNED NOT NULL,
  ukuran      VARCHAR(10)  NOT NULL DEFAULT '-',
  CONSTRAINT pk_item PRIMARY KEY (item_id),
  CONSTRAINT uq_item_kategori_ukuran UNIQUE (category_id, ukuran),
  CONSTRAINT fk_item_category FOREIGN KEY (category_id)
    REFERENCES ITEM_CATEGORY (category_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Associative entity ITEM x SPEED (R9: satu kombinasi punya satu tarif).
CREATE TABLE TARIFF (
  item_id  INT UNSIGNED     NOT NULL,
  speed_id TINYINT UNSIGNED NOT NULL,
  harga    DECIMAL(10,0)    NOT NULL,
  CONSTRAINT pk_tariff PRIMARY KEY (item_id, speed_id),
  CONSTRAINT fk_tariff_item FOREIGN KEY (item_id)
    REFERENCES ITEM (item_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_tariff_speed FOREIGN KEY (speed_id)
    REFERENCES SPEED (speed_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_tariff_harga CHECK (harga >= 0)
);

-- R16: daftar metode pembayaran.
CREATE TABLE PAYMENT_METHOD (
  method_id   TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nama_metode VARCHAR(30)      NOT NULL,
  CONSTRAINT pk_payment_method PRIMARY KEY (method_id),
  CONSTRAINT uq_payment_method_nama UNIQUE (nama_metode)
);

-- ---------------------------------------------------------------------
-- 2. TABEL TRANSAKSI
-- ---------------------------------------------------------------------

-- order_id dipakai sebagai nomor nota (ditampilkan sebagai N-0001, dst).
-- Kolom audit: dibuat_pada, dimodifikasi_pada, dimodifikasi_oleh
-- (diisi otomatis oleh trigger di bagian 5).
CREATE TABLE ORDERS (
  order_id          INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  customer_id       INT UNSIGNED     NOT NULL,
  speed_id          TINYINT UNSIGNED NOT NULL,
  tanggal_terima    DATETIME         NOT NULL,
  estimasi_selesai  DATETIME         NOT NULL,
  tanggal_selesai   DATETIME         NULL,
  tanggal_ambil     DATETIME         NULL,
  status_cucian     VARCHAR(20)      NOT NULL DEFAULT 'Sedang diproses',
  dibuat_pada       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dimodifikasi_pada DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dimodifikasi_oleh VARCHAR(50)      NOT NULL DEFAULT 'sistem',
  CONSTRAINT pk_orders PRIMARY KEY (order_id),
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
    REFERENCES CUSTOMER (customer_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_orders_speed FOREIGN KEY (speed_id)
    REFERENCES SPEED (speed_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_orders_status CHECK
    (status_cucian IN ('Sedang diproses', 'Siap diambil', 'Sudah diambil')),
  CONSTRAINT ck_orders_estimasi CHECK (estimasi_selesai >= tanggal_terima),
  CONSTRAINT ck_orders_selesai CHECK
    (tanggal_selesai IS NULL OR tanggal_selesai >= tanggal_terima),
  CONSTRAINT ck_orders_ambil CHECK
    (tanggal_ambil IS NULL
     OR (tanggal_selesai IS NOT NULL AND tanggal_ambil >= tanggal_selesai)),
  CONSTRAINT ck_orders_status_selesai CHECK
    (status_cucian = 'Sedang diproses' OR tanggal_selesai IS NOT NULL),
  CONSTRAINT ck_orders_status_ambil CHECK
    (status_cucian <> 'Sudah diambil' OR tanggal_ambil IS NOT NULL)
);

-- Associative entity ORDERS x ITEM.
-- R5: satu item paling banyak satu kali per nota (PK gabungan).
-- R11: harga_satuan menyimpan harga saat transaksi dibuat.
-- Catatan: aturan "nota minimal satu rincian" (R3) dijaga di aplikasi
-- dengan menyimpan nota dan rincian dalam satu transaksi database.
CREATE TABLE ORDER_DETAIL (
  order_id     INT UNSIGNED  NOT NULL,
  item_id      INT UNSIGNED  NOT NULL,
  jumlah       DECIMAL(6,2)  NOT NULL,
  harga_satuan DECIMAL(10,0) NOT NULL,
  CONSTRAINT pk_order_detail PRIMARY KEY (order_id, item_id),
  CONSTRAINT fk_detail_orders FOREIGN KEY (order_id)
    REFERENCES ORDERS (order_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_detail_item FOREIGN KEY (item_id)
    REFERENCES ITEM (item_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_detail_jumlah CHECK (jumlah > 0),
  CONSTRAINT ck_detail_harga CHECK (harga_satuan >= 0)
);

-- R12: satu nota bisa dibayar berkali-kali, satu pembayaran untuk satu nota.
-- Status lunas TIDAK disimpan; dihitung di view v_nota_ringkas (R13).
CREATE TABLE PAYMENT (
  payment_id   INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  order_id     INT UNSIGNED     NOT NULL,
  method_id    TINYINT UNSIGNED NOT NULL,
  tanggal_bayar DATETIME        NOT NULL,
  jumlah_bayar DECIMAL(10,0)    NOT NULL,
  jenis_bayar  VARCHAR(10)      NOT NULL,
  CONSTRAINT pk_payment PRIMARY KEY (payment_id),
  CONSTRAINT fk_payment_orders FOREIGN KEY (order_id)
    REFERENCES ORDERS (order_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_payment_method FOREIGN KEY (method_id)
    REFERENCES PAYMENT_METHOD (method_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_payment_jumlah CHECK (jumlah_bayar > 0),
  CONSTRAINT ck_payment_jenis CHECK (jenis_bayar IN ('Uang Muka', 'Pelunasan'))
);

-- ---------------------------------------------------------------------
-- 3. DATA CONTOH (dummy)
-- ---------------------------------------------------------------------

INSERT INTO SPEED (speed_id, jenis_layanan, durasi_jam) VALUES
  (1, 'Reguler', 48),
  (2, 'One Day', 24),
  (3, 'Express', 3);

INSERT INTO ITEM_CATEGORY (category_id, nama_kategori, tipe_satuan) VALUES
  (1, 'Cuci Kiloan', 'kg'),
  (2, 'Selimut',     'pcs'),
  (3, 'Boneka',      'pcs'),
  (4, 'Sprei',       'pcs'),
  (5, 'Bed Cover',   'pcs'),
  (6, 'Handuk',      'pcs');

INSERT INTO ITEM (item_id, category_id, ukuran) VALUES
  (1, 1, '-'),
  (2, 2, 'S/M'), (3, 2, 'XL'),
  (4, 3, 'S/M'), (5, 3, 'XL'),
  (6, 4, '-'),
  (7, 5, 'S/M'), (8, 5, 'XL'),
  (9, 6, '-');

-- Tarif: (item_id, speed_id, harga). Tarif satuan adalah asumsi kelompok.
INSERT INTO TARIFF (item_id, speed_id, harga) VALUES
  (1, 1,  5000), (1, 2,  8000), (1, 3, 12000),
  (2, 1, 10000), (2, 2, 15000), (2, 3, 20000),
  (3, 1, 15000), (3, 2, 20000), (3, 3, 25000),
  (4, 1, 10000), (4, 2, 22000), (4, 3, 28000),
  (5, 1, 12000), (5, 2, 25000), (5, 3, 30000),
  (6, 1, 10000), (6, 2, 15000), (6, 3, 20000),
  (7, 1, 20000), (7, 2, 28000), (7, 3, 36000),
  (8, 1, 30000), (8, 2, 40000), (8, 3, 50000),
  (9, 1,  5000), (9, 2,  7500), (9, 3, 10000);

INSERT INTO PAYMENT_METHOD (method_id, nama_metode) VALUES
  (1, 'Tunai'),
  (2, 'Transfer'),
  (3, 'QRIS');

-- Nomor telepon dan nama adalah data dummy. Customer 1 dan 5 bernama sama.
INSERT INTO CUSTOMER (customer_id, nama, telepon, alamat) VALUES
  (1,  'Budi Santoso',   '0812-3456-7890', 'Jl. Pemogan No. 12'),
  (2,  'Ni Luh Sari',    '0813-2200-4411', 'Gg. Mawar 3'),
  (3,  'Made Wirawan',   '0821-9087-6655', 'Jl. Bypass Ngurah Rai'),
  (4,  'Putu Ayu',       '0857-1100-2299', 'Jl. Pemogan Gg. 7'),
  (5,  'Budi Santoso',   '0878-4412-3300', 'Jl. Raya Sesetan'),
  (6,  'Kadek Dwi',      '0896-5521-7788', NULL),
  (7,  'Komang Arta',    '0838-9001-2345', 'Jl. Pemogan No. 40'),
  (8,  'Wayan Gunawan',  '0812-7788-1100', 'Jl. Pura Demak'),
  (9,  'Ni Made Ratna',  '0877-3345-9012', 'Gg. Melati 5'),
  (10, 'Gede Putra',     '0819-6600-4455', NULL);

-- Nota: (order_id, customer_id, speed_id, tanggal_terima, estimasi_selesai,
--        tanggal_selesai, tanggal_ambil, status_cucian)
INSERT INTO ORDERS
  (order_id, customer_id, speed_id, tanggal_terima, estimasi_selesai,
   tanggal_selesai, tanggal_ambil, status_cucian) VALUES
  (1,  1,  1, '2026-10-28 09:10:00', '2026-10-30 09:10:00', '2026-10-29 15:00:00', '2026-10-30 10:00:00', 'Sudah diambil'),
  (2,  2,  2, '2026-10-30 08:25:00', '2026-10-31 08:25:00', '2026-10-30 17:00:00', '2026-10-31 09:00:00', 'Sudah diambil'),
  (3,  3,  3, '2026-11-01 11:00:00', '2026-11-01 14:00:00', '2026-11-01 13:30:00', '2026-11-01 15:00:00', 'Sudah diambil'),
  (4,  7,  1, '2026-11-02 10:00:00', '2026-11-04 10:00:00', '2026-11-03 16:00:00', NULL,                  'Siap diambil'),
  (5,  4,  1, '2026-11-05 10:05:00', '2026-11-07 10:05:00', '2026-11-06 14:00:00', NULL,                  'Siap diambil'),
  (6,  6,  1, '2026-11-05 13:30:00', '2026-11-07 13:30:00', '2026-11-06 17:00:00', '2026-11-07 10:00:00', 'Sudah diambil'),
  (7,  8,  2, '2026-11-07 09:00:00', '2026-11-08 09:00:00', '2026-11-07 18:00:00', '2026-11-08 11:00:00', 'Sudah diambil'),
  (8,  9,  1, '2026-11-08 15:20:00', '2026-11-10 15:20:00', '2026-11-10 09:00:00', NULL,                  'Siap diambil'),
  (9,  5,  3, '2026-11-09 13:30:00', '2026-11-09 16:30:00', '2026-11-09 16:00:00', '2026-11-09 17:00:00', 'Sudah diambil'),
  (10, 3,  2, '2026-11-10 10:05:00', '2026-11-11 10:05:00', '2026-11-10 20:00:00', NULL,                  'Siap diambil'),
  (11, 10, 1, '2026-11-11 09:10:00', '2026-11-13 09:10:00', '2026-11-12 16:00:00', NULL,                  'Siap diambil'),
  (12, 1,  1, '2026-11-12 09:10:00', '2026-11-14 09:10:00', NULL,                  NULL,                  'Sedang diproses'),
  (13, 2,  2, '2026-11-12 08:25:00', '2026-11-13 08:25:00', '2026-11-13 15:00:00', NULL,                  'Siap diambil'),
  (14, 7,  3, '2026-11-13 10:00:00', '2026-11-13 13:00:00', '2026-11-13 12:30:00', NULL,                  'Siap diambil'),
  (15, 6,  1, '2026-11-14 09:00:00', '2026-11-16 09:00:00', NULL,                  NULL,                  'Sedang diproses');

-- Kolom audit data contoh: dianggap dicatat oleh petugas saat nota diterima.
UPDATE ORDERS
   SET dibuat_pada       = tanggal_terima,
       dimodifikasi_pada = COALESCE(tanggal_ambil, tanggal_selesai, tanggal_terima),
       dimodifikasi_oleh = 'petugas'
 WHERE order_id > 0;

-- Rincian: (order_id, item_id, jumlah, harga_satuan sementara 0).
INSERT INTO ORDER_DETAIL (order_id, item_id, jumlah, harga_satuan) VALUES
  (1, 1, 4.00, 0),
  (2, 1, 3.00, 0), (2, 3, 1, 0),
  (3, 1, 2.00, 0), (3, 9, 2, 0),
  (4, 1, 5.00, 0), (4, 9, 3, 0),
  (5, 8, 2, 0),    (5, 6, 1, 0), (5, 1, 4.00, 0),
  (6, 2, 1, 0),    (6, 9, 3, 0),
  (7, 1, 6.00, 0), (7, 6, 2, 0),
  (8, 7, 1, 0),    (8, 3, 1, 0),
  (9, 4, 1, 0),    (9, 9, 1, 0),
  (10, 1, 2.50, 0), (10, 5, 2, 0),
  (11, 1, 3.50, 0), (11, 3, 1, 0), (11, 9, 2, 0),
  (12, 1, 7.00, 0),
  (13, 1, 3.00, 0), (13, 3, 1, 0), (13, 9, 1, 0),
  (14, 4, 2, 0),
  (15, 1, 5.00, 0), (15, 6, 1, 0);

-- Kunci harga dari TARIFF sesuai jenis layanan nota (R9 dan R11).
UPDATE ORDER_DETAIL d
  JOIN ORDERS o ON o.order_id = d.order_id
  JOIN TARIFF t ON t.item_id = d.item_id AND t.speed_id = o.speed_id
   SET d.harga_satuan = t.harga
 WHERE d.order_id > 0;

INSERT INTO PAYMENT (order_id, method_id, tanggal_bayar, jumlah_bayar, jenis_bayar) VALUES
  (1,  1, '2026-10-28 09:12:00', 10000, 'Uang Muka'),
  (1,  1, '2026-10-30 10:00:00', 10000, 'Pelunasan'),
  (2,  2, '2026-10-31 09:00:00', 44000, 'Pelunasan'),
  (3,  3, '2026-11-01 15:00:00', 44000, 'Pelunasan'),
  (5,  1, '2026-11-05 10:07:00', 50000, 'Uang Muka'),
  (6,  1, '2026-11-07 10:00:00', 25000, 'Pelunasan'),
  (7,  3, '2026-11-07 09:05:00', 30000, 'Uang Muka'),
  (7,  1, '2026-11-08 11:00:00', 48000, 'Pelunasan'),
  (9,  2, '2026-11-09 17:00:00', 38000, 'Pelunasan'),
  (10, 1, '2026-11-10 10:10:00', 40000, 'Uang Muka'),
  (11, 3, '2026-11-12 16:30:00', 42500, 'Pelunasan'),
  (12, 1, '2026-11-12 09:12:00', 35000, 'Pelunasan'),
  (13, 3, '2026-11-12 08:30:00', 20000, 'Uang Muka');

-- ---------------------------------------------------------------------
-- 4. VIEW (nilai turunan tidak disimpan sebagai kolom)
-- ---------------------------------------------------------------------

-- Subtotal, total biaya, total bayar, sisa, status lunas (R13), batas ambil (R15).
CREATE VIEW v_nota_ringkas AS
SELECT o.order_id,
       CONCAT('N-', LPAD(o.order_id, 4, '0')) AS no_nota,
       c.customer_id,
       c.nama                                  AS pelanggan,
       s.jenis_layanan                         AS layanan,
       o.tanggal_terima,
       o.tanggal_selesai,
       o.tanggal_ambil,
       o.status_cucian,
       b.total_biaya,
       COALESCE(p.total_bayar, 0)              AS total_bayar,
       b.total_biaya - COALESCE(p.total_bayar, 0) AS sisa_tagihan,
       CASE WHEN COALESCE(p.total_bayar, 0) >= b.total_biaya
            THEN 'Lunas' ELSE 'Belum lunas' END AS status_pembayaran,
       DATE_ADD(o.tanggal_selesai, INTERVAL 7 DAY) AS batas_ambil
  FROM ORDERS o
  JOIN CUSTOMER c ON c.customer_id = o.customer_id
  JOIN SPEED s    ON s.speed_id    = o.speed_id
  JOIN (SELECT order_id, SUM(jumlah * harga_satuan) AS total_biaya
          FROM ORDER_DETAIL GROUP BY order_id) b ON b.order_id = o.order_id
  LEFT JOIN (SELECT order_id, SUM(jumlah_bayar) AS total_bayar
               FROM PAYMENT GROUP BY order_id) p ON p.order_id = o.order_id;

-- ---------------------------------------------------------------------
-- 5. TRIGGER
-- ---------------------------------------------------------------------
-- Dibuat setelah data contoh agar data contoh tidak ikut tercatat sebagai root.
-- USER() mengembalikan akun yang sedang login (CURRENT_USER() di dalam trigger
-- mengembalikan pembuat trigger, bukan pengguna yang mengubah data).

DELIMITER $$

CREATE TRIGGER trg_orders_bi BEFORE INSERT ON ORDERS
FOR EACH ROW
BEGIN
  SET NEW.dibuat_pada       = CURRENT_TIMESTAMP;
  SET NEW.dimodifikasi_pada = CURRENT_TIMESTAMP;
  SET NEW.dimodifikasi_oleh = SUBSTRING_INDEX(USER(), '@', 1);
END$$

CREATE TRIGGER trg_orders_bu BEFORE UPDATE ON ORDERS
FOR EACH ROW
BEGIN
  SET NEW.dibuat_pada       = OLD.dibuat_pada;
  SET NEW.dimodifikasi_pada = CURRENT_TIMESTAMP;
  SET NEW.dimodifikasi_oleh = SUBSTRING_INDEX(USER(), '@', 1);
END$$

-- R10: barang dengan satuan pcs harus berjumlah bilangan bulat.
CREATE TRIGGER trg_detail_bi BEFORE INSERT ON ORDER_DETAIL
FOR EACH ROW
BEGIN
  DECLARE v_satuan VARCHAR(3);
  SELECT c.tipe_satuan INTO v_satuan
    FROM ITEM i JOIN ITEM_CATEGORY c ON c.category_id = i.category_id
   WHERE i.item_id = NEW.item_id;
  IF v_satuan = 'pcs' AND NEW.jumlah <> FLOOR(NEW.jumlah) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Jumlah barang satuan (pcs) harus bilangan bulat';
  END IF;
END$$

CREATE TRIGGER trg_detail_bu BEFORE UPDATE ON ORDER_DETAIL
FOR EACH ROW
BEGIN
  DECLARE v_satuan VARCHAR(3);
  SELECT c.tipe_satuan INTO v_satuan
    FROM ITEM i JOIN ITEM_CATEGORY c ON c.category_id = i.category_id
   WHERE i.item_id = NEW.item_id;
  IF v_satuan = 'pcs' AND NEW.jumlah <> FLOOR(NEW.jumlah) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Jumlah barang satuan (pcs) harus bilangan bulat';
  END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. USER DAN HAK AKSES (DCL)
-- ---------------------------------------------------------------------
-- petugas : membaca dan mengubah semua data.
-- owner   : hanya membaca (laporan dan audit).
-- Ganti password dengan: ALTER USER 'petugas'@'localhost' IDENTIFIED BY '...';

DROP USER IF EXISTS 'petugas'@'localhost';
DROP USER IF EXISTS 'owner'@'localhost';

CREATE USER 'petugas'@'localhost' IDENTIFIED BY 'Petugas#123';
CREATE USER 'owner'@'localhost'   IDENTIFIED BY 'Owner#123';

GRANT SELECT, INSERT, UPDATE, DELETE ON pemogan_laundry.* TO 'petugas'@'localhost';
GRANT SELECT ON pemogan_laundry.* TO 'owner'@'localhost';

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------
-- 7. PEMERIKSAAN CEPAT
-- ---------------------------------------------------------------------
-- Jumlah baris yang diharapkan: CUSTOMER 10, SPEED 3, ITEM_CATEGORY 6,
-- ITEM 9, TARIFF 27, PAYMENT_METHOD 3, ORDERS 15, ORDER_DETAIL 30, PAYMENT 13.
SELECT 'CUSTOMER' AS tabel, COUNT(*) AS jumlah_baris FROM CUSTOMER
UNION ALL SELECT 'SPEED', COUNT(*) FROM SPEED
UNION ALL SELECT 'ITEM_CATEGORY', COUNT(*) FROM ITEM_CATEGORY
UNION ALL SELECT 'ITEM', COUNT(*) FROM ITEM
UNION ALL SELECT 'TARIFF', COUNT(*) FROM TARIFF
UNION ALL SELECT 'PAYMENT_METHOD', COUNT(*) FROM PAYMENT_METHOD
UNION ALL SELECT 'ORDERS', COUNT(*) FROM ORDERS
UNION ALL SELECT 'ORDER_DETAIL', COUNT(*) FROM ORDER_DETAIL
UNION ALL SELECT 'PAYMENT', COUNT(*) FROM PAYMENT;

SELECT no_nota, pelanggan, layanan, status_cucian, total_biaya,
       total_bayar, sisa_tagihan, status_pembayaran, batas_ambil
  FROM v_nota_ringkas
 ORDER BY order_id;
