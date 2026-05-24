-- ============================================================
-- BisTracker.lua
-- 길드원 던전/레이드 입장 시 BIS 미보유 아이템 길드 채팅 안내
-- ============================================================

local function GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- spec1, spec2 통틀어 보유 중인 아이템 ID set 반환
local function GetOwnedIDs(charData)
    local owned = {}
    local function scan(spec)
        if not spec or not spec.items then return end
        for _, item in ipairs(spec.items) do
            local id = GetItemIDFromLink(item.link)
            if id then owned[id] = true end
        end
    end
    scan(charData.spec1)
    scan(charData.spec2)
    return owned
end

-- BIS 체크 및 길드 채팅 전송
-- GuildGreeter.lua 던전 입장 감지 블록에서 호출됨
function MyGreeting_CheckBIS(name, zone)
    if not MyGreeting_BisData then return end
    local gearDB = MyGreetingDB and MyGreetingDB.gearData
    if not gearDB then return end
    local charData = gearDB[name]
    if not charData then return end

    local cls = charData.class
    if not cls or cls == "" then return end

    local clsBis = MyGreeting_BisData[cls]
    if not clsBis then return end

    -- 전 스펙에서 해당 존 BIS 아이템 수집 (중복 제거)
    local seenId = {}
    local zoneBis = {}
    for _, specBis in pairs(clsBis) do
        local ids = specBis[zone]
        if ids then
            for _, id in ipairs(ids) do
                if not seenId[id] then
                    seenId[id] = true
                    zoneBis[#zoneBis + 1] = id
                end
            end
        end
    end
    if #zoneBis == 0 then return end

    -- 미보유 아이템만 추출
    local owned = GetOwnedIDs(charData)
    local missingIDs = {}
    for _, id in ipairs(zoneBis) do
        if not owned[id] then
            missingIDs[#missingIDs + 1] = id
        end
    end
    if #missingIDs == 0 then return end

    -- 아이템 이름 수집
    local names = {}
    for _, id in ipairs(missingIDs) do
        local n = GetItemInfo(id)
        names[#names + 1] = n or ("[" .. id .. "]")
    end

    -- "[BIS] 보꿈밥 카라잔: 아이템A, 아이템B" 형태로 발송
    local base = "[BIS] " .. name .. " " .. zone .. ": "
    local msg = base .. table.concat(names, ", ")
    if #msg > 250 then
        local fitted = {}
        local budget = 250 - #base - 3
        local used = 0
        for i, n in ipairs(names) do
            local seg = (i == 1) and n or (", " .. n)
            if used + #seg > budget then fitted[#fitted + 1] = "..." ; break end
            fitted[#fitted + 1] = n
            used = used + #seg
        end
        msg = base .. table.concat(fitted, ", ")
    end
    SendChatMessage(msg, "GUILD")
end
