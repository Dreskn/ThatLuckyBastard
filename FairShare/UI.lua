local _, ns = ...

local issecret = issecretvalue or function() return false end

local WIDTH, HEIGHT = 780, 540
local MAX_COLUMNS = 5     -- groups up to this size get one column per player
local COL_GAP = 6
local ACCENT = ns.ACCENT

local THEMES = {
    -- toolbarY: top of the button row under the title. scrollTop leaves
    -- room for that row and for the list view's column headers.
    classic = { rowH = 14, font = "GameFontHighlightSmall", toolbarY = -28, scrollTop = -78, scrollRight = -32 },
    modern  = { rowH = 20, font = "GameFontHighlight",      toolbarY = -44, scrollTop = -92, scrollRight = -14,
                flat = true },
}

local CATS = {
    { key = "epic",     label = "Epic BoE",                      short = "Epic BoE",    color = { 0.64, 0.21, 0.93 } },
    { key = "rare",     label = "Blue BoE",                      short = "Blue BoE",    color = { 0.20, 0.55, 1.00 } },
    { key = "uncommon", label = "Green BoE",                     short = "Green BoE",   color = { 0.12, 1.00, 0.00 } },
    { key = "bop",      label = "Bind on Pickup (vendor value)", short = "BoP",         color = { 1.00, 0.50, 0.00 } },
    { key = "prof",     label = "Profession materials",          short = "Professions", color = { 1.00, 0.82, 0.00 } },
    { key = "other",    label = "Other",                         short = "Other",       color = { 0.85, 0.85, 0.85 } },
    { key = "junk",     label = "Junk",                          short = "Junk",        color = { 0.62, 0.62, 0.62 } },
    -- Always last: quest items are worth nothing to anyone else.
    { key = "quest",    label = "Quest items (vendor value)",    short = "Quest",       color = { 1.00, 1.00, 0.45 } },
}
local cols = {}

-- Podium mode: gold, silver, bronze, then grey.
local MEDALS = { { 1.00, 0.82, 0.00 }, { 0.78, 0.78, 0.82 }, { 0.80, 0.50, 0.20 }, { 0.50, 0.50, 0.50 } }
local RANK_LABELS = { "1st", "2nd", "3rd" }

local expanded = {}   -- [playerName] = true
local viewIndex = 1   -- 1 = current / most recent run
local rows = {}
local buttons = {}
local headers = {}
local pending = false
local theme, currentTheme
local currentRun      -- the run being displayed
local needOnly = false -- show only what was won on Need rolls
local Render

-- Formats copper as gold / silver / copper, honouring the "show silver"
-- and "show copper" options. A unit that is switched off is still shown
-- when it is the largest one in the amount, so nothing reads as zero.
local function MoneyText(c, colored)
    c = math.floor((c or 0) + 0.5)
    if c <= 0 then return "-" end
    local o = ns.db.options
    local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local parts = {}
    local function unit(value, pad, color, suffix)
        local text = pad and ("%02d"):format(value) or tostring(value)
        if colored then text = color .. text .. "|r" end
        parts[#parts + 1] = text .. suffix
    end
    if g > 0 then
        local gs = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
        parts[1] = (colored and ("|cffffd700" .. gs .. "|r") or gs) .. "g"
    end
    if (g > 0 and o.showSilver) or (g == 0 and s > 0) then
        unit(s, g > 0, "|cffc7c7cf", "s")
    end
    if (#parts > 0 and o.showCopper) or #parts == 0 then
        unit(k, #parts > 0, "|cffeda55f", "c")
    end
    return table.concat(parts, " ")
end

local function Money(c)
    local text = MoneyText(c, true)
    if text == "-" then return "|cff808080-|r" end
    return text
end

-- Subtotals are shown in flat grey so they do not read as item values.
local function MoneyGrey(c)
    return "|cff8a8a8a" .. MoneyText(c, false) .. "|r"
end

local function Grey(text)
    return "|cff8a8a8a" .. text .. "|r"
end

local function CatColored(text, cat)
    local c = cat.color
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local function ClassRGB(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return ACCENT[1], ACCENT[2], ACCENT[3]
end

local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local function ItemIcon(link)
    return (GetItemIconByID and GetItemIconByID(link)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

----------------------------------------------------------------------
-- Price markers: a small dot next to an item's value.
--   "ah"   (blue)   the value is an auction price
--   "noah" (orange) the item could be auctioned but no price is known,
--                   so the vendor price was used
-- Items that cannot be auctioned, and everything in vendor-only mode,
-- get no marker.
----------------------------------------------------------------------

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
--   "off"  (grey)   an auction price is known but the player switched
--                   this item to its vendor price (right-click)
local MARK_COLORS = { ah = { 0.35, 0.70, 1.00 }, noah = { 1.00, 0.55, 0.15 }, off = { 0.55, 0.55, 0.55 } }
local LEGEND = "|cff59b3ffBlue dot|r: auction price    "
    .. "|cffff8c26Orange|r: none known, vendor price used    "
    .. "|cff8c8c8cGrey|r: auction price switched off (right-click an item)"

local function PriceMark(e)
    if ns.db.options.valueMode == "vendor" or e.cat == "bop" or e.cat == "quest" then return end
    if e.ah then return e.noAH and "off" or "ah" end
    if ns.HasPriceSource() then return "noah" end
end

-- `dominant`: this one item is more than half of the run's value.
local function PriceNote(e, mark, dominant)
    local note
    if mark == "ah" then
        note = "Auction price: " .. Money(e.ah) .. " each\nRight-click to use the vendor price instead."
    elseif mark == "off" then
        note = "Auction price (" .. Money(e.ah) .. " each) switched off. Vendor price used.\n"
            .. "Right-click to use the auction price again."
    elseif mark == "noah" then
        note = "No auction price known. Vendor price used."
    end
    if note and dominant then
        note = note .. "\n|cffff8c26This one item is more than half of the run's value.|r"
    end
    return note
end

-- Tooltip line saying how an item was won, if it was rolled for.
local function RollNote(e)
    local need, greed = e.need or 0, e.greed or 0
    if need > 0 and greed > 0 then
        return ("Won on rolls: %d Need, %d Greed"):format(need, greed)
    elseif need > 0 then
        return need > 1 and ("Won on Need rolls (%d)"):format(need) or "Won on a Need roll"
    elseif greed > 0 then
        return greed > 1 and ("Won on Greed rolls (%d)"):format(greed) or "Won on a Greed roll"
    end
end

-- True when an auction-priced item alone outweighs the rest of the run:
-- the case where one bad price decides the result.
local function IsDominant(mark, market, total)
    return mark == "ah" and total > 0 and market > total / 2
end

-- Row background: a faint white band, or orange for a dominant item.
local function SetRowBg(tex, line)
    if line.warn then
        tex:SetColorTexture(1, 0.55, 0.15, 0.20)
    else
        tex:SetColorTexture(1, 1, 1, line.bg or 0)
    end
end

local function SetMark(tex, mark)
    local c = mark and MARK_COLORS[mark]
    if c then
        tex:SetVertexColor(c[1], c[2], c[3])
        tex:Show()
    else
        tex:Hide()
    end
end

-- Over / under an equal split, as coloured text.
local function DiffText(diff)
    if math.abs(diff) < 1 then return "" end
    return (diff > 0 and "|cff40d040+|r" or "|cffe05050-|r") .. Money(math.abs(diff))
end

-- Whether the game is set to show second names (Options > Nameplates >
-- My Secondary Name). Assumed on when the client cannot tell us.
local function GameShowsSurname()
    local fn = C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname
    if fn then
        local ok, shown = pcall(fn)
        if ok and shown ~= nil and not issecret(shown) then return shown and true or false end
    end
    return true
end

-- The name to show for a player. Names are stored in full ("First Second"
-- or "First-Second"); the nameStyle option decides whether the second
-- name is displayed.
local function DisplayName(name)
    local style = ns.db.options.nameStyle
    if style == "full" or (style ~= "first" and GameShowsSurname()) then return name end
    return name:match("^([^%s%-]+)") or name
end

local function ClassColored(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

local function Runs()
    local t = {}
    if ns.db.active then t[1] = ns.db.active end
    for _, s in ipairs(ns.db.history) do t[#t + 1] = s end
    for _, s in ipairs(ns.exampleRuns) do t[#t + 1] = s end
    return t
end

----------------------------------------------------------------------
-- Base frame. The look comes from one of three "skin" child frames;
-- everything interactive lives on `ui`, which sits above the skins.
----------------------------------------------------------------------

local f = CreateFrame("Frame", "FairShareFrame", UIParent)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetFrameStrata("HIGH")
f:SetMovable(true)
f:SetResizable(true)
if f.SetResizeBounds then
    f:SetResizeBounds(620, 320, 1100, 1000)
elseif f.SetMinResize then
    f:SetMinResize(620, 320)
end
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
-- The window's place and size are remembered between sessions.
local function SaveWindow()
    local point, _, relPoint, x, y = f:GetPoint(1)
    ns.db.window = { point = point, relPoint = relPoint, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

local windowRestored = false
local function RestoreWindow()
    if windowRestored then return end
    windowRestored = true
    local w = ns.db.window
    if not w or not w.point then return end
    f:ClearAllPoints()
    f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    if w.w and w.h then f:SetSize(w.w, w.h) end
end

f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindow()
end)
f:Hide()
tinsert(UISpecialFrames, "FairShareFrame")

-- Builds the skins on a frame and returns them keyed by theme name.
-- Also used by the options panel so it follows the theme.
local function BuildSkins(frame, onClose)
    local skins = {}

    -- Classic: the old grey metal panel.
    do
        local s = CreateFrame("Frame", nil, frame, "BasicFrameTemplateWithInset")
        s:SetAllPoints()
        if s.CloseButton then s.CloseButton:SetScript("OnClick", onClose) end
        skins.classic = s
    end

    -- Modern: flat dark panel, no game art.
    do
        local s = CreateFrame("Frame", nil, frame)
        s:SetAllPoints()
        local bg = s:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.075, 0.085, 0.105, 0.97)
        local bar = s:CreateTexture(nil, "BORDER")
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("TOPRIGHT")
        bar:SetHeight(36)
        bar:SetColorTexture(1, 1, 1, 0.04)
        -- The header carries the accent colour, strongest on the left
        -- where the name is. Plain where the client cannot do gradients.
        if bar.SetGradient and CreateColor then
            bar:SetColorTexture(1, 1, 1, 1)
            local ok = pcall(bar.SetGradient, bar, "HORIZONTAL",
                             CreateColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.26),
                             CreateColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.03))
            if not ok then bar:SetColorTexture(1, 1, 1, 0.04) end
        end
        local line = s:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 0, -36)
        line:SetPoint("TOPRIGHT", 0, -36)
        line:SetHeight(2)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        local function Edge(p1, p2, w, h)
            local t = s:CreateTexture(nil, "OVERLAY")
            t:SetPoint(p1)
            t:SetPoint(p2)
            if w then t:SetWidth(w) else t:SetHeight(h) end
            t:SetColorTexture(1, 1, 1, 0.12)
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

        local close = CreateFrame("Button", nil, s)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -6, -6)
        local hl = close:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.9, 0.25, 0.25, 0.55)
        local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        x:SetPoint("CENTER")
        x:SetText("X")
        close:SetScript("OnClick", onClose)
        skins.modern = s
    end

    return skins
end

ns.BuildSkins = BuildSkins
local skins = BuildSkins(f, function() f:Hide() end)

local ui = CreateFrame("Frame", nil, f)
ui:SetAllPoints()
ui:SetFrameLevel(f:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")

-- Column layout, measured from the right edge of a row.
-- The gap to the right of "market" holds the price marker.
local COLS = {
    { key = "share",  right = -4,   width = 46, header = "Share" },
    { key = "diff",   right = -56,  width = 92, header = "vs equal" },
    { key = "market", right = -160, width = 92, header = "Market" },
    { key = "vendor", right = -258, width = 92, header = "Vendor" },
    { key = "count",  right = -356, width = 40, header = "Qty" },
}

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 44, 1)
scroll:SetScrollChild(content)

-- A gold outline around the breakdown, shown while the run on display is
-- pinned. It follows the scroll area, so it fits both themes and both
-- layouts.
local pinOutline = CreateFrame("Frame", "FairSharePinOutline", ui)
pinOutline:SetPoint("TOPLEFT", scroll, "TOPLEFT", -5, 5)
pinOutline:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 5, -5)
pinOutline:SetFrameLevel(scroll:GetFrameLevel() + 5)
pinOutline:Hide()
do
    local function Edge(point1, point2, width, height)
        local t = pinOutline:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 0.9)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if width then t:SetWidth(width) else t:SetHeight(height) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 2)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    Edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
end
scroll:SetScript("OnSizeChanged", function(_, w)
    content:SetWidth(w)
    if ns.Refresh then ns.Refresh() end -- defined at the end of this file
end)

do
    local h = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 4, 4)
    h:SetText("Player / item")
    headers[1] = h
    for _, col in ipairs(COLS) do
        h = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", col.right, 4)
        h:SetWidth(col.width)
        h:SetJustifyH("RIGHT")
        h:SetText(col.header)
        headers[#headers + 1] = h
        headers[col.key] = h
    end
end

-- Resize grip
do
    local grip = CreateFrame("Button", nil, ui)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveWindow()
    end)
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function RowOnClick(self, button)
    local line = self.line
    if not line then return end
    if button == "RightButton" then
        -- Switch this item between its auction and vendor price.
        if line.e and currentRun and ns.ToggleAuctionPrice(currentRun, line.e) then
            GameTooltip:Hide()
            Render()
        end
        return
    end
    if line.player then
        expanded[line.player] = not expanded[line.player] or nil
        Render()
    elseif line.link and IsModifiedClick("CHATLINK") then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if insert then insert(line.link) end
    end
end

local AWARDS_HINT = "Click for the list of all awards."
local shownAwards = {} -- the awards of the run on show, by player name

-- A player's awards as a list. There is one per player today (none when
-- awards are off or the run is still going); the layout copes with more.
local function AwardList(awards, name)
    return { awards[name] }
end

local function AwardTitle(award)
    return "|cffffd100" .. award.title .. "|r" -- every award in the same gold: none is a verdict
end

-- Adds one award to the tooltip being built: its name, what earned it,
-- and (in grey) the rule behind it.
local function AddAwardLines(award)
    GameTooltip:AddLine(AwardTitle(award))
    if award.text then GameTooltip:AddLine(award.text, 1, 1, 1, true) end
    if award.link then GameTooltip:AddLine(award.link) end
    if award.amount then GameTooltip:AddLine(Money(award.amount), 1, 1, 1) end
    if award.how then GameTooltip:AddLine(award.how, 0.7, 0.7, 0.7, true) end
end

-- Tooltip for a player: what is known about them from earlier runs, and
-- with `awards` (a list) what they won in this one.
local function PersonTooltip(owner, p, awards)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassColored(p.name, p.class))
    local who = ns.db.people[p.name]
    if p.name == ns.playerName then
        GameTooltip:AddLine("That's you.", 0.7, 0.7, 0.7)
    elseif who and who.runs > 0 then
        GameTooltip:AddLine(("Runs together: %d"):format(who.runs), 1, 1, 1)
        GameTooltip:AddLine("Average loot per run: " .. Money(who.value / who.runs), 1, 1, 1)
        if who.lucky > 0 then GameTooltip:AddLine(("Luckiest: %d times"):format(who.lucky), 1, 1, 1) end
        if who.ninja > 0 then GameTooltip:AddLine(("Ninja: %d times"):format(who.ninja), 1, 1, 1) end
    else
        GameTooltip:AddLine("No earlier runs together on record.", 0.7, 0.7, 0.7)
    end
    for _, award in ipairs(awards or {}) do
        GameTooltip:AddLine(" ")
        AddAwardLines(award)
    end
    GameTooltip:Show()
end

local function RowOnEnter(self)
    local line = self.line
    if line and line.p then
        -- The list view has no award cards, so they are explained here.
        PersonTooltip(self, line.p, AwardList(shownAwards, line.p.name))
    elseif line and line.link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(line.link)
        if line.note or line.roll then GameTooltip:AddLine(" ") end
        if line.roll then GameTooltip:AddLine(line.roll, 1, 0.82, 0, true) end
        if line.note then GameTooltip:AddLine(line.note, 0.6, 0.8, 1, true) end
        -- Everyone's roll on this item, when the run has them.
        if line.e and currentRun and ns.AddRollLines then
            ns.AddRollLines(currentRun, ns.ItemKey(line.e))
        end
        GameTooltip:Show()
    end
end

local StyleHighlight

local function StyleRow(r)
    r.label:SetFontObject(theme.font)
    for _, col in ipairs(COLS) do r[col.key]:SetFontObject(theme.font) end
    StyleHighlight(r)
end

function StyleHighlight(r)
    if theme.flat then
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    else
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 1)
    end
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
    for _, col in ipairs(COLS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", col.right, 0)
        fs:SetWidth(col.width)
        fs:SetJustifyH("RIGHT")
        r[col.key] = fs
    end
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    -- Item rows: icon and price marker. Category rows: colour chip.
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(CIRCLE)
    r.mark:SetSize(7, 7)
    r.mark:SetPoint("LEFT", r.market, "RIGHT", 3, 0)

    -- Player rows: round picture with a class-coloured ring.
    r.portrait = r:CreateTexture(nil, "ARTWORK")
    r.portrait:SetPoint("LEFT", 8, 0)
    r.ring = r:CreateTexture(nil, "BORDER", nil, 1)
    r.ring:SetTexture(CIRCLE)
    r.ring:SetPoint("CENTER", r.portrait)
    r.ringInner = r:CreateTexture(nil, "BORDER", nil, 2)
    r.ringInner:SetTexture(CIRCLE)
    r.ringInner:SetVertexColor(0.05, 0.05, 0.07)
    r.ringInner:SetPoint("CENTER", r.portrait)
    if r.CreateMaskTexture then
        local mask = r:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(r.portrait)
        r.portrait:AddMaskTexture(mask)
    end

    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleRow(r)
    rows[i] = r
    return r
end

local function Pct(part, whole)
    if not whole or whole <= 0 then return "" end
    return ("%.0f%%"):format(part / whole * 100)
end

----------------------------------------------------------------------
-- Column view (small groups): one column per player with a portrait,
-- their totals, then their items by category.
----------------------------------------------------------------------

local function UnitForName(name)
    -- Runs recorded by early versions stored you under your first name only.
    if name == ns.playerName or name == UnitName("player") then return "player" end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local unit = prefix .. i
        if UnitExists(unit) then
            local n = GetUnitName(unit, true)
            if n and not issecret(n) and n == name then return unit end
        end
    end
end

-- Pictures of players who are no longer around. The game cannot save a
-- portrait or a model, so two stand-ins are built from what was saved of
-- the player during the run (see SaveLook in Core.lua): the game's own
-- picture for their race and sex, and a model of that race and sex
-- wearing their gear. Neither has their face or hair.

-- The game's round picture for a race and sex, when this client has one.
local RACE_ART = { Scourge = "undead" } -- where the art is not named like the race's file
local function RaceAtlas(p)
    if not (p.race and p.sex and C_Texture and C_Texture.GetAtlasInfo) then return end
    local race = RACE_ART[p.race] or p.race:lower()
    local sex = p.sex == 3 and "female" or "male"
    for _, pattern in ipairs({ "raceicon128-%s-%s", "raceicon-%s-%s" }) do
        local atlas = pattern:format(race, sex)
        if C_Texture.GetAtlasInfo(atlas) then return atlas end
    end
end

local LOOK_SLOTS = { 1, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 16, 17 } -- head to feet, then weapons
local MIN_LOOK = 4 -- pieces of gear needed: a body in its underwear is no likeness

local function HasLook(p)
    if not (p.raceID and p.sex and p.gear) then return false end
    local n = 0
    for _ in pairs(p.gear) do n = n + 1 end
    return n >= MIN_LOOK
end

local function WearLook(model, p)
    model:Undress()
    for _, slot in ipairs(LOOK_SLOTS) do
        if p.gear[slot] then model:TryOn("item:" .. p.gear[slot]) end
    end
end

-- A model frame that can be dressed; a plain one where the client has none.
local function NewModel(parent)
    local ok, model = pcall(CreateFrame, "DressUpModel", nil, parent)
    if not ok or not model then model = CreateFrame("PlayerModel", nil, parent) end
    return model
end

-- Rebuilds a player on a model frame from their saved look. Returns true
-- when there was enough saved and the client could do it.
local function DressModel(model, p)
    if not (HasLook(p) and model.SetCustomRace and model.TryOn and model.Undress) then return false end
    local ok = pcall(function()
        model:SetUnit("player")                  -- a body to start from
        model:SetCustomRace(p.raceID, p.sex - 2) -- 0 male, 1 female
        WearLook(model, p)
    end)
    -- The new body loads a moment later and may come up bare: the gear is
    -- put on once more when it has (see ModelLoaded).
    model.look = ok and p or nil
    return ok
end

-- For a model's OnModelLoaded script.
local function ModelLoaded(model)
    local p = model.look
    if p then
        model.look = nil
        pcall(WearLook, model, p)
    end
end

-- Draws a player's flat picture: their live portrait when `unit` is given;
-- otherwise the picture of their race and sex (if `raceOK`, and where it
-- was saved and the client has it), or else their class icon.
local function FillPortrait(tex, p, unit, raceOK)
    local coords = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
    local atlas = not unit and raceOK and tex.SetAtlas and RaceAtlas(p) or nil
    if unit then
        SetPortraitTexture(tex, unit)
        tex:SetTexCoord(0, 1, 0, 1)
    elseif atlas then
        tex:SetAtlas(atlas)
    elseif coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- mode: "3d" model, "2d" portrait, "class" icon or "none". A live model
-- or portrait needs the player in the group right now; otherwise a
-- stand-in is built from their saved look, and failing that the class
-- icon is used.
--
-- Pictures are framed in the player's class colour: a ring around the
-- round 2D portrait / class icon, a square frame around the 3D model
-- (model frames cannot be masked to a circle).
local function SetPortrait(c, p, mode)
    local tex, model = c.portrait, c.model
    local unit = (mode == "2d" or mode == "3d") and UnitForName(p.name) or nil
    local lookKey = "look:" .. p.name
    local rebuilt = false
    if mode == "3d" and not unit then
        rebuilt = c.modelGUID == lookKey or DressModel(model, p)
    end
    local useModel = (mode == "3d" and unit ~= nil) or rebuilt
    local useTexture = mode ~= "none" and not useModel

    local r, g, b = ClassRGB(p.class)
    c.ring:SetVertexColor(r, g, b)
    c.box:SetColorTexture(r, g, b, 1)
    c.ring:SetShown(useTexture)
    c.ringInner:SetShown(useTexture)
    c.box:SetShown(useModel)
    c.boxInner:SetShown(useModel)
    tex:SetShown(useTexture)
    model:SetShown(useModel)

    if rebuilt then
        if c.modelGUID ~= lookKey then
            if model.SetPortraitZoom then model:SetPortraitZoom(1) end
            c.modelGUID = lookKey
        end
        return
    end
    if useModel then
        model.look = nil
        -- Reloading the model on every redraw makes it flicker.
        local guid = UnitGUID(unit)
        if issecret(guid) or c.modelGUID ~= guid then
            model:SetUnit(unit)
            if model.SetPortraitZoom then model:SetPortraitZoom(1) end
            c.modelGUID = not issecret(guid) and guid or nil
        end
        return
    end
    c.modelGUID = nil
    if useTexture then FillPortrait(tex, p, unit, mode ~= "class") end
end

local function GetCol(i)
    local c = cols[i]
    if c then return c end
    c = CreateFrame("Frame", nil, content)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.portrait = c:CreateTexture(nil, "ARTWORK")
    c.portrait:SetSize(48, 48)
    c.portrait:SetPoint("TOP", 0, -8)
    c.model = NewModel(c)
    c.model:SetScript("OnModelLoaded", ModelLoaded)
    c.model:SetSize(52, 52)
    c.model:SetPoint("TOP", 0, -6)
    c.model:Hide()

    -- Round pictures: class-coloured ring, dark disc, then the picture
    -- itself clipped to a circle.
    c.ring = c:CreateTexture(nil, "BORDER", nil, 1)
    c.ring:SetTexture(CIRCLE)
    c.ring:SetSize(54, 54)
    c.ring:SetPoint("CENTER", c.portrait)
    c.ringInner = c:CreateTexture(nil, "BORDER", nil, 2)
    c.ringInner:SetTexture(CIRCLE)
    c.ringInner:SetVertexColor(0.05, 0.05, 0.07)
    c.ringInner:SetSize(50, 50)
    c.ringInner:SetPoint("CENTER", c.portrait)
    if c.CreateMaskTexture then
        local mask = c:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(c.portrait)
        c.portrait:AddMaskTexture(mask)
    end

    -- 3D model: class-coloured square frame with a dark backdrop.
    c.box = c:CreateTexture(nil, "BORDER", nil, 1)
    c.box:SetSize(56, 56)
    c.box:SetPoint("CENTER", c.model)
    c.boxInner = c:CreateTexture(nil, "BORDER", nil, 2)
    c.boxInner:SetColorTexture(0.05, 0.05, 0.07, 1)
    c.boxInner:SetSize(52, 52)
    c.boxInner:SetPoint("CENTER", c.model)
    local function Text(font, y)
        local fs = c:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", 2, y)
        fs:SetPoint("TOPRIGHT", -2, y)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        return fs
    end
    c.name = Text("GameFontNormal", -60)
    c.market = Text("GameFontHighlight", -78)
    c.vendor = Text("GameFontHighlightSmall", -96)
    c.share = Text("GameFontHighlightSmall", -110)
    -- Modern-theme decoration: class-coloured glow and strip at the top,
    -- a pill behind the over/under figure, and a bar whose length is the
    -- player's share of the run, split into category colours.
    c.top = c:CreateTexture(nil, "BORDER")
    c.top:SetPoint("TOPLEFT")
    c.top:SetPoint("TOPRIGHT")
    c.top:SetHeight(72)
    c.strip = c:CreateTexture(nil, "ARTWORK")
    c.strip:SetPoint("TOPLEFT")
    c.strip:SetPoint("TOPRIGHT")
    c.strip:SetHeight(2)
    c.pill = c:CreateTexture(nil, "BORDER")
    c.pill:SetPoint("TOP", 0, -108)
    c.pill:SetHeight(14)
    c.track = c:CreateTexture(nil, "BORDER")
    c.track:SetPoint("TOPLEFT", 8, -126)
    c.track:SetPoint("TOPRIGHT", -8, -126)
    c.track:SetHeight(5)
    c.track:SetColorTexture(1, 1, 1, 0.08)
    c.segs = {}
    for k = 1, #CATS do
        local seg = c:CreateTexture(nil, "ARTWORK")
        seg:SetHeight(5)
        c.segs[k] = seg
    end
    -- Podium mode: medal-coloured line across the top and a rank label.
    c.medal = c:CreateTexture(nil, "OVERLAY")
    c.medal:SetPoint("TOPLEFT")
    c.medal:SetPoint("TOPRIGHT")
    c.medal:SetHeight(3)
    c.rank = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.rank:SetPoint("TOPLEFT", 6, -8)
    -- Invisible hover area over the picture and name, for the tooltip
    -- with what is known about this player from earlier runs.
    c.hover = CreateFrame("Button", nil, c)
    c.hover:SetPoint("TOPLEFT")
    c.hover:SetPoint("TOPRIGHT")
    c.hover:SetScript("OnEnter", function(self)
        if self.p then PersonTooltip(self, self.p) end
    end)
    c.hover:SetScript("OnLeave", GameTooltip_Hide)
    c.rows = {}
    cols[i] = c
    return c
end

----------------------------------------------------------------------
-- Awards: small cards under each player's totals (column view), or
-- titles after the name (list view). When the window opens by itself at
-- the end of a run, the cards are revealed one after another.
----------------------------------------------------------------------

local AWARD_H = 30
local REVEAL_STEP = 0.5 -- seconds between two cards

-- Plays one of the game's own interface sounds, by name with the numeric
-- id as a fallback. A missing sound is not worth an error.
local function PlayKit(name, id)
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT[name]) or id, "SFX")
end
local ceremonyPending = false -- reveal the cards on the next draw
local revealEnd = 0           -- GetTime() at which the reveal is over

-- The one line that fits under the title; the tooltip has the rest.
local function AwardShort(award)
    if award.link then return award.link end
    if award.amount then return Money(award.amount) end
    return award.text or ""
end

local function AwardOnEnter(self)
    local award = self.award
    if not award then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    AddAwardLines(award)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(AWARDS_HINT, 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function GetAwardFrame(c, k)
    c.awardFrames = c.awardFrames or {}
    local af = c.awardFrames[k]
    if af then return af end
    af = CreateFrame("Button", nil, c)
    af:SetHeight(AWARD_H - 3)
    local bg = af:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.07)
    af.icon = af:CreateTexture(nil, "ARTWORK")
    af.icon:SetSize(22, 22)
    af.icon:SetPoint("LEFT", 3, 0)
    af.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    af.title = af:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    af.title:SetPoint("TOPLEFT", 30, -2)
    af.title:SetPoint("TOPRIGHT", -2, -2)
    af.title:SetJustifyH("LEFT")
    af.title:SetWordWrap(false)
    af.detail = af:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    af.detail:SetPoint("BOTTOMLEFT", 30, 2)
    af.detail:SetPoint("BOTTOMRIGHT", -2, 2)
    af.detail:SetJustifyH("LEFT")
    af.detail:SetWordWrap(false)
    af:SetScript("OnEnter", AwardOnEnter)
    af:SetScript("OnLeave", GameTooltip_Hide)
    af:SetScript("OnClick", function() ns.ShowBrowse("awards") end)
    c.awardFrames[k] = af
    return af
end

local function GetColRow(c, j)
    local r = c.rows[j]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -13, 0) -- leaves room for the price marker
    r.value:SetJustifyH("RIGHT")
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(CIRCLE)
    r.mark:SetSize(7, 7)
    r.mark:SetPoint("RIGHT", -3, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetPoint("TOPLEFT")
    r.chip:SetPoint("BOTTOMLEFT")
    r.chip:SetWidth(3)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleHighlight(r)
    c.rows[j] = r
    return r
end

----------------------------------------------------------------------
-- Footer: the text lines under the breakdown. Totals, run time, dungeon
-- records, comparison with your average, and the legend for the dots.
----------------------------------------------------------------------

local footLines = {} -- font strings used by the column view

local function Duration(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes >= 60 then
        return ("%dh %02dm"):format(math.floor(minutes / 60), minutes % 60)
    end
    return ("%dm %02ds"):format(minutes, seconds % 60)
end

local RECORD_LABELS = {
    { "group", "richest run" }, { "mine", "your best haul" },
    { "jackpot", "biggest single item" }, { "fastest", "fastest run" },
}

-- "40% above" / "12% below" / "about the same as"
local function Versus(pct)
    if math.abs(pct) < 5 then return "about the same as" end
    return ("%d%% %s"):format(math.abs(pct) + 0.5, pct > 0 and "|cff40d040above|r" or "|cffe05050below|r")
end

-- includeTotals: the list view shows its totals as rows of its own.
local function FooterTexts(sum, insights, includeTotals)
    local o = ns.db.options
    local texts = {}
    local n = #sum.players

    if includeTotals and o.showTotals and n > 0 then
        local equal = sum.market / n
        if o.valueMode == "vendor" then
            texts[#texts + 1] = ("|cffffd100Total|r  %s      |cff909090Equal split|r  %s"):format(
                Money(sum.market), Money(equal))
        else
            texts[#texts + 1] = ("|cffffd100Total|r  %s      |cff909090Vendor|r  %s      |cff909090Equal split|r  %s")
                :format(Money(sum.market), Money(sum.vendor), Money(equal))
        end
    end

    if insights and o.showInsights then
        local parts = {}
        if insights.duration then
            parts[#parts + 1] = "|cff909090Run time|r  " .. Duration(insights.duration)
            if insights.perHour then
                parts[#parts + 1] = "|cff909090Group loot per hour|r  " .. Money(insights.perHour)
            end
        end
        if insights.fair then
            parts[#parts + 1] = ("|cff909090Fairness|r  %d / 100"):format(insights.fair)
        end
        if #parts > 0 then texts[#texts + 1] = table.concat(parts, "      ") end
        if insights.streak then
            local streak = insights.streak
            texts[#texts + 1] = ("|cffffd100%s|r      |cff909090together so far|r  %s      |cff909090yours|r  %s")
                :format(ns.StreakLabel(streak), Money(streak.total), Money(streak.mine))
        end
        if insights.records then
            local names = {}
            for _, label in ipairs(RECORD_LABELS) do
                if insights.records[label[1]] then names[#names + 1] = label[2] end
            end
            if #names > 0 then
                texts[#texts + 1] = "|cffffd100Record for this dungeon:|r  " .. table.concat(names, ", ")
            end
        end
        if insights.groupPct then
            local text = ("Group loot is %s your average for this dungeon"):format(Versus(insights.groupPct))
            if insights.minePct then
                text = text .. ("; your own is %s yours"):format(Versus(insights.minePct))
            end
            texts[#texts + 1] = text .. (" |cff909090(%d earlier runs)|r"):format(insights.priorRuns)
        end
    end

    if n > 0 and o.valueMode ~= "vendor" then texts[#texts + 1] = LEGEND end
    return texts
end

local function PlaceText(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 2, y)
    fs:SetPoint("TOPRIGHT", -2, y)
end

-- A column-view item row. `count` and `market` are passed separately
-- because aligned mode merges several entries of the same item.
-- `total` is the run's total value.
local function ItemLine(e, count, market, total)
    local mark = PriceMark(e)
    local dominant = IsDominant(mark, market, total)
    return {
        link = e.link, e = e,
        label = (count > 1 and (count .. "x ") or "") .. e.link,
        value = Money(market),
        mark = mark,
        warn = dominant,
        note = PriceNote(e, mark, dominant),
        roll = RollNote(e),
    }
end

local ItemKey = ns.ItemKey

-- A player's items for one category, or all of them when `cat` is false
-- (the "group by category" option is off).
local function GroupOf(p, cat)
    if cat then return p.cats[cat.key] end
    return p.all
end

-- Returns one list of lines per player. With `alignItems` every column
-- gets the same rows in the same order (a dash where the player has none
-- of that item), so a line can be compared straight across.
local function BuildColumnLines(sum, o)
    local out = {}
    for i = 1, #sum.players do out[i] = {} end
    local function add(i, line) out[i][#out[i] + 1] = line end

    local function Header(cat, cs)
        return { label = CatColored(cat.short, cat), cat = cat, bg = 0.08,
                 value = cs and MoneyGrey(cs.market) or Grey("-") }
    end

    -- Each player's own items, in their own order.
    local function Plain(cat)
        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            if cs then
                if cat then add(i, Header(cat, cs)) end
                for _, e in ipairs(cs.items) do
                    add(i, ItemLine(e, e.count, ns.EntryMarket(e), sum.market))
                end
            end
        end
    end

    -- The same rows for everyone: every item anyone has in this group,
    -- ordered by name or by combined value.
    local function Aligned(cat)
        local union, order = {}, {}
        for _, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ItemKey(e)
                local u = union[k]
                if not u then
                    u = { key = k, name = ns.ItemName(e), total = 0, quest = e.cat == "quest" }
                    union[k] = u
                    order[#order + 1] = u
                end
                u.total = u.total + ns.EntryMarket(e)
            end
        end
        if #order == 0 then return end
        table.sort(order, function(a, b)
            if a.quest ~= b.quest then return b.quest end -- quest items last
            if o.sortItems == "name" and a.name ~= b.name then return a.name < b.name end
            if a.total ~= b.total then return a.total > b.total end
            return a.key < b.key
        end)

        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            local mine = {} -- this player's items by key (same item merged)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ItemKey(e)
                local m = mine[k]
                if m then
                    m.count, m.market = m.count + e.count, m.market + ns.EntryMarket(e)
                else
                    mine[k] = { e = e, count = e.count, market = ns.EntryMarket(e) }
                end
            end
            if cat then add(i, Header(cat, cs)) end
            for _, u in ipairs(order) do
                local m = mine[u.key]
                if m then
                    add(i, ItemLine(m.e, m.count, m.market, sum.market))
                else
                    add(i, { label = "|cff505050-|r" })
                end
            end
        end
    end

    -- `false` stands for "no categories": one group holding everything.
    for _, cat in ipairs(o.groupByCategory and CATS or { false }) do
        if o.alignItems then Aligned(cat) else Plain(cat) end
    end

    if not o.alignItems then
        for i, p in ipairs(sum.players) do
            if p.count == 0 then
                add(i, { label = sum.needOnly and "|cff808080No Need wins|r" or "|cff808080No loot seen|r" })
            end
        end
    end
    return out
end

local function RenderColumns(sum, awards, insights)
    local n = #sum.players
    local colW = (content:GetWidth() - COL_GAP * (n - 1)) / n
    local rowH = theme.rowH
    local equal = sum.market / n
    local maxH = 0

    -- Header layout depends on what the options show.
    local o = ns.db.options
    local showBar = theme.flat and o.showBar
    local y = -8
    local yPortrait, yName, yMarket, yVendor, yShare, yBar
    if o.portrait ~= "none" then yPortrait = y; y = y - 58 end
    yName = y; y = y - 18
    yMarket = y; y = y - (theme.flat and 20 or 18)
    if o.showVendor and o.valueMode ~= "vendor" then yVendor = y; y = y - 14 end
    if o.showShare then yShare = y; y = y - 16 end
    if showBar then yBar = y; y = y - 9 end

    -- Award cards go under the totals. Every column reserves room for the
    -- largest number any player has, so the item rows stay level.
    local maxAwards = 0
    for _, p in ipairs(sum.players) do
        maxAwards = math.max(maxAwards, #AwardList(awards, p.name))
    end
    local yAwards = y - 4
    if maxAwards > 0 then y = yAwards - maxAwards * AWARD_H end
    local headerH = 4 - y
    local revealIndex = 0

    -- Podium: most loot in the middle, 2nd on its left, 3rd on its right,
    -- then outwards. Columns step down by rank unless items are aligned.
    local podium = o.sortPlayers == "podium"
    if podium then
        local arranged = {}
        for _, p in ipairs(sum.players) do -- already in rank order
            if p.rank % 2 == 0 then
                table.insert(arranged, 1, p)
            else
                arranged[#arranged + 1] = p
            end
        end
        sum.players = arranged
    end
    local step = (podium and not o.alignItems) and 14 or 0
    local colLines = BuildColumnLines(sum, o)

    for i, p in ipairs(sum.players) do
        local c = GetCol(i)
        c:ClearAllPoints()
        c.offset = step * math.min(p.rank - 1, 3)
        c:SetPoint("TOPLEFT", (i - 1) * (colW + COL_GAP), -c.offset)
        c:SetWidth(colW)
        c.bg:SetColorTexture(1, 1, 1, (theme.flat and 0.045 or 0.03) + ((podium and p.rank == 1) and 0.04 or 0))
        if podium then
            local medal = MEDALS[p.rank] or MEDALS[4]
            c.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
            c.rank:SetText(RANK_LABELS[p.rank] or (p.rank .. "th"))
            c.rank:SetTextColor(medal[1], medal[2], medal[3])
        end
        c.medal:SetShown(podium)
        c.rank:SetShown(podium)

        SetPortrait(c, p, o.portrait)
        if yPortrait then
            c.portrait:ClearAllPoints()
            c.portrait:SetPoint("TOP", 0, yPortrait)
            c.model:ClearAllPoints()
            c.model:SetPoint("TOP", 0, yPortrait + 2)
        end
        PlaceText(c.name, yName)
        c.name:SetText(ClassColored(DisplayName(p.name), p.class))
        c.hover.p = p
        c.hover:SetHeight(-yMarket) -- from the top down to just under the name
        PlaceText(c.market, yMarket)
        c.market:SetText(Money(p.market))
        c.vendor:SetShown(yVendor ~= nil)
        if yVendor then
            PlaceText(c.vendor, yVendor)
            c.vendor:SetText("|cff909090Vendor|r " .. Money(p.vendor))
        end
        c.share:SetShown(yShare ~= nil)
        if yShare then PlaceText(c.share, yShare) end

        local flat = theme.flat
        local cr, cg, cb = ClassRGB(p.class)
        c.top:SetShown(flat)
        c.top:SetHeight(math.min(72, headerH))
        c.strip:SetShown(flat and not podium)
        c.track:SetShown(showBar)
        if showBar then
            c.track:ClearAllPoints()
            c.track:SetPoint("TOPLEFT", 8, yBar)
            c.track:SetPoint("TOPRIGHT", -8, yBar)
        end
        if flat then
            c.strip:SetColorTexture(cr, cg, cb, 0.9)
            if c.top.SetGradient and CreateColor then
                c.top:SetColorTexture(1, 1, 1, 1)
                c.top:SetGradient("VERTICAL", CreateColor(cr, cg, cb, 0), CreateColor(cr, cg, cb, 0.30))
            else
                c.top:SetColorTexture(cr, cg, cb, 0.12)
            end
        end
        c.market:SetFontObject(flat and "GameFontHighlightLarge" or "GameFontHighlight")

        local diff = p.market - equal
        local showDiff = sum.market > 0 and math.abs(diff) >= 1
        if sum.market > 0 then
            local text = Pct(p.market, sum.market)
            if showDiff then
                text = text .. (diff > 0 and "  |cff40d040+|r" or "  |cffe05050-|r") .. Money(math.abs(diff))
            end
            c.share:SetText(text)
        else
            c.share:SetText("")
        end
        if flat and showDiff and yShare then
            c.pill:ClearAllPoints()
            c.pill:SetPoint("TOP", 0, yShare + 2)
            c.pill:SetWidth(math.min(colW - 4, c.share:GetStringWidth() + 14))
            if diff > 0 then
                c.pill:SetColorTexture(0.25, 0.82, 0.25, 0.16)
            else
                c.pill:SetColorTexture(0.88, 0.31, 0.31, 0.16)
            end
            c.pill:Show()
        else
            c.pill:Hide()
        end

        local list = AwardList(awards, p.name)
        for k = 1, math.max(#list, c.awardFrames and #c.awardFrames or 0) do
            local af = GetAwardFrame(c, k)
            local award = list[k]
            af.award = award
            if award then
                local top = yAwards - (k - 1) * AWARD_H
                af:ClearAllPoints()
                af:SetPoint("TOPLEFT", 4, top)
                af:SetPoint("TOPRIGHT", -4, top)
                af.icon:SetTexture("Interface\\Icons\\" .. award.icon)
                af.title:SetText(AwardTitle(award))
                af.detail:SetText(AwardShort(award))
                af:Show()
                if ceremonyPending then
                    -- Hidden now, faded in a little later than the one before.
                    revealIndex = revealIndex + 1
                    af:SetAlpha(0)
                    C_Timer.After(REVEAL_STEP * revealIndex, function()
                        if UIFrameFadeIn then UIFrameFadeIn(af, 0.4, 0, 1) else af:SetAlpha(1) end
                        if o.ceremonySound and f:IsShown() then PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) end
                    end)
                elseif GetTime() >= revealEnd then
                    af:SetAlpha(1)
                end
            else
                af:Hide()
            end
        end

        -- Share bar: total length = share of the run, segments = categories.
        local x = 8
        local full = (colW - 16) * (sum.market > 0 and p.market / sum.market or 0)
        for k, cat in ipairs(CATS) do
            local seg, cs = c.segs[k], p.cats[cat.key]
            if showBar and cs and cs.market > 0 and p.market > 0 then
                local w = full * cs.market / p.market
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", x, yBar)
                seg:SetWidth(math.max(w, 1))
                seg:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 0.95)
                seg:Show()
                x = x + w
            else
                seg:Hide()
            end
        end

        local lines = colLines[i]

        for j, line in ipairs(lines) do
            local r = GetColRow(c, j)
            r.line = line
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(headerH + (j - 1) * rowH))
            r:SetPoint("TOPRIGHT", 0, -(headerH + (j - 1) * rowH))
            r:SetHeight(rowH)
            local left = 4
            if line.link and o.showIcons then
                r.icon:SetSize(rowH - 4, rowH - 4)
                r.icon:SetTexture(ItemIcon(line.link))
                r.icon:Show()
                left = rowH + 4
            else
                r.icon:Hide()
            end
            if line.cat then
                r.chip:SetColorTexture(line.cat.color[1], line.cat.color[2], line.cat.color[3], 0.9)
                r.chip:Show()
                left = 8
            else
                r.chip:Hide()
            end
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", left, 0)
            r.label:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
            r.label:SetText(line.label or "")
            r.value:SetText(line.value or "")
            SetMark(r.mark, line.mark)
            SetRowBg(r.bg, line)
            r:EnableMouse(line.link ~= nil)
            r:Show()
        end
        for j = #lines + 1, #c.rows do c.rows[j]:Hide() end

        maxH = math.max(maxH, c.offset + headerH + #lines * rowH + 6)
        c:Show()
    end
    for i = 1, n do cols[i]:SetHeight(maxH - cols[i].offset) end
    for i = n + 1, #cols do cols[i]:Hide() end
    if ceremonyPending then
        ceremonyPending = false
        local length = REVEAL_STEP * revealIndex
        revealEnd = GetTime() + length + 0.5
        if revealIndex > 0 then
            -- A fanfare once the last card is up, then the souvenir photo.
            if o.ceremonySound then
                C_Timer.After(length + 0.3, function()
                    if f:IsShown() then PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
                end)
            end
            if o.ceremonyScreenshot and Screenshot then
                C_Timer.After(length + 1.2, function()
                    if f:IsShown() then Screenshot() end
                end)
            end
        end
    end

    local bottom = maxH + 10
    local texts = FooterTexts(sum, insights, true)
    for i, text in ipairs(texts) do
        local fs = footLines[i]
        if not fs then
            fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            footLines[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -bottom)
        fs:SetText(text)
        fs:Show()
        bottom = bottom + 16
    end
    for i = #texts + 1, #footLines do footLines[i]:Hide() end
    content:SetHeight(bottom + 4)
end

----------------------------------------------------------------------
-- List view (larger groups)
----------------------------------------------------------------------

-- Line kinds, told apart by their fields:
--   player row    `p` (the player's summary) - taller, with their picture
--   category row  `cat`
--   item row      `link`, plus `icon`, `mark` and `note`
local function BuildLines(sum, awards, insights)
    local o = ns.db.options
    local lines = {}
    local function add(t) lines[#lines + 1] = t end

    local n = #sum.players
    local equal = n > 0 and sum.market / n or 0

    for _, p in ipairs(sum.players) do
        local open = expanded[p.name]
        local titles = ""
        for _, award in ipairs(AwardList(awards, p.name)) do
            titles = titles .. "   " .. AwardTitle(award)
        end
        add({
            player = p.name, p = p, bg = 0.12,
            label = (open and "|cffffd100-|r " or "|cffffd100+|r ")
                .. ClassColored(DisplayName(p.name), p.class) .. titles,
            count = p.count, vendor = Money(p.vendor), market = Money(p.market),
            share = Pct(p.market, sum.market),
            diff = sum.market > 0 and DiffText(p.market - equal) or "",
            frac = sum.market > 0 and p.market / sum.market or 0,
        })
        if open then
            if p.count == 0 then
                add({ indent = 24, wide = true,
                      label = sum.needOnly and "|cff808080No Need wins|r" or "|cff808080No loot seen|r" })
            end
            for _, cat in ipairs(o.groupByCategory and CATS or { false }) do
                local c = GroupOf(p, cat)
                if c then
                    if cat then
                        add({
                            indent = 24, bg = 0.05, cat = cat,
                            label = CatColored(cat.label, cat),
                            count = Grey(tostring(c.count)), vendor = MoneyGrey(c.vendor),
                            market = MoneyGrey(c.market),
                            share = Grey(Pct(c.market, p.market)),
                        })
                    end
                    for _, e in ipairs(c.items) do
                        local mark = PriceMark(e)
                        local dominant = IsDominant(mark, ns.EntryMarket(e), sum.market)
                        add({
                            indent = cat and 36 or 24, link = e.link, e = e, label = e.link, icon = true,
                            mark = mark, warn = dominant, note = PriceNote(e, mark, dominant),
                            roll = RollNote(e),
                            count = "x" .. e.count,
                            vendor = Money(e.vendor * e.count),
                            market = Money(ns.EntryMarket(e)),
                        })
                    end
                end
            end
        end
    end

    if n > 0 and o.showTotals then
        add({})
        add({ indent = 4, bg = 0.12, label = "|cffffd100Total|r", count = sum.count,
              vendor = Money(sum.vendor), market = Money(sum.market), share = "100%" })
        add({ indent = 4, label = "Equal split (" .. n .. " players)",
              vendor = Money(sum.vendor / n), market = Money(sum.market / n), share = Pct(1, n) })
    end
    local texts = FooterTexts(sum, insights, false)
    if #texts > 0 then add({}) end
    for _, text in ipairs(texts) do
        add({ indent = 4, label = text, wide = true })
    end
    return lines
end

----------------------------------------------------------------------
-- Footer buttons. Each has a game-styled and a flat variant; the theme
-- decides which one is visible.
----------------------------------------------------------------------

-- `parent` defaults to this window; other panels pass their own and get
-- buttons that follow the theme the same way.
local function MakeButton(text, width, onClick, parent)
    local b = CreateFrame("Frame", nil, parent or ui)
    b:SetSize(width, 22)

    b.tpl = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    b.tpl:SetAllPoints()
    b.tpl:SetText(text)
    b.tpl:SetScript("OnClick", onClick)

    b.flat = CreateFrame("Button", nil, b)
    b.flat:SetAllPoints()
    local bg = b.flat:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.08)
    b.flat.bg = bg

    -- A line in the accent colour under the button, for the selected state.
    local function Mark(owner)
        local t = owner:CreateTexture(nil, "OVERLAY")
        t:SetPoint("BOTTOMLEFT", 3, 1)
        t:SetPoint("BOTTOMRIGHT", -3, 1)
        t:SetHeight(2)
        t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        t:Hide()
        return t
    end
    b.tpl.mark, b.flat.mark = Mark(b.tpl), Mark(b.flat)
    local hl = b.flat:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.30)
    b.flat.text = b.flat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.flat.text:SetPoint("CENTER")
    b.flat.text:SetText(text)
    b.flat:SetScript("OnClick", onClick)

    function b:SetLabel(label)
        self.tpl:SetText(label)
        self.flat.text:SetText(label)
    end
    function b:SetOn(on)
        self.tpl:SetEnabled(on)
        self.flat:SetEnabled(on)
        self.flat.text:SetAlpha(on and 1 or 0.35)
    end
    function b:SetFlat(flat)
        self.tpl:SetShown(not flat)
        self.flat:SetShown(flat)
    end
    -- For tabs and toggles: marks the button as the current choice. The
    -- other buttons of the set stay fully readable.
    function b:SetSelected(selected)
        self.tpl.mark:SetShown(selected)
        self.flat.mark:SetShown(selected)
        self.flat.bg:SetColorTexture(1, 1, 1, selected and 0.16 or 0.08)
        self.flat.text:SetAlpha(selected and 1 or 0.7)
        if selected then self.tpl:LockHighlight() else self.tpl:UnlockHighlight() end
    end
    buttons[#buttons + 1] = b
    return b
end

local older = MakeButton("< Older", 70, function() viewIndex = viewIndex + 1; Render() end)
older:SetPoint("BOTTOMLEFT", 12, 10)
local newer = MakeButton("Newer >", 70, function() viewIndex = viewIndex - 1; Render() end)
newer:SetPoint("LEFT", older, "RIGHT", 4, 0)

-- Pin: the run on show is never deleted, whatever clears the history.
-- Delete: remove just that run (asks first; not for a pinned run).
local pinBtn = MakeButton("Pin", 60, function() ns.TogglePin(currentRun) end)
pinBtn:SetPoint("LEFT", newer, "RIGHT", 12, 0)
local deleteBtn = MakeButton("Delete", 60, function() ns.AskDeleteRun(currentRun) end)
deleteBtn:SetPoint("LEFT", pinBtn, "RIGHT", 4, 0)

local optionsBtn = MakeButton("Options", 80, function() ns.ToggleOptions() end)
optionsBtn:SetPoint("BOTTOMRIGHT", -24, 10)

-- Top row: switch between all loot and Need-roll wins only (to see who
-- needed what). Placed by ApplyTheme.
local needBtn = MakeButton("Need rolls only", 130, function()
    needOnly = not needOnly
    Render()
end)

-- The rest of the top row. Run details: everything about the run on
-- show (podium, front page, timeline, rolls, numbers). Statistics: the
-- tables over all runs (dungeons, luck, drops, item search and so on).
local detailsBtn = MakeButton("Run details", 100, function() ns.OpenShow(ns.ViewedRun()) end)
detailsBtn:SetPoint("LEFT", needBtn, "RIGHT", 12, 0)
local statsBtn = MakeButton("Statistics", 90, function() ns.ShowBrowse("dungeons") end)
statsBtn:SetPoint("LEFT", detailsBtn, "RIGHT", 4, 0)
local bingoBtn = MakeButton("Bingo", 70, function() ns.ToggleBingo() end)
bingoBtn:SetPoint("LEFT", statsBtn, "RIGHT", 12, 0)

local expandAll = MakeButton("Expand all", 90, function()
    local s = Runs()[viewIndex]
    if not s then return end
    local anyClosed = false
    for name in pairs(s.players) do
        if not expanded[name] then anyClosed = true end
    end
    for name in pairs(s.players) do expanded[name] = anyClosed or nil end
    Render()
end)
expandAll:SetPoint("RIGHT", optionsBtn, "LEFT", -4, 0)

local runLabel = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
runLabel:SetPoint("LEFT", deleteBtn, "RIGHT", 10, 0)
runLabel:SetPoint("RIGHT", expandAll, "LEFT", -10, 0)
runLabel:SetJustifyH("LEFT")
runLabel:SetWordWrap(false)

----------------------------------------------------------------------
-- Themes
----------------------------------------------------------------------

local function ApplyTheme()
    local name = ns.db.theme
    if not THEMES[name] then name = "classic" end
    currentTheme = name
    theme = THEMES[name]

    local active = skins[name] or skins.classic
    for _, skin in pairs(skins) do skin:SetShown(skin == active) end

    title:ClearAllPoints()
    if theme.flat then
        title:SetFontObject("GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -10)
    else
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOP", 0, -5)
    end

    needBtn:ClearAllPoints()
    needBtn:SetPoint("TOPLEFT", 12, theme.toolbarY)

    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, theme.scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", theme.scrollRight, 42)
    if scroll.ScrollBar then scroll.ScrollBar:SetAlpha(theme.flat and 0 or 1) end

    for _, h in ipairs(headers) do
        if theme.flat then h:SetTextColor(0.60, 0.63, 0.68) else h:SetTextColor(1, 0.82, 0) end
    end
    for _, b in ipairs(buttons) do b:SetFlat(theme.flat) end
    for _, r in ipairs(rows) do StyleRow(r) end
    for _, c in ipairs(cols) do
        for _, r in ipairs(c.rows) do StyleHighlight(r) end
    end
end

function ns.SetTheme(name)
    if not THEMES[name] then return false end
    ns.db.theme = name
    if f:IsShown() then Render() end
    if ns.SyncOptions then ns.SyncOptions() end
    return true
end

----------------------------------------------------------------------
-- Render
----------------------------------------------------------------------

function Render()
    if currentTheme ~= (THEMES[ns.db.theme] and ns.db.theme or "classic") then ApplyTheme() end
    f:SetScale(ns.db.options.scale or 1)
    headers.market:SetText(ns.db.options.valueMode == "vendor" and "Value" or "Market")

    local runs = Runs()
    viewIndex = math.max(1, math.min(viewIndex, math.max(#runs, 1)))
    local s = runs[viewIndex]
    currentRun = s

    needBtn:SetLabel(needOnly and "Show all loot" or "Need rolls only")
    needBtn:SetSelected(needOnly)
    older:SetOn(viewIndex < #runs)
    newer:SetOn(viewIndex > 1)
    local stored = s ~= nil and not s.example
    pinBtn:SetOn(stored)
    pinBtn:SetLabel(s and s.pinned and "Unpin" or "Pin")
    pinOutline:SetShown(s ~= nil and s.pinned == true)
    deleteBtn:SetOn(stored and not s.pinned)

    local lines, sum
    if s then
        local tag = ""
        if s.example then
            tag = "  example data"
        elseif s == ns.db.active and not s.leftAt then
            tag = "  in progress"
        end
        title:SetText(ns.Title((s.name or "Run") .. (needOnly and "  -  Need rolls only" or "")))
        runLabel:SetText(("%s  |cff808080(%d/%d)%s|r%s"):format(
            date("%Y-%m-%d %H:%M", s.startedAt), viewIndex, #runs, tag,
            s.pinned and "  |cffffd100pinned|r" or ""))
        sum = ns.Summarize(s, needOnly)
    end

    -- Awards and insights are worked out from the whole run, whatever the
    -- view shows. Awards only once the run is over (or for past and
    -- example runs).
    local full = s and (needOnly and ns.Summarize(s) or sum)
    local awards = {}
    if s and ns.db.options.showAwards and not (s == ns.db.active and not s.leftAt) then
        awards = ns.Awards(s, full)
    end
    shownAwards = awards
    local insights = s and ns.RunInsights(s, full) or nil
    if insights then
        insights.fair = ns.Fairness(full)
        insights.streak = ns.db.options.streak and ns.Streak(s) or nil
    end

    if not s then
        title:SetText(ns.Title())
        runLabel:SetText("")
    end

    -- Small groups get one column per player; bigger ones the list.
    local useColumns = sum ~= nil and ns.db.options.useColumns
        and #sum.players > 0 and #sum.players <= MAX_COLUMNS
    -- The list view honours the same "show" options as the columns.
    local showVendor = ns.db.options.showVendor and ns.db.options.valueMode ~= "vendor"
    local showShare = ns.db.options.showShare
    for _, h in ipairs(headers) do h:SetShown(not useColumns) end
    headers.vendor:SetShown(not useColumns and showVendor)
    headers.share:SetShown(not useColumns and showShare)
    headers.diff:SetShown(not useColumns and showShare)
    expandAll:SetShown(not useColumns)
    if useColumns then
        for _, r in ipairs(rows) do r:Hide() end
        RenderColumns(sum, awards, insights)
        return
    end
    ceremonyPending = false -- the reveal only exists in the column view
    for _, c in ipairs(cols) do c:Hide() end
    for _, fs in ipairs(footLines) do fs:Hide() end
    if sum then
        lines = BuildLines(sum, awards, insights)
    else
        lines = { { indent = 4, wide = true,
                    label = "No run recorded yet. Enter a dungeon, or type /fs start." } }
    end

    local o = ns.db.options
    local rowH = theme.rowH
    local playerH = rowH + 14 -- player rows are taller, to hold the picture
    local width = content:GetWidth()
    local y = 0
    for i, line in ipairs(lines) do
        local r = GetRow(i)
        local h = line.p and playerH or rowH
        r.line = line
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", 0, -y)
        r:SetHeight(h)
        y = y + h

        -- Whatever sits left of the label pushes it to the right.
        local left = line.indent or 4

        local showPicture = line.p ~= nil and o.portrait ~= "none"
        if showPicture then
            local size = h - 10
            r.portrait:SetSize(size, size)
            r.ring:SetSize(size + 6, size + 6)
            r.ringInner:SetSize(size + 2, size + 2)
            r.ring:SetVertexColor(ClassRGB(line.p.class))
            -- No 3D models in the list: both picture modes use the portrait.
            FillPortrait(r.portrait, line.p, o.portrait ~= "class" and UnitForName(line.p.name) or nil,
                         o.portrait ~= "class")
            left = size + 18
        end
        r.portrait:SetShown(showPicture)
        r.ring:SetShown(showPicture)
        r.ringInner:SetShown(showPicture)

        if line.icon and o.showIcons then
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", left, 0)
            r.icon:SetSize(h - 4, h - 4)
            r.icon:SetTexture(ItemIcon(line.link))
            r.icon:Show()
            left = left + h
        else
            r.icon:Hide()
        end

        if line.cat then
            r.chip:ClearAllPoints()
            r.chip:SetPoint("LEFT", left - 8, 0)
            r.chip:SetSize(3, h - 4)
            r.chip:SetColorTexture(line.cat.color[1], line.cat.color[2], line.cat.color[3], 0.9)
            r.chip:Show()
        else
            r.chip:Hide()
        end

        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", left, 0)
        if line.wide then
            r.label:SetPoint("RIGHT", -4, 0) -- a note: no figures to make room for
        else
            r.label:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
        end
        r.label:SetText(line.label or "")
        r.count:SetText(line.count or "")
        r.vendor:SetText(showVendor and line.vendor or "")
        r.market:SetText(line.market or "")
        r.diff:SetText(showShare and line.diff or "")
        r.share:SetText(showShare and line.share or "")
        SetMark(r.mark, line.mark)
        SetRowBg(r.bg, line)
        if theme.flat and line.frac and line.frac > 0 then
            r.bar:SetWidth(math.max(1, width * line.frac))
            r.bar:Show()
        else
            r.bar:Hide()
        end
        r:EnableMouse(line.player ~= nil or line.link ~= nil)
        r:Show()
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(y, 1))
end

function ns.Refresh()
    if pending or not f:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if f:IsShown() then Render() end
    end)
end

-- Immediate redraw, used when an option changes.
function ns.Rerender()
    if f:IsShown() then Render() end
end

-- ceremony: reveal the award cards one by one (used when the window
-- opens by itself at the end of a run).
function ns.ShowWindow(ceremony)
    viewIndex = 1
    ceremonyPending = ceremony and ns.db.options.showAwards or false
    RestoreWindow()
    f:Show()
    Render()
end

function ns.ToggleWindow()
    if f:IsShown() then f:Hide() else ns.ShowWindow() end
end

-- Opens the window on one particular run (used by the item search).
function ns.ShowRun(s)
    viewIndex = 1
    for i, run in ipairs(Runs()) do
        if run == s then viewIndex = i end
    end
    ceremonyPending = false
    RestoreWindow()
    f:Show()
    Render()
end

-- The run on show in this window, or the most recent one if the window
-- has not been drawn yet.
function ns.ViewedRun()
    return currentRun or Runs()[1]
end

-- Shared with the other panels.
ns.MoneyPlain = function(copper) return MoneyText(copper, false) end
ns.UnitForName = UnitForName
ns.FillPortrait = FillPortrait
ns.NewModel, ns.DressModel, ns.ModelLoaded = NewModel, DressModel, ModelLoaded
ns.PlayKit = PlayKit
ns.AddAwardLines = AddAwardLines
ns.AWARDS_HINT = AWARDS_HINT
ns.Money = Money
ns.Duration = Duration
ns.ClassColored = ClassColored
ns.DisplayName = DisplayName
ns.ItemIcon = ItemIcon
ns.MakeButton = MakeButton
