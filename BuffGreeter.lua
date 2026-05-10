-- ============================================================
-- BuffGreeter.lua
-- 버프 감사 + 소환/인던 자동 인사
-- ============================================================

local BUFF_COOLDOWN = 10
local DEBUG_MODE    = false
local GREET_DELAY   = 1

-- ============================================================
-- 주요 버프 스펠 ID (TBC 클래식 기준 / 힐관련 제외)
-- ============================================================
local BUFF_SHORT_NAME = {
    -- 신의 권능: 인내 (Power Word: Fortitude R1~7)
    [1243]="신의 권능: 인내",[1244]="신의 권능: 인내",[1245]="신의 권능: 인내",[2791]="신의 권능: 인내",
    [10937]="신의 권능: 인내",[10938]="신의 권능: 인내",[25389]="신의 권능: 인내",
    -- 인내의 기원 (Prayer of Fortitude R1~3)
    [21562]="인내의 기원",[21564]="인내의 기원",[25392]="인내의 기원",
    -- 신비한 총명 (Arcane Intellect R1~7)
    [1459]="신비한 총명",[1460]="신비한 총명",[1461]="신비한 총명",
    [10156]="신비한 총명",[10157]="신비한 총명",[27126]="신비한 총명",[42995]="신비한 총명",
    -- 신비한 총명함 (Arcane Brilliance R1~2)
    [23028]="신비한 총명함",[27127]="신비한 총명함",
    -- 야생의 징표 (Mark of the Wild R1~9)
    [1126]="야생의 징표",[5232]="야생의 징표",[6756]="야생의 징표",[5234]="야생의 징표",
    [8907]="야생의 징표",[9884]="야생의 징표",[9885]="야생의 징표",[26990]="야생의 징표",
    -- 야생의 선물 (Gift of the Wild R1~4)
    [21849]="야생의 선물",[21850]="야생의 선물",[26991]="야생의 선물",[27166]="야생의 선물",
    -- 왕의 축복 (Blessing of Kings)
    [20217]="왕의 축복",
    -- 상급 왕의 축복 (Greater Blessing of Kings)
    [25898]="상급 왕의 축복",
    -- 힘의 축복 (Blessing of Might R1~7)
    [19740]="힘의 축복",[19834]="힘의 축복",[19835]="힘의 축복",[19836]="힘의 축복",
    [19837]="힘의 축복",[19838]="힘의 축복",[25291]="힘의 축복",
    -- 상급 힘의 축복 (Greater Blessing of Might R1~2)
    [25782]="상급 힘의 축복",[27140]="상급 힘의 축복",
}


local MAJOR_BUFF_IDS = {
    -- ── 인내 (Power Word: Fortitude R1~7)
    [1243]=true,[1244]=true,[1245]=true,[2791]=true,
    [10937]=true,[10938]=true,[25389]=true,
    -- 집단 인내 (Prayer of Fortitude R1~3)
    [21562]=true,[21564]=true,[25392]=true,

    -- ── 지능 (Arcane Intellect R1~7)
    [1459]=true,[1460]=true,[1461]=true,
    [10156]=true,[10157]=true,[27126]=true,[42995]=true,
    -- 집단 지능 (Arcane Brilliance R1~2)
    [23028]=true,[27127]=true,

    -- ── 야징 (Mark of the Wild R1~9)
    [1126]=true,[5232]=true,[6756]=true,[5234]=true,
    [8907]=true,[9884]=true,[9885]=true,[26990]=true,
    -- 집단 야징 (Gift of the Wild R1~4)
    [21849]=true,[21850]=true,[26991]=true,[27166]=true,

    -- ── 왕징 (Blessing of Kings R1)
    [20217]=true,[25898]=true,
    -- ── 역량 (Blessing of Might R1~9)
    [19740]=true,[19834]=true,[19835]=true,[19836]=true,
    [19837]=true,[19838]=true,[25291]=true,[25782]=true,[27140]=true,
}

-- ============================================================
-- 세션 변수
-- ============================================================
local lastBuffThanks    = {}
local prevPlayerBuffs   = {}   -- [spellId] = true : 직전 보유 버프
local pendingSummon     = false
local summonTimer       = nil

-- ConfirmSummon 훅: CONFIRM_SUMMON 이벤트가 TBC 클래식에서 안 뜨는 경우 대비
if ConfirmSummon then
    local _orig = ConfirmSummon
    ConfirmSummon = function(...)
        pendingSummon = true
        if summonTimer then summonTimer:Cancel() end
        summonTimer = C_Timer.NewTimer(120, function()
            pendingSummon = false
        end)
        return _orig(...)
    end
end
local preTradeBag       = {}
local preLootBag        = {}
local recentTableMage    = nil  -- {name, time}
local tablePreBag        = nil  -- 식탁 시전 시점 가방 스냅샷
local recentSoulwellLock = nil  -- {name, time}
local rezCaster         = nil
local wasDead           = false
local recentCasters     = {}   -- [spellId] = {name=..., time=...} : 전투로그 시전자 캐시
local zoneChangeTime    = 0    -- 존 전환 직후 오발 방지용
local ZONE_GRACE        = 6    -- 존 전환 후 버프 감사 억제 시간 (초)

-- 거래 아이템 친근한 이름 (없으면 게임 아이템 이름 그대로 사용)
local TRADE_FRIENDLY_NAME = {
    -- 흑마 돌
    [5512]="사탕",[19004]="사탕",[19005]="사탕",
    [19006]="사탕",[19007]="사탕",[19008]="사탕",
    [22103]="사탕",[36892]="사탕",
    -- 창조된 빵/물
    [160]="물빵",[1113]="물빵",[1487]="물빵",[2070]="물빵",[4601]="물빵",
    [5349]="물빵",[8075]="물빵",[8076]="물빵",[22895]="물빵",[22896]="물빵",
    [43523]="물빵",[65499]="물빵",
    [5350]="물빵",[8077]="물빵",[8078]="물빵",[22891]="물빵",[22892]="물빵",
    [27860]="물빵",[43524]="물빵",[65500]="물빵",
    [2287]="물빵",[2288]="물빵",
    -- 마나석
    [5514]="마나석",[5515]="마나석",[8007]="마나석",[8008]="마나석",[22044]="마나석",
}

-- 식탁/소울웰 스펠 ID
local CONJURE_TABLE_IDS   = { [43987]=true, [58659]=true }  -- Conjure Refreshment Table (법사 식탁)
local SOULWELL_IDS        = { [29893]=true, [58620]=true }  -- Ritual of Souls (흑마 소울웰)

-- 생명석 아이템 ID (TRADE_FRIENDLY_NAME 의 사탕 목록과 동일)
local HEALTHSTONE_ITEM_IDS = { [5512]=true,[19004]=true,[19005]=true,[19006]=true,[19007]=true,[19008]=true,[22103]=true,[36892]=true }

-- ============================================================
-- 가방 스냅샷
-- ============================================================
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemID   = C_Container and C_Container.GetContainerItemID   or GetContainerItemID

local function SnapshotBag()
    local snap = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                snap[itemID] = (snap[itemID] or 0) + 1
            end
        end
    end
    return snap
end

-- ============================================================
-- 유틸
-- ============================================================
local function IsInParty()
    return UnitExists("party1")
end


-- ============================================================
-- 버프 감지: 이벤트 없는 순수 OnUpdate 프레임 (오염 완전 차단)
-- 이벤트를 하나도 등록하지 않으므로 SendChatMessage 호출 가능
-- ============================================================
local buffScanFrame  = CreateFrame("Frame")
local buffScanTimer  = 0
local SCAN_INTERVAL  = 0.5

buffScanFrame:SetScript("OnUpdate", function(self, elapsed)
    if IsInRaid() then return end
    buffScanTimer = buffScanTimer + elapsed
    if buffScanTimer < SCAN_INTERVAL then return end
    buffScanTimer = 0

    local current    = {}
    local playerName = UnitName("player")
    if not playerName then return end

    local i = 1
    while true do
        local name, _, _, _, _, _, sourceUnit, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if MAJOR_BUFF_IDS[spellId] then
            current[spellId] = sourceUnit or ""
        end
        i = i + 1
    end

    local inGrace = (GetTime() - zoneChangeTime) < ZONE_GRACE

    for spellId, sourceUnit in pairs(current) do
        if not prevPlayerBuffs[spellId] and not inGrace and not IsInRaid() then
            local casterName = nil
            if sourceUnit ~= "" then
                casterName = UnitName(sourceUnit)
                if not casterName then
                    casterName = sourceUnit:match("^([^%-]+)") or sourceUnit
                end
                if casterName == playerName then casterName = nil end
            end

            if not casterName then
                local recent = recentCasters[spellId]
                if recent and (GetTime() - recent.time) < 5 then
                    casterName = recent.name
                end
            end

            if DEBUG_MODE then
                local auraName = GetSpellInfo(spellId)
                DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[BuffDebug]|r 신규: " .. (auraName or "?") ..
                    " (ID:" .. spellId .. ") sourceUnit=[" .. sourceUnit .. "] → caster=" .. (casterName or "nil"))
            end

            if casterName then
                local now = GetTime()
                if not lastBuffThanks[casterName] or (now - lastBuffThanks[casterName]) >= BUFF_COOLDOWN then
                    local spellName = GetSpellInfo(spellId) or BUFF_SHORT_NAME[spellId] or "버프"
                    lastBuffThanks[casterName] = now
                    SendChatMessage(spellName .. " 감사합니다", "WHISPER", nil, casterName)
                end
            end
        end
    end

    prevPlayerBuffs = current
end)

-- ============================================================
-- 이벤트 프레임
-- ============================================================
local buffFrame = CreateFrame("Frame", "MyGreetingBuffFrame", UIParent)

buffFrame:RegisterEvent("CONFIRM_SUMMON")
buffFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
buffFrame:RegisterEvent("TRADE_SHOW")
buffFrame:RegisterEvent("TRADE_CLOSED")
buffFrame:RegisterEvent("PLAYER_LOGIN")
buffFrame:RegisterEvent("PLAYER_DEAD")
buffFrame:RegisterEvent("RESURRECT_REQUEST")
buffFrame:RegisterEvent("PLAYER_ALIVE")
buffFrame:RegisterEvent("PLAYER_UNGHOST")
buffFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
buffFrame:RegisterEvent("LOOT_OPENED")
buffFrame:RegisterEvent("LOOT_CLOSED")
buffFrame:RegisterEvent("BAG_UPDATE_DELAYED")

buffFrame:SetScript("OnEvent", function(self, event, ...)

    -- ── 전투 로그: 버프 시전자 캐시 ──────────────────────────
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if IsInRaid() then return end
        local _, subEvent, _, _, sourceName, _, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
        if (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
            and destGUID == UnitGUID("player")
            and MAJOR_BUFF_IDS[spellId]
            and sourceName
        then
            local name = sourceName:match("^([^%-]+)") or sourceName
            if name ~= UnitName("player") then
                recentCasters[spellId] = { name = name, time = GetTime() }
            end
        end

        -- 식탁/소울웰 시전자 추적
        if subEvent == "SPELL_CAST_SUCCESS" and sourceName then
            local caster = sourceName:match("^([^%-]+)") or sourceName
            if CONJURE_TABLE_IDS[spellId] then
                recentTableMage = { name = caster, time = GetTime() }
                tablePreBag = SnapshotBag()
            elseif SOULWELL_IDS[spellId] then
                recentSoulwellLock = { name = caster, time = GetTime() }
            end
        end
        return

    -- ── 로그인 시 초기화 ──────────────────────────────────────
    elseif event == "PLAYER_LOGIN" then
        pendingSummon     = false
        prevPlayerBuffs   = {}
        rezCaster         = nil
        wasDead           = false
        recentCasters     = {}
        recentTableMage   = nil
        recentSoulwellLock = nil

    -- ── 부활 감지 ─────────────────────────────────────────────
    elseif event == "PLAYER_DEAD" then
        wasDead   = true
        rezCaster = nil

    elseif event == "RESURRECT_REQUEST" then
        rezCaster = (...)  -- 시전자 이름

    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if wasDead and rezCaster then
            local caster = rezCaster
            C_Timer.After(GREET_DELAY, function()
                local m = MyGreeting_GetMsg("resurrect")
                if m == "" then return end
                if IsInParty() then
                    SendChatMessage(m, "PARTY")
                else
                    SendChatMessage(m, "WHISPER", nil, caster)
                end
            end)
        end
        wasDead   = false
        rezCaster = nil

    -- ── 소환 감사 ─────────────────────────────────────────────
    elseif event == "CONFIRM_SUMMON" then
        pendingSummon = true
        if summonTimer then summonTimer:Cancel() end
        summonTimer = C_Timer.NewTimer(120, function()
            pendingSummon = false
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        prevPlayerBuffs = {}
        zoneChangeTime  = GetTime()  -- 존 전환 시각 기록 → 억제 타이머 시작

        if pendingSummon then
            pendingSummon = false
            if summonTimer then summonTimer:Cancel() end
            local function TrySummonThanks(n)
                local m = MyGreeting_GetMsg("summon")
                if m == "" then return end
                if IsInRaid() then
                    SendChatMessage(m, "RAID")
                elseif IsInGroup() or IsInParty() then
                    SendChatMessage(m, "PARTY")
                elseif n > 0 then
                    C_Timer.After(1, function() TrySummonThanks(n - 1) end)
                end
            end
            C_Timer.After(0.5, function() TrySummonThanks(10) end)
        end

    -- ── 식탁/소울웰 아이템 감지 ──────────────────────────────
    elseif event == "LOOT_OPENED" then
        preLootBag = SnapshotBag()

    elseif event == "LOOT_CLOSED" then
        C_Timer.After(0.3, function()
            local afterBag = SnapshotBag()
            local gotFood        = false
            local gotHealthstone = false
            for itemID, count in pairs(afterBag) do
                local before = preLootBag[itemID] or 0
                if count > before then
                    local label = TRADE_FRIENDLY_NAME[itemID]
                    if label == "물빵" then gotFood = true end
                    if HEALTHSTONE_ITEM_IDS[itemID] then gotHealthstone = true end
                end
            end
            local now = GetTime()
            local channel = IsInParty() and "PARTY" or "WHISPER"
            if gotFood and recentTableMage and (now - recentTableMage.time) < 300 then
                local m = "식탁 감사합니다"
                if channel == "WHISPER" then
                    SendChatMessage(m, "WHISPER", nil, recentTableMage.name)
                else
                    SendChatMessage(m, "PARTY")
                end
                recentTableMage = nil
                tablePreBag = nil
            end
            if gotHealthstone and recentSoulwellLock and (now - recentSoulwellLock.time) < 300 then
                local m = "생명석 감사합니다"
                if channel == "WHISPER" then
                    SendChatMessage(m, "WHISPER", nil, recentSoulwellLock.name)
                else
                    SendChatMessage(m, "PARTY")
                end
            end
            preLootBag = {}
        end)

    -- ── 식탁 음식 감지 (LOOT 이벤트 안 뜰 때 대비) ───────────
    elseif event == "BAG_UPDATE_DELAYED" then
        if not recentTableMage or not tablePreBag then return end
        if (GetTime() - recentTableMage.time) > 300 then
            recentTableMage = nil; tablePreBag = nil; return
        end
        local afterBag = SnapshotBag()
        local gotFood = false
        for itemID, count in pairs(afterBag) do
            if count > (tablePreBag[itemID] or 0) and TRADE_FRIENDLY_NAME[itemID] == "물빵" then
                gotFood = true; break
            end
        end
        if gotFood then
            local mage = recentTableMage
            recentTableMage = nil; tablePreBag = nil
            local m = "식탁 감사합니다"
            if IsInParty() then
                SendChatMessage(m, "PARTY")
            else
                SendChatMessage(m, "WHISPER", nil, mage.name)
            end
        end

    -- ── 거래 전 스냅샷 ────────────────────────────────────────
    elseif event == "TRADE_SHOW" then
        preTradeBag = SnapshotBag()

    -- ── 거래 완료 후 아이템 감지 ──────────────────────────────
    elseif event == "TRADE_CLOSED" then
        C_Timer.After(0.3, function()
            local afterBag = SnapshotBag()
            -- 친근한 이름 중복 제거용 (사탕, 물빵 등 같은 카테고리는 한 번만)
            local receivedNames = {}
            local seen = {}

            for itemID, count in pairs(afterBag) do
                local before = preTradeBag[itemID] or 0
                if count > before then
                    local label = TRADE_FRIENDLY_NAME[itemID]
                    if not label then
                        label = GetItemInfo(itemID)  -- 모르는 아이템은 실제 이름 사용
                    end
                    if label and not seen[label] then
                        seen[label] = true
                        table.insert(receivedNames, label)
                    end
                end
            end

            if #receivedNames > 0 then
                local msg = table.concat(receivedNames, ", ") .. " 감사합니다"
                local channel = IsInParty() and "PARTY" or "SAY"
                C_Timer.After(0.5, function() SendChatMessage(msg, channel) end)
            end
            preTradeBag = {}
        end)
    end

end)

-- ============================================================
-- 행동단축버튼 2~5 단축키 텍스트 숨기기
-- ============================================================
local function HideActionHotKeys()
    local bars = {
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
    }
    for _, barName in ipairs(bars) do
        for i = 1, 12 do
            local hk = _G[barName .. i .. "HotKey"]
            if hk then
                hk:SetAlpha(0)
                hk:HookScript("OnShow", function(self) self:SetAlpha(0) end)
            end
        end
    end
end

local hkFrame = CreateFrame("Frame")
hkFrame:RegisterEvent("PLAYER_LOGIN")
hkFrame:SetScript("OnEvent", function(self)
    HideActionHotKeys()
    self:UnregisterAllEvents()
end)

-- ============================================================
-- 슬래시 커맨드
-- ============================================================
SLASH_MGBUFF1 = "/mgbuff"
SlashCmdList["MGBUFF"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "debug" then
        DEBUG_MODE = not DEBUG_MODE
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[BuffGreeter]|r 디버그: " .. (DEBUG_MODE and "|cff00FF00ON|r" or "|cffFF4444OFF|r"))
    end
end
