import requests
import sys
import json

CLIENT_ID = "YOUR_CLIENT_ID"
CLIENT_SECRET = "YOUR_CLIENT_SECRET"

TOKEN_URL = "https://kr.battle.net/oauth/token"
API_BASE = "https://kr.api.blizzard.com"
# Anniversary 서버가 안 되면 "profile-classic-kr" 로 바꿔보세요
NAMESPACE = "profile-classicann-kr"


def get_token():
    resp = requests.post(
        TOKEN_URL,
        data={"grant_type": "client_credentials"},
        auth=(CLIENT_ID, CLIENT_SECRET),
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def get_equipment(realm_slug, character_name, token):
    url = f"{API_BASE}/profile/wow/character/{realm_slug}/{character_name.lower()}/equipment"
    resp = requests.get(
        url,
        params={"namespace": NAMESPACE, "locale": "ko_KR"},
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.json()


def print_equipment(data):
    items = data.get("equipped_items", [])
    if not items:
        print("장착 아이템 없음")
        return
    for item in items:
        slot = item["slot"]["name"]
        name = item.get("name", f"ID:{item['item']['id']}")
        quality = item.get("quality", {}).get("name", "")
        print(f"{slot:<14} {name} [{quality}]")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python get_equipment.py <realm_slug> <character_name>")
        print("  예시: python get_equipment.py nefarian 홍길동")
        sys.exit(1)

    realm_slug = sys.argv[1]
    character_name = sys.argv[2]

    try:
        token = get_token()
        data = get_equipment(realm_slug, character_name, token)
        print_equipment(data)
    except requests.HTTPError as e:
        print(f"API 오류: {e.response.status_code} — {e.response.text}")
