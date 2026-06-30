#!/usr/bin/env python3
# 用 Chrome 里 minimax.io 登录 cookie 读 Coding Plan 的 5 小时窗口额度（周窗口无限）。
# 接口：/v1/api/openplatform/coding_plan/remains?GroupId=<gid>
# model_remains[].current_interval_remaining_percent = 当前窗口剩余%，end_time = 重置时刻。
import json, os, subprocess, sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    try:
        from curl_cffi import requests
    except Exception:
        print("ERR:no-curl_cffi", file=sys.stderr); sys.exit(4)
    try:
        ck = subprocess.check_output(["python3", os.path.join(HERE, "decrypt-chrome-cookie.py"), "%minimax.io"],
                                     text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        print("ERR:no-cookie", file=sys.stderr); sys.exit(2)
    cookies = dict(p.split("=", 1) for p in ck.split("; ") if "=" in p)
    gid = cookies.get("minimax_group_id_v2", "")
    s = requests.Session(impersonate="chrome", cookies=cookies)
    s.headers.update({"referer": "https://platform.minimax.io/subscribe/coding-plan", "accept": "application/json"})
    try:
        d = s.get("https://platform.minimax.io/v1/api/openplatform/coding_plan/remains",
                  params={"GroupId": gid}, timeout=15).json()
    except Exception as e:
        print(f"ERR:request:{e}", file=sys.stderr); sys.exit(3)

    models = d.get("model_remains")
    if not models:
        print("ERR:no-plan", file=sys.stderr); sys.exit(5)

    # 选 5 小时窗口（interval≈5h）；多条取剩余最少（最受限）的那个
    def hrs(m):
        return (m["end_time"] - m["start_time"]) / 3600000.0
    five = [m for m in models if 4 <= hrs(m) <= 6]
    pick = min(five or models, key=lambda m: m.get("current_interval_remaining_percent", 100))

    used = round(100 - float(pick.get("current_interval_remaining_percent", 100)), 1)
    reset_iso = datetime.fromtimestamp(pick["end_time"] / 1000).astimezone().isoformat(timespec="seconds")
    weekly_remain = float(pick.get("current_weekly_remaining_percent", 100))
    week_unlimited = pick.get("current_weekly_status") == 3 or weekly_remain >= 100

    out = {
        "five": {"pct": used, "resetAt": reset_iso},
        "week": {"pct": 0 if week_unlimited else round(100 - weekly_remain, 1), "resetAt": None},
        "weekUnlimited": week_unlimited,
        "source": "minimax-official",
        "at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
