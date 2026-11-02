local _, ns = ...  -- Compat.lua (beta 포팅)
local GetAddOnMetadata, GetItemInfo, SendChatMessage = ns.GetAddOnMetadata, ns.GetItemInfo, ns.SendChatMessage
-- ============================================================
-- GuildGreeter.lua
-- 길드 커스텀 인사 시스템
-- ============================================================

local ADDON_NAME      = "MyGreeting"
local GREET_DELAY     = 1
local REJOIN_SKIP_SEC = 5 * 60
local INIT_DELAY      = 3

local DELAY_LOCAL   = 0
local DELAY_WHISPER = 1.0
local DELAY_GUILD   = 1.5

-- ============================================================
-- 클래식 던전 이름 목록 (한글/영문 둘 다)
-- ============================================================
local DUNGEONS = {
    -- ── 클래식 ────────────────────────────────────────────────
    ["성난불길 협곡"]=true,
    ["통곡의 동굴"]=true,
    ["죽음의 폐광"]=true,
    ["그림자송곳니 성채"]=true,
    ["검은심연의 나락"]=true,
    ["스톰윈드 지하감옥"]=true,
    ["놈리건"]=true,
    ["가시덩굴 우리"]=true,
    ["붉은십자군 수도원"]=true,  -- 클래식은 날개 구분 없이 이 이름으로 나올 수 있음
    ["붉은십자군 수도원 - 묘지"]=true,
    ["붉은십자군 수도원 - 도서관"]=true,
    ["붉은십자군 수도원 - 무기고"]=true,
    ["붉은십자군 수도원 - 예배당"]=true,
    ["가시덩굴 구릉"]=true,
    ["울다만"]=true,
    ["줄파락"]=true,
    ["마라우돈"]=true,
    ["아탈학카르 신전"]=true,
    ["검은바위 나락"]=true,
    ["검은바위 첨탑"]=true,
    ["검은바위 첨탑 (하층)"]=true,
    ["검은바위 첨탑 (상층)"]=true,
    ["혈투의 전장"]=true,
    ["혈투의 전장 (동쪽)"]=true,
    ["혈투의 전장 (서쪽)"]=true,
    ["혈투의 전장 (북쪽)"]=true,
    ["스칼로맨스"]=true,
    ["스트라솔름"]=true,
    -- ── beta 신규 ─────────────────────────────────────────────
    ["영주의 전당"]=true,
    ["로데론의 폐허"]=true,
    ["발굴현장: 저습지"]=true,  -- 공백/콜론은 무시하고 비교 (ZoneKey)
    -- ── TBC ───────────────────────────────────────────────────
    ["지옥불 성루"]=true,
    ["피의 용광로"]=true,
    ["으스러진 손의 전당"]=true,
    ["마나 무덤"]=true,
    ["아키나이 납골당"]=true,
    ["세데크 전당"]=true,
    ["어둠의 미궁"]=true,
    ["강제 노역소"]=true,
    ["지하수렁"]=true,
    ["증기 저장고"]=true,
    ["옛 힐스브래드 구릉지"]=true,
    ["검은늪"]=true,
    ["알카트라즈"]=true,
    ["신록의 정원"]=true,
    ["메카나르"]=true,
    ["마법학자의 정원"]=true,
    -- ── TBC 레이드 ────────────────────────────────────────────
    ["카라잔"]=true,
    ["그룰의 둥지"]=true,
    ["마그테리돈의 둥지"]=true,
    ["불뱀 제단"]=true,
    ["폭풍우 요새"]=true,
    ["검은 사원"]=true,
    ["하이잘 정상"]=true,
    ["줄아만"]=true,
    ["태양샘 고원"]=true,
}

-- 한글 던전 지역명 → 영어 약자 (DUNGEON_ABBR 정의 뒤에서 채움). beta 영어 서버 출력용
local ZONE_ABBR = {}
-- 지역명 비교용 키: 공백·콜론 제거 ("발굴현장: 저습지" = "발굴 현장:저습지")
local function ZoneKey(zone) return (zone:gsub("[%s:：]", "")) end
local ZONE_ABBR_N = setmetatable({}, { __index = function(t, k)
    for full, abbr in pairs(ZONE_ABBR) do
        if ZoneKey(full) == k then t[k] = abbr; return abbr end
    end
end })
local function ZoneAbbr(zone)
    if not zone or zone == "" then return zone end
    return ZONE_ABBR[zone] or ZONE_ABBR_N[ZoneKey(zone)] or zone
end

local DUNGEONS_N = {}
for z in pairs(DUNGEONS) do DUNGEONS_N[ZoneKey(z)] = true end

local function IsDungeon(zone)
    if not zone or zone == "" then return false end
    return DUNGEONS[zone] == true or DUNGEONS_N[ZoneKey(zone)] == true
end

-- NWB 영문 던전명 → 한글 지역명
local NWB_DUNGEON_KO = {
    ["The Arcatraz"]          = "알카트라즈",
    ["The Steamvault"]        = "증기 저장고",
    ["Shadow Labyrinth"]      = "어둠의 미궁",
    ["Black Morass"]          = "검은늪",
    ["Shattered Halls"]       = "으스러진 손의 전당",
    ["The Shattered Halls"]   = "으스러진 손의 전당",
    ["Magisters' Terrace"]    = "마법학자의 정원",
    ["The Botanica"]          = "신록의 정원",
    ["The Mechanar"]          = "메카나르",
    ["The Underbog"]          = "지하수렁",
    ["The Blood Furnace"]     = "피의 용광로",
    ["Hellfire Ramparts"]     = "지옥불 성루",
    ["Mana-Tombs"]            = "마나 무덤",
    ["Old Hillsbrad Foothills"] = "옛 힐스브래드 구릉지",
    ["Auchenai Crypts"]       = "아키나이 납골당",
    ["Sethekk Halls"]         = "세데크 전당",
    ["The Slave Pens"]        = "강제 노역소",
}
-- NWB PvP 일퀘 ID → 한글 전장 지역명 (ID는 안정적이므로 유지)
local NWB_PVP_DAILY = {
    [1]="전쟁노래 협곡", [2]="아라시 분지", [3]="알터랙 계곡", [4]="폭풍의 눈",
    [5]="전쟁노래 협곡", [6]="아라시 분지", [7]="알터랙 계곡", [8]="폭풍의 눈",
}

local function NWBLookupName(nwbObj, lookupFn, id)
    if not nwbObj or not nwbObj[lookupFn] then return nil end
    local ok, data = pcall(nwbObj[lookupFn], nwbObj, id)
    if not ok or not data then return nil end
    local eng = data.dungeon or data.name
    return eng and (NWB_DUNGEON_KO[eng] or eng) or nil
end

local function GetNWBObj()
    if not LibStub then return nil end
    local ok, ace = pcall(LibStub, "AceAddon-3.0")
    if not ok or not ace then return nil end
    local ok2, obj = pcall(ace.GetAddon, ace, "NovaWorldBuffs", true)
    return ok2 and obj or nil
end

-- NWB 데이터에서 오늘의 일퀘 지역명 반환
local function GetNWBDailyInfo()
    if not NWBdatabase then return {} end
    local realm   = GetRealmName()
    local faction = UnitFactionGroup("player")
    local d = NWBdatabase.global
           and NWBdatabase.global[realm]
           and NWBdatabase.global[realm][faction]
    if not d then return {} end
    local now = GetServerTime()
    local nwb = GetNWBObj()
    return {
        normalZone = (d.tbcDD and d.tbcDDT and now - d.tbcDDT < 86400)
                     and NWBLookupName(nwb, "getDungeonDailyData", d.tbcDD) or nil,
        heroicZone = (d.tbcHD and d.tbcHDT and now - d.tbcHDT < 86400)
                     and NWBLookupName(nwb, "getHeroicDailyData", d.tbcHD) or nil,
        pvpZone    = (d.tbcPD and d.tbcPDT and now - d.tbcPDT < 86400)
                     and NWB_PVP_DAILY[d.tbcPD] or nil,
    }
end

local BATTLEGROUNDS = {
    ["전쟁노래 협곡"]=true, ["아라시 분지"]=true,
    ["알터랙 계곡"]=true,   ["폭풍의 눈"]=true,
}

local function IsBattleground(zone)
    if not zone or zone == "" then return false end
    return BATTLEGROUNDS[zone] == true
end

-- ============================================================
-- 런타임 변수
-- ============================================================
local db          = nil
local myName      = nil
local initialized = false
local optPanel    = nil
local paused      = false

-- ============================================================
-- 메시지 기본값 & 조회 함수 (전역 — PartyGreeter/BuffGreeter 공유)
-- ============================================================
MyGreeting_DEFAULT_MESSAGES = {
    morning        = "좋은 아침입니다",
    noon           = "식사들 하셨습니까? 맛점 하세요",
    welcome_new    = "{name} 님 어서오세요 환영합니다",
    welcome        = "{name} 님 어서오세요",
    rejoin         = "{name} 님 재접하셨습니다 ~리하요",
    sleep          = "{name} 님 푹쉬세요",
    dungeon              = "{name} 님 [{zone}] 무사히 돌고 득템하세요 :)",
    dungeon_daily_normal = "{name} 님 [{zone}] 오늘 일반 일퀘에요! 무사히 돌고 득템하세요 :)",
    dungeon_daily_heroic = "{name} 님 [{zone}] 오늘 영웅 일퀘에요! 무사히 돌고 득템하세요 :)",
    battleground_daily   = "{name} 님 [{zone}] 주간 전장! 잘 싸우세요 :)",
    levelup_guild  = "{name} 님 레벨업 축하해요 ({level})",
    summon         = "소환 감사합니다",
    resurrect      = "부활 감사합니다",
    party_greet    = "안녕하세요 반갑습니다",
    party_leave    = "담에 봬요 즐와세요",
    sugo           = "수고하셨습니다",
}

function MyGreeting_GetMsg(key, vars)
    local saved = MyGreetingDB and MyGreetingDB.messages and MyGreetingDB.messages[key]
    local msg   = type(saved) == "string" and saved or (MyGreeting_DEFAULT_MESSAGES[key] or "")
    if vars then
        for k, v in pairs(vars) do
            msg = msg:gsub("{" .. k .. "}", tostring(v))
        end
    end
    return msg
end

local prevOnline  = {}   -- [이름] = true/false : 직전 온라인 상태
local prevLevels  = {}   -- [이름] = level
local prevRoster  = {}   -- [이름] = true : 직전 로스터 전체 (온+오프)
local prevZones   = {}   -- [이름] = zone : 직전 위치
local lastOffline = {}   -- [이름] = GetTime()
local dungeonGreeted    = {} -- [이름] = {zone, time} : 이미 인사한 던전 (DB persist)
local bgGreeted         = {} -- [이름] = {zone, time} : 이미 인사한 전장 (DB persist)
local rosterTimer = nil
local guildCmdCooldown = {} -- [커맨드] = GetTime() : 길드 명령 중복 방지

-- ============================================================
-- 길드 채팅 전송 (모든 길드원에게 보임)
-- ============================================================
-- feature: 길드 기능 꺼짐 상태에서도 개별 허용할 기능 키 (ns.GuildAllow)
local function GG_Print(msg, onSent, feature)
    if paused then
        if onSent then onSent() end
        return
    end
    if not msg or msg == "" then
        if onSent then onSent() end
        return
    end
    if ns.IsAFK() then msg = "<자리비움> " .. msg end
    local box = ChatFrame1EditBox
    if box and box:IsVisible() then
        C_Timer.After(2, function()
            SendChatMessage(msg, "GUILD", nil, nil, feature)
            if onSent then onSent() end
        end)
    else
        SendChatMessage(msg, "GUILD", nil, nil, feature)
        if onSent then onSent() end
    end
end

local _queues = {
    LOCAL   = {queue = {}, running = false, delay = DELAY_LOCAL},
    WHISPER = {queue = {}, running = false, delay = DELAY_WHISPER},
    GUILD   = {queue = {}, running = false, delay = DELAY_GUILD},
}

local function _QueueKey(whisperTo)
    if whisperTo == "LOCAL" then return "LOCAL"
    elseif whisperTo then return "WHISPER"
    else return "GUILD"
    end
end

local function _QueueFlush(key)
    local q = _queues[key]
    if #q.queue == 0 then q.running = false; return end
    local e = table.remove(q.queue, 1)
    local function doSend()
        if e.whisperTo == "LOCAL" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. e.msg)
        elseif e.whisperTo then
            SendChatMessage(e.msg, "WHISPER", nil, e.whisperTo)
        elseif not paused then
            SendChatMessage(e.msg, "GUILD", nil, nil, "cmd")  -- 길드챗 큐 = !길드 명령 응답
        end
        if q.delay == 0 then
            _QueueFlush(key)
        else
            C_Timer.After(q.delay, function() _QueueFlush(key) end)
        end
    end
    local box = ChatFrame1EditBox
    if e.whisperTo ~= "LOCAL" and box and box:IsVisible() then
        C_Timer.After(2, doSend)
    else
        doSend()
    end
end

local function GG_Send(msg, whisperTo)
    if not msg or msg == "" then return end
    if whisperTo ~= "LOCAL" and ns.IsAFK() then
        msg = "<자리비움> " .. msg
    end
    local key = _QueueKey(whisperTo)
    local q = _queues[key]
    q.queue[#q.queue+1] = {msg = msg, whisperTo = whisperTo}
    if not q.running then
        q.running = true
        _QueueFlush(key)
    end
end

MyGreeting_QSend = GG_Send

-- 아이템 출처 영문 → 한글
local BIS_SRC_KO = {
    ["Tailoring"]                = "재봉",
    ["Jewelcrafting"]            = "보석세공",
    ["Leatherworking"]           = "가죽세공",
    ["Blacksmithing"]            = "대장",
    ["Engineering"]              = "기공",
    ["Enchanting"]               = "마부",
    ["Alchemy"]                  = "연금",
    ["25 ×Badge of Justice"]     = "정의의 휘장 25개",
    ["Badge of Justice"]         = "정의의 휘장",
    ["35 ×Badge of Justice"]     = "정의의 휘장 35개",
    ["45 ×Badge of Justice"]     = "정의의 휘장 45개",
    ["Honor Points"]             = "명예 점수",
    ["Arena Points"]             = "투기장 점수",
    ["World Drop"]               = "월드 드랍",
}

-- !비스 슬롯 조회용 한글 키워드 → BisSlotData 슬롯 키
local BIS_SLOT_KO = {
    ["머리"]={"머리"}, ["목"]={"목"}, ["목걸이"]={"목"},
    ["어깨"]={"어깨"},
    ["등"]={"등"}, ["망토"]={"등"},
    ["가슴"]={"가슴"},
    ["손목"]={"손목"}, ["팔찌"]={"손목"},
    ["장갑"]={"장갑"}, ["손"]={"장갑"},
    ["허리"]={"허리"}, ["벨트"]={"허리"},
    ["다리"]={"다리"},
    ["발"]={"발"}, ["신발"]={"발"},
    ["반지1"]={"반지1"}, ["반지2"]={"반지2"},
    ["반지"]={"반지1","반지2"},
    ["장신구1"]={"장신구1"}, ["장신구2"]={"장신구2"},
    ["장신구"]={"장신구1","장신구2"},
    ["주장비"]={"주장비"}, ["무기"]={"주장비"},
    ["보조장비"]={"보조장비"}, ["방패"]={"보조장비"},
    ["원거리"]={"원거리"}, ["활"]={"원거리"}, ["총"]={"원거리"},
}

local function HandleBisSlotQuery(cls, specHint, slotKeys, whisperTo)
    if not MyGreeting_BisSlotData then
        GG_Send("[비스] BisData 없음 (BisData.lua 확인)", whisperTo)
        return
    end
    local clsData = MyGreeting_BisSlotData[cls]
    if not clsData then
        GG_Send("[비스] " .. cls .. " 직업 데이터 없음", whisperTo)
        return
    end

    local specs = {}
    if specHint and clsData[specHint] then
        specs = {specHint}
    else
        for sp in pairs(clsData) do specs[#specs+1] = sp end
        table.sort(specs)
    end

    -- 전 스펙 아이템을 페이즈별로 묶어서 수집 (중복 ID 제거, 아이템명은 발송 시점에 조회)
    local byPhase = {}
    local seenId  = {}
    for _, spec in ipairs(specs) do
        local specData = clsData[spec]
        for _, slotKey in ipairs(slotKeys) do
            local entries = specData and specData[slotKey]
            if entries then
                for _, e in ipairs(entries) do
                    if e.id and not seenId[e.id] then
                        seenId[e.id] = true
                        local n = tonumber(e.phase and e.phase:match("P(%d+)")) or 0
                        if not byPhase[n] then
                            byPhase[n] = {label = e.phase or ("P"..n), entries = {}}
                        end
                        byPhase[n].entries[#byPhase[n].entries+1] = e
                        GetItemInfo(e.id)  -- 캐시 요청
                    end
                end
            end
        end
    end

    local phases = {}
    for n in pairs(byPhase) do phases[#phases+1] = n end
    table.sort(phases)

    local slotLabel = slotKeys[1] or ""

    if #phases == 0 then
        GG_Send("[비스] 해당 슬롯 데이터 없음", whisperTo)
        return
    end

    GG_Send(string.format("[비스] %s %s", cls, slotLabel), whisperTo)
    for _, phaseIdx in ipairs(phases) do
        local p = byPhase[phaseIdx]
        local parts = {}
        for _, e in ipairs(p.entries) do
            local _, link = GetItemInfo(e.id)
            local display = link or ("[" .. e.id .. "]")
            local zone = e.zone or ""
            local src = BIS_SRC_KO[zone] or zone
            if src == "" then src = "월드 드랍" end
            if e.boss and e.boss ~= "" then src = src .. "/" .. e.boss end
            parts[#parts+1] = display .. "(" .. src .. ")"
        end
        GG_Send(p.label .. ": " .. table.concat(parts, ", "), whisperTo)
    end
end

-- ============================================================
-- 언급 경보 프레임
-- ============================================================
local mentionAlertTimer = nil

local mentionFrame = CreateFrame("Frame", "MyGreetingMentionFrame", UIParent)
mentionFrame:SetSize(500, 70)
mentionFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
mentionFrame:SetFrameStrata("HIGH")
mentionFrame:Hide()

local mentionLabel = mentionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mentionLabel:SetPoint("TOP", mentionFrame, "TOP", 0, -8)
mentionLabel:SetTextColor(1, 1, 0)

local mentionBody = mentionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mentionBody:SetPoint("TOP", mentionLabel, "BOTTOM", 0, -4)
mentionBody:SetTextColor(1, 1, 1)
mentionBody:SetWidth(480)

local function ShowMentionAlert(sender, msg)
    mentionLabel:SetText(myName or "")
    mentionBody:SetText(sender .. ": " .. msg)
    mentionFrame:Show()
    PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
    if mentionAlertTimer then mentionAlertTimer:Cancel() end
    mentionAlertTimer = C_Timer.NewTimer(6, function()
        mentionFrame:Hide()
    end)
end

-- ============================================================
-- Forever(한국 서버): 길드 명령 응답은 한글. *_EN 표는 영어 별칭 참고용으로만 남김
-- ============================================================
local CLASS_EN = {
    ["전사"]="Warrior", ["성기사"]="Paladin", ["사냥꾼"]="Hunter", ["도적"]="Rogue",
    ["사제"]="Priest", ["주술사"]="Shaman", ["마법사"]="Mage", ["흑마법사"]="Warlock",
    ["드루이드"]="Druid", ["죽음의 기사"]="Death Knight",
}
local RACE_EN = {
    ["오크"]="Orc", ["포세이큰"]="Undead", ["언데드"]="Undead", ["타우렌"]="Tauren", ["트롤"]="Troll",
    ["블엘"]="Blood Elf", ["혈요정"]="Blood Elf", ["블러드 엘프"]="Blood Elf",
    ["인간"]="Human", ["드워프"]="Dwarf", ["나이트 엘프"]="Night Elf", ["노움"]="Gnome", ["드레나이"]="Draenei",
}
-- GetPlayerInfoByGUID 영문 종족 토큰 → 표시명
local RACE_TOKEN_EN = { Scourge="Undead", NightElf="Night Elf", BloodElf="Blood Elf" }
local PROF_EN = {
    ["대장"]="Blacksmithing", ["재봉"]="Tailoring", ["연금"]="Alchemy", ["기공"]="Engineering",
    ["가세"]="Leatherworking", ["보세"]="Jewelcrafting", ["채광"]="Mining", ["채집"]="Herbalism",
    ["마부"]="Enchanting", ["무두"]="Skinning", ["요리"]="Cooking", ["낚시"]="Fishing",
}
local function EN(tbl, s) return s end  -- 한글 그대로 출력

-- ============================================================
-- 직업/종족 분포 수집 후 콜백 호출
-- ============================================================
local function CollectClassDistribution(callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local counts = {}
        local online = 0
        local total = GetNumGuildMembers()
        for i = 1, total do
            local _, _, _, _, className, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline then
                online = online + 1
                if className and className ~= "" then
                    counts[className] = (counts[className] or 0) + 1
                end
            end
        end
        local parts = {}
        for cls, n in pairs(counts) do parts[#parts + 1] = EN(CLASS_EN, cls) .. " " .. n end
        table.sort(parts)
        callback(parts, online)
    end)
end

local function CollectRaceDistribution(callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local counts = {}
        local online = 0
        local total = GetNumGuildMembers()
        for i = 1, total do
            local _, _, _, _, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
            if isOnline then
                online = online + 1
                if guid and guid ~= "" then
                    local _, _, localizedRace, raceToken = GetPlayerInfoByGUID(guid)
                    local race = (localizedRace and localizedRace ~= "") and localizedRace or raceToken
                    if race and race ~= "" then
                        counts[race] = (counts[race] or 0) + 1
                    end
                end
            end
        end
        local parts = {}
        for race, n in pairs(counts) do parts[#parts + 1] = race .. " " .. n end
        table.sort(parts)
        callback(parts, online)
    end)
end

local PROF_KEYWORDS = {
    "대장", "재봉", "연금", "기공", "가세", "보세", "채광", "채집", "마부", "무두", "요리", "낚시"
}
-- 풀네임 → 단축키워드 (쪽지에 풀네임으로 써도 단축키워드로 집계)
local PROF_ALIASES = {
    ["대장기술"] = "대장",
    ["보석세공"] = "보세",
    ["기계공학"] = "기공",
    ["가죽세공"] = "가세",
    ["마법부여"] = "마부",
    ["약초"]     = "채집",
    ["약초채집"] = "채집",
}
local function ProfMatches(combined, keyword)
    if combined:find(keyword, 1, true) then return true end
    for alias, canonical in pairs(PROF_ALIASES) do
        if canonical == keyword and combined:find(alias, 1, true) then return true end
    end
    return false
end

local function CollectProfessionDistribution(callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local counts = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local _, _, _, _, _, _, note, officerNote = GetGuildRosterInfo(i)
            local combined = (note or "") .. " " .. (officerNote or "")
            for _, kw in ipairs(PROF_KEYWORDS) do
                if ProfMatches(combined, kw) then
                    counts[kw] = (counts[kw] or 0) + 1
                end
            end
        end
        local parts = {}
        for _, kw in ipairs(PROF_KEYWORDS) do
            if counts[kw] then
                parts[#parts + 1] = EN(PROF_EN, kw) .. " " .. counts[kw]
            end
        end
        callback(parts, total)
    end)
end

local GUILD_CMD_COOLDOWN_SEC = 10

local GEAR_SLOT_CMDS = {
    ["머리"]       = {1},
    ["목"]         = {2},
    ["어깨"]       = {3},
    ["가슴"]       = {5},
    ["벨트"]       = {6},  ["허리"]     = {6},
    ["다리"]       = {7},
    ["발"]         = {8},  ["신발"]     = {8},
    ["손목"]       = {9},
    ["손"]         = {10}, ["장갑"]     = {10},
    ["손가락"]     = {11, 12},
    ["장신구"]     = {13, 14},
    ["등"]         = {15}, ["망토"]     = {15}, ["망또"]     = {15},
    ["주장비"]     = {16}, ["주무기"]   = {16},
    ["보조장비"]   = {17}, ["보조무기"] = {17},
    ["원거리"]     = {18},
}

-- ============================================================
-- 전문기술별 멤버 목록 수집
-- ============================================================
local PROF_CMD_KEYWORDS = {}
for _, kw in ipairs({ "대장", "재봉", "연금", "기공", "가세", "보세", "채광", "채집", "마부", "무두", "요리", "낚시" }) do
    PROF_CMD_KEYWORDS["!" .. kw] = kw
end
for alias, canonical in pairs(PROF_ALIASES) do
    PROF_CMD_KEYWORDS["!" .. alias] = canonical
end
-- English
for en, kw in pairs({ bs="대장", blacksmithing="대장", tailoring="재봉", alchemy="연금", engineering="기공",
                      lw="가세", leatherworking="가세", jc="보세", jewelcrafting="보세", mining="채광",
                      herbalism="채집", herb="채집", enchanting="마부", ench="마부", skinning="무두",
                      cooking="요리", fishing="낚시" }) do
    PROF_CMD_KEYWORDS["!" .. en] = kw
end

local function CollectProfessionMembers(keyword, callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local members = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, _, _, level, _, _, note, officerNote, isOnline = GetGuildRosterInfo(i)
            if isOnline and name then
                local combined = (note or "") .. " " .. (officerNote or "")
                if ProfMatches(combined, keyword) then
                    name = name:match("^([^%-]+)") or name
                    members[#members + 1] = { name = name, level = level }
                end
            end
        end
        table.sort(members, function(a, b) return a.level > b.level end)
        local parts = {}
        for _, m in ipairs(members) do
            parts[#parts + 1] = m.name .. "(" .. m.level .. ")"
        end
        callback(parts)
    end)
end

local function HandleGuildProfList(keyword, whisperTo)
    if not whisperTo then
        local now = GetTime()
        local coolKey = "prof_" .. keyword
        if guildCmdCooldown[coolKey] and (now - guildCmdCooldown[coolKey]) < GUILD_CMD_COOLDOWN_SEC then return end
        guildCmdCooldown[coolKey] = now
    end

    CollectProfessionMembers(keyword, function(members)
        if #members == 0 then
            GG_Send(EN(PROF_EN, keyword) .. ": 접속자 없음", whisperTo)
        else
            GG_Send(EN(PROF_EN, keyword) .. " (" .. #members .. "): " .. table.concat(members, "  "), whisperTo)
        end
    end)
end

-- ============================================================
-- 직업별 멤버 목록 수집
-- ============================================================
local CLASS_KEYWORDS = {
    ["!전사"]       = "전사",
    ["!성기사"]     = "성기사",
    ["!사냥꾼"]     = "사냥꾼",
    ["!도적"]       = "도적",
    ["!사제"]       = "사제",
    ["!주술사"]     = "주술사",
    ["!마법사"]     = "마법사",
    ["!흑마법사"]   = "흑마법사",
    ["!드루이드"]   = "드루이드",
    ["!죽기"]       = "죽음의 기사",
    ["!죽음의기사"] = "죽음의 기사",
    -- 한글 별칭
    ["!기사"]="성기사", ["!성기"]="성기사", ["!냥꾼"]="사냥꾼", ["!냥"]="사냥꾼",
    ["!술사"]="주술사", ["!법사"]="마법사", ["!흑마"]="흑마법사", ["!드루"]="드루이드",
    -- English
    ["!warrior"]="전사", ["!paladin"]="성기사", ["!hunter"]="사냥꾼", ["!rogue"]="도적",
    ["!priest"]="사제", ["!shaman"]="주술사", ["!mage"]="마법사", ["!warlock"]="흑마법사",
    ["!druid"]="드루이드", ["!dk"]="죽음의 기사",
}

local function CollectClassMembers(className, callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local members = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, _, _, level, cls, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline and cls == className then
                name = name:match("^([^%-]+)") or name
                members[#members + 1] = { name = name, level = level }
            end
        end
        table.sort(members, function(a, b) return a.level > b.level end)
        local parts = {}
        for _, m in ipairs(members) do
            parts[#parts + 1] = m.name .. "(" .. m.level .. ")"
        end
        callback(parts)
    end)
end

local RACE_KEYWORDS = {
    ["!오크"]       = "오크",
    ["!언데드"]     = "포세이큰",
    ["!포세이큰"]   = "포세이큰",
    ["!타우렌"]     = "타우렌",
    ["!트롤"]       = "트롤",
    ["!블엘"]       = "블엘",
    ["!인간"]       = "인간",
    ["!드워프"]     = "드워프",
    ["!나엘"]       = "나이트 엘프",
    ["!나이트엘프"] = "나이트 엘프",
    ["!노움"]       = "노움",
    ["!드레나이"]   = "드레나이",
    -- 한글 별칭
    ["!휴먼"]="인간", ["!혈요정"]="블엘", ["!블러드엘프"]="블엘", ["!드레"]="드레나이",
    ["!나이트 엘프"]="나이트 엘프", ["!언데"]="포세이큰",
    -- English
    ["!orc"]="오크", ["!undead"]="포세이큰", ["!tauren"]="타우렌", ["!troll"]="트롤",
    ["!bloodelf"]="블엘", ["!be"]="블엘", ["!human"]="인간", ["!dwarf"]="드워프",
    ["!nightelf"]="나이트 엘프", ["!ne"]="나이트 엘프", ["!gnome"]="노움", ["!draenei"]="드레나이",
}

local RACE_API_NAMES = { ["블엘"] = "혈요정" }

local function CollectRaceMembers(raceName, callback)
    local apiRace = RACE_API_NAMES[raceName] or raceName
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local members = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, _, _, level, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
            if isOnline and guid and guid ~= "" then
                local _, _, localizedRace = GetPlayerInfoByGUID(guid)
                if localizedRace == apiRace then
                    name = name:match("^([^%-]+)") or name
                    members[#members + 1] = { name = name, level = level }
                end
            end
        end
        table.sort(members, function(a, b) return a.level > b.level end)
        local parts = {}
        for _, m in ipairs(members) do
            parts[#parts + 1] = m.name .. "(" .. m.level .. ")"
        end
        callback(parts)
    end)
end

local function HandleGuildRaceList(raceName, whisperTo)
    if not whisperTo then
        local now = GetTime()
        local coolKey = "race_" .. raceName
        if guildCmdCooldown[coolKey] and (now - guildCmdCooldown[coolKey]) < GUILD_CMD_COOLDOWN_SEC then return end
        guildCmdCooldown[coolKey] = now
    end

    CollectRaceMembers(raceName, function(members)
        if #members == 0 then
            GG_Send(EN(RACE_EN, raceName) .. ": 접속자 없음", whisperTo)
        else
            GG_Send(EN(RACE_EN, raceName) .. " (" .. #members .. "): " .. table.concat(members, "  "), whisperTo)
        end
    end)
end

local function HandleGuildCharInfo(targetName, whisperTo)
    targetName = strtrim(targetName)
    if targetName == "" then
        local me = UnitName("player")
        targetName = me and (me:match("^([^%-]+)") or me) or ""
        if targetName == "" then return end
    end

    if not whisperTo then
        local now = GetTime()
        local coolKey = "info_" .. targetName
        if guildCmdCooldown[coolKey] and (now - guildCmdCooldown[coolKey]) < GUILD_CMD_COOLDOWN_SEC then return end
        guildCmdCooldown[coolKey] = now
    end

    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, rankName, _, level, className, zone, publicNote, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
            if name then
                local shortName = name:match("^([^%-]+)") or name
                if shortName:lower() == targetName:lower() then
                    local race = ""
                    if guid and guid ~= "" then
                        local _, _, localizedRace, raceToken = GetPlayerInfoByGUID(guid)
                        if localizedRace and localizedRace ~= "" then race = localizedRace
                        elseif raceToken and raceToken ~= "" then race = raceToken end
                    end
                    local onlineStr  = isOnline and "● 접속중" or "○ 오프라인"
                    local zoneStr    = (zone and zone ~= "") and zone or "-"
                    local noteStr    = (publicNote and publicNote ~= "") and publicNote or "-"
                    local gsStr = ""
                    local gearInfo = MyGreetingDB and MyGreetingDB.gearData and MyGreetingDB.gearData[shortName]
                    if gearInfo then
                        local gs = gearInfo.gs and tostring(gearInfo.gs) or "?"
                        local scoreDisp = gearInfo.ilvl and ("ilvl:" .. tostring(gearInfo.ilvl) .. "(gs:" .. gs .. ")") or tostring(gearInfo.score or "?")
                        gsStr = "  /  " .. scoreDisp
                    end
                    GG_Send(shortName .. " [" .. rankName .. "]  lv" .. level .. " " .. race .. " " .. EN(CLASS_EN, className) .. "  " .. onlineStr .. gsStr, whisperTo)
                    GG_Send("지역: " .. zoneStr .. "  /  쪽지: " .. noteStr, whisperTo)
                    return
                end
            end
        end
        GG_Send("[" .. targetName .. "] 길드에 없는 이름입니다", whisperTo)
    end)
end

local function HandleGuildClassList(className, whisperTo)
    if not whisperTo then
        local now = GetTime()
        local coolKey = "class_" .. className
        if guildCmdCooldown[coolKey] and (now - guildCmdCooldown[coolKey]) < GUILD_CMD_COOLDOWN_SEC then return end
        guildCmdCooldown[coolKey] = now
    end

    CollectClassMembers(className, function(members)
        if #members == 0 then
            GG_Send(EN(CLASS_EN, className) .. ": 접속자 없음", whisperTo)
        else
            GG_Send(EN(CLASS_EN, className) .. " (" .. #members .. "): " .. table.concat(members, "  "), whisperTo)
        end
    end)
end

local function CollectDungeonStatus(callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local dungeons = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, _, _, _, _, zone, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline and name and zone and IsDungeon(zone) then
                name = name:match("^([^%-]+)") or name
                if not dungeons[zone] then dungeons[zone] = {} end
                table.insert(dungeons[zone], name)
            end
        end
        callback(dungeons)
    end)
end

local DAILY_LABEL = {
    dailyHeroic = "영웅 일퀘",
    dailyNormal = "일반 일퀘",
    weeklyBG    = "주간 전장",
}

local function GetDailyInfo(key)
    if not db or not db.dailyInfo then return nil end
    local entry = db.dailyInfo[key]
    if not entry then return nil end
    if key == "weeklyBG" then
        -- 주간 전장은 월요일 기준 주간 체크
        local t = date("*t")
        local weekday = t.wday  -- 1=일, 2=월 ... 7=토
        local daysSinceMon = (weekday - 2) % 7
        local monDate = date("%Y-%m-%d", time() - daysSinceMon * 86400)
        if (entry.weekStart or "") ~= monDate then return nil end
    else
        if entry.date ~= date("%Y-%m-%d") then return nil end
    end
    return entry
end

-- Nova World Buffs SavedVariables에서 오늘 일일 던전/전장 이름을 읽어옴
local function GetNWBDailyName(key)
    if not NWBdatabase then return nil end
    local realm   = GetRealmName()
    local faction = UnitFactionGroup("player")
    local d = NWBdatabase.global
           and NWBdatabase.global[realm]
           and NWBdatabase.global[realm][faction]
    if not d then return nil end
    local nwb = GetNWBObj()
    local today = date("%Y-%m-%d")
    if key == "dailyNormal" then
        if not d.tbcDD or not d.tbcDDT then return nil end
        if date("%Y-%m-%d", d.tbcDDT) ~= today then return nil end
        return NWBLookupName(nwb, "getDungeonDailyData", d.tbcDD)
    elseif key == "dailyHeroic" then
        if not d.tbcHD or not d.tbcHDT then return nil end
        if date("%Y-%m-%d", d.tbcHDT) ~= today then return nil end
        return NWBLookupName(nwb, "getHeroicDailyData", d.tbcHD)
    elseif key == "weeklyBG" then
        if not d.tbcPD or not d.tbcPDT then return nil end
        local t = date("*t")
        local daysSinceMon = (t.wday - 2) % 7
        local monDate = date("%Y-%m-%d", time() - daysSinceMon * 86400)
        if date("%Y-%m-%d", d.tbcPDT) < monDate then return nil end
        return NWB_PVP_DAILY[d.tbcPD]
    end
    return nil
end

local function HandleDailyQuery(key, whisperTo)
    local label = DAILY_LABEL[key] or key
    local nwbName = GetNWBDailyName(key)
    if nwbName then
        GG_Send(label .. ": " .. nwbName .. "  [NWB]", whisperTo)
        return
    end
    local entry = GetDailyInfo(key)
    if entry then
        GG_Send(label .. ": " .. entry.value .. "  (등록: " .. entry.setter .. ")", whisperTo)
    else
        GG_Send(label .. ": 미확인", whisperTo)
    end
end

local function HandleDailyAll(whisperTo)
    local function line(key)
        local label = DAILY_LABEL[key] or key
        local nwbName = GetNWBDailyName(key)
        if nwbName then
            return label .. ": " .. nwbName .. "  [NWB]"
        end
        local entry = GetDailyInfo(key)
        if entry then
            return label .. ": " .. entry.value .. "  (등록: " .. entry.setter .. ")"
        else
            return label .. ": 미확인"
        end
    end
    GG_Send(line("dailyNormal"), whisperTo)
    GG_Send(line("dailyHeroic"), whisperTo)
    GG_Send(line("weeklyBG"), whisperTo)
end

local function HandleGuildCommand(cmd, whisperTo)
    if not whisperTo then
        local now = GetTime()
        if guildCmdCooldown[cmd] and (now - guildCmdCooldown[cmd]) < GUILD_CMD_COOLDOWN_SEC then return end
        guildCmdCooldown[cmd] = now
    end

    if cmd == "help" then
        GG_Send("-- 길드 명령어 (길드챗에 입력, 답은 귓말로) --", whisperTo)
        GG_Send("!현황  !레벨  !직업  !종족  !지역  !인던  !전문기술  !등급  !정보 <이름>", whisperTo)
        GG_Send("!일일  !일던  !영던  !전장", whisperTo)
        GG_Send("!길드<명령> 으로 치면 길드챗으로 답함 (예: !길드직업)", whisperTo)
        GG_Send("더보기: !도움 직업 / !도움 종족 / !도움 전문기술", whisperTo)
    elseif cmd == "help_class" then
        GG_Send("직업별 접속자: !전사 !성기사 !사냥꾼 !도적 !사제 !주술사 !마법사 !흑마법사 !드루이드", whisperTo)
    elseif cmd == "help_race" then
        GG_Send("종족별 접속자: !오크 !언데드 !타우렌 !트롤 !블엘 !인간 !드워프 !나엘 !노움 !드레나이", whisperTo)
    elseif cmd == "help_prof" then
        GG_Send("전문기술별 접속자 (쪽지 기준): !대장 !재봉 !연금 !기공 !가세 !보세 !채광 !채집 !마부 !무두 !요리 !낚시", whisperTo)
    elseif cmd == "help_gear" then
        GG_Send("장비 명령: !장비 [이름]", whisperTo)
    elseif cmd == "help_daily" then
        GG_Send("확인: !일일  !일던  !영던  !전장", whisperTo)
    elseif cmd == "status" then
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local total = GetNumGuildMembers()
            local online = 0
            for i = 1, total do
                local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline then online = online + 1 end
            end
            GG_Send("접속: " .. online .. "명 / 전체: " .. total .. "명", whisperTo)
        end)
    elseif cmd == "levels" then
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local total = GetNumGuildMembers()
            -- Forever 만렙 60: 60 / 10레벨 단위 구간
            local ranges = {
                { 60, 60, "60" }, { 50, 59, "50-59" }, { 40, 49, "40-49" },
                { 30, 39, "30-39" }, { 20, 29, "20-29" }, { 10, 19, "10-19" }, { 1, 9, "1-9" },
            }
            local counts = {}
            local online = 0
            for i = 1, total do
                local _, _, _, level, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline then
                    online = online + 1
                    for r = 1, #ranges do
                        if level >= ranges[r][1] then
                            counts[r] = (counts[r] or 0) + 1
                            break
                        end
                    end
                end
            end
            local parts = {}
            for r = 1, #ranges do
                parts[#parts + 1] = ranges[r][3] .. ": " .. (counts[r] or 0)
            end
            if #parts == 0 then return end
            GG_Send("레벨 분포 (접속 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "classes" then
        CollectClassDistribution(function(parts, online)
            if #parts == 0 then return end
            GG_Send("직업 분포 (접속 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "races" then
        CollectRaceDistribution(function(parts, online)
            if #parts == 0 then return end
            GG_Send("종족 분포 (접속 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "dungeon" then
        CollectDungeonStatus(function(dungeons)
            local parts = {}
            for zone, members in pairs(dungeons) do
                parts[#parts + 1] = zone .. " (" .. #members .. "): " .. table.concat(members, ", ")
            end
            table.sort(parts)
            if #parts == 0 then
                GG_Send("인던에 있는 길드원 없음", whisperTo)
            else
                GG_Send("인던 - " .. table.concat(parts, " / "), whisperTo)
            end
        end)
    elseif cmd == "profs" then
        CollectProfessionDistribution(function(parts, total)
            if #parts == 0 then
                GG_Send("쪽지에 전문기술 정보 없음", whisperTo)
            else
                GG_Send("전문기술 (" .. total .. "명, 쪽지 기준): " .. table.concat(parts, " / "), whisperTo)
            end
        end)
    elseif cmd == "zones" then
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local zones = {}
            local total = GetNumGuildMembers()
            for i = 1, total do
                local name, _, _, _, _, zone, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline and zone and zone ~= "" then
                    name = name:match("^([^%-]+)") or name
                    if not zones[zone] then zones[zone] = {} end
                    table.insert(zones[zone], name)
                end
            end
            local zoneNames = {}
            for zone in pairs(zones) do zoneNames[#zoneNames + 1] = zone end
            table.sort(zoneNames)
            if #zoneNames == 0 then
                GG_Send("접속자 없음", whisperTo)
            else
                -- 채팅 전송 횟수 제한(beta) 때문에 지역별 한 줄씩이 아니라 255바이트 안에서 묶어 보냄
                local line = ""
                for _, zone in ipairs(zoneNames) do
                    local members = zones[zone]
                    table.sort(members)
                    local part = zone .. " (" .. #members .. "): " .. table.concat(members, ", ")
                    if line ~= "" and #line + 3 + #part > 250 then
                        GG_Send(line, whisperTo)
                        line = part
                    else
                        line = (line == "") and part or (line .. " / " .. part)
                    end
                end
                if line ~= "" then GG_Send(line, whisperTo) end
            end
        end)
    elseif cmd == "ranks" then
        local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        if num == 0 then
            GG_Send("길드 등급을 읽을 수 없음", whisperTo)
        else
            local parts = {}
            for i = 1, num do
                local rankName = GuildControlGetRankName(i)
                if rankName and rankName ~= "" then
                    parts[#parts + 1] = i .. ". " .. rankName
                end
            end
            GG_Send("길드 등급 (" .. num .. "): " .. table.concat(parts, " / "), whisperTo)
        end
    elseif cmd:sub(1, 5) == "rank:" then
        local targetRank = cmd:sub(6)
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local members = {}
            local total = GetNumGuildMembers()
            for i = 1, total do
                local name, rankName, _, level, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline and rankName == targetRank then
                    name = name:match("^([^%-]+)") or name
                    members[#members + 1] = { name = name, level = level }
                end
            end
            table.sort(members, function(a, b) return a.level > b.level end)
            local parts = {}
            for _, m in ipairs(members) do
                parts[#parts + 1] = m.name .. "(" .. m.level .. ")"
            end
            if #parts == 0 then
                GG_Send("[" .. targetRank .. "] 접속자 없음", whisperTo)
            else
                GG_Send("[" .. targetRank .. "] (" .. #parts .. "): " .. table.concat(parts, "  "), whisperTo)
            end
        end)
    elseif cmd == "추적" or cmd == "추적끄기" then
        local canceled = false
        if C_Minimap and C_Minimap.GetNumTrackingTypes then
            for i = 1, C_Minimap.GetNumTrackingTypes() do
                local info = C_Minimap.GetTrackingInfo(i)
                if info and info.active and info.name and info.type == "spell" then
                    C_Minimap.SetTracking(i, false)
                    GG_Print(info.name .. " 해제 시도")
                    canceled = true
                end
            end
        elseif GetNumTrackingTypes then
            for i = 1, GetNumTrackingTypes() do
                local _, name, active = GetTrackingInfo(i)
                if active and name then
                    CancelUnitBuff("player", name)
                    GG_Print(name .. " 해제 시도")
                    canceled = true
                end
            end
        end
        if not canceled then
            GG_Print("활성 추적 없음")
        end
    end
end

-- ============================================================
-- 공통 명령어 디스패처
-- sub: 명령어, whisperTo: "LOCAL"/이름/nil(길드챗), senderName: 기본 대상 이름
-- 반환: 처리됐으면 true, 아니면 false
-- ============================================================
local DAILY_GET = {
    ["normal"] = "dailyNormal", ["heroic"] = "dailyHeroic", ["bg"] = "weeklyBG",
    ["일던"] = "dailyNormal",
    ["영던"] = "dailyHeroic",
    ["전장"] = "weeklyBG",
}

local CMD_MAP = {
    -- English (beta 영어 테스터 서버)
    ["status"]="status", ["online"]="status", ["levels"]="levels", ["classes"]="classes",
    ["races"]="races", ["dungeons"]="dungeon", ["zones"]="zones", ["profs"]="profs",
    ["ranks"]="ranks", ["help"]="help", ["commands"]="help",
    -- 단수형도 허용 (!guildrace 등)
    ["level"]="levels", ["class"]="classes", ["race"]="races", ["zone"]="zones",
    ["dungeon"]="dungeon", ["prof"]="profs", ["professions"]="profs", ["rank"]="ranks",
    ["help class"]="help_class", ["help race"]="help_race", ["help prof"]="help_prof",
    ["help gear"]="help_gear", ["help daily"]="help_daily",
    ["현황"]="status", ["레벨"]="levels", ["직업"]="classes",
    ["종족"]="races",  ["인던"]="dungeon", ["지역"]="zones",
    ["전문기술"]="profs", ["등급"]="ranks",
    ["도움"]="help", ["도움 직업"]="help_class",
    ["도움 종족"]="help_race", ["도움 전문기술"]="help_prof",
    ["도움 장비"]="help_gear", ["도움 일정"]="help_daily",
}

-- 영어 단축 접두어 !g 판별용: 실행 없이 알려진 영어/한글 기본 명령인지 확인
local function IsKnownCommand(sub)
    local key = strtrim(sub):lower()
    return CMD_MAP[key] or DAILY_GET[key] or key == "daily" or key == "일일"
        or CLASS_KEYWORDS["!" .. key] or RACE_KEYWORDS["!" .. key] or PROF_CMD_KEYWORDS["!" .. key]
        or key:match("^info%s+.+$") ~= nil
end

local function DispatchCommand(sub, whisperTo, senderName)
    local key = strtrim(sub):lower()  -- 영어 명령어 대소문자 무시 (한글은 영향 없음)
    if CMD_MAP[key] then
        HandleGuildCommand(CMD_MAP[key], whisperTo)
    elseif key == "일일" or key == "daily" then
        HandleDailyAll(whisperTo)
    elseif DAILY_GET[key] then
        HandleDailyQuery(DAILY_GET[key], whisperTo)
    elseif CLASS_KEYWORDS["!" .. key] then
        HandleGuildClassList(CLASS_KEYWORDS["!" .. key], whisperTo)
    elseif RACE_KEYWORDS["!" .. key] then
        HandleGuildRaceList(RACE_KEYWORDS["!" .. key], whisperTo)
    elseif PROF_CMD_KEYWORDS["!" .. key] then
        HandleGuildProfList(PROF_CMD_KEYWORDS["!" .. key], whisperTo)
    elseif sub == "장비" then
        if MyGreeting_GetGearScore then MyGreeting_GetGearScore(senderName, whisperTo) end
    elseif sub == "장비현황" or sub == "수집" then
        if MyGreeting_GearStatus then MyGreeting_GearStatus(whisperTo) end
    elseif sub == "장비길드" then
        if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(whisperTo, true) end
    elseif sub == "장비전체" then
        if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(whisperTo, false) end
    else
        local guildFrom = sub:match("^장비길드 (%d+)$")
        local allFrom   = sub:match("^장비전체 (%d+)$")
        local gearT     = sub:match("^장비 (.+)$")
        local classGear = sub:match("^장비(.+)$")
        local classFile = classGear and CLASS_KEYWORDS["!" .. classGear]
        local bisQ      = sub:match("^비스%s+(.+)$")
        if guildFrom then
            if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(whisperTo, true, tonumber(guildFrom)) end
        elseif allFrom then
            if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(whisperTo, false, tonumber(allFrom)) end
        elseif classFile then
            if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(whisperTo, false, nil, classFile, classGear) end
        elseif gearT then
            if MyGreeting_GetGearScore then MyGreeting_GetGearScore(strtrim(gearT), whisperTo) end
        elseif bisQ then
            local cls, specHint, slotInput
            cls, specHint, slotInput = bisQ:match("^(%S+)/(%S+)%s+(%S+)$")
            if not slotInput then cls, slotInput = bisQ:match("^(%S+)%s+(%S+)$") end
            local slotKeys = slotInput and BIS_SLOT_KO[slotInput]
            if cls and slotKeys then HandleBisSlotQuery(cls, specHint, slotKeys, whisperTo) end
        else
            local slotCmd, slotTarget = sub:match("^(%S+)%s+(.+)$")
            if not slotCmd then slotCmd = sub end
            local slotIds = GEAR_SLOT_CMDS[slotCmd]
            if slotIds then
                local targetName = (slotTarget and strtrim(slotTarget) ~= "") and strtrim(slotTarget) or senderName
                if MyGreeting_GetGearSlot then MyGreeting_GetGearSlot(targetName, slotIds, whisperTo) end
            else
                local infoT = sub:match("^정보%s+(.+)$") or sub:match("^[Ii][Nn][Ff][Oo]%s+(.+)$")
                local rankT = sub:match("^등급%s+(.+)$")
                if infoT then
                    HandleGuildCharInfo(infoT, whisperTo)
                elseif rankT then
                    HandleGuildCommand("rank:" .. strtrim(rankT), whisperTo)
                else
                    return false
                end
            end
        end
    end
    return true
end

-- ============================================================
-- 로스터 스냅샷 수집
-- 반환: online[이름], levels[이름], allNames[이름]
-- allNames = 온라인 + 오프라인 전체 멤버
-- ============================================================
local function CollectRosterSnapshot()
    local online   = {}
    local levels   = {}
    local allNames = {}
    local zones    = {}
    local total    = GetNumGuildMembers()

    for i = 1, total do
        local name, _, _, level, _, zone, _, _, isOnline = GetGuildRosterInfo(i)
        if name then
            name            = name:match("^([^%-]+)") or name
            online[name]    = isOnline and true or false
            levels[name]    = level
            allNames[name]  = true
            zones[name]     = zone or ""
        end
    end

    return online, levels, allNames, zones
end

-- ============================================================
-- 인사 예약 (1초 딜레이)
-- isNew = true  → 길드에 처음 등장한 신규 가입자
-- isNew = false → 기존 멤버 재접속
-- ============================================================
local function ScheduleGreeting(name, isNew)
    C_Timer.After(GREET_DELAY, function()
        -- 공대 중이면 길드 인사 생략
        if IsInRaid() then
            if db then db.knownMembers[name] = true end
            return
        end

        -- 현재 파티원이면 PartyGreeter가 인사하므로 길드 인사 생략
        for i = 1, 4 do
            local pu = "party" .. i
            if UnitExists(pu) and (UnitName(pu) == name or ns.UnitWhisperName(pu) == name) then
                if db then db.knownMembers[name] = true end
                return
            end
        end

        local key  = isNew and "welcome_new" or "welcome"
        local msg  = MyGreeting_GetMsg(key, {name=name})
        local note = MyGreeting_GetNote and MyGreeting_GetNote(name)
        if note and note ~= "" then
            msg = msg .. " <" .. note .. ">"
        end
        GG_Print(msg, nil, key)
        -- 인사 후 knownMembers에 등록
        if db then
            db.knownMembers[name] = true
        end
    end)
end

-- ============================================================
-- 레벨업 축하 예약 (1초 딜레이)
-- ============================================================
local function ScheduleLevelUp(name, newLevel)
    C_Timer.After(GREET_DELAY, function()
        GG_Print(MyGreeting_GetMsg("levelup_guild", {name=name, level=newLevel}))
    end)
end

-- ============================================================
-- 로스터 비교 및 처리
-- ============================================================
local function ProcessRosterUpdate()
    local currentOnline, currentLevels, currentRoster, currentZones = CollectRosterSnapshot()

    if not initialized then
        prevOnline  = currentOnline
        prevLevels  = currentLevels
        prevRoster  = currentRoster
        prevZones   = currentZones
        if db then
            for name in pairs(currentRoster) do
                db.knownMembers[name] = true
            end
        end
        return
    end

    -- ── 신규 길드 가입자 감지 ─────────────────────────────
    local newlyJoined = {}
    for name in pairs(currentRoster) do
        if not ns.IsMe(name) and not prevRoster[name] then
            if currentOnline[name] then
                ScheduleGreeting(name, true)
                newlyJoined[name] = true  -- 접속 감지 중복 방지
            else
                if db then db.knownMembers[name] = nil end
            end
        end
    end

    -- ── 접속 / 오프라인 감지 ─────────────────────────────
    for name, isOnline in pairs(currentOnline) do
        if not ns.IsMe(name) and not newlyJoined[name] then
            local wasOnline = prevOnline[name]

            if isOnline and not wasOnline and db and db.loginGreetOff then
                -- 접속 인사 꺼짐 (/mg 접속인사): 인사 없이 기존 멤버로만 등록
                db.knownMembers[name] = true
                dungeonGreeted[name] = nil

            elseif isOnline and not wasOnline then
                local now            = GetTime()
                local offTime        = lastOffline[name]
                local recentRejoined = offTime and (now - offTime) < REJOIN_SKIP_SEC

                if recentRejoined then
                    local n = name
                    C_Timer.After(GREET_DELAY, function()
                        GG_Print(MyGreeting_GetMsg("rejoin", {name=n}))
                    end)
                else
                    local isNew = not (db and db.knownMembers[name])
                    ScheduleGreeting(name, isNew)
                end
                -- 재접속 시 던전 인사 초기화
                dungeonGreeted[name] = nil

            elseif not isOnline and wasOnline then
                lastOffline[name]    = GetTime()
                dungeonGreeted[name] = nil
            end
        end
    end

    -- ── 길드원 던전 입장 감지 ─────────────────────────────
    for name, zone in pairs(currentZones) do
        if not ns.IsMe(name) and currentOnline[name] then
            local prevZone = prevZones[name] or ""
            local greetEntry = dungeonGreeted[name]
            local recentlyGreeted = greetEntry and greetEntry.zone == zone
                and (time() - greetEntry.time) < 7200
            if zone ~= prevZone and IsDungeon(zone) and not recentlyGreeted then
                dungeonGreeted[name] = { zone = zone, time = time() }
                local n2, z2 = name, zone
                C_Timer.After(GREET_DELAY, function()
                    local daily = GetNWBDailyInfo()
                    local msgKey = "dungeon"
                    if daily.normalZone == z2 then msgKey = "dungeon_daily_normal"
                    elseif daily.heroicZone == z2 then msgKey = "dungeon_daily_heroic"
                    end
                    local n3, z3 = n2, z2
                    GG_Print(MyGreeting_GetMsg(msgKey, {name=n2, zone=z2}), function()
                        if MyGreeting_CheckBIS then
                            MyGreeting_CheckBIS(n3, z3)
                        end
                    end)
                end)
            end
        end
    end

    -- ── 길드원 전장 입장 감지 ─────────────────────────────
    for name, zone in pairs(currentZones) do
        if not ns.IsMe(name) and currentOnline[name] then
            local prevZone = prevZones[name] or ""
            local bgEntry = bgGreeted[name]
            local recentlyGreeted = bgEntry and bgEntry.zone == zone
                and (time() - bgEntry.time) < 7200
            if zone ~= prevZone and IsBattleground(zone) and not recentlyGreeted then
                local daily = GetNWBDailyInfo()
                if daily.pvpZone == zone then
                    bgGreeted[name] = { zone = zone, time = time() }
                    local n2, z2 = name, zone
                    C_Timer.After(GREET_DELAY, function()
                        GG_Print(MyGreeting_GetMsg("battleground_daily", {name=n2, zone=z2}))
                    end)
                end
            end
            if zone ~= "" and not IsBattleground(zone) then
                bgGreeted[name] = nil
            end
        end
    end

    -- ── 레벨업 감지 ──────────────────────────────────────
    for name, newLevel in pairs(currentLevels) do
        if not ns.IsMe(name) then
            local oldLevel = prevLevels[name]
            if oldLevel and oldLevel > 0 and newLevel > oldLevel and (newLevel - oldLevel) <= 2 and currentOnline[name] then
                ScheduleLevelUp(name, newLevel)
            end
        end
    end

    prevOnline = currentOnline
    prevLevels = currentLevels
    prevRoster = currentRoster
    for name, zone in pairs(currentZones) do
        if zone ~= "" then prevZones[name] = zone end
    end
end

-- ============================================================
-- 이벤트 프레임
-- ============================================================
local frame = CreateFrame("Frame", "MyGreetingFrame", UIParent)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("CHAT_MSG_GUILD")

frame:SetScript("OnEvent", function(self, event, ...)

    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end

        if not MyGreetingDB then MyGreetingDB = {} end
        if not MyGreetingDB.knownMembers then MyGreetingDB.knownMembers = {} end
        if not MyGreetingDB.messages then MyGreetingDB.messages = {} end
        if not MyGreetingDB.dailyInfo then MyGreetingDB.dailyInfo = {} end
        if MyGreetingDB.loginGreetOff == nil then MyGreetingDB.loginGreetOff = true end  -- beta 기본값: 접속 인사 끔
        if MyGreetingDB.guildOff == nil then MyGreetingDB.guildOff = true end  -- beta 기본값: 길드 기능 전체 끔
        -- 길드 기능 꺼짐이어도 켜둘 개별 기능 (welcome_new / sleep 등) — 현재 모두 끔
        if not MyGreetingDB.guildOn or not MyGreetingDB.guildOnV then
            MyGreetingDB.guildOn  = {}
            MyGreetingDB.guildOnV = 2
        end
        if MyGreetingDB.guildOnV < 3 then  -- !명령어(cmd)는 길드 기능 꺼짐이어도 기본 켬
            MyGreetingDB.guildOn.cmd = true
            MyGreetingDB.guildOnV    = 3
        end
        if not MyGreetingDB.dungeonGreeted then MyGreetingDB.dungeonGreeted = {} end
        if not MyGreetingDB.bgGreeted then MyGreetingDB.bgGreeted = {} end
        db = MyGreetingDB
        dungeonGreeted = db.dungeonGreeted
        bgGreeted      = db.bgGreeted


    elseif event == "PLAYER_LOGIN" then
        myName = UnitName("player")
        pcall(function() SetCVar("guildMemberAlert", 0) end)
        C_GuildInfo.GuildRoster()

        -- 채팅창 내 이름 색상 강조 (직업 색상)
        if myName then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            local colorCode = cc
                and string.format("|cff%02X%02X%02X", cc.r * 255, cc.g * 255, cc.b * 255)
                or "|cffFFFF00"
            local highlight = colorCode .. myName .. "|r"
            local function NameHighlightFilter(_, _, msg, ...)
                -- 보안값(secret) 메시지는 읽거나 바꿀 수 없음 → 그대로 통과
                if issecretvalue and issecretvalue(msg) then return false, msg, ... end
                if type(msg) == "string" and msg:find(myName, 1, true) then
                    msg = msg:gsub(myName, highlight)
                end
                return false, msg, ...
            end
            local channels = {
                "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_OFFICER",
                "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                "CHAT_MSG_RAID",  "CHAT_MSG_RAID_LEADER",
                "CHAT_MSG_SAY",   "CHAT_MSG_YELL",
                "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
            }
            for _, ch in ipairs(channels) do
                ns.AddMessageEventFilter(ch, NameHighlightFilter)
            end
        end

        -- 옵션 패널 등록 (PLAYER_LOGIN 시점이 가장 안전)
        if optPanel then
            if Settings and Settings.RegisterCanvasLayoutCategory then
                local cat = Settings.RegisterCanvasLayoutCategory(optPanel, "myGreeting")
                ns.settingsCategory = cat
                Settings.RegisterAddOnCategory(cat)
            elseif InterfaceOptions_AddCategory then
                InterfaceOptions_AddCategory(optPanel)
            end
        end

        -- 정각 인사 공통 함수
        local function ScheduleDailyGreeting(targetHour, windowSec, dbKey, msgKey)
            local sentThisSession = false

            local function SendGreeting()
                if paused then return end
                if sentThisSession then return end
                local today = date("%Y-%m-%d")
                if db and db[dbKey] == today then return end
                local msg = MyGreeting_GetMsg(msgKey)
                if IsInGuild() and msg ~= "" then
                    sentThisSession = true
                    SendChatMessage(msg, "GUILD")
                    if db then db[dbKey] = today end
                end
            end

            local function Schedule()
                local t = date("*t")
                local now = t.hour * 3600 + t.min * 60 + t.sec
                local delay = targetHour * 3600 - now
                if delay <= 0 then delay = delay + 86400 end
                C_Timer.After(delay, function()
                    sentThisSession = false  -- 새 날이므로 세션 플래그 초기화
                    SendGreeting()
                    Schedule()
                end)
            end

            -- 로그인/리로드 시점에 이미 시간대 안이면 즉시 발송
            local function CheckNow()
                local t = date("*t")
                local now = t.hour * 3600 + t.min * 60 + t.sec
                local delay = targetHour * 3600 - now
                if delay <= 0 and delay >= -windowSec then
                    C_Timer.After(3, SendGreeting)
                end
            end

            CheckNow()
            Schedule()
        end

        ScheduleDailyGreeting(6,  7200, "lastMorningGreeting", "morning")
        ScheduleDailyGreeting(11, 7200, "lastNoonGreeting",    "noon")

        -- INIT_DELAY 후 초기화 완료
        -- 그 전 GUILD_ROSTER_UPDATE 는 기존 멤버 등록만 함
        C_Timer.After(INIT_DELAY, function()
            C_GuildInfo.GuildRoster()
            C_Timer.After(0.5, function()
                local online, levels, roster, zones = CollectRosterSnapshot()
                prevOnline  = online
                prevLevels  = levels
                prevRoster  = roster
                prevZones   = zones
                -- 현재 온라인 전원을 lastOffline 에 기록
                -- → 로그인 직후 "방금 접속" 으로 오탐 방지
                for name, isOnline in pairs(online) do
                    if isOnline and not ns.IsMe(name) then
                        lastOffline[name] = GetTime()
                    end
                end
                if db then
                    for name in pairs(roster) do
                        db.knownMembers[name] = true
                    end
                end
                -- 한 박자 더 쉬고 initialized
                C_Timer.After(0.5, function()
                    initialized = true
                    -- 30초마다 로스터 갱신 → 레벨업 빠르게 감지
                    C_Timer.NewTicker(30, function()
                        C_GuildInfo.GuildRoster()
                    end)
                end)
            end)
        end)

    elseif event == "GUILD_ROSTER_UPDATE" then
        if rosterTimer then rosterTimer:Cancel() end
        rosterTimer = C_Timer.NewTimer(0.2, function()
            rosterTimer = nil
            ProcessRosterUpdate()
        end)

    elseif event == "PLAYER_GUILD_UPDATE" then
        -- 길드 변경(가입/탈퇴) 시 상태 초기화 → 기존 길드원 일괄 인사 방지
        initialized  = false
        prevOnline   = {}
        prevLevels   = {}
        prevRoster   = {}
        prevZones    = {}
        dungeonGreeted = {}
        bgGreeted      = {}
        lastOffline    = {}
        if db then
            db.knownMembers  = {}
            db.dungeonGreeted = {}; dungeonGreeted = db.dungeonGreeted
            db.bgGreeted      = {}; bgGreeted      = db.bgGreeted
        end
        C_GuildInfo.GuildRoster()
        C_Timer.After(INIT_DELAY, function()
            C_GuildInfo.GuildRoster()
            C_Timer.After(0.5, function()
                local online, levels, roster, zones = CollectRosterSnapshot()
                prevOnline  = online
                prevLevels  = levels
                prevRoster  = roster
                prevZones   = zones
                if db then
                    for name in pairs(roster) do
                        db.knownMembers[name] = true
                    end
                end
                C_Timer.After(0.5, function()
                    initialized = true
                end)
            end)
        end)

    elseif event == "CHAT_MSG_GUILD" then
        local msg, sender = ...
        if not msg or not sender then return end
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        local replyTo = sender  -- 귓말 답장용 원래 이름 (서버명/성 포함 그대로)
        sender = sender:match("^([^%-]+)") or sender
        local cmdOn   = ns.GuildAllow("cmd")
        local sleepOn = ns.GuildAllow("sleep")
        if not cmdOn and not sleepOn then return end

        -- 길드 채팅 명령 감지 (본인 포함) — /mg 길드명령 으로 끄면 건너뜀
        local trimmed = strtrim(msg)
        if cmdOn then

            if trimmed == "!장비보내기" then
                local macroCmd = '/script CreateMacro("/장비","135266",\'/script MyGS=GEAR_SCORE_CACHE and GEAR_SCORE_CACHE[UnitGUID("player")]\\n/script SendChatMessage("GS:"..(MyGS and MyGS[1]or 0),"WHISPER",nil,"보꿈밥")\',false)'
                SendChatMessage(macroCmd, "WHISPER", nil, sender)
            end

            local whisperTarget, whisperMsg = trimmed:match("^!귓말%s+(%S+)%s*(.-)%s*$")
            if whisperTarget then
                if ns.IsMe(replyTo) then
                    local msg = (whisperMsg and whisperMsg ~= "") and whisperMsg or "안녕하세요 :)"
                    SendChatMessage(msg, "WHISPER", nil, whisperTarget)
                end
            end

            -- !길드X → 길드챗으로 출력
            local guildSub = trimmed:match("^!길드(.+)$") or trimmed:match("^![Gg][Uu][Ii][Ll][Dd]%s*(.+)$")
            -- !g 단축 (예: !gclass). 단 !gnome 처럼 그 자체가 명령어면 일반 명령으로 처리
            if not guildSub then
                local whole = trimmed:match("^!(.+)$")
                local gSub  = trimmed:match("^![Gg]%s*(.+)$")
                if gSub and not (whole and IsKnownCommand(whole)) and IsKnownCommand(gSub) then
                    guildSub = gSub
                end
            end
            if guildSub then DispatchCommand(guildSub, nil, sender) end

            -- !X → 친 사람 귓말로 출력
            local plainSub = trimmed:match("^!(.+)$")
            if plainSub and not guildSub then DispatchCommand(plainSub, replyTo, sender) end
        end

        if ns.IsMe(replyTo) then return end

        local lower = msg:lower()
        local isSleepMsg =
            lower:find("자야") or lower:find("잘게") or lower:find("잘께") or
            lower:find("잠자") or lower:find("잡니다") or lower:find("잘랍니다") or
            lower:find("자러") or lower:find("잔다") or lower:find("자겠") or
            lower:find("쉬어야") or lower:find("쉬겠") or lower:find("쉴게") or
            lower:find("쉴께") or lower:find("쉰다") or lower:find("쉬러") or
            lower:find("쉬다 올") or lower:find("쉬다올") or
            lower:find("쉬다 옵") or lower:find("쉬다옵") or
            lower:find("이따 올") or lower:find("이따올") or
            lower:find("이따 옵") or lower:find("이따옵") or
            lower:find("들어가야") or lower:find("들어갈게") or lower:find("들어갑니다") or
            lower:find("들어간다") or lower:find("들어가겠") or lower:find("들어가볼") or lower:find("들어가보겠") or lower:find("들어가 보겠") or
            lower:find("먼저 들어가") or lower:find("먼저들어가") or
            lower:find("드가보겠") or lower:find("드가 보겠") or lower:find("드갑니다") or lower:find("드갈게") or
            lower:find("먼저가볼") or lower:find("먼저 가볼") or
            lower:find("먼저갑니다") or lower:find("먼저 갑니다") or
            lower:find("먼저갈") or lower:find("먼저 갈") or
            lower:find("퇴근") or
            lower:find("내일 뵐") or lower:find("내일뵐") or
            lower:find("내일 봬") or lower:find("내일봬") or
            lower:find("먼저 잡니다") or lower:find("먼저잡니다") or
            lower:find("이만 가보겠") or lower:find("이만가보겠") or
            lower:find("이만 갑니다") or lower:find("이만갑니다") or
            lower:find("이만 가겠") or lower:find("이만가겠") or
            lower:find("가봐야겠")

        if isSleepMsg and sleepOn then
            local s = sender
            C_Timer.After(GREET_DELAY, function()
                GG_Print(MyGreeting_GetMsg("sleep", {name=s}), nil, "sleep")
            end)
        end

        -- 내 캐릭명 언급 감지
        if myName and msg:find(myName) then
            ShowMentionAlert(sender, msg)
        end

    end

end)

-- ============================================================
-- 던전 약자 → 한글 이름 (/mg 약자, /mg rfc)
-- ============================================================
local DUNGEON_ABBR = {
    -- 클래식 던전
    { "RFC",   "성난불길 협곡" },
    { "WC",    "통곡의 동굴" },
    { "DM/VC", "죽음의 폐광 (DM은 혈투의 전장일 수도)" },
    { "SFK",   "그림자송곳니 성채" },
    { "BFD",   "검은심연의 나락" },
    { "STOCKS","스톰윈드 지하감옥" },
    { "GNOMER","놈리건" },
    { "RFK",   "가시덩굴 우리" },
    { "SM",    "붉은십자군 수도원" },
    { "GY",    "붉은십자군 수도원 - 묘지" },
    { "LIB",   "붉은십자군 수도원 - 도서관" },
    { "ARM",   "붉은십자군 수도원 - 무기고" },
    { "CATH",  "붉은십자군 수도원 - 예배당" },
    { "RFD",   "가시덩굴 구릉" },
    { "ULDA/ULD", "울다만" },
    { "ZF",    "줄파락" },
    { "MARA",  "마라우돈" },
    { "ST",    "아탈학카르 신전 (가라앉은 사원)" },
    { "BRD",   "검은바위 나락" },
    { "LBRS",  "검은바위 첨탑 (하층)" },
    { "UBRS",  "검은바위 첨탑 (상층)" },
    { "DME",   "혈투의 전장 (동쪽)" },
    { "DMW",   "혈투의 전장 (서쪽)" },
    { "DMN",   "혈투의 전장 (북쪽)" },
    { "SCHOLO/SCHOLOMANCE", "스칼로맨스" },
    { "STRAT", "스트라솔름" },
    { "UD",    "스트라솔름 (언데드 쪽)" },
    { "LIVE",  "스트라솔름 (살아있는 쪽)" },
    -- beta 신규
    { "ROL",   "로데론의 폐허 (Ruins of Lordaeron)" },
    { "HOT",   "영주의 전당 (Hall of Thanes)" },
    { "ES/ESW", "발굴현장: 저습지 (Excavation Site: Wetlands)" },
    -- 클래식 레이드
    { "MC",    "화산 심장부" },
    { "ONY",   "오닉시아의 둥지" },
    { "BWL",   "검은날개 둥지" },
    { "ZG",    "줄구룹" },
    { "AQ20",  "안퀴라즈 폐허" },
    { "AQ40",  "안퀴라즈 사원" },
    { "NAXX",  "낙스라마스" },
    -- TBC 던전
    { "RAMPS", "지옥불 성루" },
    { "BF",    "피의 용광로" },
    { "SH",    "으스러진 손의 전당" },
    { "SP",    "강제 노역소" },
    { "UB",    "지하수렁" },
    { "SV",    "증기 저장고" },
    { "MT",    "마나 무덤" },
    { "AC",    "아키나이 납골당" },
    { "SETH",  "세데크 전당" },
    { "SL/SLABS", "어둠의 미궁" },
    { "OHB/OH/DURN", "옛 힐스브래드 구릉지" },
    { "BM",    "검은늪" },
    { "BOT",   "신록의 정원" },
    { "MECH",  "메카나르" },
    { "ARC",   "알카트라즈" },
    { "MGT",   "마법학자의 정원" },
    -- TBC 레이드
    { "KARA",  "카라잔" },
    { "GRUUL", "그룰의 둥지" },
    { "MAG",   "마그테리돈의 둥지" },
    { "SSC",   "불뱀 제단" },
    { "TK",    "폭풍우 요새" },
    { "HYJAL/MH", "하이잘 정상" },
    { "BT",    "검은 사원" },
    { "ZA",    "줄아만" },
    { "SWP",   "태양샘 고원" },
}
-- ZONE_ABBR 채우기: "SL/SLABS" → 첫 약자, "스트라솔름 (언데드 쪽)" → 괄호 앞 이름도 등록 (먼저 나온 것 우선)
for _, e in ipairs(DUNGEON_ABBR) do
    local abbr = e[1]:match("^[^/]+")
    local full = e[2]
    local base = full:match("^(.-)%s*%(") or full
    ZONE_ABBR[full] = ZONE_ABBR[full] or abbr
    ZONE_ABBR[base] = ZONE_ABBR[base] or abbr
end
-- 실제 지역명이 약자표와 다르거나 애매한 것
ZONE_ABBR["혈투의 전장"]   = "DIRE MAUL"
ZONE_ABBR["검은바위 첨탑"] = "BRS"
ZONE_ABBR["울다만"]        = "ULDA"
ZONE_ABBR["스칼로맨스"]    = "SCHOLO"

-- 일반 지역 (필드/도시/전장) → 영어 약자 또는 짧은 영어명. 없는 지역은 한글 그대로
for ko, en in pairs({
    -- 동부 왕국
    ["스톰윈드"]="SW", ["아이언포지"]="IF", ["언더시티"]="UC", ["실버문"]="SMC",
    ["엘윈 숲"]="Elwynn", ["서부 몰락지대"]="Westfall", ["붉은마루 산맥"]="Redridge",
    ["그늘숲"]="Duskwood", ["가시덤불 골짜기"]="STV", ["저습지"]="Wetlands",
    ["던 모로"]="Dun Morogh", ["모단 호수"]="Loch Modan", ["은빛소나무 숲"]="Silverpine",
    ["티리스팔 숲"]="Tirisfal", ["힐스브래드 구릉지"]="Hillsbrad", ["알터랙 산맥"]="Alterac",
    ["아라시 고원"]="Arathi", ["동부 내륙지"]="Hinterlands", ["황야의 땅"]="Badlands",
    ["이글거리는 협곡"]="Searing Gorge", ["불타는 평원"]="BSteppes", ["슬픔의 늪"]="Swamp",
    ["저주받은 땅"]="Blasted Lands", ["서부 역병지대"]="WPL", ["동부 역병지대"]="EPL",
    ["죽음의 고개"]="Deadwind", ["영원노래 숲"]="Eversong", ["유령의 땅"]="Ghostlands",
    ["쿠엘다나스 섬"]="IoQD", ["무법항"]="Booty Bay",
    -- 칼림도어
    ["오그리마"]="Org", ["썬더 블러프"]="TB", ["다르나서스"]="Darn", ["엑소다르"]="Exodar",
    ["듀로타"]="Durotar", ["불모의 땅"]="Barrens", ["멀고어"]="Mulgore", ["텔드랏실"]="Teldrassil",
    ["어둠해안"]="Darkshore", ["잿빛 골짜기"]="Ashenvale", ["돌발톱 산맥"]="Stonetalon",
    ["잊혀진 땅"]="Desolace", ["먼지진흙 습지대"]="Dustwallow", ["버섯구름 봉우리"]="1k Needles",
    ["페랄라스"]="Feralas", ["타나리스"]="Tanaris", ["운고로 분화구"]="Un'Goro",
    ["실리더스"]="Silithus", ["악령의 숲"]="Felwood", ["아즈샤라"]="Azshara",
    ["여명의 설원"]="Winterspring", ["달의 숲"]="Moonglade",
    ["하늘안개 섬"]="Azuremyst", ["핏빛안개 섬"]="Bloodmyst",
    -- 아웃랜드
    ["지옥불 반도"]="HFP", ["장가르 습지대"]="Zangar", ["테로카르 숲"]="Terokkar",
    ["나그란드"]="Nagrand", ["칼날 산맥"]="BEM", ["황천의 폭풍"]="Netherstorm",
    ["어둠달 골짜기"]="SMV", ["샤트라스"]="Shatt",
    -- 전장
    ["전쟁노래 협곡"]="WSG", ["아라시 분지"]="AB", ["알터랙 계곡"]="AV", ["폭풍의 눈"]="EotS",
}) do ZONE_ABBR[ko] = ZONE_ABBR[ko] or en end

-- 채팅/게임 용어 약자 → 영어 원문 + 한글 뜻 (/mg 채팅약자, /mg lfg)
local CHAT_ABBR = {
    -- 파티 구하기 / 거래
    { "LFG",   "Looking For Group",  "파티 구함 (나를 넣어줄 파티 찾음)" },
    { "LFM",   "Looking For More",   "인원 더 구함 (파티가 사람 모집)" },
    { "LF",    "Looking For",        "~ 구함" },
    { "LF1M",  "Looking For 1 More", "1명 더 구함" },
    { "LF2M",  "Looking For 2 More", "2명 더 구함" },
    { "LF3M",  "Looking For 3 More", "3명 더 구함" },
    { "WTS",   "Want To Sell",       "팝니다" },
    { "WTB",   "Want To Buy",        "삽니다" },
    { "WTT",   "Want To Trade",      "교환합니다" },
    { "PST",   "Please Send Tell",   "귓속말 주세요" },
    { "PM/W",  "Private Message / Whisper", "귓속말" },
    { "INV",   "Invite",             "초대 (파티 초대해 주세요)" },
    { "SUMM/SUMMON", "Summon",       "소환" },
    -- 인사 / 대화
    { "TY/THX/TYVM", "Thank You",    "고마워요" },
    { "NP",    "No Problem",         "천만에요 / 괜찮아요" },
    { "GG",    "Good Game",          "수고했어요" },
    { "GJ",    "Good Job",           "잘했어요" },
    { "GL",    "Good Luck",          "행운을 빌어요" },
    { "HF",    "Have Fun",           "즐겜하세요" },
    { "GM",    "Good Morning / Game Master", "좋은 아침 / 운영자" },
    { "GN",    "Good Night",         "잘 자요" },
    { "GTG/G2G", "Got To Go",        "가봐야 해요" },
    { "CYA",   "See Ya",             "또 봐요" },
    { "BRB",   "Be Right Back",      "금방 올게요 (잠깐 자리비움)" },
    { "AFK",   "Away From Keyboard", "자리비움" },
    { "OMW",   "On My Way",          "가는 중" },
    { "NVM",   "Never Mind",         "신경 쓰지 마세요" },
    { "IDK",   "I Don't Know",       "몰라요" },
    { "BTW",   "By The Way",         "그런데" },
    { "LOL",   "Laughing Out Loud",  "ㅋㅋㅋ" },
    { "OOM",   "Out Of Mana",        "마나 없음" },
    { "WB",    "Welcome Back / World Buff", "어서 와요 / 월드 버프" },
    -- 파티 역할 / 전투
    { "DPS",   "Damage Per Second",  "딜러" },
    { "MT",    "Main Tank",          "메인 탱커" },
    { "OT",    "Off Tank",           "서브 탱커" },
    { "CC",    "Crowd Control",      "군중 제어 (양·덫 등으로 몹 묶기)" },
    { "AOE",   "Area Of Effect",     "광역" },
    { "DOT",   "Damage Over Time",   "지속 피해" },
    { "HOT",   "Heal Over Time",     "지속 치유" },
    { "LOS",   "Line Of Sight",      "시야 (기둥 뒤로 숨기)" },
    { "CD",    "Cooldown",           "재사용 대기시간" },
    { "RES/REZ", "Resurrect",        "부활" },
    { "HS",    "Hearthstone / Healthstone", "귀환석 / 생명석" },
    { "SS",    "Soulstone",          "영혼석" },
    { "HP",    "Health Points",      "생명력" },
    { "MP",    "Mana Points",        "마나" },
    { "XP/EXP", "Experience",        "경험치" },
    { "LVL",   "Level",              "레벨" },
    { "HC",    "Heroic",             "영웅 난이도" },
    { "NM",    "Normal",             "일반 난이도" },
    -- 아이템 / 루팅
    { "BOP",   "Bind On Pickup",     "획득 시 귀속" },
    { "BOE",   "Bind On Equip",      "착용 시 귀속" },
    { "BIS",   "Best In Slot",       "부위별 최고 아이템" },
    { "MS",    "Main Spec",          "주 특성 (주 특성 우선 입찰)" },
    { "OS",    "Off Spec",           "보조 특성" },
    { "SR",    "Soft Reserve",       "아이템 찜 (예약)" },
    { "HR",    "Hard Reserve",       "아이템 확정 예약 (입찰 불가)" },
    { "GDKP",  "Gold DKP",           "골드 경매 공대" },
    { "DKP",   "Dragon Kill Points", "공대 점수제" },
    { "SP",    "Spell Power",        "주문력" },
    { "AP",    "Attack Power",       "전투력" },
    { "MP5",   "Mana Per 5 sec",     "5초당 마나 회복" },
    -- PvP / 지역
    { "BG",    "Battleground",       "전장" },
    { "WSG",   "Warsong Gulch",      "전쟁노래 협곡" },
    { "AB",    "Arathi Basin",       "아라시 분지" },
    { "AV",    "Alterac Valley",     "알터랙 계곡" },
    { "EOTS",  "Eye Of The Storm",   "폭풍의 눈" },
    { "KOS",   "Kill On Sight",      "보이면 죽임 (적대 대상)" },
    { "WPVP",  "World PvP",          "필드 쟁" },
    { "SW",    "Stormwind",          "스톰윈드" },
    { "IF",    "Ironforge",          "아이언포지" },
    { "DARN",  "Darnassus",          "다르나서스" },
    { "ORG/OG", "Orgrimmar",         "오그리마" },
    { "UC",    "Undercity",          "언더시티" },
    { "TB",    "Thunder Bluff",      "썬더 블러프" },
    { "SHATT", "Shattrath",          "샤트라스" },
    { "BB",    "Booty Bay",          "무법항" },
    { "STV",   "Stranglethorn Vale", "가시덤불 골짜기" },
    { "EPL",   "Eastern Plaguelands", "동부 역병지대" },
    { "WPL",   "Western Plaguelands", "서부 역병지대" },
}

-- 약자 → 설명 목록 (던전 MT=마나 무덤 / 채팅 MT=메인 탱커 처럼 겹치면 둘 다 보여줌)
local ABBR_MAP = {}
local function AddAbbr(keys, text)
    for a in keys:gmatch("[^/]+") do
        local k = strlower(a)
        ABBR_MAP[k] = ABBR_MAP[k] or {}
        table.insert(ABBR_MAP[k], text)
    end
end
for _, e in ipairs(DUNGEON_ABBR) do AddAbbr(e[1], e[2] .. " (던전)") end
for _, e in ipairs(CHAT_ABBR) do AddAbbr(e[1], e[2] .. " — " .. e[3]) end

local function PrintAbbrList(title, list, fmt, perLine)
    local L, line = "LOCAL", {}
    GG_Send("─── " .. title .. " ───", L)
    for i, e in ipairs(list) do
        line[#line + 1] = fmt(e)
        if #line == perLine or i == #list then
            GG_Send(table.concat(line, ", "), L)
            line = {}
        end
    end
end

local function PrintDungeonAbbr()
    PrintAbbrList("던전 약자", DUNGEON_ABBR, function(e) return e[1] .. "=" .. e[2] end, 4)
    GG_Send("채팅 약자(LFG, WTS 등)는 /mg 채팅약자", "LOCAL")
end

local function PrintChatAbbr()
    PrintAbbrList("채팅 약자", CHAT_ABBR, function(e) return e[1] .. "=" .. e[3] end, 4)
end

-- ============================================================
-- 슬래시 커맨드
-- ============================================================
SLASH_MYGREETING1 = "/mg"
SLASH_MYGREETING2 = "/mygreeting"
SLASH_MYGREETING3 = "/엠지"

SlashCmdList["MYGREETING"] = function(msg)
    msg = strtrim(msg or "")
    local lower = strlower(msg)

    if lower == "help" or lower == "도움" or lower == "헬프" or lower == "" then
        local L = "LOCAL"
        GG_Send("--- 길드 정보 ---", L)
        GG_Send("/mg 현황 / 레벨 / 직업 / 종족 / 지역 / 인던 / 전문기술 / 등급", L)
        GG_Send("/mg 정보 <이름> / 등급 <등급명>", L)
        GG_Send("--- 장비 ---", L)
        GG_Send("/mg 장비현황 / 장비 <이름> / 장비길드 / 장비전체 / 장비<직업> / 장비초기화", L)
        GG_Send("--- 길드챗 명령 (!도움 으로 자세히) ---", L)
        GG_Send("!현황 !레벨 !직업 !종족 !지역 !인던 !전문기술 !등급 !정보 <이름>", L)
        GG_Send("!일일 !일던 !영던 !전장  /  !길드<명령> = 길드챗으로 답 (예: !길드직업)", L)
        GG_Send("!전사 !법사 ... / !오크 !인간 ... / !대장 !재봉 ...", L)
        GG_Send("--- 기타 ---", L)
        GG_Send("/mg 중지 — 자동 인사 멈춤  /  /mg 시작 — 다시 시작", L)
        GG_Send("/mg 길드 — 길드 기능 전체 켜기/끄기", L)
        GG_Send("/mg 길드명령 — 길드챗 !명령만 켜기/끄기", L)
        GG_Send("/mg 접속인사 — 길드원 접속 인사 켜기/끄기", L)
        GG_Send("/mg 약자 — 던전 약자 목록 / 채팅약자 — LFG, WTS 등 / /mg rfc, /mg lfg — 뜻 찾기", L)
        GG_Send("/mg 이름확인 — 이름 형식 진단 (Forever 성+이름)", L)
        GG_Send("/mg reset / remove <이름> / status (애드온 상태) / db", L)
        GG_Send("/mg 도움 타겟 — 타겟 감시 명령", L)

    elseif lower == "도움 타겟" then
        local L = "LOCAL"
        GG_Send("─── 타겟 감시 ───", L)
        GG_Send("/mg 타겟 [이름] — 한 번 찾아 징표+소리 후 종료", L)
        GG_Send("/mg 타겟별|동그라미|다이아|삼각|달|사각|십자|해골 [이름] — 계속 감시+징표 (동시 여러 개 가능)", L)
        GG_Send("/mg 타겟별해제 — 해당 징표만 해제 / 타겟해제 — 전체 해제", L)
        GG_Send("/mg 타겟다시 — 현재 감시 중인 모든 대상 재탐색", L)

    elseif lower == "중지" then
        paused = true
        GG_Send("자동 인사 일시중지.", "LOCAL")

    elseif lower == "시작" then
        paused = false
        GG_Send("자동 인사 재개.", "LOCAL")

    elseif lower == "reset" then
        if db then
            db.knownMembers = {}
            GG_Send("신규 목록 초기화 완료.", "LOCAL")
        end

    elseif lower:sub(1, 7) == "remove " then
        local targetName = strtrim(msg:sub(8))
        targetName = targetName:sub(1,1):upper() .. targetName:sub(2):lower()
        if db and targetName ~= "" then
            db.knownMembers[targetName] = nil
            GG_Send(targetName .. " 신규 처리로 변경.", "LOCAL")
        end

    elseif msg == "장비" then
        local name
        if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
            name = UnitName("target")
            name = name and (name:match("^([^%-]+)") or name)
        else
            name = UnitName("player")
            name = name and (name:match("^([^%-]+)") or name)
        end
        if name and MyGreeting_GetGearScore then MyGreeting_GetGearScore(name, "LOCAL") end

    elseif msg:match("^타겟 (.+) (%d+)$") then
        local targetName, markIdx = msg:match("^타겟 (.+) (%d+)$")
        if MyGreeting_MarkTarget then MyGreeting_MarkTarget(targetName, markIdx) end

    elseif msg:match("^타겟 (.+)$") then
        local targetName = msg:match("^타겟 (.+)$")
        if MyGreeting_MarkTarget then MyGreeting_MarkTarget(targetName) end

    elseif msg:match("^타겟%S+ .+$") then
        local markName, targetName = msg:match("^타겟(%S+) (.+)$")
        local markIdx = MyGreeting_GetMarkIndex and MyGreeting_GetMarkIndex(markName)
        if markIdx and MyGreeting_WatchTarget then
            MyGreeting_WatchTarget(targetName, markIdx)
        end

    elseif msg:match("^타겟%S+해제$") then
        local markName = msg:match("^타겟(%S+)해제$")
        local markIdx = MyGreeting_GetMarkIndex and MyGreeting_GetMarkIndex(markName)
        if markIdx and MyGreeting_StopWatchMark then MyGreeting_StopWatchMark(markIdx) end

    elseif msg == "타겟해제" or msg == "타겟리셋" or msg == "타겟취소" then
        if MyGreeting_StopWatch then MyGreeting_StopWatch() end

    elseif msg == "타겟다시" or msg == "타겟재탐" or msg == "타겟재설정" then
        if MyGreeting_RetryWatch then MyGreeting_RetryWatch() end

    elseif msg == "타겟상태" or msg == "타겟현황" or msg == "타겟정보" then
        if MyGreeting_WatchStatus then MyGreeting_WatchStatus() end

    elseif msg:match("^타겟양 (.+)$") then
        local name = msg:match("^타겟양 (.+)$")
        if MyGreeting_WatchFocus then MyGreeting_WatchFocus(name) end

    elseif msg == "타겟양" then
        if UnitExists("target") and not UnitIsUnit("target", "player") then
            local n = UnitName("target")
            n = n and (n:match("^([^%-]+)") or n)
            if n and MyGreeting_WatchFocus then MyGreeting_WatchFocus(n) end
        else
            GG_Send("타겟을 먼저 선택하세요", "LOCAL")
        end

    elseif msg:match("^타겟%S+$") then
        local markName = msg:match("^타겟(%S+)$")
        local markIdx = MyGreeting_GetMarkIndex and MyGreeting_GetMarkIndex(markName)
        if markIdx then
            if UnitExists("target") and not UnitIsUnit("target", "player") then
                local n = UnitName("target")
                n = n and (n:match("^([^%-]+)") or n)
                if n and MyGreeting_WatchTarget then MyGreeting_WatchTarget(n, markIdx) end
            else
                GG_Send("타겟을 먼저 선택하세요", "LOCAL")
            end
        end

    elseif msg == "장비초기화" then
        if MyGreetingDB then MyGreetingDB.gearData = {} end
        GG_Send("장비 데이터 초기화 완료", "LOCAL")

    elseif lower == "db" then
        if MyGreeting_PrintAltDB then MyGreeting_PrintAltDB() end

    elseif lower == "status" then
        local count = 0
        if db then for _ in pairs(db.knownMembers) do count = count + 1 end end
        GG_Send("초기화: " .. (initialized and "완료" or "대기중"), "LOCAL")
        GG_Send("기존 멤버 수: " .. count, "LOCAL")
        GG_Send("내 이름: " .. (myName or "?"), "LOCAL")

    elseif lower == "길드" then
        if db then
            db.guildOff = not db.guildOff
            GG_Send("길드 기능 (인사/던전/레벨업/정각/!명령/자동초대): " .. (db.guildOff and "끔" or "켬"), "LOCAL")
        end

    elseif lower == "길드명령" then
        if db then
            db.guildOn = db.guildOn or {}
            db.guildOn.cmd = not db.guildOn.cmd
            GG_Send("길드챗 !명령어: " .. (db.guildOn.cmd and "켬" or "끔") .. " (길드 기능 전체: " .. (db.guildOff and "끔" or "켬") .. ")", "LOCAL")
        end

    elseif lower == "접속인사" then
        if db then
            db.loginGreetOff = not db.loginGreetOff
            GG_Send("길드 접속 인사: " .. (db.loginGreetOff and "끔" or "켬"), "LOCAL")
        end

    elseif lower == "약자" or lower == "던전약자" then
        PrintDungeonAbbr()

    elseif lower == "채팅약자" then
        PrintChatAbbr()

    elseif ABBR_MAP[(lower:gsub("%s", ""))] then
        for _, text in ipairs(ABBR_MAP[(lower:gsub("%s", ""))]) do
            GG_Send(msg:upper() .. " = " .. text, "LOCAL")
        end

    elseif lower == "이름확인" or lower == "names" then
        -- Forever 이름 형식 확인 (성+이름 / 구분자 / 채팅 보낸 사람 원문)
        local function q(v)
            if issecretvalue and issecretvalue(v) then return "(보안값)" end
            return v == nil and "nil" or ("[" .. tostring(v) .. "]")
        end
        local n1, n2 = UnitName("player")
        GG_Send("성+이름 체계: " .. tostring(RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled())
            .. "  구분자: " .. q(ns.SURNAME_SEP), "LOCAL")
        GG_Send("UnitName: " .. q(n1) .. " " .. q(n2) .. "  /  귓말용: " .. q(ns.UnitWhisperName("player")), "LOCAL")
        if GetUnitName then GG_Send("GetUnitName(true): " .. q(GetUnitName("player", true)), "LOCAL") end
        if UnitFullName then
            local f1, f2 = UnitFullName("player")
            GG_Send("UnitFullName: " .. q(f1) .. " " .. q(f2), "LOCAL")
        end
        if IsInGuild() then
            for i = 1, GetNumGuildMembers() do
                local rn = GetGuildRosterInfo(i)
                if rn and ns.IsMe(rn) then GG_Send("길드 명단의 내 이름: " .. q(rn), "LOCAL"); break end
            end
            local rn1 = GetGuildRosterInfo(1)
            GG_Send("길드 명단 1번 이름: " .. q(rn1), "LOCAL")
        end
        if UnitExists("target") then
            local t1, t2 = UnitName("target")
            GG_Send("대상 UnitName: " .. q(t1) .. " " .. q(t2) .. "  /  귓말용: " .. q(ns.UnitWhisperName("target")), "LOCAL")
        end
        local any = false
        for ev, snd in pairs(ns.lastSenders) do
            any = true
            GG_Send("마지막 " .. ev:gsub("CHAT_MSG_", "") .. " 보낸 사람: " .. q(snd)
                .. (type(snd) == "string" and ("  나?" .. tostring(ns.IsMe(snd))) or ""), "LOCAL")
        end
        if not any then GG_Send("받은 채팅 기록 없음 — 길드/파티챗을 받은 뒤 다시 실행", "LOCAL") end
        GG_Send("채팅 잠금(인스턴스): " .. tostring(ns.InChatLockdown()), "LOCAL")

    elseif lower == "config" or lower == "옵션" then
        ns.OpenOptions("myGreeting")

    else
        local playerName = myName or UnitName("player")
        playerName = playerName and (playerName:match("^([^%-]+)") or playerName)
        local handled = DispatchCommand(msg, "LOCAL", playerName)
        if not handled then
            GG_Send("알 수 없는 명령: " .. msg .. "  (/mg 도움)", "LOCAL")
        end
    end
end

-- ============================================================
-- 인터페이스 옵션 패널 (애드온 탭에 등록)
-- ============================================================
local OPT_FIELDS = {
    { key="morning",       label="아침 인사",       hint="" },
    { key="noon",          label="점심 인사",       hint="" },
    { key="welcome_new",   label="환영 (신규)",      hint="{name} {main}" },
    { key="welcome",       label="환영 (기존)",      hint="{name} {main}" },
    { key="rejoin",        label="재접속",           hint="{name}" },
    { key="sleep",         label="잠자리 응답",      hint="{name}" },
    { key="dungeon",             label="던전 입장",          hint="{name} {zone}" },
    { key="dungeon_daily_normal",label="던전 입장 (일반일퀘)", hint="{name} {zone}" },
    { key="dungeon_daily_heroic",label="던전 입장 (영웅일퀘)", hint="{name} {zone}" },
    { key="battleground_daily",  label="전장 입장 (주간전장)", hint="{name} {zone}" },
    { key="levelup_guild", label="레벨업 (길드)",    hint="{name} {level}" },
    { key="summon",        label="소환 감사",        hint="" },
    { key="resurrect",     label="부활 감사",        hint="" },
    { key="party_greet",   label="파티 참가 인사",   hint="" },
    { key="party_leave",   label="파티 퇴장 인사",   hint="" },
    { key="sugo",          label="수고 응답",        hint="" },
}

optPanel = CreateFrame("Frame", "MyGreetingOptionsPanel")
optPanel.name = "myGreeting"

-- 타이틀
local optTitle = optPanel:CreateFontString(nil, "ARTWORK")
optTitle:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
optTitle:SetPoint("TOPLEFT", optPanel, "TOPLEFT", 16, -16)
optTitle:SetText("myGreeting")
optTitle:SetTextColor(0.4, 1.0, 0.4)

local optVer = optPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
optVer:SetPoint("LEFT", optTitle, "RIGHT", 8, 0)
optVer:SetText("v" .. (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "1.0.0"))
optVer:SetTextColor(0.6, 0.6, 0.6)

local optVarHint = optPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
optVarHint:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -2)
optVarHint:SetText("변수: {name}=이름  {zone}=지역  {level}=레벨  |  빈칸으로 두면 해당 메시지 비활성화")
optVarHint:SetTextColor(0.85, 0.85, 0.4)

-- 메시지 행 목록
local optEditBoxes = {}
local ROW_H  = 26
local START_Y = -52

for i, field in ipairs(OPT_FIELDS) do
    local y = START_Y - (i - 1) * ROW_H

    local lbl = optPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", optPanel, "TOPLEFT", 16, y)
    lbl:SetWidth(110)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(field.label)

    if field.hint ~= "" then
        local hintLbl = optPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        hintLbl:SetPoint("TOPLEFT", optPanel, "TOPLEFT", 128, y + 1)
        hintLbl:SetText(field.hint)
        hintLbl:SetTextColor(0.5, 0.85, 0.5)
        hintLbl:SetWidth(75)
    end

    local eb = CreateFrame("EditBox", "MyGreetingEB_"..field.key, optPanel, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", optPanel, "TOPLEFT", 205, y + 4)
    eb:SetSize(370, 20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)

    optEditBoxes[field.key] = eb
end

-- 패널 열릴 때 DB 값 로드
optPanel:SetScript("OnShow", function()
    for _, field in ipairs(OPT_FIELDS) do
        local eb  = optEditBoxes[field.key]
        local saved = MyGreetingDB and MyGreetingDB.messages and MyGreetingDB.messages[field.key]
        eb:SetText(type(saved) == "string" and saved or (MyGreeting_DEFAULT_MESSAGES[field.key] or ""))
        eb:SetCursorPosition(0)
    end
end)

-- 저장 버튼
local optSaveBtn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
optSaveBtn:SetSize(110, 28)
local btnY = START_Y - #OPT_FIELDS * ROW_H - 8
optSaveBtn:SetPoint("TOPLEFT", optPanel, "TOPLEFT", 16, btnY)
optSaveBtn:SetText("저장")
optSaveBtn:SetScript("OnClick", function()
    if not MyGreetingDB then MyGreetingDB = {} end
    if not MyGreetingDB.messages then MyGreetingDB.messages = {} end
    for _, field in ipairs(OPT_FIELDS) do
        MyGreetingDB.messages[field.key] = optEditBoxes[field.key]:GetText()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 메시지 저장 완료")
end)

-- 기본값 초기화 버튼
local optDefaultBtn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
optDefaultBtn:SetSize(130, 28)
optDefaultBtn:SetPoint("LEFT", optSaveBtn, "RIGHT", 6, 0)
optDefaultBtn:SetText("기본값으로")
optDefaultBtn:SetScript("OnClick", function()
    if MyGreetingDB then MyGreetingDB.messages = {} end
    for _, field in ipairs(OPT_FIELDS) do
        optEditBoxes[field.key]:SetText(MyGreeting_DEFAULT_MESSAGES[field.key] or "")
        optEditBoxes[field.key]:SetCursorPosition(0)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 기본값 복원 (저장 버튼을 눌러야 적용됩니다)")
end)

-- ============================================================
-- 본인이 보내는 길드 메시지에서 명령 감지
-- (Classic에서는 CHAT_MSG_GUILD가 자신의 메시지를 돌려주지 않으므로)
-- ============================================================

