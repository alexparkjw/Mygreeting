#!/usr/bin/env python3
"""
fetch_bis.py — Icy Veins에서 TBC Classic 직업별 BIS 데이터 수집
"""
import requests
import json
import re
import time
from bs4 import BeautifulSoup

BASE_URL = "https://www.icy-veins.com/tbc-classic"

SPECS = [
    ("전사", "분노",   "fury-warrior-dps-pve-gear-best-in-slot"),
    ("전사", "무기",   "arms-warrior-dps-pve-gear-best-in-slot"),
    ("전사", "방어",   "protection-warrior-tank-pve-gear-best-in-slot"),
    ("성기사", "신성", "holy-paladin-healer-pve-gear-best-in-slot"),
    ("성기사", "보호", "protection-paladin-tank-pve-gear-best-in-slot"),
    ("성기사", "응징", "retribution-paladin-dps-pve-gear-best-in-slot"),
    ("사냥꾼", "야수", "beast-mastery-hunter-dps-pve-gear-best-in-slot"),
    ("사냥꾼", "사격", "marksmanship-hunter-dps-pve-gear-best-in-slot"),
    ("사냥꾼", "생존", "survival-hunter-dps-pve-gear-best-in-slot"),
    ("도적",  "전투",  "rogue-dps-pve-gear-best-in-slot"),
    ("사제",  "신성",  "holy-priest-healer-pve-gear-best-in-slot"),
    ("사제",  "암흑",  "shadow-priest-dps-pve-gear-best-in-slot"),
    ("주술사", "원소", "elemental-shaman-dps-pve-gear-best-in-slot"),
    ("주술사", "고양", "enhancement-shaman-dps-pve-gear-best-in-slot"),
    ("주술사", "회복", "restoration-shaman-healer-pve-gear-best-in-slot"),
    ("마법사", "비전", "arcane-mage-dps-pve-gear-best-in-slot"),
    ("마법사", "화염", "fire-mage-dps-pve-gear-best-in-slot"),
    ("마법사", "냉기", "frost-mage-dps-pve-gear-best-in-slot"),
    ("흑마법사", "고통",   "affliction-warlock-dps-pve-gear-best-in-slot"),
    ("흑마법사", "악마",   "demonology-warlock-dps-pve-gear-best-in-slot"),
    ("흑마법사", "파괴",   "destruction-warlock-dps-pve-gear-best-in-slot"),
    ("드루이드", "조화",   "balance-druid-dps-pve-gear-best-in-slot"),
    ("드루이드", "야성",   "feral-druid-dps-pve-gear-best-in-slot"),
    ("드루이드", "회복",   "restoration-druid-healer-pve-gear-best-in-slot"),
]

def fetch_bis(slug):
    url = f"{BASE_URL}/{slug}"
    resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
    if not resp.ok:
        return None
    soup = BeautifulSoup(resp.text, "html.parser")

    result = {}

    # 페이즈 섹션 찾기
    headers = soup.find_all(["h2", "h3"])
    for h in headers:
        phase_text = h.get_text(strip=True)
        if not any(k in phase_text for k in ["Phase", "Pre-Raid", "Tier"]):
            continue

        phase = phase_text
        items = []

        # 다음 테이블 찾기
        table = h.find_next("table")
        if not table:
            continue

        for row in table.find_all("tr")[1:]:  # 헤더 스킵
            cols = row.find_all("td")
            if len(cols) < 2:
                continue
            slot = cols[0].get_text(strip=True)
            name = cols[1].get_text(strip=True)

            # 아이템 ID 추출 (wowclassicdb.com/tbc/item/{id})
            item_link = cols[1].find("a", href=True)
            item_id = None
            if item_link:
                m = re.search(r"/item/(\d+)", item_link["href"])
                if m:
                    item_id = int(m.group(1))

            # source: 첫 번째 링크=보스, 두 번째 링크=던전
            boss, dungeon = "", ""
            if len(cols) > 2:
                links = cols[2].find_all("a", href=True)
                if len(links) >= 2:
                    boss    = links[0].get_text(strip=True)
                    dungeon = links[1].get_text(strip=True)
                elif len(links) == 1:
                    dungeon = links[0].get_text(strip=True)
                else:
                    dungeon = cols[2].get_text(strip=True)

            if slot and name:
                items.append({
                    "slot":    slot,
                    "name":    name,
                    "boss":    boss,
                    "dungeon": dungeon,
                    "id":      item_id,
                })

        if items:
            result[phase] = items

    return result


def main():
    import os
    if os.path.exists("bis_data.json"):
        with open("bis_data.json", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = {}
    total = len(SPECS)

    for i, (cls, spec, slug) in enumerate(SPECS, 1):
        print(f"[{i}/{total}] {cls} {spec} ... ", end="", flush=True)
        try:
            bis = fetch_bis(slug)
            if bis:
                if cls not in data:
                    data[cls] = {}
                data[cls][spec] = bis
                total_items = sum(len(v) for v in bis.values())
                print(f"{len(bis)}개 페이즈, {total_items}개 아이템")
            else:
                print("데이터 없음")
        except Exception as e:
            print(f"오류: {e}")
        time.sleep(1)

    out = "bis_data.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"\n완료 → {out}")


if __name__ == "__main__":
    main()
