# MyGreeting 애드온 — 개발 참고

## 파일 구성

| 파일 | 역할 |
|------|------|
| GuildGreeter.lua | 핵심. 길드 인사, 던전 감지, 레벨업, 정각 인사, 슬래시 명령어 |
| PartyGreeter.lua | 파티 참가/퇴장 인사, 레벨업 귓말 |
| BuffGreeter.lua | 버프/소환/부활 감사 인사, 식탁 감지 |
| GearTracker.lua | 길드원 장비점수(ilvl/GS) 수집·조회·랭킹 |
| GuildDB.lua | 본캐/부캐 매핑(쪽지 파싱), 쪽지 조회 |
| MyTarget.lua | 타겟 감시·징표 시스템 |

---

## DB 구조 (MyGreetingDB — SavedVariables)

```
MyGreetingDB
├── messages{}          -- 커스텀 메시지 (key → string)
├── knownMembers{}      -- 기존 길드원 (name → true)
├── dungeonGreeted{}    -- 던전 첫 입장 시각 (name → {zone, time=Unix})
├── dailyInfo{}         -- 정각 인사 발송 날짜 기록
└── gearData{}          -- 장비 데이터
    └── [name]
        ├── class
        ├── spec1 { name, ilvl, gs, items, date, time=Unix }
        └── spec2 { name, ilvl, gs, items, date, time=Unix }
```

**주의:** `time` 필드는 `time()` (Unix 타임스탬프). `GetTime()`(게임 기동 후 경과초)와 혼용하면 안 됨. `/reload` 시 `GetTime()`은 리셋되지만 `time()`은 유지됨.

---

## GuildGreeter 핵심 런타임 변수

### 스냅샷 테이블 (ProcessRosterUpdate 기준)
```
prevOnline{}    -- [name] = true/false  : 직전 온라인 상태
prevLevels{}    -- [name] = level
prevRoster{}    -- [name] = true        : 온+오프 전체 멤버
prevZones{}     -- [name] = zone        : 마지막 실제 지역
```

**prevZones 갱신 규칙:** `zone ~= ""` 일 때만 업데이트. zone=""(로딩 화면)은 스킵 → 마지막 실제 지역 보존.

### 쿨타임/상태
```
dungeonGreeted{}   -- db.dungeonGreeted 와 동일 참조 (DB에 persist)
                   -- [name] = {zone, time=Unix}
lastOffline{}      -- [name] = GetTime() : 마지막 오프라인 시각
guildCmdCooldown{} -- [cmd]  = GetTime() : 길드 명령 쿨타임
```

**dungeonGreeted 생명주기:**
- ADDON_LOADED: `dungeonGreeted = db.dungeonGreeted` (DB 참조 연결)
- 던전 입장 감지 시: `{zone, time=time()}` 기록
- 로그아웃 감지 시: `nil` (line ~882)
- 로그인 감지 시: `nil` (line ~878)
- 비던전 zone으로 이동 시: `nil` (zone ~= "" 조건)
- PLAYER_GUILD_UPDATE: 전체 초기화 후 DB 재연결

### 초기화 흐름
```
ADDON_LOADED → DB 연결, dungeonGreeted = db.dungeonGreeted
PLAYER_LOGIN → initialized = false
             → INIT_DELAY(3초) 후 GuildRoster()
             → 0.5초 후 CollectRosterSnapshot() → prev* 세팅
             → 0.5초 후 initialized = true
             → NewTicker(30초, GuildRoster)  ← 주기적 갱신
```

`initialized = false` 동안 ProcessRosterUpdate는 prev* 갱신만 하고 return.

---

## 던전 입장 감지 로직

```lua
-- ProcessRosterUpdate 내부
zone ~= prevZone        -- 지역이 바뀌었고
and IsDungeon(zone)     -- 던전이며
and not recentlyGreeted -- 7200초(2시간) 이내 같은 던전 인사 안 했을 때
```

`recentlyGreeted` = `dungeonGreeted[name].zone == zone and time() - .time < 7200`

**로딩 화면 중복 방지:** zone=""일 때 prevZones 미갱신 → 로딩 전후 zone이 동일하면 `zone ~= prevZone` = false → 트리거 없음.

---

## 메시지 시스템

`MyGreeting_GetMsg(key, vars)` — 전역 함수, 모든 파일에서 사용.
- DB에 커스텀 메시지 있으면 우선 사용
- 없으면 `MyGreeting_DEFAULT_MESSAGES[key]` 폴백
- `{name}`, `{zone}`, `{level}` 등 vars로 치환

메시지 키: `morning / noon / welcome_new / welcome / rejoin / sleep / dungeon / levelup_guild / summon / resurrect / party_greet / party_leave / sugo`

---

## 파일 간 전역 공유

| 전역 | 정의 위치 | 사용처 |
|------|-----------|--------|
| `MyGreeting_GetMsg` | GuildGreeter | PartyGreeter, BuffGreeter |
| `MyGreeting_DEFAULT_MESSAGES` | GuildGreeter | PartyGreeter, BuffGreeter |
| `MyGreeting_GetGearScore` | GearTracker | GuildGreeter |
| `MyGreeting_GearStatus` | GearTracker | GuildGreeter |
| `MyGreeting_PrintGearRank` | GearTracker | GuildGreeter |
| `MyGreeting_GetNote` | GuildDB | GuildGreeter |
| `MyGreeting_MarkTarget` | MyTarget | GuildGreeter |
| `MyGreeting_WatchTarget` | MyTarget | GuildGreeter |

---

## 수정 시 주의사항

- **`dungeonGreeted`는 `db.dungeonGreeted`와 동일 참조** — `dungeonGreeted = {}` 로 재할당하면 DB 연결 끊김. 재할당 후 반드시 `dungeonGreeted = db.dungeonGreeted` 재연결.
- **`prevZones = currentZones` 금지** — 통째 교체하면 zone=""(로딩) 정보가 덮어써짐. 루프로 zone ~= "" 만 업데이트.
- **`time()` vs `GetTime()`** — DB 저장 시각은 `time()`. 세션 내 짧은 딜레이 비교는 `GetTime()` 가능.
- **`ProcessRosterUpdate`는 `GUILD_ROSTER_UPDATE` 0.2초 디바운스** — 30초 ticker + 자연 이벤트 둘 다 이 경로로 처리됨.
