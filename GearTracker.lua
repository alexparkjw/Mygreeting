-- ============================================================
-- GearTracker.lua
-- 길드원 장비점수 API 임포트 및 조회
-- ============================================================

local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT_NAMES = {
    [1]="머리", [2]="목걸이", [3]="어깨", [5]="가슴",
    [6]="허리", [7]="다리", [8]="발", [9]="손목", [10]="장갑",
    [11]="반지1", [12]="반지2", [13]="장신구1", [14]="장신구2",
    [15]="등", [16]="주장비", [17]="보조장비", [18]="원거리",
}
local SKIP_SLOTS = { [4] = true, [19] = true }  -- 속옷, 휘장 제외

local GearSend    -- 전방 선언 (MyGreeting_GearStatus에서 참조)

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

-- 두 특성 중 점수 높은 것 반환, 구버전 데이터도 처리
local function GetBestSpec(info)
    local best = nil
    for _, key in ipairs({"spec1", "spec2"}) do
        local spec = info[key]
        if spec then
            local score = spec.gs or spec.ilvl or 0
            if not best or score > (best.gs or best.ilvl or 0) then
                best = spec
            end
        end
    end
    return best or (info.ilvl and info or nil)
end

function MyGreeting_GearStatus(whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    local total = 0
    local guildCount = 0
    local totalIlvl = 0
    local maxIlvl, maxName = 0, nil
    local classCounts = {}
    local latest = nil

    if data then
        for name, info in pairs(data) do
            local isGuild = IsGuildMember(name)
            local hasSpec = false
            for _, key in ipairs({"spec1", "spec2"}) do
                local spec = info[key]
                if spec then
                    hasSpec = true
                    total = total + 1
                    if isGuild then guildCount = guildCount + 1 end
                    local score = spec.gs or spec.ilvl or 0
                    totalIlvl = totalIlvl + score
                    if score > maxIlvl then
                        maxIlvl = score
                        maxName = name .. "(" .. (spec.name or "?") .. ")"
                    end
                    if not latest or (spec.date or "") > latest then latest = spec.date end
                end
            end
            if not hasSpec and info.ilvl then  -- 구버전 폴백
                total = total + 1
                if isGuild then guildCount = guildCount + 1 end
                local score = info.gs or info.ilvl or 0
                totalIlvl = totalIlvl + score
                if score > maxIlvl then maxIlvl = score; maxName = name end
                if not latest or (info.date or "") > latest then latest = info.date end
            end
            if info.class then
                classCounts[info.class] = (classCounts[info.class] or 0) + 1
            end
        end
    end

    local wt = whisperTo
    if total == 0 then
        GearSend("수집된 데이터 없음", wt)
        return
    end

    local avgIlvl = math.floor(totalIlvl / total)
    GearSend("── 장비 수집 현황 ──", wt)
    GearSend("총 수집: " .. total .. "명  (길드원: " .. guildCount .. "명)", wt)
    GearSend("평균 gs/ilvl: " .. avgIlvl .. "  최고: " .. (maxName or "?") .. " " .. maxIlvl, wt)
    GearSend("마지막 수집: " .. (latest or "?"), wt)

    local classParts = {}
    for cls, cnt in pairs(classCounts) do
        classParts[#classParts + 1] = cls .. " " .. cnt
    end
    if #classParts > 0 then
        table.sort(classParts)
        GearSend("직업별: " .. table.concat(classParts, " / "), wt)
    end
end

local gearFrame = CreateFrame("Frame", "MyGreetingGearFrame")
gearFrame:RegisterEvent("PLAYER_LOGIN")

gearFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            if not MyGreetingDB then return end
            if not MyGreetingDB.gearData then MyGreetingDB.gearData = {} end

            -- 새 API 데이터가 있으면 임포트
            if MyGreeting_ImportData and MyGreeting_ImportData.members then
                local importTs = MyGreeting_ImportData.fetched_at or 0
                if importTs > (MyGreetingDB.lastAPIImport or 0) then
                    local count = 0
                    for name, apiData in pairs(MyGreeting_ImportData.members) do
                        local existing = MyGreetingDB.gearData[name]
                        if not existing then
                            MyGreetingDB.gearData[name] = {
                                class = apiData.class or "",
                                spec1 = {
                                    name = "?", ilvl = apiData.ilvl or 0, gs = false,
                                    items = apiData.items or {}, date = apiData.date or "", time = importTs,
                                },
                            }
                        else
                            local s = existing.spec1 or {}
                            s.items = apiData.items or s.items
                            s.ilvl  = apiData.ilvl or s.ilvl
                            s.date  = apiData.date or s.date
                            s.time  = importTs
                            if not existing.class or existing.class == "" then
                                existing.class = apiData.class or ""
                            end
                            existing.spec1 = s
                        end
                        count = count + 1
                    end
                    MyGreetingDB.lastAPIImport = importTs
                    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r API 장비 임포트: " .. count .. "명")
                end
            end

        end)
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
    end
end)

-- ============================================================
-- 출력 헬퍼
-- ============================================================
GearSend = function(msg, whisperTo)
    MyGreeting_QSend(msg, whisperTo)
end

-- ============================================================
-- 조회 함수 (슬래시 커맨드 및 길드챗 명령어에서 호출)
-- whisperTo: "LOCAL" = 나만 보임 / 플레이어명 = 귓말 / nil = 길드챗
-- ============================================================
-- guildOnly=true면 길드원만, false/nil이면 수집된 전체
-- startFrom: 시작 순위 (기본 1), 5개씩 표시
-- classFilter: 한글 직업명 (예: "전사") — 해당 직업만
-- classLabel: 출력용 직업명 (보통 classFilter와 동일)
function MyGreeting_PrintGearRank(whisperTo, guildOnly, startFrom, classFilter, classLabel)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not next(data) then
        GearSend("수집된 데이터 없음", whisperTo)
        return
    end

    local list = {}
    for name, info in pairs(data) do
        local passGuild = not guildOnly or IsGuildMember(name)
        local passClass = not classFilter or info.class == classFilter
        if passGuild and passClass then
            local best = GetBestSpec(info)
            if best then
                local sortKey = best.gs or best.ilvl or 0
                list[#list + 1] = { name = name .. "(" .. (best.name or "?") .. ")", info = best, sortKey = sortKey }
            end
        end
    end
    table.sort(list, function(a, b) return a.sortKey > b.sortKey end)

    local RANK_LIMIT = 5
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
    GearSend(title .. suffix .. ":", whisperTo)
    for i = from, to do
        local e = list[i]
        GearSend(i .. ". " .. e.name .. "  " .. ScoreStr(e.info) .. "  (" .. (e.info.date or "?") .. ")", whisperTo)
    end
end

-- 아이템 링크를 조회 시점에 캐싱 후 콜백 실행
-- items의 link 필드를 GetItemInfo 결과로 교체한 뒤 callback() 호출
local function CacheLinks(items, whisperTo, callback)
    if whisperTo == "LOCAL" then callback(); return end
    local pending = 0
    local idToItems = {}

    for _, item in ipairs(items) do
        local id = item.link and tonumber(item.link:match("item:(%d+)"))
        if id then
            local _, link = GetItemInfo(id)
            if link then
                item.link = link
            else
                pending = pending + 1
                if not idToItems[id] then idToItems[id] = {} end
                idToItems[id][#idToItems[id] + 1] = item
            end
        end
    end

    if pending == 0 then
        callback()
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(self, event, itemId)
        itemId = tonumber(itemId)
        if not idToItems[itemId] then return end
        local _, link = GetItemInfo(itemId)
        if not link then return end
        for _, it in ipairs(idToItems[itemId]) do it.link = link end
        idToItems[itemId] = nil
        pending = pending - 1
        if pending <= 0 then
            self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            self:SetScript("OnEvent", nil)
            callback()
        end
    end)
end

local SLOT_GROUPS = {
    { slots = {1, 2, 3} },          -- 머리, 목, 어깨
    { slots = {15, 5, 9} },         -- 등, 가슴, 손목
    { slots = {10, 6, 7, 8} },      -- 손, 허리, 다리, 발
    { slots = {11, 12, 13, 14} },   -- 반지1, 반지2, 장신구1, 장신구2
    { slots = {16, 17, 18} },       -- 주장비, 보조장비, 원거리
}

local function PrintItems(items, whisperTo)
    if not items or #items == 0 then return end

    local filtered = {}
    for _, item in ipairs(items) do
        if not SKIP_SLOTS[item.slot] then filtered[#filtered + 1] = item end
    end
    if #filtered == 0 then return end

    CacheLinks(filtered, whisperTo, function()
        local bySlot = {}
        for _, item in ipairs(filtered) do bySlot[item.slot] = item end

        local lines = {}
        for _, group in ipairs(SLOT_GROUPS) do
            local parts = {}
            for _, slot in ipairs(group.slots) do
                if bySlot[slot] then parts[#parts + 1] = ItemDisplay(bySlot[slot]) end
            end
            if #parts > 0 then lines[#lines + 1] = table.concat(parts, " / ") end
        end

        for _, line in ipairs(lines) do
            GearSend(line, whisperTo)
        end
    end)
end

function MyGreeting_GetGearScore(name, whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not data[name] then
        GearSend(name .. " 데이터 없음", whisperTo)
        return
    end
    local info = data[name]
    local best = GetBestSpec(info)
    if not best then
        GearSend(name .. " 데이터 없음", whisperTo)
        return
    end
    local specLabel = best.name and ("(" .. best.name .. ")") or ""
    GearSend(name .. specLabel .. "  장비점수: " .. ScoreStr(best) .. "  (수집: " .. (best.date or "?") .. ")", whisperTo)

    if not best.items or #best.items == 0 then
        GearSend("  (장비 목록 없음)", whisperTo)
    else
        PrintItems(best.items, whisperTo)
    end
end

function MyGreeting_GetGearSlot(name, slotIds, whisperTo)
    local data = MyGreetingDB and MyGreetingDB.gearData
    if not data or not data[name] then
        GearSend(name .. " 데이터 없음", whisperTo)
        return
    end
    local info = data[name]
    local best = GetBestSpec(info)
    if not best or not best.items or #best.items == 0 then
        GearSend(name .. " 장비 목록 없음", whisperTo)
        return
    end
    local slotSet = {}
    for _, s in ipairs(slotIds) do slotSet[s] = true end
    local slotItems = {}
    for _, item in ipairs(best.items) do
        if slotSet[item.slot] then slotItems[#slotItems + 1] = item end
    end
    if #slotItems == 0 then
        GearSend(name .. " 해당 슬롯 장비 없음", whisperTo)
        return
    end
    CacheLinks(slotItems, whisperTo, function()
        for _, item in ipairs(slotItems) do
            GearSend(name .. "  " .. ItemDisplay(item), whisperTo)
        end
    end)
end

-- ============================================================
-- 커뮤니티 채널 명령어 핸들러
-- ============================================================
local COMM_CLUB_ID  = 57029383
local COMM_STREAM_ID = 1
local COMM_CH_NAME  = "Community:" .. COMM_CLUB_ID .. ":" .. COMM_STREAM_ID

local function CommSend(msg)
    local chNum = GetChannelName(COMM_CH_NAME)
    if not chNum or chNum == 0 then return end
    SendChatMessage(msg, "CHANNEL", nil, chNum)
end

local function CommGearLine(name)
    local data = MyGreetingDB and MyGreetingDB.gearData
    local info = data and data[name]
    local best = info and GetBestSpec(info)
    if not best then return name .. " 데이터 없음" end
    return name .. " (" .. (best.name or "?") .. ")  " .. ScoreStr(best) .. "  (" .. (best.date or "?") .. ")"
end

local function CommDispatch(text, sender)
    text = strtrim(text or "")
    if text == "안녕하세요" then
        CommSend("안녕합니다")
        return
    end
    if text == "!장비" then
        if sender and #sender > 0 then
            CommSend(CommGearLine(sender))
        else
            CommSend("사용법: !장비 캐릭명")
        end
    elseif text:find("!장비 ", 1, true) == 1 then
        local name = strtrim(text:sub(#"!장비 " + 1))
        if #name > 0 then CommSend(CommGearLine(name)) end
    elseif text:find("!장비순위 ", 1, true) == 1 then
        local prefix = "!장비순위 "
        local from = tonumber(strtrim(text:sub(#prefix + 1)))
        if not from then return end
        local data = MyGreetingDB and MyGreetingDB.gearData
        if not data or not next(data) then CommSend("수집된 데이터 없음"); return end
        local list = {}
        for name, info in pairs(data) do
            if IsGuildMember(name) then
                for _, key in ipairs({"spec1", "spec2"}) do
                    local spec = info[key]
                    if spec then
                        list[#list+1] = { label = name.."(".. (spec.name or "?") ..")", spec = spec, sortKey = spec.gs or spec.ilvl or 0 }
                    end
                end
            end
        end
        table.sort(list, function(a, b) return a.sortKey > b.sortKey end)
        local total = #list
        if total == 0 then CommSend("길드원 데이터 없음"); return end
        if from > total then CommSend("해당 순위 없음 (전체 "..total.."명)"); return end
        local to = math.min(total, from + 9)
        CommSend("── 길드원 장비순위 "..from.."-"..to.." / "..total.."명 ──")
        for i = from, to do
            local e = list[i]
            C_Timer.After((i - from + 1) * 0.5, function()
                CommSend(i..". "..e.label.."  "..ScoreStr(e.spec))
            end)
        end
    end
end

local lastCommDispatch = 0

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CLUB_MESSAGE_ADDED")
commFrame:SetScript("OnEvent", function(self, event, clubId, streamId, messageId)
    if tostring(clubId) ~= tostring(COMM_CLUB_ID) then return end
    if tostring(streamId) ~= tostring(COMM_STREAM_ID) then return end
    local now = GetTime()
    if now - lastCommDispatch < 0.5 then return end
    lastCommDispatch = now
    C_Timer.After(0.1, function()
        local msgs = C_Club.GetMessagesInRange(clubId, streamId, messageId, messageId)
        if not msgs or not msgs[1] then return end
        local text = strtrim(msgs[1].content or "")
        if text == "" then return end
        local author = msgs[1].author
        local sender = author and (author.name or author.characterName) or ""
        CommDispatch(text, sender)
    end)
end)
