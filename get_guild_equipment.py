import requests
import json
import time
import sys
import os
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")

TOKEN_URL = "https://kr.battle.net/oauth/token"
API_BASE = "https://kr.api.blizzard.com"
NAMESPACE_PROFILE = "profile-classicann-kr"
REALM = "fengus-ferocity"
GUILDS = ["moira", "불꽃-싸다구"]


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


def main():
    min_level = int(sys.argv[1]) if len(sys.argv) > 1 else 0

    print(f"[{datetime.now().strftime('%H:%M:%S')}] 토큰 발급 중...")
    token = get_token()

    members = []
    for guild in GUILDS:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] 길드 {guild} 로스터 조회 중...")
        roster = get_roster(token, guild)
        roster = [m for m in roster if m["character"].get("level", 0) >= min_level]
        print(f"  → {len(roster)}명")
        members.extend(roster)

    # 중복 캐릭 제거 (같은 캐릭이 두 길드에 있는 경우 대비)
    seen = set()
    unique = []
    for m in members:
        name = m["character"]["name"]
        if name not in seen:
            seen.add(name)
            unique.append(m)
    members = unique
    print(f"  → 전체 {len(members)}명 대상\n")

    results = {}
    failed = []

    for i, m in enumerate(members, 1):
        name = m["character"]["name"]
        level = m["character"].get("level", "?")
        rank = m["rank"]
        print(f"[{i}/{len(members)}] {name} (lv{level} rank{rank}) ... ", end="", flush=True)

        try:
            char_class = get_character_class(token, name)
            items = get_equipment(token, name)
            if items is None:
                print("404 스킵")
                failed.append(name)
            else:
                results[name] = {
                    "level": level,
                    "rank": rank,
                    "class": char_class,
                    "items": parse_items(items),
                }
                print(f"{len(items)}개 슬롯 [{char_class}]")
        except requests.HTTPError as e:
            print(f"오류 {e.response.status_code}")
            failed.append(name)

        time.sleep(0.1)  # API rate limit 방지

    output = {
        "guilds": GUILDS,
        "realm": REALM,
        "fetched_at": datetime.now().isoformat(),
        "members": results,
    }

    out_file = f"guild_equipment_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n완료: {len(results)}명 저장 → {out_file}")
    if failed:
        print(f"실패/스킵: {', '.join(failed)}")


if __name__ == "__main__":
    main()
