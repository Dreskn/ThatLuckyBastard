local _, ns = ...

-- Bets: who will be the lucky bastard, the player with the most loot at
-- the end? A small card asks as a dungeon or raid run starts, once there
-- are two of you: the group's names, five to a row (a raid group to a
-- row), your own among them. Players who join are added, and a call on
-- someone who leaves is dropped, until calls close: at the first roll, the
-- first green or better item anyone loots, or the first boss kill,
-- whichever comes first. Who joins after that is too late. When the run
-- ends the same card says whether you called it. Nothing is ever sent by
-- itself: "Say it" posts one line to the group, and only when clicked.
--
-- The call is kept with the run:
--   s.bet = { pick = name, offered = true, closed = true }
-- and once the run is filed, { pick = name, scored = true } or nothing.
-- db.bets = { calls = n, right = n } counts the calls of the runs filed.

local BTN_W, BTN_H, GAP, PAD = 80, 20, 4, 8
local PER_ROW = 5
local BAR_H = 22       -- a slim title bar, like the meter's
local FOOT_H = 22      -- the line at the foot: the state, and Say it
local AUTO_CLOSE = 8   -- seconds the card stays after a call, unless the mouse is on it
local RESULT_DELAY = 7 -- seconds after leaving before the result, when the race is shown first
local WIDTH = 2 * PAD + PER_ROW * BTN_W + (PER_ROW - 1) * GAP
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t " -- beside your call, wherever names are

local issecret = issecretvalue or function() return false end

local frame, ui, title, skins = ns.MakeWindow("ThatLuckyBastardBetFrame", WIDTH, 100, "MEDIUM", true, nil, BAR_H)
frame:SetPoint("TOP", UIParent, "TOP", 0, -140)

local cardRun        -- the run the card is about
local buttons = {}   -- the name buttons, made as they are needed
local closeToken, resultToken
local Draw

local status = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
local text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")
text:SetWordWrap(true)
text:SetWidth(WIDTH - 2 * PAD)

local function On() return ns.db and ns.db.options.bets end
-- A run you can bet on: one in a dungeon or a raid, not one tracked by hand.
local function Bettable(s) return s ~= nil and not s.manual end
local function InProgress(s) return s ~= nil and s == ns.db.active and not s.leftAt end
local function Open(s) return InProgress(s) and not (s.bet and s.bet.closed) end
local function Tally()
    ns.db.bets = ns.db.bets or { calls = 0, right = 0 }
    return ns.db.bets
end

-- A name in the colour of its class; in ink on the Receipt's paper.
local function Named(name, class, paper)
    local shown = ns.DisplayName(name)
    if paper then return shown end
    return ns.ClassColored(shown, class)
end

----------------------------------------------------------------------
-- Who is there
----------------------------------------------------------------------

-- The group right now, as { name, class, group }: a raid by its groups,
-- a party as one; you are in it.
local function Roster(s)
    local list, seen = {}, {}
    local function Add(unit, group)
        if not UnitExists(unit) then return end
        local name = GetUnitName(unit, true)
        if issecret(name) or not name or name == UNKNOWNOBJECT or seen[name] then return end
        local _, class = UnitClass(unit)
        if issecret(class) then class = nil end
        seen[name] = true
        list[#list + 1] = { name = name, class = class, group = group }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local sub = select(3, GetRaidRosterInfo(i))
            Add("raid" .. i, (not issecret(sub) and tonumber(sub)) or 1)
        end
    else
        Add("player", 1)
        for i = 1, 4 do Add("party" .. i, 1) end
    end
    local me = ns.Me(s)
    if not seen[me] then
        local _, class = UnitClass("player")
        table.insert(list, 1, { name = me, class = not issecret(class) and class or nil, group = 1 })
    end
    table.sort(list, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if (a.name == me) ~= (b.name == me) then return a.name == me end -- you first in your group
        return a.name < b.name
    end)
    return list
end

----------------------------------------------------------------------
-- The outcome
----------------------------------------------------------------------

-- How a call turned out: the lucky bastard (your call, if it shares the
-- top), whether you called it, where your call came, and the share of the
-- loot. Nil when there is no call or no loot.
local function Outcome(s)
    local pick = s and s.bet and s.bet.pick
    if not pick then return nil end
    local sum = ns.Summarize(s)
    if sum.market <= 0 then return nil end
    local top, mine
    for _, p in ipairs(sum.players) do
        if p.rank == 1 then top = p end
        if p.name == pick then mine = p end
    end
    if not top then return nil end
    local called = mine ~= nil and mine.market == top.market
    local winner = called and mine or top
    return { called = called, winner = winner, mine = mine, pick = pick,
             pct = math.floor(winner.market / sum.market * 100 + 0.5) }
end

-- The calls right and made, this run's included before it is filed.
local function Score(s, o)
    local t = Tally()
    local right, calls = t.right, t.calls
    if o and not s.bet.scored then
        calls = calls + 1
        if o.called then right = right + 1 end
    end
    return right, calls
end

-- The line Say it posts, plain: chat takes no colour codes.
local function SayLine(s)
    local pick = s and s.bet and s.bet.pick
    if not pick then return nil end
    local line
    if InProgress(s) then
        line = ("I'm calling %s as That Lucky Bastard."):format(ns.DisplayName(pick))
    else
        local o = Outcome(s)
        if not o then return nil end
        local tail = ("%s is That Lucky Bastard: %s (%d%%)."):format(ns.DisplayName(o.winner.name),
            ns.MoneyPlain(o.winner.market), o.pct)
        if o.called then
            line = "Called it! " .. tail
        else
            line = ("I called %s (%s). "):format(ns.DisplayName(pick), o.mine and ns.Ordinal(o.mine.rank) or "gone")
                .. tail
        end
    end
    return (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""))
end

-- Where Say it posts: the group you are in.
local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and not IsInGroup(LE_PARTY_CATEGORY_HOME or 1) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

----------------------------------------------------------------------
-- The card
----------------------------------------------------------------------

local function NameTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(ns.ClassColored(ns.DisplayName(self.name), self.class))
    GameTooltip:AddLine(Open(cardRun) and "Call them the lucky bastard." or "Calls are closed.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function NameButton(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, ui)
    b.betName = true
    b:SetSize(BTN_W, BTN_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self) ns.BetPick(cardRun, self.name) end)
    b:SetScript("OnEnter", NameTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local sayBtn = ns.MakeButton("Say it", 64, function()
    local line, channel = SayLine(cardRun), Channel()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if line and channel and send then send(line, channel) end
end, ui)
sayBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)

function Draw()
    local s = cardRun
    local _, top = ns.ApplyWindowTheme(skins, title)
    local theme = ns.ThemeName()
    local paper = theme == "receipt"
    local accent = ns.ThemeAccent()
    for _, b in ipairs(buttons) do b:Hide() end
    text:Hide()
    sayBtn:SetFlat(theme ~= "classic")

    local y = top - PAD -- where the next thing goes, from the top
    local heading, foot
    local pick = s and s.bet and s.bet.pick
    if not On() then
        heading, foot = "Bets", "Bets are off: Options › During a run."
    elseif not s or not Bettable(s) then
        heading, foot = "Bets", "Bets are for dungeon and raid runs."
    elseif Open(s) then
        heading = "Who's the lucky bastard?"
        foot = pick and ("Your call: " .. ns.FirstName(pick)) or "Calls close at the first roll."
        local row, col, lastGroup = 0, PER_ROW, nil
        for i, r in ipairs(Roster(s)) do
            if r.group ~= lastGroup or col == PER_ROW then row, col, lastGroup = row + 1, 0, r.group end
            col = col + 1
            local b = NameButton(i)
            b.name, b.class = r.name, r.class
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", PAD + (col - 1) * (BTN_W + GAP), y - (row - 1) * (BTN_H + GAP))
            local mine = r.name == pick
            if paper then
                b.bg:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
                if mine then b.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.45) end
                b.hl:SetColorTexture(ns.INK[1], ns.INK[2], ns.INK[3], 0.10)
                b.text:SetFontObject("ThatLuckyBastardReceiptInk")
            else
                if mine then
                    b.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.40)
                elseif theme == "classic" then
                    b.bg:SetColorTexture(0, 0, 0, 0.35) -- dark on the game's panel
                else
                    b.bg:SetColorTexture(1, 1, 1, 0.06)
                end
                b.hl:SetColorTexture(1, 1, 1, 0.15)
                b.text:SetFontObject("GameFontHighlightSmall")
            end
            local first = ns.FirstName(r.name)
            b.text:SetText((mine and STAR or "") .. (paper and first:upper() or ns.ClassColored(first, r.class)))
            b:Show()
        end
        y = y - row * (BTN_H + GAP) + GAP - PAD
    else
        local lines
        if InProgress(s) then
            heading = "Your call"
            lines = pick and ("You called " .. Named(pick, s.players[pick] and s.players[pick].class, paper)
                .. ". Calls are closed.") or "No call this run: calls are closed."
        else
            heading = "That Lucky Bastard"
            local o = Outcome(s)
            if not pick then
                lines = "No call this run."
            elseif not o then
                lines = "No loot in this run, so no lucky bastard."
            else
                local who = Named(o.winner.name, o.winner.class, paper)
                local tail = ("%s is the lucky bastard: %s, %d%% of the loot."):format(who,
                    ns.MoneyPlain(o.winner.market), o.pct)
                if o.called then
                    lines = (paper and "CALLED IT! " or "|cffffd100Called it!|r ") .. tail
                else
                    lines = tail .. ("\nYour call, %s, came %s."):format(
                        Named(pick, o.mine and o.mine.class, paper), o.mine and ns.Ordinal(o.mine.rank) or "nowhere")
                end
                local right, calls = Score(s, o)
                lines = lines .. ("\n|cff909090Calls right: %d of %d.|r"):format(right, calls)
            end
        end
        text:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlight")
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", PAD, y)
        text:SetText(lines)
        text:Show()
        y = y - (text:GetStringHeight() or 14) - PAD
    end

    title:SetText(("|T%s:14:14:0:0|t %s"):format(ns.LOGO, heading))
    status:ClearAllPoints()
    status:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
    status:SetPoint("RIGHT", sayBtn, "LEFT", -6, 0)
    status:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
    status:SetText(foot or "")
    local say = SayLine(s) ~= nil and On()
    sayBtn:SetShown(say)
    if say then sayBtn:SetOn(Channel() ~= nil) end
    frame:SetHeight(-y + FOOT_H + PAD)
end

-- Opens the card on run `s`, where it was last put.
local function Show(s)
    cardRun = s
    local at = ns.db.betCard
    if at and at.point then
        frame:ClearAllPoints()
        frame:SetPoint(at.point, UIParent, at.relPoint or at.point, at.x or 0, at.y or 0)
    end
    if frame:IsShown() then Draw() else frame:Show() end
    frame:Raise()
end

frame:SetScript("OnShow", function() Draw() end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.db.betCard = { point = point, relPoint = relPoint, x = x, y = y }
end)

----------------------------------------------------------------------
-- What the rest of the addon calls
----------------------------------------------------------------------

-- The Bet button and /tlb bet: the card for run `s` (the one on show), or
-- shut if it is already open on it.
function ns.ToggleBet(s)
    if frame:IsShown() and cardRun == s then
        frame:Hide()
    else
        Show(s)
    end
end

-- A call on `name` in run `s`, while calls are open.
function ns.BetPick(s, name)
    if not (On() and Bettable(s) and Open(s)) then return end
    s.bet = s.bet or {}
    s.bet.pick = name
    ns.PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    if frame:IsShown() and cardRun == s then Draw() end
    ns.Refresh() -- the mark beside your call, in the windows and the meter
    local token = {}
    closeToken = token
    C_Timer.After(AUTO_CLOSE, function()
        if closeToken == token and frame:IsShown() and cardRun == s and not frame:IsMouseOver() then frame:Hide() end
    end)
end

-- The group changed (Core's UpdateRoster), or a run started: the card is
-- offered once there are two of you, and keeps up with who is there.
function ns.BetRoster(s)
    if not (On() and Bettable(s) and Open(s)) then return end
    local roster = Roster(s)
    if s.bet and s.bet.pick then
        local here = false
        for _, r in ipairs(roster) do
            if r.name == s.bet.pick then here = true end
        end
        if not here then s.bet.pick = nil end -- a call on someone who left is no call
    end
    if not (s.bet and s.bet.offered) and #roster >= 2 then
        s.bet = s.bet or {}
        s.bet.offered = true
        Show(s)
    elseif frame:IsShown() and cardRun == s then
        Draw()
    end
end

-- Something worth having has turned up in run `s` (a roll, a green or
-- better item, a boss): calls are closed.
function ns.BetClose(s)
    if not (Bettable(s) and InProgress(s)) or (s.bet and s.bet.closed) then return end
    s.bet = s.bet or {}
    s.bet.closed = true
    if frame:IsShown() and cardRun == s then frame:Hide() end
end

-- Run `s` was left (Core's ShowRunEnd): once the race has been run, the
-- card says how the call turned out.
function ns.BetResult(s)
    if not (On() and Bettable(s) and Outcome(s)) then return end
    local token = {}
    resultToken = token
    C_Timer.After(ns.db.options.popupLeave and RESULT_DELAY or 1, function()
        if resultToken ~= token then return end
        Show(s)
        local o = Outcome(s)
        if o and o.called and ns.db.options.ceremonySound then ns.PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
    end)
end

-- Run `s` is filed (Core's FinalizeSession): its call is counted, once,
-- and only the call itself is kept.
function ns.BetScore(s)
    if not (s and s.bet) then return end
    local pick = s.bet.pick
    if pick and not s.bet.scored then
        local o = Outcome(s)
        if o then
            local t = Tally()
            t.calls = t.calls + 1
            if o.called then t.right = t.right + 1 end
        end
    end
    s.bet = pick and { pick = pick, scored = true } or nil
end

-- What goes before a name in the windows: a star beside your call.
function ns.BetMark(s, name)
    if On() and s and s.bet and s.bet.pick == name then return STAR end
    return ""
end

-- The game's own roll window: calls close as it opens.
local events = CreateFrame("Frame")
events:RegisterEvent("START_LOOT_ROLL")
events:SetScript("OnEvent", function()
    if ns.db then ns.BetClose(ns.db.active) end
end)

ns.OnRerender(function()
    if not frame:IsShown() then return end
    if On() then Draw() else frame:Hide() end
end)
