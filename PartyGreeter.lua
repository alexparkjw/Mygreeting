local _, ns = ...  -- Compat.lua (beta 포팅)
local SendChatMessage = ns.SendChatMessage
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
local memberJoinTime    = {}   -- [이름] = time() : 파티 참가 시각 (Unix, /reload 넘어 유지하려고 GetTime 대신 사용)
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
local lastGreetTime     = 0      -- 파티 인사 마지막 전송 시각 (중복 인사 방지)
local GREET_COOLDOWN    = 10     -- 이 시간 안에 또 들어오면 인사 생략 (초)
local JOIN_SETTLE       = 5      -- 내가 파티 들어간 직후 로스터가 나눠 들어오는 시간 (초)
local settleUntil       = 0      -- 남의 파티에 들어간 경우 이 시각까지 새 멤버 인사 생략

-- 파티 인사 1회 (쿨타임 안이면 생략)
local function GreetParty()
    local now = GetTime()
    if now - lastGreetTime < GREET_COOLDOWN then return end
    lastGreetTime = now
    C_Timer.After(GREET_DELAY, function()
        local m = MyGreeting_GetMsg("party_greet")
        if m ~= "" then SendChatMessage(m, "PARTY") end
    end)
end

-- ============================================================
-- 현재 파티원 목록 (자신 제외)
-- ============================================================
local function GetCurrentPartyMembers()
    local members = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            -- 로스터 로딩 중 "알 수 없음" 이름은 제외 (나중에 실제 이름으로 바뀌며 새 멤버로 오인됨)
            if name and name ~= "" and name ~= UNKNOWNOBJECT then
                -- 값 = 귓말용 전체 이름 (beta: 이름+성). 떠난 뒤엔 유닛이 없어 성을 못 구하므로 미리 저장
                members[name] = ns.UnitWhisperName(unit) or name
            end
        end
    end
    return members
end

local function IsInParty()
    return UnitExists("party1")
end

-- 파티원 현재 레벨을 미리 기억 (없으면 첫 레벨업을 놓침). 아직 모르는 레벨(0 이하)은 건너뜀
local function SeedPartyLevels()
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local name, level = UnitName(unit), UnitLevel(unit)
            if name and level and level > 0 and not partyLevels[name] then
                partyLevels[name] = level
            end
        end
    end
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

-- 작별 귓말: 던전 안(채팅 잠금)이면 모아 뒀다가 밖에서 전송
local function SendWhisper(name, msg, fullName)
    -- 파티 유닛 중 해당 이름 찾아서 접속 상태 확인
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitName(unit) == name then
            if not UnitIsConnected(unit) then return end
            break
        end
    end
    ns.SendChatMessageLater(msg, "WHISPER", nil, fullName or name)
end

-- ============================================================
-- InviteUnit 훅
-- 내가 초대한 사람을 추적하기 위해 후킹
-- ============================================================
-- beta: 전역 덮어쓰기는 taint 유발 → hooksecurefunc 사용
local function OnInvite(name)
    if name and name ~= "" then
        myInvites[name] = true
    end
end
if InviteUnit then hooksecurefunc("InviteUnit", OnInvite) end
if C_PartyInfo and C_PartyInfo.InviteUnit then hooksecurefunc(C_PartyInfo, "InviteUnit", OnInvite) end

-- ============================================================
-- LeaveParty 훅 (구/신 API 양쪽)
-- ============================================================
local function OnLeaveParty()
    if IsInRaid() then return end
    local stayedLong = myPartyJoinTime and (time() - myPartyJoinTime) >= JOIN_THRESHOLD
    local base = MyGreeting_GetMsg("party_leave")
    local msg  = stayedLong and ("먼저 갈게요 " .. base) or base
    local remaining = GetCurrentPartyMembers()
    for name, full in pairs(remaining) do
        if not alreadyWhispered[name] then
            alreadyWhispered[name] = true
            local n, f = name, full
            C_Timer.After(0, function()
                SendWhisper(n, msg, f)
            end)
        end
    end
end

if LeaveParty then hooksecurefunc("LeaveParty", OnLeaveParty) end
if C_PartyInfo and C_PartyInfo.LeaveParty then hooksecurefunc(C_PartyInfo, "LeaveParty", OnLeaveParty) end

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
        myPartyJoinTime = time()
        -- 현재 파티원 중 내가 초대한 사람이 있는지 확인
        local invitedSomeone = false
        for name in pairs(currentMembers) do
            if myInvites[name] then
                invitedSomeone = true
                break
            end
        end

        if not invitedSomeone then
            settleUntil = GetTime() + JOIN_SETTLE
            GreetParty()
            for name in pairs(currentMembers) do
                memberJoinTime[name] = memberJoinTime[name] or time()
            end
            wasInParty       = true
            prevPartyMembers = currentMembers
            SeedPartyLevels()
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
                if joinTime and (time() - joinTime) >= JOIN_THRESHOLD and not alreadyWhispered[name] then
                    alreadyWhispered[name] = true
                    local n, f = name, prevPartyMembers[name]
                    C_Timer.After(GREET_DELAY, function()
                        SendWhisper(n, MyGreeting_GetMsg("party_leave"), f)
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
    -- 내가 막 들어간 직후엔 기존 파티원이 나눠서 들어오므로 인사 안 함
    local settling = GetTime() < settleUntil
    local anyNew = false
    for name in pairs(currentMembers) do
        if not prevPartyMembers[name] then
            memberJoinTime[name] = time()
            partyLevels[name]    = nil   -- 아래 SeedPartyLevels 에서 현재 레벨로 채움
            myInvites[name] = nil
            anyNew = true
        end
    end
    SeedPartyLevels()
    -- 여러 명이 한꺼번에 들어와도 인사는 1번
    if anyNew and not settling then GreetParty() end

    -- ── 3. 나간 멤버 감지 ───────────────────────────────
    for name in pairs(prevPartyMembers) do
        if not currentMembers[name] then
            local joinTime = memberJoinTime[name]
            if joinTime and (time() - joinTime) >= JOIN_THRESHOLD and not alreadyWhispered[name] then
                alreadyWhispered[name] = true
                local n, f = name, prevPartyMembers[name]
                C_Timer.After(GREET_DELAY, function()
                    SendWhisper(n, MyGreeting_GetMsg("party_leave"), f)
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
partyFrame:RegisterEvent("PLAYER_LOGOUT")
partyFrame:RegisterEvent("UNIT_LEVEL")
partyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
partyFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
partyFrame:RegisterEvent("CHAT_MSG_PARTY")
partyFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
partyFrame:RegisterEvent("CHAT_MSG_RAID")
partyFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

partyFrame:SetScript("OnEvent", function(self, event, ...)

    if event == "PLAYER_LOGOUT" then
        -- /reload·로그아웃 시 참가 시각 저장 → 다시 들어오면 복원 (5분 기준 리셋 방지)
        if MyGreetingDB and IsInParty() then
            local m = {}
            for name, t in pairs(memberJoinTime) do m[name] = t end
            MyGreetingDB.partyJoin = { members = m, me = myPartyJoinTime }
        end

    elseif event == "PLAYER_LEAVING_WORLD" then
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
            -- /reload 전 저장해 둔 참가 시각 (PLAYER_LOGOUT 에서 기록)
            local saved     = MyGreetingDB and MyGreetingDB.partyJoin
            local persisted = (saved and saved.members) or {}
            if saved and saved.me and IsInParty() and not myPartyJoinTime then myPartyJoinTime = saved.me end
            if MyGreetingDB then MyGreetingDB.partyJoin = nil end
            wasInParty       = IsInParty()
            prevPartyMembers = GetCurrentPartyMembers()
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    if name then
                        -- savedJoinTimes 우선 복원 (존 전환으로 리셋된 경우 대비)
                        memberJoinTime[name] = savedJoinTimes[name] or memberJoinTime[name] or persisted[name] or time()
                    end
                end
            end
            SeedPartyLevels()
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
                            ns.DoEmote("MOURN", unit)
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
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        if ns.IsMe(sender) then return end
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
