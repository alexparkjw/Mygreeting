-- ============================================================
-- GearTracker.lua
-- 길드원 장비점수 자동 수집 및 조회
-- ============================================================

local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT_NAMES = {
    [1]="머리", [2]="목걸이", [3]="어깨", [5]="가슴",
    [6]="허리", [7]="다리", [8]="발", [9]="손목", [10]="장갑",
    [11]="반지1", [12]="반지2", [13]="장신구1", [14]="장신구2",
    [15]="등", [16]="주장비", [17]="보조장비", [18]="원거리",
}
local SKIP_SLOTS = { [4] = true, [19] = true }  -- 속옷, 휘장 제외

local INSPECT_COOLDOWN_SEC = 30

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

local inspecting   = nil
local cooldowns    = {}
local lastTryTime  = {}  -- 중복 호출 방지용 (1초 이내 동일 유닛 재호출 무시)
local scanPending  = false

local function FindUnit(guid)
    if UnitGUID("target") == guid then return "target" end
    local prefix = IsInRaid() and "raid" or "party"
    local max    = IsInRaid() and 40 or 4
    for i = 1, max do
        if UnitGUID(prefix .. i) == guid then return prefix .. i end
    end
    return nil
end


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

-- 반환: ilvl(평균), gs(기어스코어 or nil), items
local function CollectGear(unit)
    local items = {}
    local totalIlvl, count = 0, 0
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, _, quality, ilvl = GetItemInfo(link)
            items[#items + 1] = { slot = slot, link = link, ilvl = ilvl or 0, quality = quality }
            if ilvl and ilvl > 0 then
                totalIlvl = totalIlvl + ilvl
                count = count + 1
            end
        end
    end

    if count == 0 then return nil, nil, nil end

    local avgIlvl = math.floor(totalIlvl / count)
    local raw = GetGearScoreFromCache(unit)
    local gs = (raw and raw > 0) and math.floor(raw) or nil
    return avgIlvl, gs, items
end

local function ScoreStr(info)
    local gs = info.gs and tostring(info.gs) or "?"
    return "ilvl:" .. tostring(info.ilvl) .. "(gs:" .. gs .. ")"
end

local function ItemDisplay(item)
    local slotName = SLOT_NAMES[item.slot] or "?"
    local ilvl     = "[" .. item.ilvl .. "]"
    if item.link then
        return slotName .. " " .. ilvl .. " " .. item.link
    else
        return slotName .. " " .. ilvl .. " " .. (item.name or "?")
    end
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

    local pf = UnitFactionGroup("player")
    local uf = UnitFactionGroup(unit)
    if pf and uf and pf ~= uf then return end

    local now = GetTime()
    if lastTryTime[name] and (now - lastTryTime[name]) < 1 then return end
    lastTryTime[name] = now

    if gearDebugMode then
        local canInspect = CanInspect(unit)
        local isBusy     = inspecting ~= nil
        local now        = GetTime()
        local coolLeft   = cooldowns[name] and math.floor(INSPECT_COOLDOWN_SEC - (now - cooldowns[name])) or 0
        local cached     = MyGreetingDB and MyGreetingDB.gearData and MyGreetingDB.gearData[name]
        local cacheStr   = cached and (ScoreStr(cached) .. " (" .. cached.date .. ")") or "없음"

        local skip = nil
        if isBusy then
            skip = "수집중 (busy)"
        elseif not canInspect then
            local pf = UnitFactionGroup("player")
            local uf = UnitFactionGroup(unit)
            if pf and uf and pf ~= uf then
                skip = "inspect 불가 (타진영)"
            else
                skip = "inspect 불가 (범위 밖)"
            end
        elseif coolLeft > 0 then
            skip = "쿨다운 " .. coolLeft .. "s"
        end

        local status = skip and ("|cffFF6060스킵: " .. skip .. "|r") or "|cff40FF40수집 시도→|r"
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffFFFF00[장비디버그]|r " .. name ..
            "  캐시=" .. cacheStr ..
            "  " .. status)
    end

    -- GearScore가 이미 캐시를 채운 경우 점수 즉시 저장, 아이템은 inspect로 보완
    local ilvl, gs, items = CollectGear(unit)
    if ilvl then
        if not MyGreetingDB then return end
        if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end
        local specs = GetSpecInfo(false, unit)
        -- 아이템 목록이 비어있으면 inspect도 진행해서 목록 채움
        if items and #items > 0 then
            local classDisplay = UnitClass(unit)
            MyGreetingDB.gearData[name] = { ilvl = ilvl, gs = gs, date = date("%m/%d %H:%M"), specs = specs, items = items, class = classDisplay }
            if gearDebugMode then
                local saved = MyGreetingDB.gearData[name]
                if unit == "target" then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[장비디버그]|r DB저장: " .. name .. "  " .. ScoreStr(saved) .. SpecToString(specs))
                    for _, item in ipairs(saved.items or {}) do
                        if not SKIP_SLOTS[item.slot] then
                            DEFAULT_CHAT_FRAME:AddMessage(ItemDisplay(item))
                        end
                    end
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[장비디버그]|r " .. name .. " 완료: " .. ilvl .. SpecToString(specs))
            end
            return
        end
        -- 아이템 목록 없으면 inspect로 계속 진행
    end

    if inspecting then return end
    if not CanInspect(unit) then return end

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
            C_Timer.After(idx * 3, function()
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
    local ilvl, gs, items = CollectGear("player")
    local specs = GetSpecInfo(false, "player")
    if not ilvl then
        if (retry or 0) < 5 then
            C_Timer.After(5, function() CollectSelf((retry or 0) + 1) end)
        end
        return
    end
    if not MyGreetingDB then return end
    if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end
    local classDisplay = UnitClass("player")
    MyGreetingDB.gearData[name] = { ilvl = ilvl, gs = gs, date = date("%m/%d %H:%M"), specs = specs, items = items, class = classDisplay }
    if gearDebugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 내 장비 수집완료: " .. ilvl)
    end
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
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. name .. "] " .. ScoreStr(info) .. " date=" .. tostring(info.date))
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
        if not inspecting then return end
        if gearDebugMode then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffFFFF00[장비디버그]|r INSPECT_READY " .. inspecting.name ..
                "  match=" .. tostring(inspecting.guid == guid))
        end
        if inspecting.guid ~= guid then
            inspecting = nil
            return
        end

        local savedGuid  = inspecting.guid
        local name       = inspecting.name
        local fromTarget = (inspecting.unit == "target")
        inspecting = nil

        local function TrySave(retry)
            local unit = FindUnit(savedGuid)
            local ilvl, gs, items, specs
            local classDisplay
            if unit then
                ilvl, gs, items = CollectGear(unit)
                specs = GetSpecInfo(true, unit)
                classDisplay = UnitClass(unit)
            end
            if ilvl then
                if not MyGreetingDB then return end
                if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end
                MyGreetingDB.gearData[name] = { ilvl = ilvl, gs = gs, date = date("%m/%d %H:%M"), specs = specs, items = items, class = classDisplay }
                if gearDebugMode then
                    if fromTarget then
                        local saved = MyGreetingDB.gearData[name]
                        DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[장비디버그]|r DB저장: " .. name .. "  " .. ScoreStr(saved) .. SpecToString(specs))
                        for _, item in ipairs(saved.items or {}) do
                            DEFAULT_CHAT_FRAME:AddMessage(ItemDisplay(item))
                        end
                    end
                    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[장비디버그]|r " .. name .. " 완료: " .. ilvl .. SpecToString(specs))
                end
            elseif retry > 0 then
                if gearDebugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00[장비디버그]|r " .. name .. " 대기중 (재시도 " .. retry .. ")")
                end
                C_Timer.After(1, function() TrySave(retry - 1) end)
            else
                if gearDebugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffFF4040[장비디버그]|r " .. name .. " 실패 (캐시 없음)")
                end
            end
        end
        TrySave(5)

    elseif event == "PLAYER_TARGET_CHANGED" then
        TryInspect("target")

    elseif event == "GROUP_ROSTER_UPDATE" then
        if not scanPending then
            scanPending = true
            C_Timer.After(3, function()
                scanPending = false
                ScanGroup()
            end)
        end

    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, CollectSelf)
        C_Timer.After(5, function()
            local data = MyGreetingDB and MyGreetingDB.gearData
            if not data then return end
            C_GuildInfo.GuildRoster()
            C_Timer.After(0.5, function()
                local total = GetNumGuildMembers()
                local guildClassMap = {}
                for i = 1, total do
                    local n, _, _, _, classDisplay = GetGuildRosterInfo(i)
                    if n then
                        n = n:match("^([^%-]+)") or n
                        guildClassMap[n] = classDisplay
                    end
                end
                for n, info in pairs(data) do
                    if not info.class and guildClassMap[n] then
                        info.class = guildClassMap[n]
                    end
                end
            end)
        end)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(1, CollectSelf)
    end
end)

-- ============================================================
-- 출력 헬퍼
-- ============================================================
local function GearSend(msg, whisperTo)
    if whisperTo ~= "LOCAL" and UnitIsAFK("player") then
        msg = "<자리비움> " .. msg
    end
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
-- guildOnly=true면 길드원만, false/nil이면 수집된 전체
-- startFrom: 시작 순위 (기본 1), 10개씩 표시
-- classFilter: 한글 직업명 (예: "전사") — 해당 직업만
-- classLabel: 출력용 직업명 (보통 classFilter와 동일)
function MyGreeting_PrintGearRank(whisperTo, guildOnly, startFrom, classFilter, classLabel)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not next(data) then
        GearSend("수집된 데이터 없음 — 길드원 타겟 또는 파티 맺으면 자동 수집됩니다", whisperTo)
        return
    end

    local list = {}
    for name, info in pairs(data) do
        local passGuild = not guildOnly or IsGuildMember(name)
        local passClass = not classFilter or info.class == classFilter
        if passGuild and passClass then
            local sortKey = info.gs or info.ilvl or info.score or 0
            list[#list + 1] = { name = name, info = info, sortKey = sortKey }
        end
    end
    table.sort(list, function(a, b) return a.sortKey > b.sortKey end)

    local RANK_LIMIT = 10
    local total = #list
    local from = math.max(1, tonumber(startFrom) or 1)
    local to   = math.min(total, from + RANK_LIMIT - 1)

    if from > total then
        GearSend("해당 범위에 데이터 없음 (전체 " .. total .. "명)", whisperTo)
        return
    end

    local title
    if classFilter then
        title = (classLabel or classFilter) .. " 장비점수 순위"
    elseif guildOnly then
        title = "길드원 장비점수 순위"
    else
        title = "전체 장비점수 순위"
    end
    local suffix = " (" .. from .. "-" .. to .. "/" .. total .. "명)"
    local wt = whisperTo
    if wt == "LOCAL" then
        GearSend(title .. suffix .. ":", wt)
        for i = from, to do
            local e = list[i]
            GearSend(i .. ". " .. e.name .. "  " .. ScoreStr(e.info) .. SpecToString(e.info.specs) .. "  (" .. (e.info.date or "?") .. ")", wt)
        end
    else
        local interval = (wt ~= nil) and 0.4 or 1.5
        GearSend(title .. suffix .. ":", wt)
        local idx = 0
        for i = from, to do
            local e = list[i]
            local line = i .. ". " .. e.name .. "  " .. ScoreStr(e.info) .. SpecToString(e.info.specs) .. "  (" .. (e.info.date or "?") .. ")"
            idx = idx + 1
            local d = idx * interval
            C_Timer.After(d, function() GearSend(line, wt) end)
        end
    end
end

local function PrintItems(items, whisperTo)
    if not items or #items == 0 then return end

    local filtered = {}
    for _, item in ipairs(items) do
        if not SKIP_SLOTS[item.slot] then
            filtered[#filtered + 1] = item
        end
    end
    if #filtered == 0 then return end

    if whisperTo == "LOCAL" then
        for _, item in ipairs(filtered) do
            GearSend(ItemDisplay(item), whisperTo)
        end
    else
        -- 3개씩 묶어서 한 메시지로 전송
        local msgIdx = 0
        local i = 1
        while i <= #filtered do
            local parts = {}
            for j = i, math.min(i + 2, #filtered) do
                parts[#parts + 1] = ItemDisplay(filtered[j])
            end
            local line = table.concat(parts, " / ")
            msgIdx = msgIdx + 1
            C_Timer.After(msgIdx * 0.8, function() GearSend(line, whisperTo) end)
            i = i + 3
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
    GearSend(name .. "  장비점수: " .. ScoreStr(info) .. SpecToString(info.specs) .. "  (수집: " .. (info.date or "?") .. ")", whisperTo)

    if not info.items or #info.items == 0 then
        -- 구버전 데이터 — 본인이면 즉시 재수집
        local myName = UnitName("player")
        myName = myName and (myName:match("^([^%-]+)") or myName)
        if name == myName then
            local ilvl, gs, items = CollectGear("player")
            if ilvl and items then
                info.items = items
                info.ilvl  = ilvl
                info.gs    = gs
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

function MyGreeting_GetGearSlot(name, slotIds, whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not data[name] then
        GearSend(name .. " 데이터 없음", whisperTo)
        return
    end
    local info = data[name]
    if not info.items or #info.items == 0 then
        GearSend(name .. " 장비 목록 없음 — 근처에서 타겟하면 자동 갱신", whisperTo)
        return
    end
    local slotSet = {}
    for _, s in ipairs(slotIds) do slotSet[s] = true end
    local found = false
    for _, item in ipairs(info.items) do
        if slotSet[item.slot] then
            GearSend(name .. "  " .. ItemDisplay(item), whisperTo)
            found = true
        end
    end
    if not found then
        GearSend(name .. " 해당 슬롯 장비 없음", whisperTo)
    end
end
