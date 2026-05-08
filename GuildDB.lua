-- ============================================================
-- GuildDB.lua
-- 길드 데이터베이스 (본캐/부캐 관리)
-- ============================================================

-- 화면 중앙 빨간 전투 에러 메세지 숨기기 (쿨다운/범위 초과 등 전투 스팸 방지)
UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")

-- 세션 테이블 (매 로그인마다 쪽지에서 재구성)
local altToMain = {}   -- [부캐이름] = 본캐이름
local memberNote = {}  -- [이름] = 공개쪽지

-- ============================================================
-- 길드 쪽지 파싱 → altToMain 테이블 구축
-- ============================================================
local function BuildAltDatabase()
    altToMain  = {}
    memberNote = {}
    local total = GetNumGuildMembers()

    for i = 1, total do
        local name, _, _, _, _, _, publicNote, officerNote = GetGuildRosterInfo(i)
        if name then
            name = name:match("^([^%-]+)") or name
            if publicNote and publicNote ~= "" then
                memberNote[name] = publicNote
            end

            -- 공개 쪽지 + 임원 쪽지 둘 다 확인
            local notes = { publicNote or "", officerNote or "" }
            for _, note in ipairs(notes) do
                local mainName =
                    note:match("부캐%s*%(본캐%s+(.-)%)") or  -- 부캐 (본캐 벌크 업) → 괄호 안 전체
                    note:match("부캐%s*%(본캐:(.-)%)")  or  -- 부캐 (본캐:벌크 업)
                    note:match("부캐[%s:]+(%S+)")             -- 부캐 벌크업 / 부캐:벌크업
                if mainName then
                    -- 앞뒤 공백 제거
                    mainName = mainName:match("^%s*(.-)%s*$")
                    altToMain[name] = mainName
                    break
                end
            end
        end
    end
end

-- ============================================================
-- 외부 접근 함수 (다른 Greeter 파일에서 사용)
-- ============================================================

-- 부캐이면 본캐이름 반환, 아니면 nil
function MyGreeting_GetMainChar(name)
    return altToMain[name]
end

-- 공개 쪽지 반환, 없으면 nil
function MyGreeting_GetNote(name)
    return memberNote[name]
end

-- 본캐/부캐 목록 출력 (디버그용)
function MyGreeting_PrintAltDB()
    local count = 0
    for alt, main in pairs(altToMain) do
        DEFAULT_CHAT_FRAME:AddMessage("|cff88CCFF[GuildDB]|r " .. alt .. " → 본캐: " .. main)
        count = count + 1
    end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff88CCFF[GuildDB]|r 등록된 부캐 없음 (쪽지 확인 필요)")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff88CCFF[GuildDB]|r 총 " .. count .. "명의 부캐 등록됨")
    end
end

-- ============================================================
-- 이벤트 프레임
-- ============================================================
local dbFrame = CreateFrame("Frame", "MyGreetingDBFrame", UIParent)

dbFrame:RegisterEvent("PLAYER_LOGIN")
dbFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

dbFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_GuildInfo.GuildRoster()

    elseif event == "GUILD_ROSTER_UPDATE" then
        -- 로스터 업데이트마다 DB 재구성
        BuildAltDatabase()
    end
end)

-- ============================================================
-- 슬래시 커맨드 확장 (/mg db)
-- GuildGreeter 의 SlashCmdList 와 별개로 여기서 처리
-- ============================================================
-- GuildGreeter.lua 의 슬래시 커맨드에서 "db" 명령어로 호출됨
-- 직접 슬래시 추가 없이 MyGreeting_PrintAltDB() 노출만 함
