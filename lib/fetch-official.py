#!/usr/bin/env python3
# 用桌面版 Claude 的 sessionKey（自动续期）调官方 usage 接口，输出标准化 JSON。
# 过 Cloudflare 依赖 curl_cffi 的浏览器 TLS 指纹模拟。失败时以非零退出码退出，由 probe 回退到估算。
import json
import os
import subprocess
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def norm_iso(s):
    if not s:
        return None
    try:
        d = datetime.fromisoformat(s)
        return d.astimezone().isoformat(timespec="seconds")
    except Exception:
        return s


def main():
    try:
        from curl_cffi import requests
    except Exception:
        print("ERR:no-curl_cffi", file=sys.stderr)
        sys.exit(4)

    try:
        sk = subprocess.check_output(
            ["python3", os.path.join(HERE, "decrypt-cookie.py"), "sessionKey"],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        print("ERR:no-sessionkey", file=sys.stderr)
        sys.exit(2)
    if not sk.startswith("sk-ant-sid"):
        print("ERR:bad-sessionkey", file=sys.stderr)
        sys.exit(2)

    s = requests.Session(impersonate="chrome", cookies={"sessionKey": sk})
    try:
        orgs = s.get("https://claude.ai/api/organizations", timeout=20).json()
        org = orgs[0]["uuid"]
        u = s.get(f"https://claude.ai/api/organizations/{org}/usage", timeout=15).json()
    except Exception as e:
        print(f"ERR:request:{e}", file=sys.stderr)
        sys.exit(3)

    fh = u.get("five_hour") or {}
    sd = u.get("seven_day") or {}
    if "utilization" not in fh:
        print("ERR:unexpected-shape", file=sys.stderr)
        sys.exit(5)

    out = {
        "five": {"pct": round(float(fh.get("utilization", 0)), 1), "cost": 0, "limit": 0,
                 "resetAt": norm_iso(fh.get("resets_at")), "startAt": None},
        "week": {"pct": round(float(sd.get("utilization", 0)), 1), "cost": 0, "limit": 0,
                 "resetAt": norm_iso(sd.get("resets_at"))},
        "source": "official",
        "at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
