local _, ns = ...

local issecret = issecretvalue or function() return false end

local WIDTH, HEIGHT = 780, 540
local MAX_COLUMNS = 5     -- groups up to this size get one column per player
local COL_GAP = 6
local ACCENT = { 0.25, 0.78, 0.72 }

local THEMES = {
    classic = { rowH = 18, font = "GameFontHighlightSmall", scrollTop = -54, scrollRight = -32 },
    retail  = { rowH = 20, font = "GameFontHighlightSmall", scrollTop = -54, scrollRight = -32 },
    modern  = { rowH = 24, font = "GameFontHighlight",      scrollTop = -66, scrollRight = -14, flat = true },
}

local CATS = {
    { key = "epic",     label = "Epic BoE",                      short = "Epic BoE",    color = { 0.64, 0.21, 0.93 } },
    { key = "rare",     label = "Blue BoE",                      short = "Blue BoE",    color = { 0.20, 0.55, 1.00 } },
    { key = "uncommon", label = "Green BoE",                     short = "Green BoE",   color = { 0.12, 1.00, 0.00 } },
    { key = "bop",      label = "Bind on Pickup (vendor value)", short = "BoP",         color = { 1.00, 0.50, 0.00 } },
    { key = "quest",    label = "Quest items (vendor value)",    short = "Quest",       color = { 1.00, 1.00, 0.45 } },
    { key = "prof",     label = "Profession materials",          short = "Professions", color = { 1.00, 0.82, 0.00 } },
    { key = "other",    label = "Other",                         short = "Other",       color = { 0.85, 0.85, 0.85 } },
    { key = "junk",     label = "Junk",                          short = "Junk",        color = { 0.62, 0.62, 0.62 } },
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
    f:SetResizeBounds(520, 320, 1100, 1000)
elseif f.SetMinResize then
    f:SetMinResize(520, 320)
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

-- Builds the three skins on a frame and returns them keyed by theme name
-- (`retail` is missing when its template does not exist on this client).
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

    -- Retail: the current default panel.
    do
        local ok, s = pcall(CreateFrame, "Frame", nil, frame, "DefaultPanelTemplate")
        if ok and s then
            s:SetAllPoints()
            local okBtn, b = pcall(CreateFrame, "Button", nil, s, "UIPanelCloseButtonDefaultAnchors")
            if not okBtn then
                b = CreateFrame("Button", nil, s, "UIPanelCloseButton")
                b:SetPoint("TOPRIGHT", 2, 2)
            end
            b:SetScript("OnClick", onClose)
            skins.retail = s
        end
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
        local line = s:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 0, -36)
        line:SetPoint("TOPRIGHT", 0, -36)
        line:SetHeight(1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
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
local COLS = {
    { key = "share",  right = -4,   width = 50, header = "Share" },
    { key = "market", right = -58,  width = 96, header = "Market" },
    { key = "vendor", right = -158, width = 96, header = "Vendor" },
    { key = "count",  right = -258, width = 44, header = "Qty" },
}

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 44, 1)
scroll:SetScrollChild(content)
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

local function RowOnClick(self)
    local line = self.line
    if not line then return end
    if line.player then
        expanded[line.player] = not expanded[line.player] or nil
        Render()
    elseif line.link and IsModifiedClick("CHATLINK") then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if insert then insert(line.link) end
    end
end

local function RowOnEnter(self)
    local line = self.line
    if line and line.link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(line.link)
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
    if name == UnitName("player") then return "player" end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local unit = prefix .. i
        if UnitExists(unit) then
            local n = GetUnitName(unit, true)
            if n and not issecret(n) and n == name then return unit end
        end
    end
end

-- mode: "3d" model, "2d" portrait, "class" icon or "none". Models and
-- portraits need the player in the group right now; otherwise the class
-- icon is used.
--
-- Pictures are framed in the player's class colour: a ring around the
-- round 2D portrait / class icon, a square frame around the 3D model
-- (model frames cannot be masked to a circle).
local function SetPortrait(c, p, mode)
    local tex, model = c.portrait, c.model
    local unit = (mode == "2d" or mode == "3d") and UnitForName(p.name) or nil
    local useModel = mode == "3d" and unit ~= nil
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

    if useModel then
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
    if not useTexture then return end
    local coords = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
    if unit then
        SetPortraitTexture(tex, unit)
        tex:SetTexCoord(0, 1, 0, 1)
    elseif coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
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
    c.model = CreateFrame("PlayerModel", nil, c)
    c.model:SetSize(52, 52)
    c.model:SetPoint("TOP", 0, -6)
    c.model:Hide()

    -- Round pictures: class-coloured ring, dark disc, then the picture
    -- itself clipped to a circle.
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
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
    c.rows = {}
    cols[i] = c
    return c
end

local function GetColRow(c, j)
    local r = c.rows[j]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
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
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleHighlight(r)
    c.rows[j] = r
    return r
end

local totalLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
totalLine:SetJustifyH("LEFT")

local function PlaceText(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 2, y)
    fs:SetPoint("TOPRIGHT", -2, y)
end

local function ItemLine(link, count, market)
    return {
        link = link,
        label = (count > 1 and (count .. "x ") or "") .. link,
        value = Money(market),
    }
end

local function ItemKey(e)
    return e.link:match("item:(%d+)") or e.link
end

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
                    add(i, ItemLine(e.link, e.count, ns.EntryMarket(e)))
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
                    u = { key = k, name = ns.ItemName(e), total = 0 }
                    union[k] = u
                    order[#order + 1] = u
                end
                u.total = u.total + ns.EntryMarket(e)
            end
        end
        if #order == 0 then return end
        table.sort(order, function(a, b)
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
                    mine[k] = { link = e.link, count = e.count, market = ns.EntryMarket(e) }
                end
            end
            if cat then add(i, Header(cat, cs)) end
            for _, u in ipairs(order) do
                local m = mine[u.key]
                if m then
                    add(i, ItemLine(m.link, m.count, m.market))
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
            if p.count == 0 then add(i, { label = "|cff808080No loot seen|r" }) end
        end
    end
    return out
end

local function RenderColumns(sum)
    local n = #sum.players
    local colW = (content:GetWidth() - COL_GAP * (n - 1)) / n
    local rowH = theme.rowH - (ns.db.options.compact and 4 or 0)
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
    local headerH = 4 - y

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
        c.name:SetText(ClassColored(p.name, p.class))
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
            r.bg:SetColorTexture(1, 1, 1, line.bg or 0)
            r:EnableMouse(line.link ~= nil)
            r:Show()
        end
        for j = #lines + 1, #c.rows do c.rows[j]:Hide() end

        maxH = math.max(maxH, c.offset + headerH + #lines * rowH + 6)
        c:Show()
    end
    for i = 1, n do cols[i]:SetHeight(maxH - cols[i].offset) end
    for i = n + 1, #cols do cols[i]:Hide() end

    totalLine:ClearAllPoints()
    totalLine:SetPoint("TOPLEFT", 4, -(maxH + 10))
    if o.valueMode == "vendor" then
        totalLine:SetText(("|cffffd100Total|r  %s      |cff909090Equal split|r  %s"):format(
            Money(sum.market), Money(equal)))
    else
        totalLine:SetText(("|cffffd100Total|r  %s      |cff909090Vendor|r  %s      |cff909090Equal split|r  %s"):format(
            Money(sum.market), Money(sum.vendor), Money(equal)))
    end
    totalLine:SetShown(o.showTotals)
    content:SetHeight(maxH + 30)
end

----------------------------------------------------------------------
-- List view (larger groups)
----------------------------------------------------------------------

local function BuildLines(sum)
    local lines = {}
    local function add(t) lines[#lines + 1] = t end

    for _, p in ipairs(sum.players) do
        local open = expanded[p.name]
        add({
            player = p.name, indent = 4, bg = 0.12,
            label = (open and "|cffffd100-|r " or "|cffffd100+|r ") .. ClassColored(p.name, p.class),
            count = p.count, vendor = Money(p.vendor), market = Money(p.market),
            share = Pct(p.market, sum.market),
            frac = sum.market > 0 and p.market / sum.market or 0,
        })
        if open then
            if p.count == 0 then
                add({ indent = 24, label = "|cff808080No loot seen|r" })
            end
            for _, cat in ipairs(ns.db.options.groupByCategory and CATS or { false }) do
                local c = GroupOf(p, cat)
                if c then
                    if cat then
                        add({
                            indent = 20, bg = 0.05,
                            label = CatColored(cat.label, cat),
                            count = Grey(tostring(c.count)), vendor = MoneyGrey(c.vendor),
                            market = MoneyGrey(c.market),
                            share = Grey(Pct(c.market, p.market)),
                        })
                    end
                    for _, e in ipairs(c.items) do
                        add({
                            indent = cat and 36 or 20, link = e.link, label = e.link,
                            count = "x" .. e.count,
                            vendor = Money(e.vendor * e.count),
                            market = Money(ns.EntryMarket(e)),
                        })
                    end
                end
            end
        end
    end

    local n = #sum.players
    if n > 0 and ns.db.options.showTotals then
        add({})
        add({ indent = 4, bg = 0.12, label = "|cffffd100Total|r", count = sum.count,
              vendor = Money(sum.vendor), market = Money(sum.market), share = "100%" })
        add({ indent = 4, label = "Equal split (" .. n .. " players)",
              vendor = Money(sum.vendor / n), market = Money(sum.market / n), share = Pct(1, n) })
        if ns.db.options.valueMode ~= "vendor" then
            add({})
            add({ indent = 4, label = "|cff808080Market = auction price when known, vendor price otherwise.|r" })
        end
    end
    return lines
end

----------------------------------------------------------------------
-- Footer buttons. Each has a game-styled and a flat variant; the theme
-- decides which one is visible.
----------------------------------------------------------------------

local function MakeButton(text, width, onClick)
    local b = CreateFrame("Frame", nil, ui)
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
    local hl = b.flat:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.30)
    b.flat.text = b.flat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.flat.text:SetPoint("CENTER")
    b.flat.text:SetText(text)
    b.flat:SetScript("OnClick", onClick)

    function b:SetOn(on)
        self.tpl:SetEnabled(on)
        self.flat:SetEnabled(on)
        self.flat.text:SetAlpha(on and 1 or 0.35)
    end
    function b:SetFlat(flat)
        self.tpl:SetShown(not flat)
        self.flat:SetShown(flat)
    end
    buttons[#buttons + 1] = b
    return b
end

local older = MakeButton("< Older", 70, function() viewIndex = viewIndex + 1; Render() end)
older:SetPoint("BOTTOMLEFT", 12, 10)
local newer = MakeButton("Newer >", 70, function() viewIndex = viewIndex - 1; Render() end)
newer:SetPoint("LEFT", older, "RIGHT", 4, 0)

local optionsBtn = MakeButton("Options", 80, function() ns.ToggleOptions() end)
optionsBtn:SetPoint("BOTTOMRIGHT", -24, 10)

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
runLabel:SetPoint("LEFT", newer, "RIGHT", 10, 0)
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

    older:SetOn(viewIndex < #runs)
    newer:SetOn(viewIndex > 1)

    local lines, sum
    if s then
        local tag = ""
        if s.example then
            tag = "  example data"
        elseif s == ns.db.active and not s.leftAt then
            tag = "  in progress"
        end
        title:SetText("FairShare - " .. (s.name or "Run"))
        runLabel:SetText(("%s  |cff808080(%d/%d)%s|r"):format(
            date("%Y-%m-%d %H:%M", s.startedAt), viewIndex, #runs, tag))
        sum = ns.Summarize(s)
    else
        title:SetText("FairShare")
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
    expandAll:SetShown(not useColumns)
    if useColumns then
        for _, r in ipairs(rows) do r:Hide() end
        RenderColumns(sum)
        return
    end
    for _, c in ipairs(cols) do c:Hide() end
    totalLine:Hide()
    if sum then
        lines = BuildLines(sum)
    else
        lines = { { indent = 4, label = "No run recorded yet. Enter a dungeon, or type /fs start." } }
    end

    local rowH = theme.rowH - (ns.db.options.compact and 4 or 0)
    local width = content:GetWidth()
    for i, line in ipairs(lines) do
        local r = GetRow(i)
        r.line = line
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)
        r:SetHeight(rowH)
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", line.indent or 0, 0)
        r.label:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
        r.label:SetText(line.label or "")
        r.count:SetText(line.count or "")
        r.vendor:SetText(showVendor and line.vendor or "")
        r.market:SetText(line.market or "")
        r.share:SetText(showShare and line.share or "")
        r.bg:SetColorTexture(1, 1, 1, line.bg or 0)
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
    content:SetHeight(math.max(#lines * rowH, 1))
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

function ns.ShowWindow()
    viewIndex = 1
    RestoreWindow()
    f:Show()
    Render()
end

function ns.ToggleWindow()
    if f:IsShown() then f:Hide() else ns.ShowWindow() end
end
