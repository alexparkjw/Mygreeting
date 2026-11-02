-- ============================================================
-- Compat.lua
-- Classic beta(1.60, 최신 엔진)에서 제거된 전역 API 대체
-- 전역은 건드리지 않고 ns에만 넣음 → 각 파일 상단에서 local로 받아씀
-- ============================================================

local _, ns = ...

ns.GetSpellInfo = GetSpellInfo or function(spell)
    if not spell then return nil end
    local info = C_Spell.GetSpellInfo(spell)
    if not info then return nil end
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
end

ns.GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

ns.UnitAura = UnitAura or function(unit, index, filter)
    -- beta: 전투 중 등 오라가 secret이면 애드온 호출 시 에러 → pcall로 막고 nil 반환
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok or not aura then return nil end
    return AuraUtil.UnpackAuraData(aura)
end

-- 오라가 지금 secret(접근 불가) 상태인지
ns.AurasSecret = function()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return true
    end
    return InCombatLockdown()
end

-- beta(Forever): 성+이름 체계(RegionalUniqueNames). UnitName(unit) → 이름, 성 을 따로 반환하고
-- 귓말 대상은 "이름<구분자>성" 전체여야 함 (이름만 넣으면 귓말 실패)
local function RegionalNames()
    return RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
end
local SURNAME_SEP = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

-- 유닛의 귓말 가능한 전체 이름
ns.UnitWhisperName = function(unit)
    local name, second = UnitName(unit)
    if not name then return nil end
    if second and second ~= "" then
        return name .. (RegionalNames() and SURNAME_SEP or "-") .. second
    end
    return name
end

-- 이름만 있는 귓말 대상 → 파티/공대/대상에서 찾아 성까지 붙임
local function ResolveWhisperTarget(target)
    if not RegionalNames() or type(target) ~= "string" then return target end
    if target:find(SURNAME_SEP, 1, true) or target:find("-", 1, true) then return target end
    local units = { "target", "focus", "mouseover" }
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        local n = UnitExists(u) and UnitName(u)
        if n and not (issecretvalue and issecretvalue(n)) and n == target then
            return ns.UnitWhisperName(u)
        end
    end
    return target
end

-- ============================================================
-- 이름 helpers (Forever: 이름+성 전체 이름 / 그 외: 이름-서버)
-- ============================================================
ns.SURNAME_SEP = SURNAME_SEP

-- "-서버" 제거 (성은 유지). 보안값/비문자열은 그대로
ns.StripRealm = function(n)
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return n end
    if RegionalNames() then return n end  -- Forever: 서버명이 붙지 않음, '-' 는 이름 일부일 수 있음
    return n:match("^([^%-]+)") or n
end

-- 성/서버 다 떼고 이름만
ns.GivenName = function(n)
    n = ns.StripRealm(n)
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return n end
    local i = n:find(SURNAME_SEP, 1, true)
    return i and n:sub(1, i - 1) or n
end

-- 내 이름의 모든 형태 (이름 / 이름+성 / GetUnitName)
local myNames
local function MyNames()
    if myNames then return myNames end
    local t = {}
    local short = UnitName("player")
    if not short then return t end  -- 아직 로딩 전: 캐시하지 않음
    t[short] = true
    local full = ns.UnitWhisperName("player")
    if full then t[full] = true end
    if GetUnitName then
        local g = GetUnitName("player", true)
        if type(g) == "string" then t[g] = true; t[ns.StripRealm(g)] = true end
    end
    myNames = t
    return t
end

-- 이 이름이 나인가? (채팅 보낸 사람·길드 명단 이름 어느 형태든)
ns.IsMe = function(n)
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return false end
    local t = MyNames()
    if t[n] or t[ns.StripRealm(n)] then return true end
    local noRealm = n:match("^([^%-]+)")  -- 혹시 Forever 에서도 "-서버" 가 붙어 오는 경우
    if noRealm and t[noRealm] then return true end
    -- 성 없이 이름만 온 경우만 이름으로 비교 (같은 이름 다른 성 = 다른 사람)
    if not n:find(SURNAME_SEP, 1, true) then
        return t[ns.GivenName(n)] == true
    end
    return false
end

-- 진단용: 마지막으로 받은 채팅의 보낸 사람 원문 (/mg 이름확인)
ns.lastSenders = {}

-- 길드 기능 전체 끄기 (/mg 길드 로 토글, 기본 끔)
ns.GuildOff = function()
    return not MyGreetingDB or MyGreetingDB.guildOff ~= false
end

-- 길드 기능이 꺼져 있어도 개별로 켠 기능 (MyGreetingDB.guildOn[key]) 은 허용
ns.GuildAllow = function(key)
    if not ns.GuildOff() then return true end
    return key ~= nil and MyGreetingDB and MyGreetingDB.guildOn and MyGreetingDB.guildOn[key] == true
end

local rawSend = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

-- Forever: 인스턴스(던전) 안에서는 애드온이 채팅을 못 보냄 (채팅 보안 잠금)
local function InLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end
ns.InChatLockdown = InLockdown

-- 잠금 중 막힌 메시지: 기본은 조용히 버림. ns.SendChatMessageLater 로 보낸 것만 모아 뒀다가 잠금 풀리면 전송
local deferred      = {}   -- { {msg, chatType, target, time} }
local DEFER_MAX     = 20
local DEFER_EXPIRE  = 30 * 60  -- 30분 지난 건 버림
local lockdownNoted = false    -- 잠금 안내는 잠금 1회당 한 번만 출력

local function NoteLockdown()
    if lockdownNoted then return end
    lockdownNoted = true
    print("|cffFFFF00[myGreeting]|r 인스턴스 안이라 채팅 자동 전송이 막혀 있어요 (작별 인사는 밖에서 보냄)")
end

-- 전송 실패/제한 시 이유를 채팅창에 표시 (beta 진단용)
ns.SendChatMessage = function(msg, chatType, lang, target, guildKey)
    if chatType == "GUILD" and not ns.GuildAllow(guildKey) then return end
    if chatType == "WHISPER" then target = ResolveWhisperTarget(target) end
    if InLockdown() then
        NoteLockdown()
        return
    end
    local ok, err = pcall(rawSend, msg, chatType, lang, target)
    if not ok then
        local sec = issecretvalue and issecretvalue(msg) and " [메시지가 secret 값]" or ""
        print("|cffFF4040[myGreeting 진단]|r 전송 실패 (" .. tostring(chatType) .. ")" .. sec .. ": " .. tostring(err))
        -- 원인 분석용: 저장변수에 기록 (/reload 후 SavedVariables/MyGreeting.lua 에서 확인)
        if MyGreetingDB then
            MyGreetingDB.sendErrors = MyGreetingDB.sendErrors or {}
            local log = MyGreetingDB.sendErrors
            log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. tostring(chatType) .. sec .. " | " .. tostring(err)
                .. " | lockdown=" .. tostring(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
                .. " combat=" .. tostring(InCombatLockdown())
            while #log > 20 do table.remove(log, 1) end
        end
    end
end

-- 잠금 중이면 모아 뒀다가 풀리면 전송 (작별 귓말처럼 나중에 가도 의미 있는 것만)
ns.SendChatMessageLater = function(msg, chatType, lang, target)
    if not InLockdown() then
        return ns.SendChatMessage(msg, chatType, lang, target)
    end
    NoteLockdown()
    if chatType == "WHISPER" then target = ResolveWhisperTarget(target) end
    -- 같은 대상에게 같은 내용이 이미 있으면 중복 저장 안 함
    for _, d in ipairs(deferred) do
        if d.msg == msg and d.chatType == chatType and d.target == target then return end
    end
    deferred[#deferred + 1] = { msg = msg, chatType = chatType, lang = lang, target = target, time = time() }
    while #deferred > DEFER_MAX do table.remove(deferred, 1) end
end

-- 잠금 해제 감시: 5초마다 확인해서 모아 둔 메시지 전송 (파티 채널은 이미 파티가 없으면 버림)
C_Timer.NewTicker(5, function()
    if InLockdown() then return end
    lockdownNoted = false
    if #deferred == 0 then return end
    local list = deferred
    deferred = {}
    local now, i = time(), 0
    for _, d in ipairs(list) do
        local valid = (now - d.time) < DEFER_EXPIRE
        if d.chatType == "PARTY" and not IsInGroup() then valid = false end
        if valid then
            i = i + 1
            C_Timer.After(i * 1.0, function()
                ns.SendChatMessage(d.msg, d.chatType, d.lang, d.target)
            end)
        end
    end
end)

-- beta: UnitIsAFK 가 secret boolean 을 돌려줄 때가 있음 → 판별 불가면 false
ns.IsAFK = function()
    local afk = UnitIsAFK("player")
    if issecretvalue and issecretvalue(afk) then return false end
    return afk and true or false
end

ns.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Settings 카테고리는 GuildGreeter에서 등록 시 ns.settingsCategory에 저장
ns.OpenOptions = function(panelName)
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panelName)
    end
end

ns.AddMessageEventFilter = ChatFrame_AddMessageEventFilter
    or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    or function() end

ns.DoEmote = DoEmote or function(emote, target)
    return C_ChatInfo.PerformEmote(emote, target)
end

-- 접속 시 자가진단: 이 애드온이 쓰는 API 중 없는 것을 채팅창에 출력
local REQUIRED = {
    "GetGuildRosterInfo", "GetNumGuildMembers", "GuildControlGetNumRanks", "GuildControlGetRankName",
    "IsInRaid", "IsInGroup", "UnitName", "UnitGUID", "UnitIsDeadOrGhost", "UnitPosition",
    "GetChannelName", "SetRaidTarget", "GetRaidTargetIndex", "GetShapeshiftForm", "CancelShapeshiftForm",
    "GetRealZoneText", "GetRealmName", "InCombatLockdown", "PlaySound", "SetCVar",
}
local diag = CreateFrame("Frame")
diag:RegisterEvent("PLAYER_LOGIN")
diag:SetScript("OnEvent", function()
    local missing = {}
    for _, n in ipairs(REQUIRED) do
        if type(_G[n]) ~= "function" then missing[#missing + 1] = n end
    end
    if not (C_GuildInfo and C_GuildInfo.GuildRoster) then missing[#missing + 1] = "C_GuildInfo.GuildRoster" end
    if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
        missing[#missing + 1] = "(이 서버는 애드온 채팅 전송 제한됨)"
    end
    if #missing > 0 then
        print("|cffFF4040[myGreeting 진단]|r 없는 API: " .. table.concat(missing, ", "))
    else
        print("|cff40FF40[myGreeting 진단]|r API 확인 완료 — 이상 없음")
    end
end)

-- 이름 형식 확인용: 채널별 마지막 보낸 사람 원문 기록 (/mg 이름확인)
local senderDiag = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_SAY" }) do
    senderDiag:RegisterEvent(ev)
end
senderDiag:SetScript("OnEvent", function(_, event, _, sender)
    if issecretvalue and issecretvalue(sender) then
        ns.lastSenders[event] = "(보안값)"
    elseif type(sender) == "string" then
        ns.lastSenders[event] = sender
    end
end)

-- 길드 채팅 ! 명령 수신 진단
local chatDiag = CreateFrame("Frame")
chatDiag:RegisterEvent("CHAT_MSG_GUILD")
chatDiag:SetScript("OnEvent", function(_, _, msg, sender)
    if not ns.GuildAllow("cmd") then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then
        print("|cffFF4040[myGreeting 진단]|r 길드 채팅 내용이 보안값(secret)이라 읽을 수 없음")
        return
    end
    if type(msg) == "string" and msg:find("^%s*!") then
        print("|cffFFFF00[myGreeting 진단]|r 길드 명령 수신: " .. msg .. " / 보낸이: " .. tostring(sender))
    end
end)
