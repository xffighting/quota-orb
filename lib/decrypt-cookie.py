#!/usr/bin/env python3
# 解密桌面版 Claude.app 的 claude.ai sessionKey cookie（Chromium macOS 加密格式）。
# 仅在本机使用，输出解密后的 cookie 值到 stdout（调用方负责保密，不落盘）。
import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

APP_SUPPORT = os.path.expanduser("~/Library/Application Support/Claude")
COOKIES_DB = os.path.join(APP_SUPPORT, "Cookies")
SAFE_STORAGE_SERVICE = "Claude Safe Storage"
SAFE_STORAGE_ACCOUNT = "Claude"


def get_safe_storage_key():
    out = subprocess.check_output(
        ["security", "find-generic-password", "-w",
         "-s", SAFE_STORAGE_SERVICE, "-a", SAFE_STORAGE_ACCOUNT],
        stderr=subprocess.DEVNULL,
    )
    return out.strip()


def read_encrypted_cookie(name):
    tmp = tempfile.mktemp(suffix=".sqlite")
    shutil.copy2(COOKIES_DB, tmp)
    try:
        con = sqlite3.connect(tmp)
        rows = con.execute(
            "SELECT host_key, encrypted_value FROM cookies "
            "WHERE name=? AND host_key LIKE '%claude.ai' ORDER BY LENGTH(encrypted_value) DESC",
            (name,),
        ).fetchall()
        con.close()
        return rows
    finally:
        os.unlink(tmp)


def aes_decrypt(enc, key):
    # 去掉 v10/v11 前缀
    if enc[:3] in (b"v10", b"v11"):
        enc = enc[3:]
    derived = hashlib.pbkdf2_hmac("sha1", key, b"saltysalt", 1003, 16)
    iv = b" " * 16
    p = subprocess.run(
        ["openssl", "enc", "-aes-128-cbc", "-d", "-nopad",
         "-K", derived.hex(), "-iv", iv.hex()],
        input=enc, capture_output=True,
    )
    data = p.stdout
    # 去 PKCS7 padding
    if data:
        pad = data[-1]
        if 1 <= pad <= 16:
            data = data[:-pad]
    return data


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "sessionKey"
    key = get_safe_storage_key()
    rows = read_encrypted_cookie(name)
    if not rows:
        print("ERR:no-cookie", file=sys.stderr)
        sys.exit(2)
    for host, enc in rows:
        data = aes_decrypt(enc, key)
        # 新版 Chromium 在明文前加 32 字节 domain SHA256，sessionKey 以 sk-ant-sid 开头
        for candidate in (data, data[32:]):
            try:
                text = candidate.decode("utf-8")
            except UnicodeDecodeError:
                continue
            if text.startswith("sk-ant-sid"):
                sys.stdout.write(text)
                return
    print("ERR:decrypt-failed", file=sys.stderr)
    sys.exit(3)


if __name__ == "__main__":
    main()
