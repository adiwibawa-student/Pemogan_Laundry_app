import os

import mysql.connector

HOST = os.environ.get("DB_HOST", "localhost")
PORT = int(os.environ.get("DB_PORT", "3306"))
DATABASE = os.environ.get("DB_NAME", "pemogan_laundry")


def koneksi(username, password):
    """Buka koneksi MySQL memakai akun yang diketik pengguna."""
    return mysql.connector.connect(
        host=HOST,
        port=PORT,
        user=username,
        password=password,
        database=DATABASE,
        autocommit=True,
    )


def query(conn, sql, params=None):
    """Jalankan SELECT, kembalikan daftar baris (dictionary)."""
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params or ())
    hasil = cur.fetchall()
    cur.close()
    return hasil


def execute(conn, sql, params=None):
    """Jalankan INSERT/UPDATE/DELETE, kembalikan jumlah baris terpengaruh."""
    cur = conn.cursor()
    cur.execute(sql, params or ())
    jumlah = cur.rowcount
    cur.close()
    return jumlah