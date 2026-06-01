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
    if not C_Minimap then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.name == trackName and info.active then
            C_Minimap.SetTracking(i, false)
            break
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if select(2, UnitClass("player")) ~= "DRUID" then return end

    trackName = GetSpellInfo(5225)
    if trackName then
        local tf = CreateFrame("Frame")
        tf:RegisterEvent("MINIMAP_UPDATE_TRACKING")
        tf:SetScript("OnEvent", CancelHumanoidTracking)
    end

    hooksecurefunc("TaxiFrame_OnShow", function()
        if GetShapeshiftForm() > 0 then
            CancelShapeshiftForm()
        end
    end)
end)
