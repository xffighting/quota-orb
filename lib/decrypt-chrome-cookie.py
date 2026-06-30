#!/usr/bin/env python3
# 解密 Chrome 里指定域名的全部 cookie（Chromium macOS 加密），输出 "name=value; name=value" 串。
# 仅本机使用，供读取用户自己已登录的会话额度。
import hashlib, os, shutil, sqlite3, subprocess, sys, tempfile

CHROME = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/Cookies")
DOMAIN_LIKE = sys.argv[1] if len(sys.argv) > 1 else "%minimax%"


def safe_storage_key():
    out = subprocess.check_output(
        ["security", "find-generic-password", "-w", "-s", "Chrome Safe Storage", "-a", "Chrome"],
        stderr=subprocess.DEVNULL)
    return out.strip()


def aes_decrypt(enc, key):
    if enc[:3] in (b"v10", b"v11"):
        enc = enc[3:]
    derived = hashlib.pbkdf2_hmac("sha1", key, b"saltysalt", 1003, 16)
    iv = b" " * 16
    p = subprocess.run(["openssl", "enc", "-aes-128-cbc", "-d", "-nopad",
                        "-K", derived.hex(), "-iv", iv.hex()], input=enc, capture_output=True)
    data = p.stdout
    if data:
        pad = data[-1]
        if 1 <= pad <= 16:
            data = data[:-pad]
    # 新版 Chromium 明文前 32 字节是 domain SHA256，cookie 值在其后
    for cand in (data[32:], data):
        try:
            t = cand.decode("utf-8")
            if t and all(32 <= ord(c) < 127 or ord(c) > 160 for c in t):
                return t
        except UnicodeDecodeError:
            continue
    return None


def main():
    key = safe_storage_key()
    tmp = tempfile.mktemp(suffix=".sqlite")
    shutil.copy2(CHROME, tmp)
    try:
        con = sqlite3.connect(tmp)
        rows = con.execute(
            "SELECT name, encrypted_value, host_key FROM cookies WHERE host_key LIKE ? ORDER BY LENGTH(encrypted_value) DESC",
            (DOMAIN_LIKE,)).fetchall()
        con.close()
    finally:
        os.unlink(tmp)
    pairs = []
    for name, enc, host in rows:
        val = aes_decrypt(enc, key)
        if val:
            pairs.append(f"{name}={val}")
    if not pairs:
        print("ERR:no-cookies", file=sys.stderr); sys.exit(2)
    sys.stdout.write("; ".join(pairs))


if __name__ == "__main__":
    main()
