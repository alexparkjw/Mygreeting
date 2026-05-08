# MyGreeting

WoW Classic Anniversary 전용 길드 관리 애드온입니다.  
길드원 자동 인사, 파티 인사, 버프/힐 감사, 장비점수 추적 기능을 제공합니다.

A guild management addon for WoW Classic Anniversary.  
Features automatic guild greetings, party greetings, buff/heal thanks, and gear score tracking.

---

## 기능 / Features

### 길드 자동 인사 / Guild Auto Greetings
- 길드원 접속 시 시간대별 자동 인사 (아침/점심/저녁)  
  Automatic time-based greetings when guild members log in (morning / noon / evening)
- 신규 길드원과 기존 길드원 구분 인사  
  Different messages for new vs. returning guild members
- 재접속 감지 (5분 이내 재접 별도 처리)  
  Rejoin detection (separate message within 5 minutes)
- 레벨업 축하 메시지  
  Level-up congratulation messages
- 던전 입장 감지 후 "무사히 돌고 득템하세요" 인사  
  Dungeon entry detection with a good-luck message
- 길드챗에서 내 이름 언급 시 화면 상단 경보 표시  
  On-screen alert when your name is mentioned in guild chat

### 파티 자동 인사 / Party Auto Greetings
- 파티/레이드 참가·퇴장 시 자동 인사  
  Auto greet and farewell when joining or leaving a party/raid

### 버프/힐 감사 / Buff & Heal Thanks
- 버프·소환·부활 받았을 때 자동 감사 인사  
  Automatically thanks players for buffs, summons, and resurrections

### 장비점수 추적 / Gear Score Tracking
- 길드원 타겟 또는 파티 결성 시 자동 인스펙트 → 장비점수 수집  
  Auto-inspects guild members when targeted or grouped to collect gear scores
- GearScore 애드온 캐시 우선 사용, 없으면 자체 공식 계산  
  Uses GearScore addon cache if available, otherwise calculates internally
- 특성(이중특성 포함) 자동 감지 및 표시  
  Detects and displays talent spec (dual spec supported)
- 장비 목록 아이템 링크(로컬) / 아이템명(귓말·길드챗) 출력  
  Item links in local chat, plain item names in whispers/guild chat
- 수집 데이터 SavedVariables에 영구 저장  
  Data persisted in SavedVariables across sessions

---

## 설치 / Installation

1. 이 저장소를 다운로드합니다.  
   Download this repository.
2. `MyGreeting` 폴더를 다음 경로에 복사합니다.  
   Copy the `MyGreeting` folder to:
   ```
   World of Warcraft/_anniversary_/Interface/AddOns/MyGreeting/
   ```
3. 게임 실행 후 애드온 목록에서 **MyGreeting** 활성화  
   Launch the game and enable **MyGreeting** in the AddOns list.

---

## 슬래시 명령어 / Slash Commands

| 명령어 / Command | 설명 / Description |
|---|---|
| `/mg` | 도움말 표시 / Show help |
| `/mg 장비` | 내 장비점수 + 장비 목록 / My gear score & item list |
| `/mg 장비 [이름]` | 특정 길드원 장비점수 + 장비 목록 / Gear score & items for a guild member |
| `/mg 장비순위` | 수집된 길드원 전체 장비점수 순위 / Full guild gear score ranking |
| `/mg 장비초기화` | 장비 데이터 전체 초기화 / Reset all gear data |
| `/mg 장비디버그온` | 인스펙트 디버그 로그 활성화 / Enable inspect debug log |
| `/mg 장비디버그오프` | 인스펙트 디버그 로그 비활성화 / Disable inspect debug log |

---

## 길드 채팅 명령어 / Guild Chat Commands

길드원 누구나 길드 채팅에서 사용 가능합니다.  
Any guild member can use these commands in guild chat.

| 명령어 / Command | 설명 / Description |
|---|---|
| `!장비` | 내 장비점수 (귓말 응답) / My gear score (whisper reply) |
| `!장비 [이름]` | 특정 길드원 장비점수 (귓말 응답) / A member's gear score (whisper reply) |
| `!장비순위` | 길드원 장비점수 순위 (귓말 응답) / Guild gear ranking (whisper reply) |
| `!길드장비` | 길드원 장비점수 순위 (길드챗 출력) / Guild gear ranking (guild chat) |
| `!길드장비 [이름]` | 특정 길드원 장비점수 (길드챗 출력) / A member's gear score (guild chat) |

---

## 메시지 커스터마이즈 / Customizing Messages

`/mg` 설정 패널에서 각 인사 메시지를 수정할 수 있습니다.  
You can edit greeting messages from the `/mg` settings panel.

사용 가능한 변수 / Available variables: `{name}`, `{level}`, `{zone}`

---

## 파일 구성 / File Structure

| 파일 / File | 역할 / Role |
|---|---|
| `GuildGreeter.lua` | 길드 자동 인사, 언급 경보, 슬래시 명령어 / Guild greetings, mention alert, slash commands |
| `GuildDB.lua` | 본캐/부캐 DB, 직업·종족 분포 / Main/alt DB, class & race distribution |
| `PartyGreeter.lua` | 파티 자동 인사 / Party auto greetings |
| `BuffGreeter.lua` | 버프·소환·부활 감사 / Buff, summon & resurrect thanks |
| `GearTracker.lua` | 장비점수 수집 및 조회 / Gear score tracking & lookup |

---

## 요구사항 / Requirements

- WoW Classic Anniversary (Interface 20505)
- GearScore 애드온 (선택 / Optional — 없으면 자체 계산 / falls back to internal calculation)
