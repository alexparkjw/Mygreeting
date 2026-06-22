import requests
import json
import time
import sys
import os
import re
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")

TOKEN_URL = "https://kr.battle.net/oauth/token"
API_BASE = "https://kr.api.blizzard.com"
NAMESPACE_PROFILE = "profile-classicann-kr"
REALM = "fengus-ferocity"
GUILDS = []

ADDON_DIR = os.path.dirname(os.path.abspath(__file__))


def get_token():
    resp = requests.post(
        TOKEN_URL,
        data={"grant_type": "client_credentials"},
        auth=(CLIENT_ID, CLIENT_SECRET),
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def get_roster(token, guild):
    resp = requests.get(
        f"{API_BASE}/data/wow/guild/{REALM}/{guild}/roster",
        params={"namespace": NAMESPACE_PROFILE, "locale": "ko_KR"},
        headers={"Authorization": f"Bearer {token}"},
    )
    if not resp.ok:
        print(f"  [{guild}] 로스터 조회 실패 ({resp.status_code}) — 스킵")
        return []
    return resp.json()["members"]


def get_character_class(token, name):
    resp = requests.get(
        f"{API_BASE}/profile/wow/character/{REALM}/{name.lower()}",
        params={"namespace": NAMESPACE_PROFILE, "locale": "ko_KR"},
        headers={"Authorization": f"Bearer {token}"},
    )
    if not resp.ok:
        return ""
    return resp.json().get("character_class", {}).get("name", "")


def get_equipment(token, name):
    resp = requests.get(
        f"{API_BASE}/profile/wow/character/{REALM}/{name.lower()}/equipment",
        params={"namespace": NAMESPACE_PROFILE, "locale": "ko_KR"},
        headers={"Authorization": f"Bearer {token}"},
    )
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json().get("equipped_items", [])


def parse_items(equipped_items):
    result = {}
    for item in equipped_items:
        slot = item["slot"]["type"]
        result[slot] = {
            "name": item.get("name", f"ID:{item['item']['id']}"),
            "id": item["item"]["id"],
            "quality": item.get("quality", {}).get("type", ""),
        }
    return result


def find_wtf_dir():
    """와우 WTF/Account 경로 찾기"""
    # AddOns/MyGreeting -> Interface/AddOns/MyGreeting -> _anniversary_/Interface/...
    # WTF/Account/WARCRAFTPLUS/SavedVariables/Spy.lua
    possible = [
        # 같은 _anniversary_ 버전
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ADDON_DIR))),
                     "WTF", "Account", "WARCRAFTPLUS", "SavedVariables"),
        # WTF이 AddOns와 동일한 WoW 디렉토리 내에 있을 경우
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ADDON_DIR))),
                     os.pardir, "WTF", "Account", "WARCRAFTPLUS", "SavedVariables"),
    ]
    for p in possible:
        resolved = os.path.realpath(p)
        if os.path.isdir(resolved):
            return resolved
    return None


def get_spy_kos_names(spy_lua_path=None):
    """SpyDB.lua에서 KOS(살생부) 대상 캐릭명 추출"""
    if spy_lua_path is None:
        wtf_dir = find_wtf_dir()
        if not wtf_dir:
            print("  [Spy] WTF/Account 경로를 찾을 수 없음 — 스킵")
            return set()
        spy_lua_path = os.path.join(wtf_dir, "Spy.lua")

    if not os.path.exists(spy_lua_path):
        print(f"  [Spy] SpyDB 없음: {spy_lua_path}")
        return set()

    with open(spy_lua_path, "r", encoding="utf-8") as f:
        content = f.read()

    # SpyDB.KOSData 영역만 추출 (한글/영문 캐릭명 모두 대응)
    # 패턴: ["name"] = "캐릭명" 또는 name = "캐릭명"
    # kosData 블록 안에서만 수집
    kos_start = content.find('["kosData"]')
    if kos_start < 0:
        kos_start = content.find("kosData")
    if kos_start < 0:
        print("  [Spy] kosData 섹션 없음")
        return set()

    kos_section = content[kos_start:]

    # ["name"] = "..." 형태 추출 (Lua bracket key notation)
    names = re.findall(r'\["name"\]\s*=\s*"([^"]+)"', kos_section)
    # 중복 제거, 빈 문자열 제거
    unique = {n for n in names if n.strip()}
    print(f"  [Spy] KOS 대상 {len(unique)}명 발견")
    return unique


def main():
    min_level = int(sys.argv[1]) if len(sys.argv) > 1 else 0

    print(f"[{datetime.now().strftime('%H:%M:%S')}] 토큰 발급 중...")
    token = get_token()

    # ── 수집 대상 수집 ──
    # (name, level, rank, source) 튜플 리스트
    targets = []
    seen = set()

    # 1. 길드 로스터
    for guild in GUILDS:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] 길드 {guild} 로스터 조회 중...")
        roster = get_roster(token, guild)
        roster = [m for m in roster if m["character"].get("level", 0) >= min_level]
        for m in roster:
            name = m["character"]["name"]
            if name not in seen:
                seen.add(name)
                targets.append({
                    "name": name,
                    "level": m["character"].get("level", "?"),
                    "rank": m["rank"],
                    "source": f"길드({guild})"
                })
        print(f"  → {len(roster)}명")

    # 2. Spy KOS 대상 (살생부)
    spy_names = get_spy_kos_names()
    for name in spy_names:
        if name not in seen:
            seen.add(name)
            targets.append({
                "name": name,
                "level": "?",
                "rank": None,
                "source": "Spy KOS"
            })

    guild_count = len([t for t in targets if t["source"].startswith("길드")])
    spy_count = len([t for t in targets if t["source"] == "Spy KOS"])
    print(f"  → 전체 {len(targets)}명 대상 (길드 {guild_count} / Spy {spy_count})\n")

    # ── 장비 조회 ──
    results = {}
    failed = []

    for i, t in enumerate(targets, 1):
        name = t["name"]
        print(f"[{i}/{len(targets)}] {name} ({t['source']}) ... ", end="", flush=True)

        try:
            char_class = get_character_class(token, name)
            items = get_equipment(token, name)
            if items is None:
                print("404 스킵")
                failed.append(name)
            else:
                results[name] = {
                    "level": t["level"],
                    "rank": t["rank"],
                    "class": char_class,
                    "source": t["source"],
                    "items": parse_items(items),
                }
                print(f"{len(items)}개 슬롯 [{char_class}]")
        except requests.HTTPError as e:
            print(f"오류 {e.response.status_code}")
            failed.append(name)

        time.sleep(0.1)

    # ── 출력 ──
    output = {
        "guilds": GUILDS,
        "realm": REALM,
        "fetched_at": datetime.now().isoformat(),
        "members": results,
    }

    out_file = f"guild_equipment_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n완료: {len(results)}명 저장 → {out_file} ({len(targets) - len(results)}명 실패)")
    if failed:
        print(f"실패/스킵: {', '.join(failed)}")


if __name__ == "__main__":
    main()
