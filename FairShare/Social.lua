local _, ns = ...

-- What FairShare knows about the people and items you come across,
-- surfaced where you meet them. All of it is shown to you alone.
--   * Familiar faces: a notice when someone you have run with joins your
--     group.
--   * One line in a player's tooltip: runs together, Ninja and Luckiest.
--   * One line in an item's tooltip: in how many of your runs it was
--     seen, and who got it last.
-- Each can be switched off in the options.

local issecret = issecretvalue or function() return false end

local FACE_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local MAX_NOTICES = 4 -- familiar faces announced at once (a raid can hold many)

-- "5 runs together   avg 3g 20s   Ninja x2"
local function PersonLine(who)
    local parts = { who.runs == 1 and "1 run together" or (who.runs .. " runs together") }
    parts[#parts + 1] = "avg " .. ns.Money(who.value / math.max(who.runs, 1))
    if (who.ninja or 0) > 0 then parts[#parts + 1] = "Ninja x" .. who.ninja end
    if (who.lucky or 0) > 0 then parts[#parts + 1] = "Luckiest x" .. who.lucky end
    return table.concat(parts, "   ")
end

----------------------------------------------------------------------
-- Familiar faces
----------------------------------------------------------------------

local announced = {} -- names already dealt with in the current group
local pending = false
local quietUntil = 0  -- GetTime() until which the group is not news

-- quiet: note who is here without announcing anyone (after a login or a
-- reload, when the group is not news).
local function CheckGroup(quiet)
    local db = ns.db
    if not db then return end
    local n = GetNumGroupMembers()
    if n == 0 then
        wipe(announced)
        return
    end
    local raid = IsInRaid()
    local shown = 0
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = GetUnitName(unit, true)
            -- A name that has not loaded yet is looked at again next time.
            if name and not issecret(name) and name ~= UNKNOWNOBJECT and not announced[name] then
                announced[name] = true
                local who = db.people[name]
                if who and who.runs > 0 and not quiet and db.options.familiar and shown < MAX_NOTICES then
                    shown = shown + 1
                    ns.Notice(ns.ClassColored(ns.DisplayName(name), who.class) .. " |cffb0b0b0- you have met before|r",
                              PersonLine(who), FACE_ICON)
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, isLogin, isReload)
    if event == "PLAYER_ENTERING_WORLD" then
        if isLogin or isReload then
            -- Names can take a few seconds to load after a login.
            quietUntil = GetTime() + 10
            CheckGroup(true)
        end
        return
    end
    -- Roster changes come in bursts, and names take a moment to load.
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        CheckGroup(GetTime() < quietUntil)
    end)
end)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

----------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------

local function PlayerTip(tooltip)
    if not ns.db or not ns.db.options.tipPlayers then return end
    if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
    local _, unit = tooltip:GetUnit()
    if not unit or issecret(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
    local name = GetUnitName(unit, true)
    if not name or issecret(name) then return end
    local who = ns.db.people[name]
    if who and who.runs > 0 then
        tooltip:AddLine("|cff33ff99FairShare|r  " .. PersonLine(who), 1, 1, 1)
    end
end

local function ItemTip(tooltip, data)
    if not ns.db or not ns.db.options.tipItems then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id or issecret(id) or type(id) ~= "number" then return end
    local runs, by = ns.ItemSeen(id)
    if runs then
        tooltip:AddLine(("|cff33ff99FairShare|r  seen in %d %s%s"):format(
            runs, runs == 1 and "run" or "runs", by and (", last to " .. ns.DisplayName(by)) or ""), 1, 1, 1)
    end
end

-- A fault in a tooltip line must never break the game's own tooltip.
local function Safe(fn)
    return function(...) pcall(fn, ...) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    if Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Safe(PlayerTip))
    end
    if Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Safe(ItemTip))
    end
end
