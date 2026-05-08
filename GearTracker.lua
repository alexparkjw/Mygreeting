-- ============================================================
-- GearTracker.lua
-- 길드원 장비점수 자동 수집 및 조회
-- ============================================================

local GEAR_SLOTS = { 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local SLOT_NAMES = {
    [1]="머리", [2]="목걸이", [3]="어깨", [4]="망토", [5]="가슴",
    [8]="손목", [9]="장갑", [10]="허리", [11]="다리", [12]="신발",
    [13]="반지1", [14]="반지2", [15]="장신구1", [16]="장신구2",
    [17]="주무기", [18]="보조", [19]="원거리",
}

local INSPECT_COOLDOWN_SEC = 60

-- 클래스별 특성 탭 이름 (GetTalentTabInfo 가 이름을 못 돌려줄 때 폴백)
local CLASS_SPECS = {
    WARRIOR     = {"무기", "분노", "방어"},
    PALADIN     = {"신성", "방어", "응징"},
    HUNTER      = {"야수술", "사격술", "생존"},
    ROGUE       = {"암살", "전투", "강도"},
    PRIEST      = {"훈육", "신성", "암흑"},
    SHAMAN      = {"원소", "고양", "복원"},
    MAGE        = {"비전", "냉기", "불"},
    WARLOCK     = {"고통", "악마학", "파멸"},
    DRUID       = {"조화", "야성", "회복"},
    DEATHKNIGHT = {"혈기", "냉기", "부정"},
}

local inspecting  = nil
local cooldowns   = {}

local function IsGuildMember(name)
    local total = GetNumGuildMembers()
    for i = 1, total do
        local n = GetGuildRosterInfo(i)
        if n then
            n = n:match("^([^%-]+)") or n
            if n == name then return true end
        end
    end
    return false
end

local function GetGearScoreFromCache(unit)
    if not GEAR_SCORE_CACHE then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local cache = GEAR_SCORE_CACHE[guid]
    if not cache then return nil end
    return cache[1], cache[2]  -- GearScore, 평균iLvl
end

local function CollectGear(unit)
    local gs = GetGearScoreFromCache(unit)
    if not gs then return nil, nil end

    local items = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, _, quality, ilvl = GetItemInfo(link)
            if ilvl and ilvl > 0 then
                items[#items + 1] = { slot = slot, link = link, ilvl = ilvl, quality = quality }
            end
        end
    end

    return math.floor(gs), items
end

local function ReadTalentTab(tabIndex, isInspect, group)
    local ok, r1, r2, r3, r4, r5
    if group then
        ok, r1, r2, r3, r4, r5 = pcall(GetTalentTabInfo, tabIndex, isInspect, false, group)
    else
        ok, r1, r2, r3, r4, r5 = pcall(GetTalentTabInfo, tabIndex, isInspect)
    end
    if not ok then
        ok, r1, r2, r3, r4, r5 = pcall(GetTalentTabInfo, tabIndex)
    end
    if not ok then return nil, 0 end

    -- 이 클라이언트에서는 위치1이 텍스처ID(숫자)일 수 있으므로 문자열 위치를 탐색
    local name = (type(r1)=="string" and #r1>0 and r1)
              or (type(r2)=="string" and #r2>0 and r2) or nil

    -- 재능 포인트: 0~119 범위의 숫자를 탐색 (텍스처ID는 보통 더 크거나 범위 밖)
    local points = 0
    local rvals = {r1, r2, r3, r4, r5}
    for i = 1, 5 do
        local v = rvals[i]
        if type(v) == "number" and v >= 0 and v < 120 then
            points = v
            break
        end
    end

    -- 폴백: GetNumTalents/GetTalentInfo 로 직접 집계
    if points == 0 and GetNumTalents then
        local ok2, num
        if group then
            ok2, num = pcall(GetNumTalents, tabIndex, isInspect, false, group)
        else
            ok2, num = pcall(GetNumTalents, tabIndex, isInspect)
        end
        if ok2 and num and num > 0 then
            for j = 1, num do
                local ok3, _, _, _, _, rank
                if group then
                    ok3, _, _, _, _, rank = pcall(GetTalentInfo, tabIndex, j, isInspect, false, group)
                else
                    ok3, _, _, _, _, rank = pcall(GetTalentInfo, tabIndex, j, isInspect)
                end
                if ok3 and rank then points = points + rank end
            end
        end
    end

    return name, points
end

local function GetSpecInfo(isInspect, unit)
    if not GetNumTalentTabs then return nil end

    local numTabs = GetNumTalentTabs() or 0
    if numTabs == 0 then return nil end

    local _, classFile = UnitClass(unit or (isInspect and "target") or "player")
    local specNames = classFile and CLASS_SPECS[classFile]

    local numGroups   = (GetNumTalentGroups and GetNumTalentGroups(isInspect)) or 1
    local activeGroup = (GetActiveTalentGroup and GetActiveTalentGroup(isInspect)) or 1

    local specs = {}
    for g = 1, numGroups do
        local maxPoints, specName = -1, nil
        local parts = {}
        for i = 1, numTabs do
            local tabName, points = ReadTalentTab(i, isInspect, numGroups > 1 and g or nil)
            points = points or 0
            parts[#parts + 1] = tostring(points)
            if points > maxPoints then
                maxPoints = points
                specName = tabName or (specNames and specNames[i]) or ("특성" .. i)
            end
        end
        specs[g] = { name = specName or "?", points = table.concat(parts, "/"), active = (g == activeGroup) }
    end
    return specs
end

local function SpecToString(specs)
    if not specs or type(specs) ~= "table" then return "" end
    local ok, result = pcall(function()
        local parts = {}
        for _, s in ipairs(specs) do
            if type(s) == "table" and s.name then
                local mark = s.active and "★" or "☆"
                parts[#parts + 1] = mark .. s.name .. " " .. (s.points or "")
            end
        end
        if #parts == 0 then return "" end
        return "  [" .. table.concat(parts, " / ") .. "]"
    end)
    return ok and result or ""
end

local gearDebugMode = false

local function TryInspect(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end

    local name = UnitName(unit)
    if not name then return end
    name = name:match("^([^%-]+)") or name

    if gearDebugMode then
        local canInspect = CanInspect(unit)
        local isGuild    = IsGuildMember(name)
        local isBusy     = inspecting ~= nil
        local now        = GetTime()
        local coolLeft   = cooldowns[name] and math.floor(INSPECT_COOLDOWN_SEC - (now - cooldowns[name])) or 0
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffFFFF00[장비디버그]|r " .. name ..
            "  canInspect=" .. tostring(canInspect) ..
            "  isGuild=" .. tostring(isGuild) ..
            "  busy=" .. tostring(isBusy) ..
            "  cooldown=" .. coolLeft .. "s")
    end

    if inspecting then return end
    if not CanInspect(unit) then return end

    local now = GetTime()
    if cooldowns[name] and (now - cooldowns[name]) < INSPECT_COOLDOWN_SEC then return end

    inspecting = { unit = unit, name = name, guid = UnitGUID(unit) }
    cooldowns[name] = now
    NotifyInspect(unit)
end

local function ScanGroup()
    local prefix = IsInRaid() and "raid" or "party"
    local max    = IsInRaid() and 40 or 4
    for i = 1, max do
        local u = prefix .. i
        if UnitExists(u) then
            local idx = i
            C_Timer.After(idx * 2, function()
                TryInspect(prefix .. idx)
            end)
        end
    end
end

-- ============================================================
-- 이벤트
-- ============================================================
local function CollectSelf(retry)
    local name = UnitName("player")
    if not name then return end
    name = name:match("^([^%-]+)") or name
    local score, items = CollectGear("player")
    local specs = GetSpecInfo(false, "player")
    if not score then
        if (retry or 0) < 5 then
            C_Timer.After(5, function() CollectSelf((retry or 0) + 1) end)
        end
        return
    end
    if not MyGreetingDB then return end
    if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end
    MyGreetingDB.gearData[name] = { score = score, date = date("%m/%d %H:%M"), specs = specs, items = items }
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 내 장비점수 수집완료: " .. score)
end

function MyGreeting_GearDebugMode(on)
    gearDebugMode = on
end

function MyGreeting_GearDebug()
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not next(data) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r gearData 비어있음")
        return
    end
    for name, info in pairs(data) do
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. name .. "] score=" .. tostring(info.score) .. " date=" .. tostring(info.date))
    end
end

local gearFrame = CreateFrame("Frame", "MyGreetingGearFrame")
gearFrame:RegisterEvent("INSPECT_READY")
gearFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
gearFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
gearFrame:RegisterEvent("PLAYER_LOGIN")
gearFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

gearFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "INSPECT_READY" then
        local guid = ...
        if gearDebugMode then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffFFFF00[장비디버그]|r INSPECT_READY guid=" .. tostring(guid) ..
                "  inspecting=" .. tostring(inspecting and inspecting.name) ..
                "  match=" .. tostring(inspecting and inspecting.guid == guid))
        end
        if not inspecting then return end
        if inspecting.guid ~= guid then
            inspecting = nil
            return
        end

        local score, items = CollectGear(inspecting.unit)
        local specs = GetSpecInfo(true, inspecting.unit)
        local name  = inspecting.name
        inspecting  = nil

        if score then
            if not MyGreetingDB then return end
            if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end
            MyGreetingDB.gearData[name] = { score = score, date = date("%m/%d %H:%M"), specs = specs, items = items }
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff40FF40[myGreeting]|r " .. name .. " 장비점수 수집: " .. score .. SpecToString(specs))
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        TryInspect("target")

    elseif event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(3, ScanGroup)

    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, CollectSelf)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(1, CollectSelf)
    end
end)

-- ============================================================
-- 출력 헬퍼
-- ============================================================
local function GearSend(msg, whisperTo)
    if whisperTo == "LOCAL" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. msg)
    elseif whisperTo then
        SendChatMessage(msg, "WHISPER", nil, whisperTo)
    else
        SendChatMessage(msg, "GUILD")
    end
end

-- ============================================================
-- 조회 함수 (슬래시 커맨드 및 길드챗 명령어에서 호출)
-- whisperTo: "LOCAL" = 나만 보임 / 플레이어명 = 귓말 / nil = 길드챗
-- ============================================================
function MyGreeting_PrintGearRank(whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not next(data) then
        GearSend("수집된 데이터 없음 — 길드원 타겟 또는 파티 맺으면 자동 수집됩니다", whisperTo)
        return
    end

    local list = {}
    for name, info in pairs(data) do
        if IsGuildMember(name) then
            list[#list + 1] = { name = name, score = info.score, date = info.date, specs = info.specs }
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)

    local wt = whisperTo
    if wt == "LOCAL" then
        GearSend("길드원 장비점수 순위 (" .. #list .. "명):", wt)
        for i, e in ipairs(list) do
            GearSend(i .. ". " .. e.name .. "  " .. e.score .. "점" .. SpecToString(e.specs) .. "  (" .. e.date .. ")", wt)
        end
    else
        local interval = (wt ~= nil) and 0.4 or 1.5
        GearSend("길드원 장비점수 순위 (" .. #list .. "명):", wt)
        for i, e in ipairs(list) do
            local line = i .. ". " .. e.name .. "  " .. e.score .. "점" .. SpecToString(e.specs) .. "  (" .. e.date .. ")"
            local d = i * interval
            C_Timer.After(d, function() GearSend(line, wt) end)
        end
    end
end

local function ItemDisplay(item, isLocal)
    local slotName = SLOT_NAMES[item.slot] or "?"
    local ilvl     = "[" .. item.ilvl .. "]"
    if isLocal and item.link then
        return slotName .. " " .. ilvl .. " " .. item.link
    else
        local name = item.link and (item.link:match("|h%[(.-)%]|h") or item.link) or (item.name or "?")
        return slotName .. " " .. ilvl .. " " .. name
    end
end

local function PrintItems(items, whisperTo)
    if not items or #items == 0 then return end
    local isLocal  = (whisperTo == "LOCAL")
    local interval = isLocal and 0 or 0.4
    for i, item in ipairs(items) do
        local line = ItemDisplay(item, isLocal)
        if interval == 0 then
            GearSend(line, whisperTo)
        else
            C_Timer.After(i * interval, function() GearSend(line, whisperTo) end)
        end
    end
end

function MyGreeting_GetGearScore(name, whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not data[name] then
        GearSend(name .. " 데이터 없음", whisperTo)
        return
    end
    local info = data[name]
    GearSend(name .. "  장비점수: " .. info.score .. "점" .. SpecToString(info.specs) .. "  (수집: " .. info.date .. ")", whisperTo)

    if not info.items then
        -- 구버전 데이터 — 본인이면 즉시 재수집
        local myName = UnitName("player")
        myName = myName and (myName:match("^([^%-]+)") or myName)
        if name == myName then
            local score, items = CollectGear("player")
            if score and items then
                info.items = items
                info.score = score
                info.date  = date("%m/%d %H:%M")
                PrintItems(items, whisperTo)
            end
        else
            GearSend("  (장비 목록 없음 — 근처에서 타겟하면 자동 갱신)", whisperTo)
        end
    else
        PrintItems(info.items, whisperTo)
    end
end
