#!/usr/bin/env python3
"""
convert_bis.py — bis_data.json → BisData.lua 변환
BisData        : class → spec → zone → [item_ids]   (던전 입장 BIS 체크용)
BisSlotData    : class → spec → slot → [{id,zone,boss,phase}]  (!비스 슬롯 조회용)
"""
import json, re

# bis_data.json 영문 던전/레이드명 → WoW 한글 지역명
DUNGEON_KO = {
    # TBC 레이드
    "Karazhan":             "카라잔",
    "Gruul's Lair":         "그룰의 둥지",
    "Magtheridon's Lair":   "마그테리돈의 둥지",
    "Serpentshrine Cavern": "불뱀 제단",
    "Tempest Keep":         "폭풍우 요새",
    "Black Temple":         "검은 사원",
    "Hyjal Summit":         "하이잘 정상",
    "Zul'Aman":             "줄아만",
    "Sunwell Plateau":      "태양샘 고원",
    # TBC 5인 던전
    "Hellfire Ramparts":       "지옥불 성루",
    "The Blood Furnace":       "피의 용광로",
    "Blood Furnace":           "피의 용광로",
    "The Shattered Halls":     "으스러진 손의 전당",
    "Mana Tombs":              "마나 무덤",
    "Mana-Tombs":              "마나 무덤",
    "Auchenai Crypts":         "아키나이 납골당",
    "Sethekk Halls":           "세데크 전당",
    "Shadow Labyrinth":        "어둠의 미궁",
    "The Slave Pens":          "강제 노역소",
    "The Underbog":            "지하수령",
    "The Steamvault":          "증기 저장고",
    "Old Hillsbrad Foothills": "옛 힐스브래드 구릉지",
    "Black Morass":            "검은늪",
    "The Arcatraz":            "알카트라즈",
    "The Botanica":            "신록의 정원",
    "The Mechanar":            "메카나르",
    "Magister's Terrace":      "마법학자의 정원",
    # 별칭 (fetch_preraid_bis.py 등에서 다양한 표기 사용)
    "Shattered Halls":         "으스러진 손의 전당",
    "Slave Pens":              "강제 노역소",
    "Underbog":                "지하수령",
    "Steamvault":              "증기 저장고",
    "Arcatraz":                "알카트라즈",
    "Botanica":                "신록의 정원",
    "Mechanar":                "메카나르",
    "The Black Morass":        "검은늪",
    "(H) Old Hillsbrad Foothills": "옛 스브레드 구릉지",
}

# fetch_bis.py 특성명 → WoW 게임 실제 특성명
CLASS_SPEC_RENAME = {
    "사냥꾼":   {"야수": "야수술", "사격": "사격술"},
    "주술사":   {"회복": "복원"},
    "흑마법사": {"악마": "악마학", "파괴": "파멸"},
}

# 영문 슬롯명 → 한글 슬롯 키
SLOT_MAP = {
    "Helm":            "머리",
    "Neck":            "목",
    "Shoulder":        "어깨",
    "Shoulders":       "어깨",
    "Back":            "등",
    "Cloak":           "등",
    "Chest":           "가슴",
    "Bracer":          "손목",
    "Wrists":          "손목",
    "Gloves":          "장갑",
    "Hands":           "장갑",
    "Belt":            "허리",
    "Waist":           "허리",
    "Legs":            "다리",
    "Boots":           "발",
    "Feet":            "발",
    "Ring 1":          "반지1",
    "Ring 2":          "반지2",
    "Trinket 1":       "장신구1",
    "Trinket 2":       "장신구2",
    "Weapon":          "주장비",
    "2-Hander":        "주장비",
    "Main-Hand":       "주장비",
    "Melee Weapon":    "주장비",
    "One-Hand":        "주장비",
    "Two-Hand":        "주장비",
    "Dual Wield - MH": "주장비",
    "Off-Hand":        "보조장비",
    "Off-hand":        "보조장비",
    "Off-hands":       "보조장비",
    "Shield":          "보조장비",
    "Dual Wield - OH": "보조장비",
    "Ranged":          "원거리",
    "Ranged Weapon":   "원거리",
    "Wand":            "원거리",
    "Relic":           "원거리",
    "Relics":          "원거리",
    "Idols":           "원거리",
    "Libram":          "원거리",
    # 복합 슬롯 — 스킵
    "Rings": None, "Trinkets": None, "Best Trinkets": None, "Weapons": None,
}

def phase_order(phase_str):
    """페이즈 문자열에서 정렬 키 반환 (높을수록 최신). Pre-Raid=0."""
    m = re.search(r"Phase\s+(\d+)", phase_str)
    if m:
        return int(m.group(1))
    if "Pre" in phase_str:
        return 0
    return -1


def lua_str(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    with open("bis_data.json", encoding="utf-8") as f:
        data = json.load(f)

    # ── BisData: zone → [ids] ─────────────────────────────────────────────
    zone_result = {}
    # ── BisSlotData: slot → [{id, zone, boss, phase}] ────────────────────
    slot_result = {}
    skipped_zones = set()

    for cls, specs in data.items():
        zone_result[cls] = {}
        slot_result[cls] = {}
        spec_rename = CLASS_SPEC_RENAME.get(cls, {})

        for spec, phases in specs.items():
            spec_ko = spec_rename.get(spec, spec)
            zone_items = {}   # zone_ko → set of ids
            slot_items = {}   # slot_ko → list of {id, zone, boss, phase, order}

            # 페이즈를 최신순으로 처리해 phase label 결정
            sorted_phases = sorted(phases.items(), key=lambda x: phase_order(x[0]), reverse=True)

            for phase_str, items in sorted_phases:
                p_ord = phase_order(phase_str)
                phase_label = f"P{p_ord}" if p_ord > 0 else "P0"

                for item in items:
                    item_id = item.get("id")
                    dungeon_en = item.get("dungeon", "")
                    boss_en    = item.get("boss", "")
                    slot_en    = item.get("slot", "")
                    zone_ko    = DUNGEON_KO.get(dungeon_en)

                    # ── zone 데이터 (BisData) ─────────────────────────
                    if item_id and zone_ko:
                        zone_items.setdefault(zone_ko, set()).add(item_id)
                    elif item_id and dungeon_en:
                        skipped_zones.add(dungeon_en)

                    # ── slot 데이터 (BisSlotData) ─────────────────────
                    slot_ko = SLOT_MAP.get(slot_en)
                    if not slot_ko or not item_id:
                        continue

                    # 같은 슬롯에 이미 같은 아이템이 있으면 스킵 (최신 페이즈 우선)
                    existing = slot_items.get(slot_ko, [])
                    if any(e["id"] == item_id for e in existing):
                        continue

                    slot_items.setdefault(slot_ko, []).append({
                        "id":    item_id,
                        "zone":  zone_ko or dungeon_en,
                        "boss":  boss_en,
                        "phase": phase_label,
                        "order": p_ord,
                    })

            if zone_items:
                zone_result[cls][spec_ko] = {k: sorted(v) for k, v in zone_items.items()}
            if slot_items:
                # 각 슬롯 내 페이즈 최신순 정렬
                slot_result[cls][spec_ko] = {
                    sk: sorted(v, key=lambda x: -x["order"])
                    for sk, v in slot_items.items()
                }

    # ── BisData 출력 ──────────────────────────────────────────────────────
    lines = [
        "-- BisData.lua — 자동 생성 (convert_bis.py로 재생성 가능)",
        "-- BisData     : class → spec → zone(한글) → item ID 목록",
        "-- BisSlotData : class → spec → slot(한글) → [{id, zone, boss, phase}]",
        "",
        "MyGreeting_BisData = {",
    ]
    for cls, specs in sorted(zone_result.items()):
        lines.append(f'    ["{cls}"] = {{')
        for spec, zones in sorted(specs.items()):
            lines.append(f'        ["{spec}"] = {{')
            for zone, ids in sorted(zones.items()):
                lines.append(f'            ["{lua_str(zone)}"] = {{{", ".join(str(i) for i in ids)}}},')
            lines.append('        },')
        lines.append('    },')
    lines.append("}")
    lines.append("")

    # ── BisSlotData 출력 ─────────────────────────────────────────────────
    lines.append("MyGreeting_BisSlotData = {")
    for cls, specs in sorted(slot_result.items()):
        lines.append(f'    ["{cls}"] = {{')
        for spec, slots in sorted(specs.items()):
            lines.append(f'        ["{spec}"] = {{')
            for slot, entries in sorted(slots.items()):
                lines.append(f'            ["{slot}"] = {{')
                for e in entries:
                    boss_lua = lua_str(e["boss"])
                    zone_lua = lua_str(e["zone"])
                    lines.append(
                        f'                {{id={e["id"]}, zone="{zone_lua}", boss="{boss_lua}", phase="{e["phase"]}"}},')
                lines.append('            },')
            lines.append('        },')
        lines.append('    },')
    lines.append("}")
    lines.append("")

    out = "BisData.lua"
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    total_zone = sum(len(ids) for sp in zone_result.values() for ids in sp.values() for ids in ids.values())
    total_slot = sum(len(v) for sp in slot_result.values() for sl in sp.values() for v in sl.values())
    print(f"완료 → {out}  (zone:{total_zone}개 / slot:{total_slot}개)")
    if skipped_zones:
        print("zone 매핑 없음:", sorted(skipped_zones))


if __name__ == "__main__":
    main()
