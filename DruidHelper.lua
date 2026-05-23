-- ============================================================
-- DruidHelper.lua
-- 드루이드: 인간형 추적 자동 비활성화
-- ============================================================

local trackName = nil
local lastTrackCancel = 0

local function CancelHumanoidTracking()
    if not trackName then return end
    if GetTime() - lastTrackCancel < 3 then return end
    lastTrackCancel = GetTime()
    CancelUnitBuff("player", trackName)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_LOGIN")
    if select(2, UnitClass("player")) ~= "DRUID" then return end

    trackName = GetSpellInfo(5225)
    if trackName then
        local trackFrame = CreateFrame("Frame")
        trackFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
        trackFrame:SetScript("OnEvent", CancelHumanoidTracking)
    end
end)
