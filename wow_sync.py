#!/usr/bin/env python3
"""
wow_sync.py — cron으로 실행. WoW 켜져있을 때만 길드 장비 갱신.

crontab 등록:
  crontab -e
  */30 * * * * /usr/bin/python3 /Applications/World\ of\ Warcraft/_anniversary_/Interface/AddOns/MyGreeting/wow_sync.py >> /tmp/wow_sync.log 2>&1
"""

import subprocess
import sys
import os
from datetime import datetime

ADDON_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_PREFIX = f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}]"


def is_wow_running():
    result = subprocess.run(
        ["pgrep", "-f", "World of Warcraft"],
        capture_output=True,
    )
    return result.returncode == 0


def run(script, *args):
    subprocess.run(
        [sys.executable, os.path.join(ADDON_DIR, script), *args],
        check=True,
        cwd=ADDON_DIR,
    )


if not is_wow_running():
    print(f"{LOG_PREFIX} WoW 실행 중 아님 — 스킵")
    sys.exit(0)

print(f"{LOG_PREFIX} WoW 실행 중 — 길드 장비 갱신 시작")

try:
    run("get_guild_equipment.py")
    run("import_gear.py")
    print(f"{LOG_PREFIX} 완료 — WoW에서 /reload 하면 반영됩니다.")
except subprocess.CalledProcessError as e:
    print(f"{LOG_PREFIX} 오류: {e}")
    sys.exit(1)
