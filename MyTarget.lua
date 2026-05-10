-- ============================================================
-- MyTarget.lua
-- /mg 타겟 [이름]          — 한 번 찾아 징표+소리 후 종료
-- /mg 타겟별|달|... [이름] — 비전투 중 자동 타겟+징표, 죽으면 재탐색
-- /mg 타겟해제             — 전체 해제
-- /mg 타겟별해제           — 해당 징표만 해제
-- ============================================================

local MARK_NAMES = {
    ["별"]=1, ["동그라미"]=2, ["동글"]=2, ["다이아"]=3, ["삼각"]=4, ["세모"]=4, ["역삼"]=4,
    ["달"]=5, ["사각"]=6, ["네모"]=6, ["십자"]=7, ["엑스"]=7, ["해골"]=8,
}
local MARK_IDX_TO_NAME = {}
for k, v in pairs(MARK_NAMES) do MARK_IDX_TO_NAME[v] = k end

-- watches[mark] = { name, paused, guid }
-- paused=true: 이미 찍음, 죽거나 전투끝나면 false로 복구
local watches   = {}
local onceWatch = nil

local function TryMarkUnit(unit, mark)
    if InCombatLockdown() then return false end
    SetRaidTarget(unit, mark)
    return GetRaidTargetIndex(unit) == mark
end

local function CheckUnit(unit)
    if not UnitExists(unit) then return end
    local n = UnitName(unit)
    if not n then return end
    n = n:match("^([^%-]+)") or n

    for mark, w in pairs(watches) do
        if not w.paused and w.name == n then
            local ok = TryMarkUnit(unit, mark)
            if ok then
                w.paused = true
                w.guid   = UnitGUID(unit)
                DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. (MARK_IDX_TO_NAME[mark] or mark) .. "] " .. n .. " 징표 완료")
            end
        end
    end

    if onceWatch and onceWatch == n then
        TryMarkUnit(unit, 8)
        PlaySound(8959)
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. n .. " 발견! 징표 완료")
        onceWatch = nil
    end
end

local watchFrame = CreateFrame("Frame")
watchFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watchFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
watchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
watchFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

watchFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if not next(watches) and not onceWatch then return end
        CheckUnit(...)

    elseif event == "PLAYER_TARGET_CHANGED" then
        if not next(watches) and not onceWatch then return end
        CheckUnit("target")

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- 내가 죽인 대상이 감시 중 대상이면 재탐색 재개
        local _, subEvent, _, _, _, _, _, destGUID = ...
        if subEvent ~= "UNIT_DIED" then return end
        for mark, w in pairs(watches) do
            if w.paused and w.guid and w.guid == destGUID then
                w.paused = false
                w.guid   = nil
                DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. (MARK_IDX_TO_NAME[mark] or mark) .. "] " .. w.name .. " 처치 — 재탐색 시작")
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        local resumed = false
        for mark, w in pairs(watches) do
            if w.paused then
                w.paused = false
                w.guid   = nil
                resumed  = true
            end
        end
        if resumed then
            DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 전투 종료 — 감시 재개")
        end
    end
end)

local function FindAndMark(name, mark)
    if InCombatLockdown() then return nil end
    -- 현재 타겟이 맞으면 바로 찍기 (자기 자신 제외)
    if UnitExists("target") and not UnitIsUnit("target", "player") then
        local n = UnitName("target")
        n = n and (n:match("^([^%-]+)") or n)
        if n == name then
            SetRaidTarget("target", mark)
            if GetRaidTargetIndex("target") == mark then return "target" end
        end
    end
    -- 파티/레이드
    local prefix = IsInRaid() and "raid" or "party"
    local max    = IsInRaid() and 40 or 4
    for i = 1, max do
        local u = prefix .. i
        if UnitExists(u) then
            local n = UnitName(u)
            n = n and (n:match("^([^%-]+)") or n)
            if n == name then
                SetRaidTarget(u, mark)
                if GetRaidTargetIndex(u) == mark then return u end
            end
        end
    end
    -- 네임플레이트 — 같은 이름이 여럿이면 가장 가까운 유닛 선택
    local px, py = UnitPosition("player")
    local best, bestDist = nil, math.huge
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then
            local n = UnitName(u)
            n = n and (n:match("^([^%-]+)") or n)
            if n == name then
                local ux, uy = UnitPosition(u)
                local dist = ux and px and (ux - px)^2 + (uy - py)^2 or math.huge
                if dist < bestDist then bestDist = dist; best = u end
            end
        end
    end
    if best then
        SetRaidTarget(best, mark)
        if GetRaidTargetIndex(best) == mark then return best end
    end
    return nil
end

function MyGreeting_MarkTarget(name)
    onceWatch = name
    local unit = FindAndMark(name, 8)
    if unit then
        PlaySound(8959)
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. name .. " 징표 완료")
        onceWatch = nil
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. name .. " 감시 시작")
    end
end

function MyGreeting_WatchTarget(name, markIndex)
    local mark = tonumber(markIndex) or 8
    for m, w in pairs(watches) do
        if w.name == name then ClearMark(w); watches[m] = nil end
    end
    watches[mark] = { name = name, paused = false }
    local unit = FindAndMark(name, mark)
    if unit then
        watches[mark].paused = true
        watches[mark].guid   = UnitGUID(unit)
    end
    local markName = MARK_IDX_TO_NAME[mark] or tostring(mark)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. markName .. "] " .. name .. " 감시 시작")
end

local function FindUnitByGUID(guid)
    if not guid then return nil end
    local prefix = IsInRaid() and "raid" or "party"
    local max    = IsInRaid() and 40 or 4
    for i = 1, max do
        local u = prefix .. i
        if UnitExists(u) and UnitGUID(u) == guid then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and UnitGUID(u) == guid then return u end
    end
    if UnitExists("target") and UnitGUID("target") == guid then return "target" end
    return nil
end

local function ClearMark(w)
    if w.guid then
        local unit = FindUnitByGUID(w.guid)
        if unit then SetRaidTarget(unit, 0) end
    end
end

function MyGreeting_StopWatchMark(markIndex)
    local mark = tonumber(markIndex)
    if mark and watches[mark] then
        ClearMark(watches[mark])
        local markName = MARK_IDX_TO_NAME[mark] or tostring(mark)
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. markName .. "] " .. watches[mark].name .. " 감시 해제")
        watches[mark] = nil
    end
end

function MyGreeting_RetryWatch()
    local saved = {}
    local count = 0
    for mark, w in pairs(watches) do
        saved[mark] = w.name
        count = count + 1
    end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 감시 중인 대상 없음")
        return
    end
    -- 완전 리셋
    for _, w in pairs(watches) do ClearMark(w) end
    watches   = {}
    onceWatch = nil
    -- 재적용
    for mark, name in pairs(saved) do
        watches[mark] = { name = name, paused = false }
        local unit = FindAndMark(name, mark)
        if unit then
            watches[mark].paused = true
            watches[mark].guid   = UnitGUID(unit)
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 재탐색 — 타겟 클릭 시 즉시 적용")
end

function MyGreeting_StopWatch()
    local count = 0
    for _ in pairs(watches) do count = count + 1 end
    if onceWatch then count = count + 1 end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 감시 중인 대상 없음")
        return
    end
    for _, w in pairs(watches) do ClearMark(w) end
    watches  = {}
    onceWatch = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 전체 감시 해제")
end

function MyGreeting_WatchStatus()
    local count = 0
    for mark, w in pairs(watches) do
        local state   = w.paused and "징표완료" or "감시중"
        local markName = MARK_IDX_TO_NAME[mark] or tostring(mark)
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [" .. markName .. "] " .. w.name .. " — " .. state)
        count = count + 1
    end
    if onceWatch then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [일회] " .. onceWatch .. " — 감시중")
        count = count + 1
    end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r 감시 중인 대상 없음")
    end
end

function MyGreeting_WatchFocus(name)
    MyGreeting_WatchTarget(name, 2)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r [동그라미] " .. name .. " 양 설정 (주시는 /focus 매크로 사용)")
end

function MyGreeting_GetMarkIndex(markName)
    return MARK_NAMES[markName]
end
