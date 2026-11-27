local _, ns = ...

-- The farm strip: a small band on the screen for farming outside
-- dungeons, in two rows. Before a farm it holds a Start key; during one,
-- its clock (pauses left out) and the keys Pause (Resume) and Stop, and
-- under them your gold: your total, and smaller, your coins, your items
-- and your gold per hour. It is as long as that row needs, and never
-- shorter than WIDTH. In a group, a switch sits above the strip's right
-- end, like the slide switch on an old radio: "group" with the group's
-- total, a slot with a ridged slider, "solo". The strip holds only what
-- is yours; a click on the switch slides it over, making the farm solo
-- (you alone are recorded) and back (ns.SetFarmSolo). Opened by a shift-click
-- on the minimap button or /tlb farm; moved by dragging it, or locked in
-- place with the padlock; where it was and whether it was open are kept
-- from one session to the next (db.farmStrip).
--
-- What you pick up drops out from under the strip as a line (the item,
-- how many, what it is worth), stays a moment, then folds back under it,
-- and its worth goes into your total. The same item again while its line
-- is out adds to it; at most MAX_POPS lines show at once. Coins you loot,
-- and in a group what the others get, rise as small amounts: yours out of
-- the gold row into the free part of the row above, the others' above
-- the group's tab. Until each has gone in, the totals leave it out.
--
-- Going into a dungeon sets the farm aside (Core): the strip shows it as
-- it stood at the door, with only Stop. Out of the dungeon, the gold row
-- asks "Add <dungeon> and resume?", with Yes and No (ns.AnswerAside);
-- after a Yes, the dungeons are one more small figure.
--
-- The farm itself (start, pause, stop, how it ends) is Core's: ns.StartFarm
-- and the others. This file only shows it.

local WIDTH, HEIGHT = 250, 50
local ROW1, ROW2 = -15, -36  -- the middles of the two rows, from the top
local KEY = 22               -- the keys' side
local CORNER = 14            -- the padlock and the cross, on show under the mouse
local MEDIA = "Interface\\AddOns\\ThatLuckyBastard\\Media\\"
local ROW_H = 26             -- a pop-up line
local INSET = 8              -- the lines are this much narrower than the strip, on each side
local IN, STAY, FOLD = 0.15, 2.6, 0.3 -- a line drops out, stays, folds back (seconds from its start)
local RISE, RISE_PX = 1.5, 14 -- an amount rises this many pixels in this many seconds, fading at the end
local FLASH = 0.3            -- a total shows in the accent this long once something goes in
local MAX_POPS = 5

local strip = CreateFrame("Frame", "ThatLuckyBastardFarmFrame", UIParent)
strip:SetSize(WIDTH, HEIGHT)
strip:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -240) -- under the minimap, to begin with
strip:SetFrameStrata("MEDIUM")
strip:SetClampedToScreen(true)
strip:SetMovable(true)
strip:EnableMouse(true)
strip:RegisterForDrag("LeftButton")
strip:Hide()

-- The look: a dark band with the accent under it (Modern), the game's
-- dark with a thin frame (Classic), a strip of till paper (Receipt).
strip.bg = strip:CreateTexture(nil, "BACKGROUND")
strip.bg:SetAllPoints()
strip.line = strip:CreateTexture(nil, "BORDER")
strip.line:SetPoint("BOTTOMLEFT")
strip.line:SetPoint("BOTTOMRIGHT")
strip.edges = {}
for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = strip:CreateTexture(nil, "BORDER")
    t:SetPoint(side[1])
    t:SetPoint(side[2])
    if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
    strip.edges[i] = t
end

strip.logo = strip:CreateTexture(nil, "ARTWORK")
strip.logo:SetSize(16, 16)
strip.logo:SetPoint("LEFT", strip, "TOPLEFT", 8, ROW1)
strip.logo:SetTexture(ns.LOGO)

local function Text(font)
    local fs = strip:CreateFontString(nil, "OVERLAY", font)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end
strip.clock = Text("GameFontHighlight")
strip.clock:SetPoint("LEFT", strip.logo, "RIGHT", 8, 0)
strip.clock:SetWidth(58)
-- The gold row: the total, then the smaller figures one after the other.
strip.total = Text("GameFontHighlight")
strip.total:SetPoint("LEFT", strip, "TOPLEFT", 8, ROW2)
strip.coins = Text("GameFontHighlightSmall")
strip.coins:SetPoint("LEFT", strip.total, "RIGHT", 12, 0)
strip.items = Text("GameFontHighlightSmall")
strip.items:SetPoint("LEFT", strip.coins, "RIGHT", 10, 0)
strip.dungeons = Text("GameFontHighlightSmall")
strip.dungeons:SetPoint("LEFT", strip.items, "RIGHT", 10, 0)
strip.hour = Text("GameFontHighlightSmall") -- after the dungeons, or the items (see Place)
strip.hour:SetPoint("LEFT", strip.items, "RIGHT", 10, 0)
-- Out of a dungeon, in place of the gold row: the question.
strip.ask = Text("GameFontHighlight")
strip.ask:SetPoint("LEFT", strip, "TOPLEFT", 8, ROW2)
strip.ask:Hide()
-- The switch, above the strip (in a group, or with others in the farm,
-- only): the group's word and total, the slot and its slider, "solo".
-- The word of the side chosen is in the strong ink, the other dim.
local SLOT_W, SLOT_H, THUMB_W = 30, 10, 14
local SLIDE = 0.15 -- seconds the slider takes from one end to the other
local tab = CreateFrame("Button", nil, strip)
strip.tab = tab
tab:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", -INSET, 0)
tab:SetHeight(19)
tab.bg = tab:CreateTexture(nil, "BACKGROUND")
tab.bg:SetAllPoints()
tab.hl = tab:CreateTexture(nil, "HIGHLIGHT")
tab.hl:SetAllPoints()
tab:Hide()
strip.group = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
strip.group:SetWordWrap(false)
strip.group:SetPoint("LEFT", 8, 0)
tab.slot = CreateFrame("Frame", nil, tab)
tab.slot:SetSize(SLOT_W + 2, SLOT_H + 2)
tab.slot:SetPoint("LEFT", strip.group, "RIGHT", 7, 0)
tab.slot.edge = tab.slot:CreateTexture(nil, "BACKGROUND")
tab.slot.edge:SetAllPoints()
tab.slot.well = tab.slot:CreateTexture(nil, "BORDER")
tab.slot.well:SetPoint("TOPLEFT", 1, -1)
tab.slot.well:SetPoint("BOTTOMRIGHT", -1, 1)
tab.thumb = tab.slot:CreateTexture(nil, "ARTWORK")
tab.thumb:SetSize(THUMB_W, SLOT_H)
tab.ridges = {}
for i = -1, 1 do
    local r = tab.slot:CreateTexture(nil, "OVERLAY")
    r:SetSize(1, SLOT_H - 4)
    r:SetPoint("CENTER", tab.thumb, "CENTER", i * 3, 0)
    tab.ridges[#tab.ridges + 1] = r
end
strip.soloWord = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
strip.soloWord:SetPoint("LEFT", tab.slot, "RIGHT", 7, 0)
strip.soloWord:SetText("solo")
local SMALL = { strip.coins, strip.items, strip.dungeons, strip.hour, strip.group }

-- The slider towards the side chosen (tab.side), `dt` seconds on; at
-- once without `dt`, or when it has no place yet (tab.x).
local function Slide(dt)
    local target = tab.side == "solo" and (SLOT_W - THUMB_W) or 0
    local x = tab.x
    if x == target then return end
    if x == nil or not dt then
        x = target
    else
        local step = (SLOT_W - THUMB_W) * dt / SLIDE
        x = x < target and math.min(target, x + step) or math.max(target, x - step)
    end
    tab.x = x
    tab.thumb:ClearAllPoints()
    tab.thumb:SetPoint("LEFT", tab.slot, "LEFT", 1 + x, 0)
end

----------------------------------------------------------------------
-- Keys: Start (Resume), Pause, Stop; the padlock and the cross
----------------------------------------------------------------------

-- A key: its face, the edge under it on paper, its tooltip.
local function KeyBase(onClick, tip)
    local k = CreateFrame("Button", nil, strip)
    k:SetSize(KEY, KEY)
    k.face = k:CreateTexture(nil, "BACKGROUND")
    k.face:SetAllPoints()
    k.edge = k:CreateTexture(nil, "BORDER")
    k.edge:SetPoint("BOTTOMLEFT")
    k.edge:SetPoint("BOTTOMRIGHT")
    k.edge:SetHeight(2)
    k.hl = k:CreateTexture(nil, "HIGHLIGHT")
    k.hl:SetAllPoints()
    k:SetScript("OnClick", onClick)
    k:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        tip(self)
        GameTooltip:Show()
    end)
    k:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return k
end

-- A square key with a glyph from keys.tga (start, pause, stop, close).
local GLYPH = { start = 0, pause = 1, stop = 2, close = 3 }
local function Key(onClick, tip)
    local k = KeyBase(onClick, tip)
    k.icon = k:CreateTexture(nil, "ARTWORK")
    k.icon:SetSize(14, 14)
    k.icon:SetPoint("CENTER")
    k.icon:SetTexture(MEDIA .. "keys")
    function k:SetGlyph(name)
        local i = GLYPH[name]
        self.icon:SetTexCoord(i / 4, (i + 1) / 4, 0, 1)
        self.glyph = name
    end
    return k
end

-- A lower key with a word on it (Yes, No), as wide as the word.
local function WordKey(word, onClick, tip)
    local k = KeyBase(onClick, tip)
    k:SetHeight(KEY - 4)
    k.text = k:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k.text:SetPoint("CENTER", 0, 1)
    k.text:SetText(word)
    k:Hide()
    return k
end

local Draw -- below

-- Locked, the strip stays where it is (db.farmStrip.locked).
local function Saved() return ns.db and ns.db.farmStrip or {} end
local function Locked() return Saved().locked == true end

-- The first key: Start, Pause or Resume, as the farm stands.
strip.main = Key(function()
    local s = ns.ActiveFarm()
    if not s then
        local ok, why = ns.StartFarm()
        if not ok and why then ns.Notice(ns.NAME, why) end
    elseif s.pausedAt then
        ns.ResumeFarm()
    else
        ns.PauseFarm()
    end
    Draw()
end, function(self)
    local s = ns.ActiveFarm()
    if not s then
        GameTooltip:AddLine("Start")
        GameTooltip:AddLine(self.blocked or "Records your loot from now on.", 0.8, 0.8, 0.8, true)
    elseif s.pausedAt then
        GameTooltip:AddLine("Resume")
    else
        GameTooltip:AddLine("Pause")
        GameTooltip:AddLine("Nothing is recorded, and the clock stops.", 0.8, 0.8, 0.8, true)
    end
end)
strip.stop = Key(function()
    ns.StopFarm()
    Draw()
end, function()
    GameTooltip:AddLine("Stop")
    GameTooltip:AddLine(ns.ActiveFarm() and "Ends the farm and shows it." or "Ends the farm where you went in.",
                        0.8, 0.8, 0.8, true)
end)
strip.stop:SetGlyph("stop")

-- The answers to the question, at the right end of the gold row.
local flash -- below
strip.no = WordKey("No", function()
    ns.AnswerAside(false)
    Draw()
end, function()
    GameTooltip:AddLine("No")
    GameTooltip:AddLine("The farm ends where you went in.", 0.8, 0.8, 0.8, true)
end)
strip.no:SetPoint("RIGHT", strip, "TOPRIGHT", -6, ROW2)
strip.yes = WordKey("Yes", function()
    ns.AnswerAside(true)
    flash.dungeons = GetTime()
    Draw()
end, function()
    GameTooltip:AddLine("Yes")
    GameTooltip:AddLine("The farm goes on, with the dungeon in it.", 0.8, 0.8, 0.8, true)
end)
strip.yes:SetPoint("RIGHT", strip.no, "LEFT", -4, 0)

-- The padlock and the cross, at the right end, under the mouse only.
strip.lock = CreateFrame("Button", nil, strip)
strip.lock:SetSize(CORNER, CORNER)
strip.lock:SetPoint("RIGHT", strip, "TOPRIGHT", -6, ROW1)
strip.lock.icon = strip.lock:CreateTexture(nil, "OVERLAY")
strip.lock.icon:SetAllPoints()
strip.lock.icon:SetTexture(MEDIA .. "lock")
strip.close = CreateFrame("Button", nil, strip)
strip.close:SetSize(CORNER, CORNER)
strip.close:SetPoint("RIGHT", strip.lock, "LEFT", -4, 0)
strip.close.icon = strip.close:CreateTexture(nil, "OVERLAY")
strip.close.icon:SetAllPoints()
strip.close.icon:SetTexture(MEDIA .. "keys")
strip.close.icon:SetTexCoord(0.75, 1, 0, 1)
strip.stop:SetPoint("RIGHT", strip.close, "LEFT", -6, 0)
strip.main:SetPoint("RIGHT", strip.stop, "LEFT", -4, 0)

local function CornerTip(self, line, more)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(line)
    GameTooltip:AddLine(more, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end
strip.lock:SetScript("OnClick", function(self)
    ns.db.farmStrip = ns.db.farmStrip or {}
    ns.db.farmStrip.locked = not Locked() or nil
    Draw()
    CornerTip(self, Locked() and "Unlock" or "Lock", Locked() and "Its place is locked." or "Keeps its place.")
end)
strip.lock:SetScript("OnEnter", function(self)
    CornerTip(self, Locked() and "Unlock" or "Lock", Locked() and "Its place is locked." or "Keeps its place.")
end)
strip.lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
strip.close:SetScript("OnClick", function() strip:Hide() end)
strip.close:SetScript("OnEnter", function(self)
    CornerTip(self, "Hide", "A farm goes on. Shift-click the minimap button to show it again.")
end)
strip.close:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The switch: a click slides it between the group and you alone.
local function TabTip(self)
    local s = ns.ActiveFarm()
    if s and s.solo then
        CornerTip(self, "Solo", "Only your loot is recorded. Click: the group's too.")
    else
        CornerTip(self, "Group", "Everyone's loot is recorded. Click: only yours.")
    end
end
strip.tab:SetScript("OnClick", function(self)
    local s = ns.ActiveFarm()
    ns.SetFarmSolo(not (s and s.solo))
    Draw()
    TabTip(self)
end)
strip.tab:SetScript("OnEnter", TabTip)
strip.tab:SetScript("OnLeave", function() GameTooltip:Hide() end)

strip:SetScript("OnDragStart", function(self)
    if not Locked() then self:StartMoving() end
end)
strip:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.db.farmStrip = ns.db.farmStrip or {}
    local saved = ns.db.farmStrip
    saved.point, saved.relPoint, saved.x, saved.y = point, relPoint, x, y
end)
strip:SetScript("OnEnter", function(self)
    local aside = not ns.ActiveFarm() and ns.FarmAside()
    local s = ns.ActiveFarm() or aside
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(s and (s.name or ns.NAME) or ns.BRAND)
    if aside then
        GameTooltip:AddLine("Set aside for a dungeon.", 0.8, 0.8, 0.8)
    elseif s and s.pausedAt then
        GameTooltip:AddLine("Paused", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(s and "Click the breakdown's run label to add a note." or "Start with the key on the right.",
                        0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
strip:SetScript("OnLeave", function() GameTooltip:Hide() end)

----------------------------------------------------------------------
-- What the strip says
----------------------------------------------------------------------

-- What has not gone into the totals yet (copper): your coins still
-- rising, your items still out, and all of that and the others' for the
-- group.
local held = { coins = 0, items = 0, group = 0 }
-- The farm's totals as the breakdown has them, from the last draw.
local totals = { coins = 0, items = 0, dungeons = 0, group = 0, players = 1 }
flash = { coins = 0, items = 0, dungeons = 0, group = 0 } -- GetTime() of the last thing that went in
-- The question, from the last draw: its words, when it is up.
local asking

local function Clock(seconds)
    seconds = math.floor(seconds or 0)
    return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

-- Gold alone, for the smaller figures: "61g" (silver under a gold).
local function Gold(copper, ink)
    local g = math.floor((copper or 0) / 10000)
    if g <= 0 then return ink and ns.MoneyPlain(copper) or ns.Money(copper) end
    local text = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
    return (ink and text or ("|cffffd700" .. text .. "|r")) .. "g"
end

local function Paper() return ns.ThemeName() == "receipt" end

-- The addon's name, as the strip says it before a farm: "Lucky" in the
-- accent (plain ink on paper).
local function Brand(ink)
    if ink then return ns.NAME end
    local a = ns.ThemeAccent()
    return ("That |cff%02x%02x%02xLucky|r Bastard"):format(a[1] * 255 + 0.5, a[2] * 255 + 0.5, a[3] * 255 + 0.5)
end

-- The strip as long as its gold row (or the question) needs, never
-- shorter than WIDTH; the switch as wide as its words and its slot.
local function Place()
    local need = 8
    if asking then
        need = need + strip.ask:GetStringWidth() + 10 + strip.yes:GetWidth() + 4 + strip.no:GetWidth() + 6
    else
        local dungeons = (strip.dungeons:GetText() or "") ~= ""
        strip.hour:ClearAllPoints()
        strip.hour:SetPoint("LEFT", dungeons and strip.dungeons or strip.items, "RIGHT", 10, 0)
        for i, fs in ipairs({ strip.total, strip.coins, strip.items, strip.dungeons, strip.hour }) do
            if i ~= 4 or dungeons then need = need + fs:GetStringWidth() + (i == 1 and 12 or 10) end
        end
    end
    strip:SetWidth(math.max(WIDTH, math.ceil(need)))
    local group = (strip.group:GetText() or "") ~= ""
    tab:SetShown(group)
    if group then
        tab:SetWidth(8 + strip.group:GetStringWidth() + 7 + SLOT_W + 2 + 7 + strip.soloWord:GetStringWidth() + 8)
    end
end

-- The totals and the clock, from what is known; called every second and
-- whenever something goes in.
local function Figures()
    local s = ns.ActiveFarm() or ns.FarmAside()
    local ink = Paper()
    local now = GetTime()
    for _, w in ipairs({ strip.ask, strip.yes, strip.no }) do w:SetShown(asking ~= nil) end
    strip.total:SetShown(not asking)
    if not s then
        strip.clock:SetText(Clock(0))
        strip.total:SetText(Brand(ink))
        for _, fs in ipairs(SMALL) do fs:SetText("") end
        Place()
        return
    end
    local seconds = ns.RunDuration(s) or 0
    strip.clock:SetText(Clock(seconds))
    if asking then
        strip.ask:SetText(asking)
        for _, fs in ipairs(SMALL) do fs:SetText("") end
        Place()
        return
    end
    local coins = math.max(0, totals.coins - held.coins)
    local items = math.max(0, totals.items - held.items)
    local mine = coins + items + totals.dungeons
    local group = math.max(0, totals.group - held.group)
    -- Lit up in the accent for a moment, once something has gone in.
    local accent = ns.ThemeAccent()
    local function Lit(text, at)
        if now - at >= FLASH then return text end
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return ("|cff%02x%02x%02x%s|r"):format(accent[1] * 255 + 0.5, accent[2] * 255 + 0.5, accent[3] * 255 + 0.5, plain)
    end
    strip.total:SetText(Lit(ink and ns.MoneyPlain(mine) or ns.Money(mine), math.max(flash.coins, flash.items, flash.dungeons)))
    strip.coins:SetText("coins " .. Lit(Gold(coins, ink), flash.coins))
    strip.items:SetText("items " .. Lit(Gold(items, ink), flash.items))
    strip.dungeons:SetText(totals.dungeons > 0 and ("dungeons " .. Lit(Gold(totals.dungeons, ink), flash.dungeons)) or "")
    strip.hour:SetText(seconds >= 60 and (Gold(mine * 3600 / seconds, ink) .. "/h") or "")
    -- The switch: in a group, or with others in the farm (none while it
    -- is set aside); the group's total on its side, when it counts.
    if s == ns.ActiveFarm() and (IsInGroup() or totals.players > 1) then
        strip.group:SetText(s.solo and "group" or ("group " .. Lit(Gold(group, ink), flash.group)))
        tab.side = s.solo and "solo" or "group"
        local on, off = ink and ns.INK or { 1, 1, 1 }, ink and ns.INK_GREY or { 0.43, 0.46, 0.51 }
        local g, w = s.solo and off or on, s.solo and on or off
        strip.group:SetTextColor(g[1], g[2], g[3])
        strip.soloWord:SetTextColor(w[1], w[2], w[3])
        if tab.x == nil then Slide() end
    else
        strip.group:SetText("")
        tab.x = nil -- shown again: in place at once
    end
    Place()
end

function Draw()
    if not ns.db then return end
    strip:SetScale(ns.db.options.scale or 1)
    local theme = ns.ThemeName()
    local paper = theme == "receipt"
    local accent = ns.ThemeAccent()
    local ink, grey = ns.INK, ns.INK_GREY
    local KEY_FACE, KEY_EDGE = ns.Breakdown.KEY, ns.Breakdown.KEY_EDGE
    if paper then
        strip.bg:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
        strip.line:SetColorTexture(grey[1], grey[2], grey[3], 1)
        strip.line:SetHeight(1)
    elseif theme == "classic" then
        strip.bg:SetColorTexture(0, 0, 0, 0.8)
        strip.line:SetColorTexture(0, 0, 0, 0)
    else
        strip.bg:SetColorTexture(0.075, 0.085, 0.105, 0.97)
        strip.line:SetColorTexture(accent[1], accent[2], accent[3], 1)
        strip.line:SetHeight(2)
    end
    -- The switch: of the same stuff as the strip (paper on the Receipt, so
    -- its ink reads over the world); a dark slot with the slider in the
    -- accent, or on paper an inked slot and slider.
    if paper then
        tab.bg:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
        tab.hl:SetColorTexture(1, 1, 1, 0.22)
    elseif theme == "classic" then
        tab.bg:SetColorTexture(0, 0, 0, 0.8)
        tab.hl:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
    else
        tab.bg:SetColorTexture(0.075, 0.085, 0.105, 0.97)
        tab.hl:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
    end
    if paper then
        tab.slot.edge:SetColorTexture(ink[1], ink[2], ink[3], 1)
        tab.slot.well:SetColorTexture(ns.PAPER[1] * 0.9, ns.PAPER[2] * 0.9, ns.PAPER[3] * 0.9, 1)
        tab.thumb:SetColorTexture(ink[1], ink[2], ink[3], 1)
    else
        tab.slot.edge:SetColorTexture(0.16, 0.19, 0.22, 1)
        tab.slot.well:SetColorTexture(0.02, 0.027, 0.04, 1)
        tab.thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
    end
    for _, r in ipairs(tab.ridges) do
        if paper then
            r:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
        else
            r:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 1)
        end
    end
    for _, t in ipairs(strip.edges) do
        t:SetColorTexture(0.55, 0.5, 0.4, theme == "classic" and 1 or 0)
    end
    local strong = paper and ink or { 1, 1, 1 }
    local soft = paper and grey or { 0.62, 0.66, 0.71 }
    strip.clock:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontHighlight")
    for _, fs in ipairs({ strip.total, strip.ask }) do
        fs:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontHighlight")
        fs:SetTextColor(strong[1], strong[2], strong[3])
    end
    for _, fs in ipairs(SMALL) do
        fs:SetFontObject(paper and "ThatLuckyBastardReceiptSmall" or "GameFontHighlightSmall")
        fs:SetTextColor(soft[1], soft[2], soft[3])
    end
    strip.soloWord:SetFontObject(paper and "ThatLuckyBastardReceiptSmall" or "GameFontHighlightSmall")

    local s = ns.ActiveFarm()
    local aside = not s and ns.FarmAside() or nil
    -- Out of the dungeon: the question, for the dungeon runs it would add.
    local _, runs = ns.AsideAsk()
    asking = nil
    if runs then
        asking = #runs == 1 and ("Add " .. (runs[1].name or "the dungeon") .. " and resume?")
            or #runs > 1 and ("Add " .. #runs .. " dungeons and resume?") or "Resume the farm?"
    end
    local running = s ~= nil and not s.pausedAt
    strip.clock:SetTextColor(running and strong[1] or soft[1], running and strong[2] or soft[2],
                             running and strong[3] or soft[3])
    -- The keys: till keys on paper, flat squares elsewhere.
    for _, k in ipairs({ strip.main, strip.stop, strip.yes, strip.no }) do
        local mark = k.icon or k.text
        if paper then
            k.face:SetColorTexture(KEY_FACE[1], KEY_FACE[2], KEY_FACE[3], 1)
            k.edge:SetColorTexture(KEY_EDGE[1], KEY_EDGE[2], KEY_EDGE[3], 1)
            mark[k.icon and "SetVertexColor" or "SetTextColor"](mark, ink[1], ink[2], ink[3], 1)
            k.hl:SetColorTexture(1, 1, 1, 0.22)
        else
            k.face:SetColorTexture(1, 1, 1, theme == "classic" and 0.12 or 0.08)
            k.edge:SetColorTexture(0, 0, 0, 0)
            mark[k.icon and "SetVertexColor" or "SetTextColor"](mark, 1, 1, 1, 1)
            k.hl:SetColorTexture(accent[1], accent[2], accent[3], 0.35)
        end
    end
    for _, k in ipairs({ strip.yes, strip.no }) do
        k.text:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontHighlightSmall")
        k:SetWidth(math.max(KEY + 6, math.ceil(k.text:GetStringWidth()) + 16))
    end
    -- Set aside: only Stop; with the question up, only its answers.
    strip.main:SetGlyph((s and not s.pausedAt) and "pause" or "start")
    strip.main:SetShown(not aside)
    strip.stop:SetShown(s ~= nil or (aside ~= nil and not asking))
    strip.main:ClearAllPoints()
    if s then
        strip.main:SetPoint("RIGHT", strip.stop, "LEFT", -4, 0)
    else
        strip.main:SetPoint("RIGHT", strip.close, "LEFT", -6, 0)
    end
    -- Inside a dungeon there is nothing to start: its run is recorded.
    local inside = not s and IsInInstance() and select(2, IsInInstance()) ~= "none"
    strip.main.blocked = inside and "Inside a dungeon, its run is recorded already." or nil
    strip.main:SetAlpha(inside and 0.4 or 1)
    for _, b in ipairs({ strip.lock, strip.close }) do
        b.icon:SetVertexColor(strong[1], strong[2], strong[3], 1)
    end
    strip.lock.icon:SetTexCoord(Locked() and 0 or 0.5, Locked() and 0.5 or 1, 0, 1)

    -- The farm's totals, as the breakdown counts them.
    totals.coins, totals.items, totals.dungeons, totals.group, totals.players = 0, 0, 0, 0, 1
    local farm = s or aside
    if farm then
        local sum = ns.Summarize(farm)
        local me = ns.Me(farm)
        totals.group, totals.players = sum.market, #sum.players
        for _, p in ipairs(sum.players) do
            if p.name == me then
                totals.coins, totals.items, totals.dungeons = p.money, p.market - p.money - p.dungeon, p.dungeon
            end
        end
    end
    Figures()
end

----------------------------------------------------------------------
-- Pop-ups and rising amounts
----------------------------------------------------------------------

-- The lines hang under the strip in a frame that cuts off what goes
-- above it: a line folding back slides up under the strip.
local well = CreateFrame("Frame", nil, strip)
well:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", INSET, 0)
well:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", -INSET, 0)
well:SetHeight(1)
if well.SetClipsChildren then well:SetClipsChildren(true) end

local pops, sparePops = {}, {} -- the lines out, oldest first; and the ones put aside

local function NewPop()
    local p = table.remove(sparePops)
    if p then return p end
    p = CreateFrame("Frame", nil, well)
    p.farmPop = true
    if p.SetClipsChildren then p:SetClipsChildren(true) end
    p.inner = CreateFrame("Frame", nil, p)
    p.inner:SetHeight(ROW_H)
    p.inner:SetPoint("BOTTOMLEFT")
    p.inner:SetPoint("BOTTOMRIGHT")
    p.bg = p.inner:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.icon = p.inner:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(16, 16)
    p.icon:SetPoint("LEFT", 8, 0)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.value = p.inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.value:SetPoint("RIGHT", -8, 0)
    p.value:SetJustifyH("RIGHT")
    p.label = p.inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.label:SetPoint("LEFT", p.icon, "RIGHT", 8, 0)
    p.label:SetPoint("RIGHT", p.value, "LEFT", -8, 0)
    p.label:SetJustifyH("LEFT")
    p.label:SetWordWrap(false)
    return p
end

-- A line's words and look: "3x [Runecloth]" and "+1g 05s".
local function PaintPop(p)
    local paper = Paper()
    if paper then
        p.bg:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 0.96)
        p.label:SetFontObject("ThatLuckyBastardReceiptInk")
        p.value:SetFontObject("ThatLuckyBastardReceiptInk")
    else
        p.bg:SetColorTexture(0.075, 0.085, 0.105, 0.9)
        p.label:SetFontObject("GameFontHighlightSmall")
        p.value:SetFontObject("GameFontHighlightSmall")
    end
    local link = p.e.link or ""
    if paper then link = link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|r", "") end
    p.label:SetText((p.count > 1 and (p.count .. "x ") or "") .. link)
    p.value:SetText(p.worth > 0 and ("+" .. (paper and ns.MoneyPlain(p.worth) or ns.Money(p.worth))) or "")
    p.icon:SetTexture(ns.ItemIcon and ns.ItemIcon(p.e.link) or nil)
    p.icon:SetShown(not paper)
end

-- Something went into the totals: no longer held back, and they light up.
local function GoIn(coins, items, group)
    local now = GetTime()
    for key, amount in pairs({ coins = coins, items = items, group = group }) do
        held[key] = math.max(0, held[key] - amount)
        if amount > 0 then flash[key] = now end
    end
end

local floats, spareFloats = {}, {}
local farmShown -- the farm the strip last showed

-- An amount rising above a total: yours (`mine`), or the group's. What of
-- it counts (`counted`) is held back from the totals until it is in.
local function Rise(copper, mine, counted)
    if copper <= 0 then return end
    held.group = held.group + counted
    if mine then held.coins = held.coins + counted end
    local fs = table.remove(spareFloats) or strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs.farmRise = true
    local paper = Paper()
    fs:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
    fs:SetText("+" .. (paper and ns.MoneyPlain(copper) or ns.Money(copper)))
    floats[#floats + 1] = { fs = fs, t0 = GetTime(), worth = copper, mine = mine, counted = counted }
    fs:Show()
end

-- Lays the lines out and moves everything on; returns whether anything
-- is still moving.
local function Animate()
    local now = GetTime()
    local y = 0
    local i = 1
    while pops[i] do
        local p = pops[i]
        local a = now - p.t0
        local k = 1
        if a < IN then
            k = a / IN
        elseif a >= STAY then
            k = math.max(0, 1 - (a - STAY) / FOLD)
        end
        if a >= STAY + FOLD then
            table.remove(pops, i)
            p:Hide()
            sparePops[#sparePops + 1] = p
            GoIn(0, p.counted, p.counted)
        else
            local h = ROW_H * k
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", 0, -y)
            p:SetPoint("TOPRIGHT", 0, -y)
            p:SetHeight(math.max(h, 0.01))
            p.drawnH = h
            y = y + h
            i = i + 1
        end
    end
    well:SetHeight(math.max(y, 1))
    i = 1
    while floats[i] do
        local f = floats[i]
        local a = now - f.t0
        if a >= RISE then
            table.remove(floats, i)
            f.fs:Hide()
            spareFloats[#spareFloats + 1] = f.fs
            GoIn(f.mine and f.counted or 0, 0, f.counted)
        else
            -- Yours rise into the free part of the row above, after the
            -- clock; the others' above the group's tab.
            f.fs:ClearAllPoints()
            if f.mine then
                f.fs:SetPoint("LEFT", strip.clock, "RIGHT", 10, -4 + RISE_PX * a / RISE)
            else
                f.fs:SetPoint("BOTTOMLEFT", strip.group, "TOPLEFT", 0, 4 + RISE_PX * a / RISE)
            end
            f.fs:SetAlpha(a < 0.15 and a / 0.15 or (a > RISE - 0.4 and (RISE - a) / 0.4) or 1)
            i = i + 1
        end
    end
    return pops[1] ~= nil or floats[1] ~= nil
end

local function ClearAll()
    farmShown = ns.ActiveFarm()
    for _, p in ipairs(pops) do
        p:Hide()
        sparePops[#sparePops + 1] = p
    end
    for _, f in ipairs(floats) do
        f.fs:Hide()
        spareFloats[#spareFloats + 1] = f.fs
    end
    wipe(pops)
    wipe(floats)
    held.coins, held.items, held.group = 0, 0, 0
    well:SetHeight(1)
end

-- Another farm than the one on show (or none): nothing of the last one
-- is still to come in.
local function Follow()
    if ns.ActiveFarm() ~= farmShown then ClearAll() end
end

-- From Core, for each pickup of a farm: who, the item entry, how many,
-- their worth, and what of it counts in the totals.
function ns.FarmLoot(name, e, count, worth, counted)
    if not strip:IsShown() or not ns.ActiveFarm() then return end
    Follow()
    local s = ns.ActiveFarm()
    if name ~= ns.Me(s) then
        Rise(worth, false, counted) -- someone else's: its worth alone, over the group's total
        return
    end
    local now = GetTime()
    for _, p in ipairs(pops) do
        if p.e == e and now - p.t0 < STAY then
            p.count, p.worth, p.counted = p.count + count, p.worth + worth, p.counted + counted
            p.t0 = now - IN -- out in full, and staying again
            held.items, held.group = held.items + counted, held.group + counted
            PaintPop(p)
            return
        end
    end
    local p = NewPop()
    p.e, p.count, p.worth, p.counted, p.t0 = e, count, worth, counted, now
    held.items, held.group = held.items + counted, held.group + counted
    PaintPop(p)
    p:Show()
    pops[#pops + 1] = p
    -- Too many out: the oldest still staying starts to fold.
    local staying = 0
    for _, q in ipairs(pops) do
        if now - q.t0 < STAY then staying = staying + 1 end
    end
    for _, q in ipairs(pops) do
        if staying <= MAX_POPS then break end
        if now - q.t0 < STAY then
            q.t0 = now - STAY
            staying = staying - 1
        end
    end
    Animate()
end

-- From Core, for coins in a farm: your share, and the others' together.
function ns.FarmCoins(mine, others)
    if not strip:IsShown() or not ns.ActiveFarm() then return end
    Follow()
    local o = ns.db.options
    local counts = o.cats.coins ~= false or o.countHidden
    Rise(mine, true, counts and mine or 0)
    Rise(others, false, counts and others or 0)
end

----------------------------------------------------------------------
-- Keeping up
----------------------------------------------------------------------

local since, hovered = 0, nil
strip:SetScript("OnUpdate", function(_, dt)
    local moving = Animate()
    Slide(dt)
    since = since + dt
    -- The clock and the totals each second, and while something moves.
    if since >= 1 or moving or GetTime() - math.max(flash.coins, flash.items, flash.dungeons, flash.group) < FLASH + 0.1 then
        since = 0
        Figures()
    end
    local over = strip:IsMouseOver()
    if over ~= hovered then
        hovered = over
        strip.lock:SetShown(over)
        strip.close:SetShown(over)
    end
end)
strip.lock:Hide()
strip.close:Hide()

-- Loot comes in bursts: drawn once a burst is in (with ns.Refresh).
local pending = false
function ns.FarmRefresh()
    if pending or not strip:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if not strip:IsShown() then return end
        Follow()
        Draw()
    end)
end
local function Redraw()
    if strip:IsShown() then Draw() end
end
ns.OnRerender(Redraw)
ns.OnAccent(Redraw)
strip:SetScript("OnShow", function()
    ClearAll()
    Draw()
end)

function ns.ShowFarmStrip()
    strip:Show()
    strip:Raise()
end

function ns.ToggleFarmStrip()
    if strip:IsShown() then strip:Hide() else ns.ShowFarmStrip() end
end

-- At login it is put back where it was, and opened if it was open; at
-- logout, whether it is open is noted.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGOUT" then
        ns.db.farmStrip = ns.db.farmStrip or {}
        ns.db.farmStrip.shown = strip:IsShown() or nil
        return
    end
    local saved = Saved()
    if saved.point then
        strip:ClearAllPoints()
        strip:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    end
    if saved.shown then strip:Show() end
end)

strip.floats = floats -- for the tests
ns.FarmStrip = strip
