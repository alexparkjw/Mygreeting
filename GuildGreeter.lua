-- ============================================================
-- GuildGreeter.lua
-- 길드 커스텀 인사 시스템
-- ============================================================

local ADDON_NAME      = "MyGreeting"
local GREET_DELAY     = 1
local REJOIN_SKIP_SEC = 5 * 60
local INIT_DELAY      = 3

-- ============================================================
-- 클래식 던전 이름 목록 (한글/영문 둘 다)
-- ============================================================
local DUNGEONS = {
    -- ── 클래식 ────────────────────────────────────────────────
    ["성난불길 협곡"]=true,
    ["통곡의 동굴"]=true,
    ["죽음의 폐광"]=true,
    ["그림자송곳니 생채"]=true,
    ["검은심연의 나락"]=true,
    ["스톰윈드 지하감옥"]=true,
    ["놈리건"]=true,
    ["가시덩굴 우리"]=true,
    ["붉은심자군 수도원 - 묘지"]=true,
    ["붉은심자군 수도원 - 도서관"]=true,
    ["붉은심자군 수도원 - 무기고"]=true,
    ["붉은심자군 수도원 - 예배당"]=true,
    ["가시덩굴 구릉"]=true,
    ["울다란"]=true,
    ["줄파락"]=true,
    ["마라우돈"]=true,
    ["아탈학카르 신전"]=true,
    ["검은바위 나락"]=true,
    ["검은바위 첨탑 (하층)"]=true,
    ["검은바위 첨탑 (상층)"]=true,
    ["혈투의 전장 (동쪽)"]=true,
    ["혈투의 전장 (서쪽)"]=true,
    ["혈투의 전장 (북쪽)"]=true,
    ["스칼로만스"]=true,
    ["스트라솔름"]=true,
    -- ── TBC ───────────────────────────────────────────────────
    ["지옥불 성루"]=true,
    ["피의 용광로"]=true,
    ["으스러진 손의 전당"]=true,
    ["마나 무덤"]=true,
    ["아키나의 납골당"]=true,
    ["세데크 전당"]=true,
    ["어둠의 미궁"]=true,
    ["강제 노역소"]=true,
    ["지하수령"]=true,
    ["증기 저장고"]=true,
    ["옛 스브레드 구릉지"]=true,
    ["검은늪"]=true,
    ["알카트라즈"]=true,
    ["신록의 정원"]=true,
    ["메카르니"]=true,
    ["마법학자의 정원"]=true,
}

local function IsDungeon(zone)
    if not zone or zone == "" then return false end
    return DUNGEONS[zone] == true
end

-- ============================================================
-- 런타임 변수
-- ============================================================
local db          = nil
local myName      = nil
local initialized = false
local optPanel    = nil

-- ============================================================
-- 메시지 기본값 & 조회 함수 (전역 — PartyGreeter/BuffGreeter 공유)
-- ============================================================
MyGreeting_DEFAULT_MESSAGES = {
    morning        = "좋은아침 입니다",
    noon           = "식사들 하셨습니까? 맛점 하세요",
    welcome_new    = "{name} 님 어서오세요 환영합니다",
    welcome        = "{name} 님 어서오세요",
    rejoin         = "{name} 님 재접하셨습니다 ~리하요",
    sleep          = "{name} 님 푹쉬세요",
    dungeon        = "{name} 님 [{zone}] 무사히 돌고 득템하세요 :)",
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
local dungeonGreeted    = {} -- [이름] = zone : 이미 인사한 던전 (중복 방지)
local rosterTimer = nil
local guildCmdCooldown = {} -- [커맨드] = GetTime() : 길드 명령 중복 방지

-- ============================================================
-- 길드 채팅 전송 (모든 길드원에게 보임)
-- ============================================================
local function GG_Print(msg)
    if not msg or msg == "" then return end
    local box = ChatFrame1EditBox
    if box and box:IsVisible() then
        C_Timer.After(2, function()
            SendChatMessage(msg, "GUILD")
        end)
    else
        SendChatMessage(msg, "GUILD")
    end
end

local function GG_Send(msg, whisperTo)
    if not msg or msg == "" then return end
    if whisperTo == "LOCAL" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. msg)
    elseif whisperTo then
        local box = ChatFrame1EditBox
        if box and box:IsVisible() then
            C_Timer.After(2, function()
                SendChatMessage(msg, "WHISPER", nil, whisperTo)
            end)
        else
            SendChatMessage(msg, "WHISPER", nil, whisperTo)
        end
    else
        GG_Print(msg)
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
        for cls, n in pairs(counts) do parts[#parts + 1] = cls .. " " .. n .. "명" end
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
                    local _, _, localizedRace = GetPlayerInfoByGUID(guid)
                    if localizedRace and localizedRace ~= "" then
                        counts[localizedRace] = (counts[localizedRace] or 0) + 1
                    end
                end
            end
        end
        local parts = {}
        for race, n in pairs(counts) do parts[#parts + 1] = race .. " " .. n .. "명" end
        table.sort(parts)
        callback(parts, online)
    end)
end

local PROF_KEYWORDS = {
    "대장", "재봉", "연금", "기공", "가세", "보세", "약초", "채광", "마부", "무두", "요리", "낚시"
}

local function CollectProfessionDistribution(callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local counts = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local _, _, _, _, _, _, note, officerNote = GetGuildRosterInfo(i)
            local combined = (note or "") .. " " .. (officerNote or "")
            for _, kw in ipairs(PROF_KEYWORDS) do
                if combined:find(kw) then
                    counts[kw] = (counts[kw] or 0) + 1
                end
            end
        end
        local parts = {}
        for _, kw in ipairs(PROF_KEYWORDS) do
            if counts[kw] then
                parts[#parts + 1] = kw .. " " .. counts[kw] .. "명"
            end
        end
        callback(parts, total)
    end)
end

local GUILD_CMD_COOLDOWN_SEC = 10

-- ============================================================
-- 전문기술별 멤버 목록 수집
-- ============================================================
local PROF_CMD_KEYWORDS = {}
for _, kw in ipairs({ "대장", "재봉", "연금", "기공", "가세", "보세", "약초", "채광", "마부", "무두", "요리", "낚시" }) do
    PROF_CMD_KEYWORDS["!" .. kw] = kw
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
                if combined:find(keyword) then
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
            GG_Send(keyword .. " 접속중인 길드원 없음", whisperTo)
        else
            GG_Send(keyword .. " (" .. #members .. "명): " .. table.concat(members, "  "), whisperTo)
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
    ["!혈요정"]     = "혈요정",
    ["!인간"]       = "인간",
    ["!드워프"]     = "드워프",
    ["!나엘"]       = "나이트 엘프",
    ["!나이트엘프"] = "나이트 엘프",
    ["!노움"]       = "노움",
    ["!드레나이"]   = "드레나이",
}

local function CollectRaceMembers(raceName, callback)
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.3, function()
        local members = {}
        local total = GetNumGuildMembers()
        for i = 1, total do
            local name, _, _, level, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
            if isOnline and guid and guid ~= "" then
                local _, _, localizedRace = GetPlayerInfoByGUID(guid)
                if localizedRace == raceName then
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
            GG_Send(raceName .. " 접속중인 길드원 없음", whisperTo)
        else
            GG_Send(raceName .. " (" .. #members .. "명): " .. table.concat(members, "  "), whisperTo)
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
                        local _, _, localizedRace = GetPlayerInfoByGUID(guid)
                        if localizedRace and localizedRace ~= "" then race = localizedRace end
                    end
                    local onlineStr  = isOnline and "O 접속중" or "X 오프라인"
                    local zoneStr    = (zone and zone ~= "") and zone or "-"
                    local noteStr    = (publicNote and publicNote ~= "") and publicNote or "-"
                    local gsStr = ""
                    local gearInfo = MyGreetingDB and MyGreetingDB.gearData and MyGreetingDB.gearData[shortName]
                    if gearInfo then
                        gsStr = "  /  GS: " .. gearInfo.score
                    end
                    GG_Send(shortName .. " [" .. rankName .. "]  " .. race .. " " .. className .. "  " .. level .. "레벨  " .. onlineStr .. gsStr, whisperTo)
                    GG_Send("지역: " .. zoneStr .. "  /  쪽지: " .. noteStr, whisperTo)
                    return
                end
            end
        end
        GG_Send("[" .. targetName .. "] 길드원을 찾을 수 없습니다", whisperTo)
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
            GG_Send(className .. " 접속중인 길드원 없음", whisperTo)
        else
            GG_Send(className .. " (" .. #members .. "명): " .. table.concat(members, "  "), whisperTo)
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
    dailyHeroic = "일일 영던",
    dailyNormal = "일일 일던",
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

-- Nova World Buffs 애드온에서 오늘 일일 던전 이름을 읽어옴
local function GetNWBDailyName(key)
    if not NWB or not NWB.data then return nil end
    local id, ts, getData
    if key == "dailyNormal" then
        id, ts, getData = NWB.data.tbcDD, NWB.data.tbcDDT, function(i) return NWB:getDungeonDailyData(i) end
    elseif key == "dailyHeroic" then
        id, ts, getData = NWB.data.tbcHD, NWB.data.tbcHDT, function(i) return NWB:getHeroicDailyData(i) end
    else
        return nil
    end
    if not id or id == 0 then return nil end
    if not ts or (GetServerTime() - ts) >= 86400 then return nil end
    local ok, d = pcall(getData, id)
    if not ok or not d then return nil end
    local name = d.nameLocale or d.dungeon or "?"
    local abbrev = d.abbrev and ("(" .. d.abbrev .. ")") or ""
    return name .. " " .. abbrev
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
        GG_Send(label .. ": " .. entry.value .. "  (설정: " .. entry.setter .. ")", whisperTo)
    else
        GG_Send(label .. " 정보 없음", whisperTo)
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
            return label .. ": " .. entry.value .. "  (설정: " .. entry.setter .. ")"
        else
            return label .. ": 미등록"
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
        GG_Send("!현황 - 길드 접속 현황", whisperTo)
        GG_Send("!등급 - 등급별 목록", whisperTo)
        GG_Send("!레벨 - 레벨 분포", whisperTo)
        GG_Send("!종족 - 종족 분포", whisperTo)
        GG_Send("!직업 - 직업 분포", whisperTo)
        GG_Send("!지역 - 지역별 현황", whisperTo)
        GG_Send("!정보 [이름] - 길드원 상세 정보", whisperTo)
        GG_Send("!인던 - 던전 입장 현황", whisperTo)
        GG_Send("!전문기술 - 전문기술 분포", whisperTo)
        GG_Send("!장비 - 내 장비점수", whisperTo)
        GG_Send("!장비 [이름] - 특정 길드원 장비점수", whisperTo)
        GG_Send("!장비순위 - 전체 장비점수 순위", whisperTo)
        GG_Send("!길드[명령어] - 위 명령어를 길드창에 표시  예) !길드현황", whisperTo)
        GG_Send("─── 기타 ───", whisperTo)
        GG_Send("!도움 종족 - 종족별 멤버 검색 키워드", whisperTo)
        GG_Send("!도움 직업 - 직업별 멤버 검색 키워드", whisperTo)
        GG_Send("!도움 장비 - 장비 명령어 목록", whisperTo)
        GG_Send("!도움 전문기술 - 전문기술별 멤버 검색 키워드", whisperTo)
        GG_Send("!도움 일정 - 일정 등록/조회 방법", whisperTo)
    elseif cmd == "help_class" then
        GG_Send("직업별 멤버목록: !전사 !성기사 !사냥꾼 !도적 !사제 !주술사 !마법사 !흑마법사 !드루이드 !죽기", whisperTo)
    elseif cmd == "help_race" then
        GG_Send("종족별 멤버목록: !오크 !언데드 !타우렌 !트롤 !혈요정 !인간 !드워프 !나엘 !노움 !드레나이", whisperTo)
    elseif cmd == "help_prof" then
        GG_Send("전문기술별 멤버목록: !대장 !재봉 !연금 !기공 !가세 !보세 !약초 !채광 !마부 !무두 !요리 !낚시", whisperTo)
    elseif cmd == "help_gear" then
        GG_Send("!장비 - 내 장비점수 + 장비 목록", whisperTo)
        GG_Send("!장비 [이름] - 특정 길드원 장비점수 + 장비 목록", whisperTo)
        GG_Send("!장비순위 - 전체 장비점수 순위", whisperTo)
        GG_Send("!길드장비 / !길드장비 [이름] / !길드장비순위 - 길드창에 표시", whisperTo)
    elseif cmd == "help_daily" then
        GG_Send("일정 등록 (길드챗): !일일일던 [이름]  /  !일일영던 [이름]  /  !주간전장 [이름]", whisperTo)
        GG_Send("일정 조회: !일던  !영던  !전장  (값 없이 등록 명령어 치면 초기화)", whisperTo)
    elseif cmd == "status" then
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local total = GetNumGuildMembers()
            local online = 0
            for i = 1, total do
                local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline then online = online + 1 end
            end
            GG_Send("접속중: " .. online .. "명 / 전체: " .. total .. "명", whisperTo)
        end)
    elseif cmd == "levels" then
        C_GuildInfo.GuildRoster()
        C_Timer.After(0.3, function()
            local total = GetNumGuildMembers()
            local buckets = { [70]=0, [60]=0, [11]=0, [1]=0 }
            local online = 0
            for i = 1, total do
                local _, _, _, level, _, _, _, _, isOnline = GetGuildRosterInfo(i)
                if isOnline then
                    online = online + 1
                    if level >= 70 then
                        buckets[70] = buckets[70] + 1
                    elseif level >= 60 then
                        buckets[60] = buckets[60] + 1
                    elseif level >= 11 then
                        buckets[11] = buckets[11] + 1
                    else
                        buckets[1] = buckets[1] + 1
                    end
                end
            end
            local parts = {
                "70레벨: " .. buckets[70] .. "명",
                "60~69: "  .. buckets[60] .. "명",
                "11~59: "  .. buckets[11] .. "명",
                "1~10: "   .. buckets[1]  .. "명",
            }
            if #parts == 0 then return end
            GG_Send("레벨분포 (접속중 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "classes" then
        CollectClassDistribution(function(parts, online)
            if #parts == 0 then return end
            GG_Send("직업분포 (접속중 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "races" then
        CollectRaceDistribution(function(parts, online)
            if #parts == 0 then return end
            GG_Send("종족분포 (접속중 " .. online .. "명): " .. table.concat(parts, " / "), whisperTo)
        end)
    elseif cmd == "dungeon" then
        CollectDungeonStatus(function(dungeons)
            local parts = {}
            for zone, members in pairs(dungeons) do
                parts[#parts + 1] = zone .. " (" .. #members .. "명): " .. table.concat(members, ", ")
            end
            table.sort(parts)
            if #parts == 0 then
                GG_Send("현재 인던 중인 길드원 없음", whisperTo)
            else
                GG_Send("인던 현황 - " .. table.concat(parts, " / "), whisperTo)
            end
        end)
    elseif cmd == "profs" then
        CollectProfessionDistribution(function(parts, total)
            if #parts == 0 then
                GG_Send("전문기술 메모 없음", whisperTo)
            else
                GG_Send("전문기술 현황 (전체 " .. total .. "명): " .. table.concat(parts, " / "), whisperTo)
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
                GG_Send("접속중인 길드원 없음", whisperTo)
            else
                local delay = 0
                for _, zone in ipairs(zoneNames) do
                    local members = zones[zone]
                    table.sort(members)
                    local line = zone .. "(" .. #members .. "명): " .. table.concat(members, ", ")
                    local d, wt = delay, whisperTo
                    C_Timer.After(d, function() GG_Send(line, wt) end)
                    delay = delay + 0.6
                end
            end
        end)
    elseif cmd == "ranks" then
        local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        if num == 0 then
            GG_Send("등급 정보를 불러올 수 없습니다", whisperTo)
        else
            local parts = {}
            for i = 1, num do
                local rankName = GuildControlGetRankName(i)
                if rankName and rankName ~= "" then
                    parts[#parts + 1] = i .. ". " .. rankName
                end
            end
            GG_Send("길드 등급 (" .. num .. "개): " .. table.concat(parts, " / "), whisperTo)
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
                GG_Send("[" .. targetRank .. "] 접속중인 길드원 없음", whisperTo)
            else
                GG_Send("[" .. targetRank .. "] (" .. #parts .. "명): " .. table.concat(parts, "  "), whisperTo)
            end
        end)
    end
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
            if UnitExists("party" .. i) and UnitName("party" .. i) == name then
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
        GG_Print(msg)
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
        if name ~= myName and not prevRoster[name] then
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
        if name ~= myName and not newlyJoined[name] then
            local wasOnline = prevOnline[name]

            if isOnline and not wasOnline then
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
        if name ~= myName and currentOnline[name] then
            local prevZone = prevZones[name] or ""
            local greetEntry = dungeonGreeted[name]
            local recentlyGreeted = greetEntry and greetEntry.zone == zone
                and (GetTime() - greetEntry.time) < 7200
            if zone ~= prevZone and IsDungeon(zone) and not recentlyGreeted then
                dungeonGreeted[name] = { zone = zone, time = GetTime() }
                local n2, z2 = name, zone
                C_Timer.After(GREET_DELAY, function()
                    GG_Print(MyGreeting_GetMsg("dungeon", {name=n2, zone=z2}))
                end)
            end
            if not IsDungeon(zone) then
                dungeonGreeted[name] = nil
            end
        end
    end

    -- ── 레벨업 감지 ──────────────────────────────────────
    for name, newLevel in pairs(currentLevels) do
        if name ~= myName then
            local oldLevel = prevLevels[name]
            if oldLevel and oldLevel > 0 and newLevel > oldLevel and (newLevel - oldLevel) <= 2 and currentOnline[name] then
                ScheduleLevelUp(name, newLevel)
            end
        end
    end

    prevOnline = currentOnline
    prevLevels = currentLevels
    prevRoster = currentRoster
    prevZones  = currentZones
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
        db = MyGreetingDB


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
                if msg and msg:find(myName, 1, true) then
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
                ChatFrame_AddMessageEventFilter(ch, NameHighlightFilter)
            end
        end

        -- 옵션 패널 등록 (PLAYER_LOGIN 시점이 가장 안전)
        if optPanel then
            if Settings and Settings.RegisterCanvasLayoutCategory then
                local cat = Settings.RegisterCanvasLayoutCategory(optPanel, "myGreeting")
                Settings.RegisterAddOnCategory(cat)
            elseif InterfaceOptions_AddCategory then
                InterfaceOptions_AddCategory(optPanel)
            end
        end

        -- 정각 인사 공통 함수
        local function ScheduleDailyGreeting(targetHour, windowSec, dbKey, msgKey)
            local sentThisSession = false

            local function SendGreeting()
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
                    if isOnline and name ~= myName then
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
        lastOffline  = {}
        if db then db.knownMembers = {} end
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
        sender = sender:match("^([^%-]+)") or sender

        -- 길드 채팅 명령 감지 (본인 포함)
        local trimmed = strtrim(msg)
        local whisperTarget, whisperMsg = trimmed:match("^!귓말%s+(%S+)%s*(.-)%s*$")
        if whisperTarget then
            if sender == myName then
                local msg = (whisperMsg and whisperMsg ~= "") and whisperMsg or "안녕하세요 :)"
                SendChatMessage(msg, "WHISPER", nil, whisperTarget)
            end
        end

        local DAILY_SET = {
            ["일일일던"] = "dailyNormal",
            ["일일영던"] = "dailyHeroic",
            ["주간전장"] = "weeklyBG",
        }
        local DAILY_GET = {
            ["일던"] = "dailyNormal",
            ["영던"] = "dailyHeroic",
            ["전장"] = "weeklyBG",
        }

        local function RouteCommand(sub, wt)
            local CMD_MAP = {
                ["현황"]="status", ["레벨"]="levels", ["직업"]="classes",
                ["종족"]="races",  ["인던"]="dungeon", ["지역"]="zones",
                ["전문기술"]="profs", ["등급"]="ranks",
                ["도움"]="help", ["도움 직업"]="help_class",
                ["도움 종족"]="help_race", ["도움 전문기술"]="help_prof", ["도움 일정"]="help_daily", ["도움 장비"]="help_gear",
            }
            local setKey, setValue = sub:match("^(%S+)%s+(.+)$")

            if CMD_MAP[sub] then
                HandleGuildCommand(CMD_MAP[sub], wt)
            elseif DAILY_SET[sub] then
                -- "!일일영던" 값 없이 → 리셋
                if wt ~= "LOCAL" and db then
                    db.dailyInfo[DAILY_SET[sub]] = nil
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff40FF40[myGreeting]|r " .. DAILY_LABEL[DAILY_SET[sub]] .. " 초기화됨")
                end
            elseif setKey and DAILY_SET[setKey] then
                -- "!일일영던 마나 무덤" → 저장 (로컬 /mg 제외)
                if wt ~= "LOCAL" and db then
                    local dbKey = DAILY_SET[setKey]
                    local t = date("*t")
                    local daysSinceMon = (t.wday - 2) % 7
                    local monDate = date("%Y-%m-%d", time() - daysSinceMon * 86400)
                    db.dailyInfo[dbKey] = {
                        value     = strtrim(setValue),
                        date      = date("%Y-%m-%d"),
                        weekStart = monDate,
                        setter    = sender,
                    }
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff40FF40[myGreeting]|r " .. DAILY_LABEL[DAILY_SET[setKey]] ..
                        " 등록: " .. strtrim(setValue) .. " (설정자: " .. sender .. ")")
                end
            elseif sub == "일일" then
                HandleDailyAll(wt)
            elseif DAILY_GET[sub] then
                HandleDailyQuery(DAILY_GET[sub], wt)
            elseif CLASS_KEYWORDS["!" .. sub] then
                HandleGuildClassList(CLASS_KEYWORDS["!" .. sub], wt)
            elseif RACE_KEYWORDS["!" .. sub] then
                HandleGuildRaceList(RACE_KEYWORDS["!" .. sub], wt)
            elseif PROF_CMD_KEYWORDS["!" .. sub] then
                HandleGuildProfList(PROF_CMD_KEYWORDS["!" .. sub], wt)
            elseif sub == "장비" then
                if MyGreeting_GetGearScore then MyGreeting_GetGearScore(sender, wt) end
            elseif sub == "장비순위" then
                if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank(wt) end
            else
                local gearT = sub:match("^장비 (.+)$")
                if gearT then
                    if MyGreeting_GetGearScore then MyGreeting_GetGearScore(strtrim(gearT), wt) end
                else
                    local infoT = sub:match("^정보%s+(.+)$")
                    if infoT then HandleGuildCharInfo(infoT, wt) end
                    local rankT = sub:match("^등급%s+(.+)$")
                    if rankT then HandleGuildCommand("rank:" .. strtrim(rankT), wt) end
                end
            end
        end

        -- !길드X → 길드챗으로 출력
        local guildSub = trimmed:match("^!길드(.+)$")
        if guildSub then
            RouteCommand(guildSub, nil)
        end

        -- !X → 친 사람 귓말로 출력 (기본)
        local plainSub = trimmed:match("^!(.+)$")
        if plainSub and not guildSub then
            RouteCommand(plainSub, sender)
        end

        if sender == myName then return end

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
            lower:find("이만 가겠") or lower:find("이만가겠")

        if isSleepMsg then
            local s = sender
            C_Timer.After(GREET_DELAY, function()
                GG_Print(MyGreeting_GetMsg("sleep", {name=s}))
            end)
        end

        -- 내 캐릭명 언급 감지
        if myName and msg:find(myName) then
            ShowMentionAlert(sender, msg)
        end

    end

end)

-- ============================================================
-- 슬래시 커맨드
-- ============================================================
SLASH_MYGREETING1 = "/mg"
SLASH_MYGREETING2 = "/mygreeting"
SLASH_MYGREETING3 = "/엠지"

SlashCmdList["MYGREETING"] = function(msg)
    msg = strtrim(msg or "")
    local lower = strlower(msg)

    if lower == "help" or lower == "" then
        local L = "LOCAL"
        GG_Send("─── 기본 ───", L)
        GG_Send("/mg reset - 신규 목록 초기화", L)
        GG_Send("/mg remove [이름] - 특정 멤버 신규 처리", L)
        GG_Send("/mg status - 애드온 상태", L)
        GG_Send("/mg db - 부캐 DB 출력", L)
        GG_Send("─── 조회 (나만 보임) ───", L)
        GG_Send("/mg 현황 - 길드 접속 현황", L)
        GG_Send("/mg 등급 [등급명] - 등급별 목록", L)
        GG_Send("/mg 레벨 - 레벨 분포", L)
        GG_Send("/mg 종족 - 종족 분포", L)
        GG_Send("/mg 직업 - 직업 분포", L)
        GG_Send("/mg 지역 - 지역별 현황", L)
        GG_Send("/mg 정보 [이름] - 길드원 상세 정보", L)
        GG_Send("/mg 인던 - 던전 입장 현황", L)
        GG_Send("/mg 전문기술 - 전문기술 분포", L)
        GG_Send("/mg 사제 / 오크 / 무두 - 직업·종족·전문기술 직접 검색", L)
        GG_Send("─── 장비 ───", L)
        GG_Send("/mg 장비 - 내 장비점수 + 장비 목록", L)
        GG_Send("/mg 장비 [이름] - 특정 길드원 장비점수 + 장비 목록", L)
        GG_Send("/mg 장비순위 - 길드원 전체 장비점수 순위", L)
        GG_Send("/mg 장비초기화 - 장비 데이터 전체 삭제", L)
        GG_Send("─── 길드챗 (!길드[명령어] - 길드창에 표시) ───", L)
        GG_Send("!현황 / !레벨 / !직업 / !종족 / !인던 / !지역 / !전문기술 / !등급", L)
        GG_Send("!정보 [이름] - 길드원 상세 정보", L)
        GG_Send("!장비 - 내 장비점수", L)
        GG_Send("!장비 [이름] - 특정 길드원 장비점수", L)
        GG_Send("!장비순위 - 전체 장비점수 순위", L)
        GG_Send("!도움 - 길드챗 도움말", L)
        GG_Send("─── 기타 ───", L)
        GG_Send("!도움 종족 - 종족별 멤버 검색 키워드", L)
        GG_Send("!도움 직업 - 직업별 멤버 검색 키워드", L)
        GG_Send("!도움 장비 - 장비 명령어 목록", L)
        GG_Send("!도움 전문기술 - 전문기술별 멤버 검색 키워드", L)
        GG_Send("!도움 일정 - 일정 등록/조회 방법", L)

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
        local me = UnitName("player")
        me = me and (me:match("^([^%-]+)") or me)
        if me and MyGreeting_GetGearScore then MyGreeting_GetGearScore(me, "LOCAL") end

    elseif msg == "장비순위" then
        if MyGreeting_PrintGearRank then MyGreeting_PrintGearRank("LOCAL") end

    elseif msg == "장비초기화" then
        if MyGreetingDB then MyGreetingDB.gearData = {} end
        GG_Send("장비 데이터 초기화 완료", "LOCAL")

    elseif msg == "장비디버그" then
        if MyGreeting_GearDebug then MyGreeting_GearDebug() end

    elseif msg == "장비디버그온" then
        MyGreeting_GearDebugMode(true)
        GG_Send("장비 디버그 모드 켜짐 — 타겟 바꿀 때마다 로그 출력", "LOCAL")

    elseif msg == "장비디버그오프" then
        MyGreeting_GearDebugMode(false)
        GG_Send("장비 디버그 모드 꺼짐", "LOCAL")

    elseif msg:find("^장비 ") then
        local target = strtrim(msg:sub(#"장비 " + 1))
        if target ~= "" and MyGreeting_GetGearScore then
            MyGreeting_GetGearScore(target, "LOCAL")
        end

    elseif lower == "db" then
        if MyGreeting_PrintAltDB then MyGreeting_PrintAltDB() end

    elseif lower == "status" then
        local count = 0
        if db then for _ in pairs(db.knownMembers) do count = count + 1 end end
        GG_Send("초기화: " .. (initialized and "완료" or "대기중"), "LOCAL")
        GG_Send("기존 멤버 수: " .. count, "LOCAL")
        GG_Send("내 이름: " .. (myName or "?"), "LOCAL")

    elseif lower == "config" or lower == "옵션" then
        InterfaceOptionsFrame_OpenToCategory("myGreeting")

    else
        local CMD_MAP = {
            ["현황"]="status", ["레벨"]="levels", ["직업"]="classes",
            ["종족"]="races",  ["인던"]="dungeon", ["지역"]="zones",
            ["전문기술"]="profs", ["등급"]="ranks",
            ["도움"]="help", ["도움 직업"]="help_class",
            ["도움 종족"]="help_race", ["도움 전문기술"]="help_prof", ["도움 장비"]="help_gear",
        }
        local mapped = CMD_MAP[msg]
        local SL_DAILY_GET = { ["일던"]="dailyNormal", ["영던"]="dailyHeroic", ["전장"]="weeklyBG" }
        if mapped then
            HandleGuildCommand(mapped, "LOCAL")
        elseif msg == "일일" then
            HandleDailyAll("LOCAL")
        elseif SL_DAILY_GET[msg] then
            HandleDailyQuery(SL_DAILY_GET[msg], "LOCAL")
        elseif CLASS_KEYWORDS["!" .. msg] then
            HandleGuildClassList(CLASS_KEYWORDS["!" .. msg], "LOCAL")
        elseif RACE_KEYWORDS["!" .. msg] then
            HandleGuildRaceList(RACE_KEYWORDS["!" .. msg], "LOCAL")
        elseif PROF_CMD_KEYWORDS["!" .. msg] then
            HandleGuildProfList(PROF_CMD_KEYWORDS["!" .. msg], "LOCAL")
        else
            local infoT = msg:match("^정보%s+(.+)$")
            if infoT then
                HandleGuildCharInfo(infoT, "LOCAL")
            else
                local rankT = msg:match("^등급%s+(.+)$")
                if rankT then
                    HandleGuildCommand("rank:" .. strtrim(rankT), "LOCAL")
                else
                    GG_Send("알 수 없는 명령어. /mg help", "LOCAL")
                end
            end
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
    { key="dungeon",       label="던전 입장",        hint="{name} {zone}" },
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
local optSaveBtn = CreateFrame("Button", nil, optPanel, "GameMenuButtonTemplate")
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
local optDefaultBtn = CreateFrame("Button", nil, optPanel, "GameMenuButtonTemplate")
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

