local _, ns = ...
-- ============================================================
-- GuildInviter.lua
-- 귓말로 "길드초대" / "길드 초대" 받으면 자동 길드 초대
-- ============================================================

local INVITE_COOLDOWN = 60   -- 같은 사람 재초대 방지 (초)
local lastInvite = {}        -- [이름] = GetTime()

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40FF40[myGreeting]|r " .. msg)
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:SetScript("OnEvent", function(_, _, msg, sender)
    if ns.GuildOff() then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    if not msg:gsub("%s+", ""):find("길드초대") then return end

    local name = sender:match("^([^%-]+)") or sender
    if not IsInGuild() then return end
    if CanGuildInvite and not CanGuildInvite() then
        Print(name .. " 님 길드초대 요청 — 초대 권한 없음")
        return
    end

    local now = GetTime()
    if lastInvite[name] and now - lastInvite[name] < INVITE_COOLDOWN then return end
    lastInvite[name] = now

    C_GuildInfo.Invite(sender)
    Print(name .. " 님 길드초대 보냄")
end)
