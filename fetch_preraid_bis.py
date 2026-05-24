#!/usr/bin/env python3
"""
fetch_preraid_bis.py — Icy Veins Pre-Raid 페이지에서 5인던 BIS 데이터 수집
기존 bis_data.json에 "Pre-Raid" 페이즈로 병합.

페이지 포맷 자동 감지:
  A) 슬롯별 h2 포맷 (전사/사제/흑마): h2 = Head/Necklace/... → 각각 table
  B) 단일 테이블 포맷 (성기사/사냥꾼/도적 등): h2 "Pre-Raid Best in Slot" → 대형 table
"""
import requests
import json
import re
import time
from bs4 import BeautifulSoup

BASE_URL = "https://www.icy-veins.com/tbc-classic"

PRE_RAID_SPECS = [
    ("전사",     "분노",  "fury-warrior-dps-pve-pre-raid-gear"),
    ("전사",     "무기",  "arms-warrior-dps-pve-pre-raid-gear"),
    ("전사",     "방어",  "protection-warrior-tank-pve-pre-raid-gear"),
    ("성기사",   "신성",  "holy-paladin-healer-pve-pre-raid-gear"),
    ("성기사",   "보호",  "protection-paladin-tank-pve-pre-raid-gear"),
    ("성기사",   "응징",  "retribution-paladin-dps-pve-pre-raid-gear"),
    ("사냥꾼",   "야수",  "beast-mastery-hunter-dps-pve-pre-raid-gear"),
    ("사냥꾼",   "사격",  "marksmanship-hunter-dps-pve-pre-raid-gear"),
    ("사냥꾼",   "생존",  "survival-hunter-dps-pve-pre-raid-gear"),
    ("도적",     "전투",  "rogue-dps-pve-pre-raid-gear"),
    ("사제",     "신성",  "holy-priest-healer-pve-pre-raid-gear"),
    ("사제",     "암흑",  "shadow-priest-dps-pve-pre-raid-gear"),
    ("주술사",   "원소",  "elemental-shaman-dps-pve-pre-raid-gear"),
    ("주술사",   "고양",  "enhancement-shaman-dps-pve-pre-raid-gear"),
    ("주술사",   "회복",  "restoration-shaman-healer-pve-pre-raid-gear"),
    ("마법사",   "비전",  "arcane-mage-dps-pve-pre-raid-gear"),
    ("마법사",   "화염",  "fire-mage-dps-pve-pre-raid-gear"),
    ("마법사",   "냉기",  "frost-mage-dps-pve-pre-raid-gear"),
    ("흑마법사", "고통",  "affliction-warlock-dps-pve-pre-raid-gear"),
    ("흑마법사", "악마",  "demonology-warlock-dps-pve-pre-raid-gear"),
    ("흑마법사", "파괴",  "destruction-warlock-dps-pve-pre-raid-gear"),
    ("드루이드", "조화",  "balance-druid-dps-pve-pre-raid-gear"),
    ("드루이드", "야성",  "feral-druid-dps-pve-pre-raid-gear"),
    ("드루이드", "회복",  "restoration-druid-healer-pve-pre-raid-gear"),
]

# icy-veins dungeon guide URL slug → 영문 던전명
SLUG_TO_DUNGEON = {
    "hellfire-ramparts":        "Hellfire Ramparts",
    "blood-furnace":            "Blood Furnace",
    "shattered-halls":          "The Shattered Halls",
    "mana-tombs":               "Mana Tombs",
    "auchenai-crypts":          "Auchenai Crypts",
    "sethekk-halls":            "Sethekk Halls",
    "shadow-labyrinth":         "Shadow Labyrinth",
    "slave-pens":               "The Slave Pens",
    "underbog":                 "The Underbog",
    "steamvault":               "The Steamvault",
    "old-hillsbrad-foothills":  "Old Hillsbrad Foothills",  # → convert_bis.py에서 한글로 변환
    "black-morass":             "Black Morass",
    "arcatraz":                 "The Arcatraz",
    "botanica":                 "The Botanica",
    "mechanar":                 "The Mechanar",
    "magisters-terrace":        "Magister's Terrace",
    "karazhan":                 "Karazhan",
    "gruuls-lair":              "Gruul's Lair",
    "serpentshrine-cavern":     "Serpentshrine Cavern",
    "tempest-keep":             "Tempest Keep",
    "black-temple":             "Black Temple",
    "hyjal-summit":             "Hyjal Summit",
    "zul-aman":                 "Zul'Aman",
    "sunwell-plateau":          "Sunwell Plateau",
}

# 포맷 A: h2가 이 슬롯명이면 슬롯별 포맷으로 인식
SLOT_H2_NAMES = {
    "Head", "Necklace", "Neck", "Shoulder", "Shoulders", "Back",
    "Chest", "Wrist", "Wrists", "Hands", "Waist", "Legs", "Feet",
    "Finger", "Trinket", "Main Hand Weapon", "Off Hand Weapon",
    "Ranged", "Wand", "2H Weapon", "Shield",
}

PHASE_KEY = "Pre-Raid"

# 포맷 B에서 무시할 헤딩 키워드
SKIP_HEADINGS = {"Alternative", "Close Alt", "Enchant", "Changelog", "Further"}


def parse_source(src_td):
    """소스 칸 파싱 → (dungeon, boss)"""
    # 보스: a.npc 또는 span.npc
    npc_el = src_td.find("a", class_="npc") or src_td.find("span", class_="npc")
    boss = npc_el.get_text(strip=True) if npc_el else ""

    # 던전: dungeon-guide 링크
    dungeon = ""
    for a in src_td.find_all("a", href=True):
        m = re.search(r"/tbc-classic/([\w-]+)-dungeon-guide", a["href"])
        if m:
            slug = m.group(1)
            dungeon = SLUG_TO_DUNGEON.get(slug, a.get_text(strip=True))
            break

    if not dungeon:
        # 전체 텍스트에서 보스명 제거
        full = src_td.get_text(separator=" ", strip=True)
        if boss:
            full = full.replace(boss, "").strip(" -—")
        dungeon = re.sub(r"\s+", " ", full).strip()

    return dungeon, boss


def extract_item(col_item):
    """아이템 칸에서 (item_id, item_name) 추출"""
    a = col_item.find("a", href=True)
    if not a:
        return None, None
    m = re.search(r"/item/(\d+)", a["href"])
    if not m:
        return None, None
    return int(m.group(1)), a.get_text(strip=True)


def parse_slot_section(soup):
    """포맷 A: h2가 슬롯명, 그 다음 table (Rank | Item | Gems | Source)"""
    items = []
    for h in soup.find_all("h2"):
        slot = h.get_text(strip=True)
        if slot not in SLOT_H2_NAMES:
            continue
        table = h.find_next("table")
        if not table:
            continue
        for row in table.find_all("tr")[1:]:
            cols = row.find_all("td")
            if len(cols) < 2:
                continue
            item_id, item_name = extract_item(cols[1])
            if not item_id:
                continue
            dungeon, boss = "", ""
            if len(cols) >= 4:
                dungeon, boss = parse_source(cols[3])
            elif len(cols) == 3:
                dungeon, boss = parse_source(cols[2])
            items.append({
                "slot": slot, "name": item_name,
                "boss": boss, "dungeon": dungeon, "id": item_id,
            })
    return items


def parse_table_format(soup):
    """포맷 B: h2/h3 'Pre-Raid Best in Slot ...' → Slot | Item | [Gems] | Source"""
    items = []
    seen_ids = set()

    for h in soup.find_all(["h2", "h3"]):
        heading = h.get_text(strip=True)
        # "Pre-Raid" 또는 "Best in Slot" 포함, Phase 기반 헤딩은 제외
        has_preraid = "Pre-Raid" in heading or "Pre-raid" in heading or "Best in Slot" in heading or "Best-in-Slot" in heading
        if not has_preraid:
            continue
        # Phase X / ... 형식은 스킵 (Mage 페이지의 Phase-specific pre-raid 테이블)
        if re.search(r"Phase\s+\d", heading):
            continue
        if any(k in heading for k in SKIP_HEADINGS):
            continue

        table = h.find_next("table")
        if not table:
            continue

        for row in table.find_all("tr")[1:]:
            cols = row.find_all("td")
            if len(cols) < 2:
                continue
            slot = cols[0].get_text(strip=True)
            item_id, item_name = extract_item(cols[1])
            if not item_id:
                continue
            if item_id in seen_ids:
                continue
            seen_ids.add(item_id)
            dungeon, boss = parse_source(cols[-1]) if len(cols) >= 3 else ("", "")
            items.append({
                "slot": slot, "name": item_name,
                "boss": boss, "dungeon": dungeon, "id": item_id,
            })

    return items


def fetch_preraid(slug):
    url = f"{BASE_URL}/{slug}"
    resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
    if not resp.ok:
        print(f"  HTTP {resp.status_code}")
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # 포맷 감지: h2 슬롯명이 3개 이상이면 포맷 A
    slot_h2s = [h for h in soup.find_all("h2") if h.get_text(strip=True) in SLOT_H2_NAMES]
    if len(slot_h2s) >= 3:
        return parse_slot_section(soup)
    else:
        return parse_table_format(soup)


def main():
    import os
    if os.path.exists("bis_data.json"):
        with open("bis_data.json", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = {}

    total = len(PRE_RAID_SPECS)
    for i, (cls, spec, slug) in enumerate(PRE_RAID_SPECS, 1):
        print(f"[{i}/{total}] {cls} {spec} ... ", end="", flush=True)
        try:
            items = fetch_preraid(slug)
            if items is None:
                print("404/오류")
                continue
            if not items:
                print("아이템 없음")
                continue
            if cls not in data:
                data[cls] = {}
            if spec not in data[cls]:
                data[cls][spec] = {}
            data[cls][spec][PHASE_KEY] = items
            print(f"{len(items)}개")
        except Exception as e:
            print(f"오류: {e}")
        time.sleep(1)

    with open("bis_data.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("\n완료 → bis_data.json")


if __name__ == "__main__":
    main()
