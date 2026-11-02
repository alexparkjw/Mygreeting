local _, ns = ...  -- Compat.lua (beta 포팅)
local GetItemInfo, GetSpellInfo, SendChatMessage, UnitAura = ns.GetItemInfo, ns.GetSpellInfo, ns.SendChatMessage, ns.UnitAura
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
local summonOfferTime   = 0    -- 소환 요청 받은 시각 (훅이 안 걸릴 때 PEW 대비용)

-- 소환 감사: 파티/공대 채널로 전송 (도착 직후 그룹 정보가 늦게 올 수 있어 재시도)
local function TrySummonThanks(n)
    local m = MyGreeting_GetMsg("summon")
    if m == "" then return end
    if IsInRaid() then
        SendChatMessage(m, "RAID")
    elseif IsInGroup() or UnitExists("party1") then
        SendChatMessage(m, "PARTY")
    elseif n > 0 then
        C_Timer.After(1, function() TrySummonThanks(n - 1) end)
    end
end

-- 소환 수락 확정 → 도착 후 감사 1회
-- 같은 대륙 소환은 로딩화면이 없어 PLAYER_ENTERING_WORLD가 안 뜸 → 수락 시점 타이머로 처리
local function FireSummonThanks(delay)
    if not pendingSummon then return end
    pendingSummon = false
    if summonTimer then summonTimer:Cancel(); summonTimer = nil end
    C_Timer.After(delay, function() TrySummonThanks(10) end)
end

-- ConfirmSummon 훅 (소환 수락 버튼)
-- beta: 전역 덮어쓰기는 taint 유발 → hooksecurefunc 사용
local function OnConfirmSummon()
    pendingSummon   = true
    summonOfferTime = 0
    if DEBUG_MODE then DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[BuffDebug]|r 소환 수락") end
    if summonTimer then summonTimer:Cancel() end
    -- 로딩화면이 있으면 타이머가 로딩 후에 돌고, PEW가 먼저 오면 그쪽에서 처리
    summonTimer = C_Timer.NewTimer(3, function()
        summonTimer = nil
        FireSummonThanks(0)
    end)
end
if ConfirmSummon then hooksecurefunc("ConfirmSummon", OnConfirmSummon) end
if C_SummonInfo and C_SummonInfo.ConfirmSummon then hooksecurefunc(C_SummonInfo, "ConfirmSummon", OnConfirmSummon) end
local preTradeBag       = nil
local tradePartner      = nil  -- 거래 상대 귓말 이름
local preLootBag        = {}
local recentTableMage    = nil  -- {name, time}
local tablePreBag        = nil  -- 식탁 시전 시점 가방 스냅샷
local recentSoulwellLock = nil  -- {name, time}
local rezCaster         = nil
local rezAccepted       = false  -- 부활 수락 버튼 눌렀는지 (AcceptResurrect 훅)
if AcceptResurrect then hooksecurefunc("AcceptResurrect", function() rezAccepted = true end) end
local wasDead           = false
local recentCasters     = {}   -- [spellId] = {name=..., time=...} : 전투로그 시전자 캐시
local zoneChangeTime    = 0    -- 존 전환 직후 오발 방지용
local ZONE_GRACE        = 6    -- 존 전환 후 버프 감사 억제 시간 (초)

-- 거래 아이템 친근한 이름 (없으면 게임 아이템 이름 그대로 사용)
local TRADE_FRIENDLY_NAME = {
    -- 흑마 돌
    [5512]="생명석",[19004]="생명석",[19005]="생명석",
    [19006]="생명석",[19007]="생명석",[19008]="생명석",
    [22103]="생명석",[36892]="생명석",
    -- 창조된 빵/물
    [160]="빵/물",[1113]="빵/물",[1487]="빵/물",[2070]="빵/물",[4601]="빵/물",
    [5349]="빵/물",[8075]="빵/물",[8076]="빵/물",[22895]="빵/물",[22896]="빵/물",
    [43523]="빵/물",[65499]="빵/물",
    [5350]="빵/물",[8077]="빵/물",[8078]="빵/물",[22891]="빵/물",[22892]="빵/물",
    [27860]="빵/물",[43524]="빵/물",[65500]="빵/물",
    [2287]="빵/물",[2288]="빵/물",
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
    -- beta: 전투 중엔 오라가 secret → 스캔 건너뜀 (prevPlayerBuffs 유지, 전투 끝나고 감지)
    if ns.AurasSecret() then return end
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
        if issecretvalue and issecretvalue(spellId) then return end  -- 스캔 중단, 직전 상태 유지
        if MAJOR_BUFF_IDS[spellId] then
            current[spellId] = sourceUnit or ""
        end
        i = i + 1
    end

    local inGrace = (GetTime() - zoneChangeTime) < ZONE_GRACE

    for spellId, sourceUnit in pairs(current) do
        if not prevPlayerBuffs[spellId] and not inGrace and not IsInRaid() then
            local casterName = nil
            if sourceUnit ~= "" and not UnitIsUnit(sourceUnit, "player") then
                casterName = ns.UnitWhisperName(sourceUnit)
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
                    lastBuffThanks[casterName] = now
                    SendChatMessage((GetSpellInfo(spellId) or "버프") .. " 감사합니다", "WHISPER", nil, casterName)
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
-- beta: COMBAT_LOG_EVENT_UNFILTERED는 제한 이벤트 → 파티원 시전 이벤트로 대체
buffFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
buffFrame:RegisterEvent("LOOT_OPENED")
buffFrame:RegisterEvent("LOOT_CLOSED")
buffFrame:RegisterEvent("BAG_UPDATE_DELAYED")

buffFrame:SetScript("OnEvent", function(self, event, ...)

    -- ── 전투 로그: 버프 시전자 캐시 ──────────────────────────
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if IsInRaid() then return end
        local unit, _, spellId = ...
        -- beta: 전투 중 spellId가 secret → 테이블 키로 못 씀
        if issecretvalue and (issecretvalue(unit) or issecretvalue(spellId)) then return end
        if not unit then return end
        -- 파티원 + 비파티(대상/주시/마우스오버/이름표) 시전도 추적
        local isParty = unit:match("^party%d$") ~= nil
        if not (isParty or unit == "target" or unit == "focus" or unit == "mouseover"
                or unit:match("^nameplate%d+$")) then return end
        if UnitIsUnit(unit, "player") then return end
        local sourceName = ns.UnitWhisperName(unit)
        if MAJOR_BUFF_IDS[spellId] and sourceName then
            -- 시전자 대상이 나 (또는 마우스오버 시전 등으로 대상 없음)
            local tu = unit .. "target"
            if UnitIsUnit(tu, "player") or not UnitExists(tu) then
                recentCasters[spellId] = { name = sourceName, time = GetTime() }
            end
        end
        if not isParty then return end  -- 식탁/소울웰은 파티원만

        -- 식탁/소울웰 시전자 추적
        if sourceName then
            local caster = sourceName
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
        rezCaster   = (...)  -- 시전자 이름
        rezAccepted = false

    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- PLAYER_ALIVE 는 영혼 풀고 묘지로 갈 때도 뜸 → 아직 유령이면 부활 아님
        if UnitIsDeadOrGhost("player") then
            if not rezAccepted then rezCaster = nil end
            return
        end
        -- 수락 버튼을 누른 부활만 감사 (훅이 없는 클라면 예전처럼 요청만 보고 판단)
        local accepted = rezAccepted or not AcceptResurrect
        if wasDead and rezCaster and accepted then
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
        wasDead     = false
        rezCaster   = nil
        rezAccepted = false

    -- ── 소환 감사 ─────────────────────────────────────────────
    elseif event == "CONFIRM_SUMMON" then
        -- 소환 요청만 온 상태 (수락 전) → 수락은 ConfirmSummon 훅에서 감지
        summonOfferTime = GetTime()
        if DEBUG_MODE then DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[BuffDebug]|r 소환 요청 받음") end

    elseif event == "PLAYER_ENTERING_WORLD" then
        prevPlayerBuffs = {}
        zoneChangeTime  = GetTime()  -- 존 전환 시각 기록 → 억제 타이머 시작
        -- 로딩화면 있는 소환 (훅이 안 걸렸어도 요청 후 120초 안에 로딩이면 소환으로 간주)
        if summonOfferTime > 0 and (GetTime() - summonOfferTime) < 120 then pendingSummon = true end
        summonOfferTime = 0
        FireSummonThanks(0.5)

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
                    if label == "빵/물" then gotFood = true end
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
            if count > (tablePreBag[itemID] or 0) and TRADE_FRIENDLY_NAME[itemID] == "빵/물" then
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
        preTradeBag  = SnapshotBag()
        -- 거래 상대 (파티 아닐 때 /s 대신 귓말로 감사). 거래창 열린 동안 "NPC" 유닛 = 상대
        tradePartner = UnitExists("NPC") and ns.UnitWhisperName("NPC") or nil

    -- ── 거래 완료 후 아이템 감지 ──────────────────────────────
    elseif event == "TRADE_CLOSED" then
        local snap = preTradeBag
        preTradeBag = nil
        if not snap then return end
        C_Timer.After(0.3, function()
            local afterBag = SnapshotBag()
            -- 친근한 이름 중복 제거용 (사탕, 물빵 등 같은 카테고리는 한 번만)
            local receivedNames = {}
            local seen = {}

            for itemID, count in pairs(afterBag) do
                local before = snap[itemID] or 0
                if count > before then
                    local label = TRADE_FRIENDLY_NAME[itemID]
                    if not label then
                        label = nil  -- 빵/물·생명석·마나석만 감사 (산 물건 등은 인사 안 함)
                    end
                    if label and not seen[label] then
                        seen[label] = true
                        table.insert(receivedNames, label)
                    end
                end
            end

            if #receivedNames > 0 then
                local CHAT_LIMIT = 255
                local parts = {}
                for _, name in ipairs(receivedNames) do
                    table.insert(parts, name)
                    local testMsg = table.concat(parts, ", ") .. " 감사합니다"
                    if #testMsg > CHAT_LIMIT then
                        table.remove(parts)
                        break
                    end
                end
                local msg
                if #parts == 0 then
                    msg = "감사합니다"
                else
                    msg = table.concat(parts, ", ") .. " 감사합니다"
                end
                C_Timer.After(0.5, function()
                    if IsInParty() then
                        SendChatMessage(msg, "PARTY")
                    elseif tradePartner then
                        SendChatMessage(msg, "WHISPER", nil, tradePartner)
                    end
                end)
            end
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
