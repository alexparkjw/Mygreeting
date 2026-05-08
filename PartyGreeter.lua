-- ============================================================
-- PartyGreeting.lua
-- 파티 자동 인사 시스템 (MyGreeting 애드온 일부)
-- ============================================================

local JOIN_THRESHOLD = 5 * 60   -- 5분 이상 있었을 때만 작별 귓말
local GREET_DELAY    = 1        -- 메세지 딜레이 (초)

-- ============================================================
-- 세션 임시 변수
-- ============================================================
local prevPartyMembers  = {}   -- [이름] = true : 직전 파티원
local memberJoinTime    = {}   -- [이름] = GetTime() : 파티 참가 시각
local myInvites         = {}   -- [이름] = true : 내가 초대한 사람
local partyLevels       = {}   -- [이름] = level : 파티원 레벨 캐시 (레벨업 오발 방지)
local alreadyWhispered  = {}   -- [이름] = true : 이미 작별 귓말 보낸 사람 (중복 방지)
local condoledMembers   = {}   -- [이름] = true : 이미 애도 보낸 사람 (중복 방지)
local wasInParty        = false
local myPartyJoinTime   = nil
local partyTimer        = nil
local isInitializing    = false  -- PLAYER_ENTERING_WORLD 1.5초 타이머 실행 중 플래그
local lastSugoTime      = 0      -- 수고 자동응답 중복 방지
local isZoneTransition  = false  -- 존 전환 중 플래그
local savedJoinTimes    = {}     -- 존 전환 전 memberJoinTime 백업

-- ============================================================
-- 현재 파티원 목록 (자신 제외)
-- ============================================================
local function GetCurrentPartyMembers()
    local members = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name then
                members[name] = true
            end
        end
    end
    return members
end

local function IsInParty()
    return UnitExists("party1")
end

local function IsInRaid()
    return UnitInRaid("player") ~= nil
end

-- ============================================================
-- 메세지 전송
-- ============================================================
local function SendParty(msg)
    SendChatMessage(msg, "PARTY")
end

local function SendGroup(msg)
    if IsInRaid() then
        SendChatMessage(msg, "RAID")
    else
        SendChatMessage(msg, "PARTY")
    end
end

local function IterateGroup(fn)
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then fn(unit) end
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then fn(unit) end
        end
    end
end

local function SendWhisper(name, msg)
    -- 파티 유닛 중 해당 이름 찾아서 접속 상태 확인
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitName(unit) == name then
            if not UnitIsConnected(unit) then return end
            break
        end
    end
    SendChatMessage(msg, "WHISPER", nil, name)
end

-- ============================================================
-- InviteUnit 훅
-- 내가 초대한 사람을 추적하기 위해 후킹
-- ============================================================
local origInviteUnit = InviteUnit
InviteUnit = function(name, ...)
    if name and name ~= "" then
        myInvites[name] = true
    end
    return origInviteUnit(name, ...)
end

-- ============================================================
-- LeaveParty 훅 (구/신 API 양쪽)
-- ============================================================
local function OnLeaveParty()
    if IsInRaid() then return end
    local stayedLong = myPartyJoinTime and (GetTime() - myPartyJoinTime) >= JOIN_THRESHOLD
    local base = MyGreeting_GetMsg("party_leave")
    local msg  = stayedLong and ("먼저갈께요 " .. base) or base
    local remaining = GetCurrentPartyMembers()
    for name in pairs(remaining) do
        if not alreadyWhispered[name] then
            alreadyWhispered[name] = true
            local n = name
            C_Timer.After(0, function()
                SendWhisper(n, msg)
            end)
        end
    end
end

if LeaveParty then
    local origLeaveParty = LeaveParty
    LeaveParty = function(...)
        OnLeaveParty()
        return origLeaveParty(...)
    end
end

if C_PartyInfo and C_PartyInfo.LeaveParty then
    local origCLeave = C_PartyInfo.LeaveParty
    C_PartyInfo.LeaveParty = function(...)
        OnLeaveParty()
        return origCLeave(...)
    end
end

-- ============================================================
-- 파티 로스터 변화 처리
-- ============================================================
local function ProcessPartyUpdate()
    if IsInRaid() then
        prevPartyMembers = {}
        memberJoinTime   = {}
        alreadyWhispered = {}
        wasInParty       = false
        return
    end
    local inParty        = IsInParty()
    local currentMembers = GetCurrentPartyMembers()

    -- ── 1. 파티에 처음 들어간 상황 ──────────────────────
    if inParty and not wasInParty then
        myPartyJoinTime = GetTime()
        -- 현재 파티원 중 내가 초대한 사람이 있는지 확인
        local invitedSomeone = false
        for name in pairs(currentMembers) do
            if myInvites[name] then
                invitedSomeone = true
                break
            end
        end

        if not invitedSomeone then
            C_Timer.After(GREET_DELAY, function()
                SendParty(MyGreeting_GetMsg("party_greet"))
            end)
            for name in pairs(currentMembers) do
                memberJoinTime[name] = memberJoinTime[name] or GetTime()
            end
            wasInParty       = true
            prevPartyMembers = currentMembers
            return
        end

        -- 내가 초대한 것 → wasInParty만 설정 후 아래 새 멤버 감지로 넘어감
        wasInParty = true
    end

    -- ── 파티 해산/퇴장 ───────────────────────────────────
    if not inParty then
        -- 존 전환 중 발생한 false disband는 귓말/리셋 건너뜀
        if not isZoneTransition then
            for name in pairs(prevPartyMembers) do
                local joinTime = memberJoinTime[name]
                if joinTime and (GetTime() - joinTime) >= JOIN_THRESHOLD and not alreadyWhispered[name] then
                    alreadyWhispered[name] = true
                    local n = name
                    C_Timer.After(GREET_DELAY, function()
                        SendWhisper(n, MyGreeting_GetMsg("party_leave"))
                    end)
                end
            end
            memberJoinTime = {}
        end
        wasInParty       = false
        prevPartyMembers = {}
        myInvites        = {}
        alreadyWhispered = {}
        partyLevels      = {}
        myPartyJoinTime  = nil
        return
    end

    -- ── 2. 새로 들어온 멤버 감지 ────────────────────────
    for name in pairs(currentMembers) do
        if not prevPartyMembers[name] then
            memberJoinTime[name] = GetTime()
            partyLevels[name]    = nil   -- UNIT_LEVEL 이벤트로만 채움

            local iInvited = myInvites[name]
            myInvites[name] = nil

            local msg = MyGreeting_GetMsg("party_greet", {name=name})

            local m = msg
            C_Timer.After(GREET_DELAY, function()
                SendParty(m)
            end)
        end
    end

    -- ── 3. 나간 멤버 감지 ───────────────────────────────
    for name in pairs(prevPartyMembers) do
        if not currentMembers[name] then
            local joinTime = memberJoinTime[name]
            if joinTime and (GetTime() - joinTime) >= JOIN_THRESHOLD and not alreadyWhispered[name] then
                alreadyWhispered[name] = true
                local n = name
                C_Timer.After(GREET_DELAY, function()
                    SendWhisper(n, MyGreeting_GetMsg("party_leave"))
                end)
            end
            memberJoinTime[name] = nil
        end
    end

    prevPartyMembers = currentMembers
    wasInParty       = inParty
end

-- ============================================================
-- 이벤트 프레임
-- ============================================================
local partyFrame = CreateFrame("Frame", "MyGreetingPartyFrame", UIParent)

partyFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
partyFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
partyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
partyFrame:RegisterEvent("UNIT_LEVEL")
partyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
partyFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
partyFrame:RegisterEvent("CHAT_MSG_PARTY")
partyFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
partyFrame:RegisterEvent("CHAT_MSG_RAID")
partyFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

partyFrame:SetScript("OnEvent", function(self, event, ...)

    if event == "PLAYER_LEAVING_WORLD" then
        -- 존 전환 시작: memberJoinTime 백업, false disband 감지용 플래그 설정
        isZoneTransition = true
        savedJoinTimes   = {}
        for name, t in pairs(memberJoinTime) do
            savedJoinTimes[name] = t
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- 존 전환 직후엔 파티 데이터가 아직 안 들어오므로 1.5초 뒤에 초기화
        -- isInitializing 플래그로 그 사이에 오는 GROUP_ROSTER_UPDATE 차단
        partyLevels    = {}
        isInitializing = true
        C_Timer.After(1.5, function()
            wasInParty       = IsInParty()
            prevPartyMembers = GetCurrentPartyMembers()
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    if name then
                        -- savedJoinTimes 우선 복원 (존 전환으로 리셋된 경우 대비)
                        memberJoinTime[name] = savedJoinTimes[name] or memberJoinTime[name] or GetTime()
                    end
                end
            end
            isZoneTransition = false
            savedJoinTimes   = {}
            isInitializing   = false
        end)

    elseif event == "GROUP_ROSTER_UPDATE" then
        if isInitializing then return end
        -- 디바운스 (연속 이벤트 묶음)
        if partyTimer then partyTimer:Cancel() end
        partyTimer = C_Timer.NewTimer(0.3, function()
            partyTimer = nil
            ProcessPartyUpdate()
        end)

    elseif event == "UNIT_LEVEL" then
        if IsInRaid() then return end
        local unit = ...
        if unit ~= "player" and unit:find("^party") then
            local name  = UnitName(unit)
            local level = UnitLevel(unit)
            if name and level and IsInParty() then
                local prevLevel = partyLevels[name]
                if prevLevel and level > prevLevel and (level - prevLevel) <= 2 then
                    C_Timer.After(GREET_DELAY, function()
                        SendParty(name .. " 님 레벨업 축하합니다 (" .. level .. ")")
                    end)
                end
                partyLevels[name] = level
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if IsInRaid() then return end
        if not IsInParty() then return end
        C_Timer.After(1, function()
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    if name then
                        if UnitIsDeadOrGhost(unit) and not condoledMembers[name] then
                            condoledMembers[name] = true
                            DoEmote("MOURN", unit)
                        elseif not UnitIsDeadOrGhost(unit) then
                            condoledMembers[name] = nil
                        end
                    end
                end
            end
        end)

    elseif event == "PLAYER_REGEN_DISABLED" then
        if not IsInRaid() then condoledMembers = {} end

    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or
           event == "CHAT_MSG_RAID"  or event == "CHAT_MSG_RAID_LEADER" then
        local msg, sender = ...
        local myName = UnitName("player")
        if sender == myName then return end
        if msg and msg:find("수고") then
            local now = GetTime()
            if now - lastSugoTime >= 60 then
                lastSugoTime = now
                C_Timer.After(GREET_DELAY, function()
                    local m = MyGreeting_GetMsg("sugo")
                    if m ~= "" then SendGroup(m) end
                end)
            end
        end
    end

end)
