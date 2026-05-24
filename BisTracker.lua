-- ============================================================
-- BisTracker.lua
-- 길드원 던전/레이드 입장 시 BIS 미보유 아이템 길드 채팅 안내
-- ============================================================

local BOSS_NAME_KO = {
    -- 피의 용광로
    ["Broggok"]                    = "브로고크",
    ["Keli'dan the Breaker"]       = "파괴자 켈리단",
    -- 지옥불 요새
    ["Omor the Unscarred"]         = "우적의 오모르",
    ["Vazruden"]                   = "나잔 & 바즈루덴",
    -- 으스러진 손의 전당
    ["Warbringer O'mrogg"]         = "돌격대장 오므로그",
    ["Warchief Kargath Bladefist"] = "대쪽장 카르가스 블레이드피스트",
    -- 마나 무덤
    ["Pandemonius"]                = "팬더모니우스",
    ["Nexus-Prince Shaffar"]       = "연합왕자 샤파르",
    -- 아키나이 납골당
    ["Shirrak the Dead Watcher"]   = "죽음의 감시인 쉴락",
    ["Exarch Maladaar"]            = "총독 말라다르",
    -- 세데크 전당
    ["Talon King Ikiss"]           = "갈퀴대왕 이키스",
    -- 어둠의 미궁
    ["Ambassador Hellmaw"]         = "사사 지옥아귀",
    ["Blackheart the Inciter"]     = "선동자 검은심장",
    ["Grandmaster Vorpil"]         = "단장 보르필",
    ["Murmur"]                     = "울림",
    -- 신록의 정원
    ["Commander Sarannis"]         = "지휘관 새래니스",
    ["Laj"]                        = "라즈",
    ["Warp Splinter"]              = "차원의 분리자",
    -- 메카나르
    ["Pathaleon the Calculator"]   = "철두철미한 파탈리온",
    -- 증기 저장고
    ["Warlord Kalithresh"]         = "장군 칼리스레쉬",
    -- 알카트라즈
    ["Zereketh the Unbound"]       = "속박 풀린 제레케스",
    ["Dalliah the Doomsayer"]      = "파멸의 예언자 달리아",
    ["Harbinger Skyriss"]          = "선구자 스키리스",
    -- 강제 노역소
    ["Mennu the Betrayer"]         = "배반자 멘누",
    ["Quagmirran"]                 = "쿠아그미란",
    -- 지하수령
    ["Hungarfen"]                  = "형가르펜",
    ["Ghaz'an"]                    = "가즈안",
    ["The Black Stalker"]          = "검은 추격자",
    -- 옛 힐스브래드 구릉지
    ["Captain Skarloc"]            = "경비대장 스칼록",
    ["Epoch Hunter"]               = "시대의 사냥꾼",
    -- 검은늪
    ["Chrono Lord Deja"]           = "시간의 군주 데자",
    ["Temporus"]                   = "템퍼루스",
    ["Aeonus"]                     = "아에누스",
    -- 마법학자의 정원
    ["Vexallus"]                   = "벡살루스",
    -- 그룰의 둥지
    ["High King Maulgar"]          = "왕중왕 마울가르",
    ["Gruul The Dragonkiller"]     = "용 학살자 그룰",
    -- 마그테리돈의 둥지
    ["Magtheridon"]                = "마그테리돈",
    -- 불뱀 제단
    ["Hydross the Unstable"]       = "불안정한 히드로스",
    ["The Lurker Below"]           = "심연의 잠복꾼",
    ["Leotheras the Blind"]        = "눈먼 레오테라스",
    ["Fathom-Lord Karathress"]     = "심연의 군주 카라드레스",
    ["Morogrim Tidewalker"]        = "경동파도 모로그림",
    ["Lady Vashj"]                 = "여군주 바쉬",
    -- 폭풍우 요새 (레이드)
    ["Al'ar"]                      = "알라르",
    ["Void Reaver"]                = "공허의 절단기",
    ["High Astromancer Solarian"]  = "고위 점성술사 솔라리안",
    ["Kael'thas Sunstrider"]       = "캘타스 선스트라이더",
    -- 하이잘 정상
    ["Rage Winterchill"]           = "격노한 윈터칠",
    ["Anetheron"]                  = "아네테론",
    ["Kaz'rogal"]                  = "카즈로갈",
    ["Azgalor"]                    = "아즈갈로",
    ["Archimonde"]                 = "아키몬드",
    -- 검은 사원
    ["High Warlord Naj'entus"]     = "대장군 나젠투스",
    ["Supremus"]                   = "궁극의 심연",
    ["Shade of Akama"]             = "아카마의 망령",
    ["Gurtogg Bloodboil"]          = "구르톡 블러드보일",
    ["Reliquary of Souls"]         = "영혼의 성물함",
    ["Teron Gorefiend"]            = "테론 고어핀드",
    ["Mother Shahraz"]             = "대모 샤라즈",
    ["The Illidari Council"]       = "일리다리 의회",
    ["Illidan Stormrage"]          = "일리단 스톰레이지",
    -- 줄아만
    ["Akil'zon"]                   = "아킬존",
    ["Hex Lord Malacrass"]         = "마술 군주 말라크라스",
    ["Zul'jin"]                    = "줄진",
    -- 태양샘 고원
    ["Kalecgos"]                   = "칼렉고스",
    ["Brutallus"]                  = "브루탈루스",
    ["Felmyst"]                    = "지옥안개",
    ["Eredar Twins"]               = "에레다르 쌍둥이",
    ["M'uru"]                      = "므우루",
    ["Kil'jaeden"]                 = "킬제덴",
    -- 월드 보스
    ["Doomwalker"]                 = "파멸의 절단기",
    ["Doom-Lord Kazzak"]           = "파멸의 군주 카자크",
}

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

-- BisSlotData에서 zone 내 id → {boss, slot} 맵 구성
-- slot: "1특" / "2특" / nil (spec1/spec2 이름 매칭 기준)
local function BuildIdBossMap(cls, zone, spec1name, spec2name)
    local map = {}
    if not MyGreeting_BisSlotData then return map end
    local clsBis = MyGreeting_BisSlotData[cls]
    if not clsBis then return map end
    for specName, specBis in pairs(clsBis) do
        local slot = nil
        if spec1name and specName == spec1name then slot = "p1"
        elseif spec2name and specName == spec2name then slot = "p2"
        end
        for _, slotItems in pairs(specBis) do
            for _, entry in ipairs(slotItems) do
                if entry.zone == zone and entry.id then
                    if not map[entry.id] then
                        map[entry.id] = {boss = entry.boss or "", slot = slot}
                    elseif slot then
                        local existing = map[entry.id].slot
                        if not existing then
                            map[entry.id].slot = slot
                        elseif existing ~= slot then
                            map[entry.id].slot = "p1/p2"
                        end
                    end
                end
            end
        end
    end
    return map
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

    -- id → {boss, slot} 맵 구성
    local spec1name = charData.spec1 and charData.spec1.name
    local spec2name = charData.spec2 and charData.spec2.name
    local idBoss = BuildIdBossMap(cls, zone, spec1name, spec2name)

    -- 비동기 로드 트리거 (캐시 없는 아이템 서버 요청)
    for _, id in ipairs(missingIDs) do
        GetItemInfo(id)
    end

    -- 2초 대기 후 아이템 링크 포함 메시지 전송
    local ids2, idBoss2 = missingIDs, idBoss
    C_Timer.After(2, function()
        local parts = {}
        for _, id in ipairs(ids2) do
            local itemName, itemLink = GetItemInfo(id)
            local display = itemLink or (itemName and "[" .. itemName .. "]") or ("[" .. id .. "]")
            local info = idBoss2[id] or {}
            local boss = info.boss or ""
            local src = BOSS_NAME_KO[boss] or (boss ~= "" and boss or "월드드랍")
            if info.slot then src = src .. " - " .. info.slot end
            parts[#parts + 1] = display .. " (" .. src .. ")"
        end

        local prefix = "[BIS] "
        local msg = prefix .. table.concat(parts, ", ")
        if #msg > 250 then
            local fitted = {}
            local budget = 250 - #prefix - 3
            local used = 0
            for i, p in ipairs(parts) do
                local seg = (i == 1) and p or (", " .. p)
                if used + #seg > budget then fitted[#fitted + 1] = "..." ; break end
                fitted[#fitted + 1] = p
                used = used + #seg
            end
            msg = prefix .. table.concat(fitted, ", ")
        end
        SendChatMessage(msg, "GUILD")
    end)
end
