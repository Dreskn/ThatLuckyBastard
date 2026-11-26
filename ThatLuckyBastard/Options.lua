local _, ns = ...

-- Options panel: a list of pages on the left, the selected page on the
-- right. Pages are named after what the player sees: a window (Breakdown,
-- Meter), a moment (During a run, End of run) or a plain noun. A page
-- reads top to bottom like the window it sets.
--
-- Labels are names. What an option does is in its tooltip, and so is why
-- it does nothing as things stand, in red, when it is greyed out (greyed
-- rather than hidden, so that nothing moves as you click). A choice of one
-- among a few is a row of buttons (radio buttons in the Classic theme),
-- an on/off switch a box: the two never look alike.

local GOLD = { 1.00, 0.82, 0.00 }
local RED = { 1.00, 0.13, 0.13 }
local WIDTH, HEIGHT = 590, 630
local SIDEBAR_W = 140
local ROW_H = 22
local ROW_X = 86 -- where the controls of a labelled row start
local GAP = 16   -- between boxes on a row

-- The last argument keeps this window at its size whatever the Size
-- option says, so that the slider does not move under the mouse.
local o, ui, title, skins = ns.MakeWindow("ThatLuckyBastardOptionsFrame", WIDTH, HEIGHT, "DIALOG", true, true)
o:SetPoint("CENTER")
title:SetText(ns.Title("Options"))

local sidebar = CreateFrame("Frame", nil, ui)
local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
sidebarBg:SetAllPoints()
local pageArea = CreateFrame("Frame", nil, ui)

local pages, navs, sections, controls, choices, buttons = {}, {}, {}, {}, {}, {}
local live = {} -- what follows the saved data, redone on every sync
local currentPage = 1
local navY = -6
local flat = false
local scaleSlider, scaleValue
local hueSliders = {} -- the custom accent's three values
local Sync

local function Opt() return ns.db.options end

----------------------------------------------------------------------
-- Why an option does nothing as things stand: a reason, or nil when it
-- works. The tooltip shows it in red.
----------------------------------------------------------------------

local function IsMini() return Opt().useColumns and Opt().mini end
local why = {}
function why.modern()
    return ns.ThemeName() ~= "modern" and "Modern theme only." or nil
end
function why.notMini()
    return IsMini() and "Not in the Mini layout." or nil
end
function why.columns()
    return (not Opt().useColumns or Opt().mini) and "Columns layout only." or nil
end
function why.icons()
    return ns.ThemeName() == "receipt" and "A receipt prints no icons." or why.notMini()
end
function why.bar()
    return ns.ThemeName() == "classic" and "Not in the Classic theme." or why.notMini()
end
function why.vendor()
    return Opt().valueMode == "vendor" and "Prices are vendor prices already." or why.notMini()
end
function why.auction()
    return Opt().valueMode == "vendor" and "Value is set to Vendor." or nil
end
function why.today()
    return why.auction() or (not ns.HasPriceSource() and "No Auctionator or TradeSkillMaster.") or nil
end
function why.selfFirst()
    return Opt().sortPlayers == "podium" and "Not with Podium order." or nil
end
-- As a run is left, its columns race for their places: that takes the
-- columns, in podium order.
function why.race()
    if why.columns() then return "Needs the Columns layout (Breakdown)." end
    return Opt().sortPlayers ~= "podium" and "Needs Podium order (Breakdown)." or nil
end
-- Without the race, the awards come up one by one: the sounds and the
-- screenshot go with either.
function why.reveal()
    local x = Opt()
    return not ((x.race and not why.race()) or x.showAwards) and "Awards and Race are off." or nil
end
function why.awards()
    return not Opt().showAwards and "Awards are off (End of run)." or nil
end
function why.hidden()
    for _, on in pairs(Opt().cats) do
        if on == false then return nil end
    end
    return "Every category is shown."
end
function why.tipKinds()
    return not Opt().tipItems and "Seen in runs is off." or nil
end
function why.ticker()
    return not Opt().ticker and "Valuable loot is off." or nil
end

----------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------

-- The option's name in white, what it does, and why it is greyed out.
local function ShowTip(self)
    if self.hover then self:hover(true) end
    local reason = self.why and self.why()
    if not (self.tip or reason) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tipTitle or "", 1, 1, 1)
    if self.tip then GameTooltip:AddLine(self.tip, GOLD[1], GOLD[2], GOLD[3], true) end
    if reason then GameTooltip:AddLine(reason, RED[1], RED[2], RED[3], true) end
    GameTooltip:Show()
end
local function HideTip(self)
    if self.hover then self:hover(false) end
    GameTooltip:Hide()
end
local function Tip(frame, name, text, reason)
    frame.tipTitle, frame.tip, frame.why = name, text, reason
    frame:SetScript("OnEnter", ShowTip)
    frame:SetScript("OnLeave", HideTip)
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

-- A page, the keys of db.options it holds (for its own Defaults), and
-- whether a gap above its name in the list starts a new group.
local ShowPage
local function NewPage(name, keys, gap)
    local index = #pages + 1
    local p = CreateFrame("Frame", nil, pageArea)
    p:SetAllPoints()
    p:Hide()
    p.name, p.keys = name, keys
    pages[index] = p

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT")
    p.title:SetText(name)
    p.y = -26

    if gap then navY = navY - 12 end
    local n = CreateFrame("Button", nil, sidebar)
    n:SetSize(SIDEBAR_W, 26)
    n:SetPoint("TOPLEFT", 0, navY)
    navY = navY - 28
    n.bg = n:CreateTexture(nil, "BACKGROUND")
    n.bg:SetAllPoints()
    n.bar = n:CreateTexture(nil, "ARTWORK")
    n.bar:SetPoint("TOPLEFT")
    n.bar:SetPoint("BOTTOMLEFT")
    n.bar:SetWidth(3)
    local hl = n:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    n.text = n:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    n.text:SetPoint("LEFT", 12, 0)
    n.text:SetText(name)
    n:SetScript("OnClick", function() ShowPage(index) end)
    navs[index] = n
    return p
end

-- A titled group of controls with a rule under the title. `tip`, if
-- given, comes up over the title.
local function Section(p, text, tip)
    p.y = p.y - 10
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 0, p.y)
    fs:SetText(text)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, p.y - 16)
    line:SetPoint("TOPRIGHT", 0, p.y - 16)
    line:SetHeight(1)
    sections[#sections + 1] = { text = fs, line = line }
    if tip then
        local hover = CreateFrame("Frame", nil, p)
        hover:SetPoint("TOPLEFT", fs)
        hover:SetPoint("BOTTOMRIGHT", fs)
        hover:EnableMouse(true)
        Tip(hover, text, tip)
    end
    p.y = p.y - 22
end

-- The name of a row, whose controls start at ROW_X.
local function RowLabel(p, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, p.y - 5)
    fs:SetText(text)
    fs:SetTextColor(0.66, 0.66, 0.66)
    return fs
end

-- Grey text on a line of its own.
local function Note(p, x)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", (x or 0) + 4, p.y - 3)
    fs:SetJustifyH("LEFT")
    p.y = p.y - 18
    return fs
end

-- An on/off box, drawn by the panel itself so it can be restyled per
-- theme. Does not move the page cursor.
local function PaintBox(b) b.tick:SetShown(b.get() and true or false) end
local function HoverBox(b, on)
    local v = on and 1 or 0.9
    b.text:SetTextColor(v, v, v)
end
local function MakeCheck(p, x, label, get, set, tip, reason)
    local b = CreateFrame("Button", nil, p)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", x, p.y)
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetPoint("CENTER", b.box)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 26, 0)
    b.text:SetText(label)
    b.text:SetTextColor(0.9, 0.9, 0.9)
    b:SetWidth(30 + b.text:GetStringWidth())
    b.get, b.Paint, b.hover = get, PaintBox, HoverBox
    b:SetScript("OnClick", function()
        set(not get())
        Sync()
    end)
    Tip(b, label, tip, reason)
    controls[#controls + 1] = b
    return b
end

-- A box's definition: { "Label", key, tip, why } for a switch in
-- db.options, or { "Label", get, set, tip, why }.
local function Def(def)
    if type(def[2]) == "string" then
        local key = def[2]
        return def[1], function() return Opt()[key] end, function(on) Opt()[key] = on end, def[3], def[4]
    end
    return def[1], def[2], def[3], def[4], def[5]
end

-- A row of boxes, each as wide as its label, from `x`.
local function Boxes(p, defs, x)
    x = x or 0
    for _, def in ipairs(defs) do
        local b = MakeCheck(p, x, Def(def))
        x = x + b:GetWidth() + GAP
    end
    p.y = p.y - ROW_H
end

-- Boxes in columns `colW` wide, `columns` to a row, from `x0`.
local function Grid(p, defs, columns, colW, x0)
    for i, def in ipairs(defs) do
        local col = (i - 1) % columns
        MakeCheck(p, (x0 or 0) + col * colW, Def(def))
        if col == columns - 1 or i == #defs then p.y = p.y - ROW_H end
    end
end

-- A choice of one among a few: a named row of buttons. options =
-- { { "Label", value, tip }, ... }; get() gives the value chosen. Laid out
-- by the theme (see StyleChoice).
local function PaintChoice(b)
    local on = b.get()
    if flat then
        local a = ns.ThemeAccent()
        if on then b.bg:SetColorTexture(a[1], a[2], a[3], 0.26) else b.bg:SetColorTexture(1, 1, 1, 0.07) end
        b.under:SetColorTexture(a[1], a[2], a[3], 1)
        b.under:SetShown(on)
        b.tick:Hide()
        local v = on and 1 or 0.8
        b.text:SetTextColor(v, v, v)
    else
        b.bg:SetColorTexture(0, 0, 0, 0)
        b.under:Hide()
        b.tick:SetShown(on)
        b.text:SetTextColor(0.9, 0.9, 0.9)
    end
end
local function HoverChoice(b, on)
    if on then b.text:SetTextColor(1, 1, 1) else b:Paint() end
end
local function Choice(p, label, options, get, set, reason)
    RowLabel(p, label)
    local c = { y = p.y, buttons = {} }
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, p)
        b:SetHeight(ROW_H)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.under = b:CreateTexture(nil, "ARTWORK")
        b.under:SetPoint("BOTTOMLEFT")
        b.under:SetPoint("BOTTOMRIGHT")
        b.under:SetHeight(2)
        b.box = b:CreateTexture(nil, "ARTWORK")
        b.tick = b:CreateTexture(nil, "OVERLAY")
        b.tick:SetPoint("CENTER", b.box)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetText(opt[1])
        local value = opt[2]
        b.get = function() return get() == value end
        b.Paint, b.hover, b.radio = PaintChoice, HoverChoice, true -- styled by StyleChoice, not as a box
        b:SetScript("OnClick", function()
            set(value)
            Sync()
        end)
        Tip(b, label .. ": " .. opt[1], opt[3], opt[4] or reason) -- a choice may have its own reason
        c.buttons[i] = b
        controls[#controls + 1] = b
    end
    choices[#choices + 1] = c
    p.y = p.y - ROW_H - 2
end

-- A small box to type a whole number in, at `x` on the row. get and set
-- work in the box's own unit; the number is kept from `min` to `max`.
local function NumberBox(p, x, key, get, set, min, max, tip, reason)
    local box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    box:SetSize(44, 20)
    box:SetPoint("TOPLEFT", x + 6, p.y - 1)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(#tostring(max))
    box:SetJustifyH("CENTER")
    box.key = key
    local function Show() box:SetText(tostring(get())) end
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", function(self)
        Show()
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText())
        if n then set(math.max(min, math.min(math.floor(n), max))) end
        Show()
        Sync()
    end)
    Tip(box, box.tipTitle, tip, reason)
    live[#live + 1] = function()
        local off = reason and reason()
        if off then box:ClearFocus() end
        if not box:HasFocus() then Show() end
        box:EnableMouse(not off)
        box:SetAlpha(off and 0.4 or 1)
    end
    return box
end

-- A slider drawn by the panel, restyled per theme like its boxes.
local function Slider(p, width, x, y)
    local s = CreateFrame("Slider", nil, p)
    s:SetOrientation("HORIZONTAL")
    s:EnableMouse(true)
    s:SetSize(width, 16)
    s:SetPoint("TOPLEFT", x, y)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    return s
end

-- A button of the window's own look, on a row of its own.
local function Button(p, label, width, onClick, tip)
    local b = ns.MakeButton(label, width, onClick, p)
    b:SetPoint("TOPLEFT", 0, p.y - 6)
    for _, face in ipairs({ b.tpl, b.flat }) do Tip(face, label, tip) end
    buttons[#buttons + 1] = b
    p.y = p.y - ROW_H - 10
    return b
end

----------------------------------------------------------------------
-- Page: Look
----------------------------------------------------------------------

local function MoneyGet()
    local x = Opt()
    return not x.showSilver and "g" or (x.showCopper and "gsc" or "gs")
end
local function MoneySet(v)
    Opt().showSilver, Opt().showCopper = v ~= "g", v == "gsc"
end

-- The game's colour picker for the custom colour, where the game has one
-- (opened the new way or the old one). The sliders do the same.
local function OpenPicker()
    local picker = ColorPickerFrame
    if not picker then return end
    local c = Opt().accentCustom
    local old = { c[1] or 0, c[2] or 0, c[3] or 0 }
    local function Take(r, g, b)
        local custom = Opt().accentCustom
        custom[1], custom[2], custom[3] = r, g, b
        Sync()
    end
    local function Picked() Take(picker:GetColorRGB()) end
    local function Cancelled() Take(old[1], old[2], old[3]) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({ r = old[1], g = old[2], b = old[3], hasOpacity = false,
                                         swatchFunc = Picked, cancelFunc = Cancelled })
    else
        picker.hasOpacity, picker.opacityFunc = false, nil
        picker.func, picker.cancelFunc = Picked, Cancelled
        picker.previousValues = { r = old[1], g = old[2], b = old[3] }
        picker:SetColorRGB(old[1], old[2], old[3])
        ShowUIPanel(picker)
    end
    if picker.Raise then picker:Raise() end
end

do
    local p = NewPage("Look", { "theme", "accent", "accentCustom", "scale", "showSilver", "showCopper", "showMinimap" })

    Section(p, "Windows", "Every window: the breakdown, the meter, statistics and the rest.")
    Choice(p, "Theme", {
        { "Modern", "modern", "Flat, in the color below." },
        { "Classic", "classic", "The game's own panels." },
        { "Receipt", "receipt", "Each player's loot on a till receipt." },
    }, ns.ThemeName, function(v) ns.db.theme = v end)

    -- The Modern theme's accent: the addon's teal, the class colour, or
    -- Custom, the player's own, as three values from 0 to 255 under it.
    Choice(p, "Color", {
        { "TLB", "teal", "The addon's own teal." },
        { "Class", "class", "Your character's class color." },
        { "Custom", "custom", "Your own: the sliders under it, or the game's color picker." },
    }, function() return Opt().accent end, function(v)
        Opt().accent = v
        if v == "custom" then OpenPicker() end
    end, why.modern)
    for i, letter in ipairs({ "R", "G", "B" }) do
        local lx = ROW_X + (i - 1) * 98
        local s = Slider(p, 70, lx + 14, p.y - 3)
        s.channel = i
        s.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.label:SetPoint("TOPLEFT", lx, p.y - 5)
        s.label:SetText(letter)
        s:SetMinMaxValues(0, 255)
        s:SetValueStep(1)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        s:SetScript("OnValueChanged", function(_, value)
            if not ns.db then return end
            value = math.floor(value + 0.5)
            local custom = Opt().accentCustom
            -- Only a value that is new: Sync sets the sliders too.
            if math.floor((custom[i] or 0) * 255 + 0.5) ~= value then
                custom[i] = value / 255
                Sync()
            end
        end)
        hueSliders[i] = s
    end
    p.y = p.y - ROW_H - 2

    RowLabel(p, "Size")
    local s = Slider(p, 180, ROW_X, p.y - 3)
    s:SetMinMaxValues(0.6, 1.6)
    s:SetValueStep(0.05)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    scaleValue = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("TOPLEFT", ROW_X + 192, p.y - 5)
    s:SetScript("OnValueChanged", function(_, value)
        if not ns.db then return end
        value = math.floor(value * 20 + 0.5) / 20
        scaleValue:SetText(("%d%%"):format(value * 100 + 0.5))
        if Opt().scale ~= value then
            Opt().scale = value
            ns.Rerender()
        end
    end)
    scaleSlider = s
    p.y = p.y - ROW_H - 2

    -- Two saved switches, offered as the three ways they can combine.
    Choice(p, "Money", {
        { "12g 34s 56c", "gsc", "Gold, silver and copper." },
        { "12g 34s", "gs", "Less than 1s still shows." },
        { "12g", "g", "Less than 1g still shows." },
    }, MoneyGet, MoneySet)

    Section(p, "Minimap")
    Boxes(p, { { "Minimap button", "showMinimap", "Left-click: the window. Right-click: the options." } })
end

----------------------------------------------------------------------
-- Page: Breakdown
----------------------------------------------------------------------

-- Two saved switches as three layouts: mini mode is the columns' own.
local function LayoutGet()
    if IsMini() then return "mini" end
    return Opt().useColumns and "columns" or "list"
end
local function LayoutSet(v)
    Opt().useColumns, Opt().mini = v ~= "list", v == "mini"
end

local function Key(key)
    return function() return Opt()[key] end, function(v) Opt()[key] = v end
end

do
    local p = NewPage("Breakdown", { "useColumns", "mini", "portrait", "nameStyle", "sortPlayers", "selfFirst",
                                     "showShare", "showBar", "showVendor", "sortItems", "showIcons", "groupByCategory",
                                     "alignItems", "benchPicture", "benchAward", "benchValue", "showTotals",
                                     "showInsights" })

    Choice(p, "Layout", {
        { "Columns", "columns", "A column per player, up to five. The others sit on the bench." },
        { "List", "list", "A line per player." },
        { "Mini", "mini", "A small window: a card per player with picture, name, award and total." },
    }, LayoutGet, LayoutSet)

    Section(p, "Players")
    local get, set = Key("portrait")
    Choice(p, "Picture", {
        { "2D", "2d", "Portrait. Players out of sight show their class icon." },
        { "3D", "3d", "Model, in the Columns layout. Players out of sight show their class icon." },
        { "Class", "class", "Class icon." },
        { "None", "none" },
    }, get, set)
    get, set = Key("nameStyle")
    Choice(p, "Names", {
        { "Game", "game", "As the game shows them." },
        { "Full", "full", "First and last name." },
        { "First", "first", "First name only." },
    }, get, set)
    get, set = Key("sortPlayers")
    Choice(p, "Order", {
        { "Podium", "podium", "Top looter in the middle." },
        { "Loot", "value", "Most loot first." },
        { "Role", "role", "Tank, healer, damage." },
        { "Name", "name" },
    }, get, set)
    Boxes(p, { { "Me first", "selfFirst", "You always come first.", why.selfFirst } }, ROW_X)

    -- What is about the loot under the players does nothing in mini mode.
    Section(p, "Per player")
    Boxes(p, {
        { "Share", "showShare", "Share of the run, and the gap to an equal split.", why.notMini },
        { "Share bar", "showBar", "A bar as long as the share.", why.bar },
        { "Vendor total", "showVendor", "What it all sells for at a vendor.", why.vendor },
    })

    Section(p, "Items")
    get, set = Key("sortItems")
    Choice(p, "Order", { { "Value", "value", "Most valuable first." }, { "Name", "name" } }, get, set, why.notMini)
    Boxes(p, {
        { "Icons", "showIcons", nil, why.icons },
        { "Group by category", "groupByCategory", "Epic BoE, Blue BoE and the rest, each under its heading.",
          why.notMini },
        { "Line up", "alignItems", "The same item on the same line in every column.", why.columns },
    })

    -- Past five players, the others follow the columns on a bench: what
    -- each of them shows there besides their name.
    Section(p, "Bench", "Players past the fifth, under the columns.")
    Boxes(p, {
        { "Picture", "benchPicture", "As Picture above says.", why.columns },
        { "Award", "benchAward", nil, why.columns },
        { "Gold", "benchValue", "Their loot value.", why.columns },
    })

    Section(p, "Bottom line")
    Boxes(p, {
        { "Run total", "showTotals", "The run's total and the equal split.", why.notMini },
        { "Run stats", "showInsights", "Run time, records here, and your average.", why.notMini },
    })
end

----------------------------------------------------------------------
-- Page: Meter
----------------------------------------------------------------------

do
    local p = NewPage("Meter", { "meterRank", "meterShare", "meterAward", "meterOpen", "meterClose" })
    p.preview = "meter"

    Section(p, "Rows", "Each row always has the bar, the name and the total.")
    Boxes(p, {
        { "Rank", "meterRank" },
        { "Share", "meterShare", "Share of the run." },
        { "Award", "meterAward", "Once the run is over.", why.awards },
    })

    Section(p, "Automatic")
    Boxes(p, {
        { "Open on entering", "meterOpen", "As a run starts. Going back in counts." },
        { "Close on leaving", "meterClose", "As you leave the dungeon." },
    })
end

----------------------------------------------------------------------
-- Page: Loot
----------------------------------------------------------------------

do
    local p = NewPage("Loot", { "valueMode", "priceTime", "cats", "countHidden" }, true)

    Section(p, "Price")
    local get, set = Key("valueMode")
    Choice(p, "Value", {
        { "Auction", "market", "Auction price; the vendor price when there is none." },
        { "Vendor", "vendor", "Vendor price only." },
    }, get, set)
    -- Auction prices as recorded when the loot dropped, or as they are today.
    get, set = Key("priceTime")
    Choice(p, "Auction", {
        { "When looted", "then", "Prices as they were when it dropped." },
        { "Today", "now", "Prices as they are now. Statistics keep the recorded ones.", why.today },
    }, get, set, why.auction)
    RowLabel(p, "Source")
    local source = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    source:SetPoint("TOPLEFT", ROW_X, p.y - 5)
    p.y = p.y - ROW_H
    live[#live + 1] = function()
        local name = ns.PriceSourceName()
        source:SetText(name or "No Auctionator or TradeSkillMaster: vendor prices.")
        source:SetAlpha(Opt().valueMode == "vendor" and 0.4 or 1)
    end

    -- The window's own list of categories, in its order.
    Section(p, "Categories", "Unticked ones are hidden from the window.")
    local defs = {}
    for i, cat in ipairs(ns.CATS) do
        defs[i] = {
            cat.name or cat.short,
            function() return Opt().cats[cat.key] ~= false end,
            function(on) Opt().cats[cat.key] = on end,
        }
    end
    Grid(p, defs, 3, 134)
    Boxes(p, { { "Hidden still count", "countHidden", "Hidden categories still count in every total.", why.hidden } })
end

----------------------------------------------------------------------
-- Page: During a run
----------------------------------------------------------------------

do
    local p = NewPage("During a run", { "ticker", "tickerMin", "familiar", "bets" }, true)

    -- The notice's switch, and its amount typed in gold beside it.
    Section(p, "Notices", "On your screen. Only you see them.")
    local b = MakeCheck(p, 0, "Valuable loot", function() return Opt().ticker end, function(on) Opt().ticker = on end,
                        "When anyone in the group loots something worth this much.")
    local x = b:GetWidth() + 8
    local at = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    at:SetPoint("TOPLEFT", x, p.y - 5)
    at:SetText("at least")
    local box = NumberBox(p, x + at:GetStringWidth(), "tickerMin",
                          function() return math.max(1, math.floor((Opt().tickerMin or 0) / 10000 + 0.5)) end,
                          function(gold) Opt().tickerMin = gold * 10000 end, 1, 9999, nil, why.ticker)
    box.tipTitle = "Valuable loot"
    box.tip = "In gold."
    local g = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g:SetPoint("LEFT", box, "RIGHT", 4, 0)
    g:SetText("g")
    live[#live + 1] = function()
        local alpha = why.ticker() and 0.4 or 1
        at:SetAlpha(alpha)
        g:SetAlpha(alpha)
    end
    p.y = p.y - ROW_H
    Boxes(p, { { "Familiar face", "familiar", "Someone you've run with joins your group." } })

    Section(p, "Bets")
    Boxes(p, { { "Bets", "bets", "Call the lucky bastard as each run starts. Calls close at the first roll." } })
end

----------------------------------------------------------------------
-- Page: End of run
----------------------------------------------------------------------

do
    local p = NewPage("End of run", { "popupLeave", "chatSummary", "streak", "showAwards", "race", "ceremonySound",
                                      "ceremonyScreenshot" })

    Section(p, "On leaving", "Leaving a dungeon alive.")
    Boxes(p, {
        { "Open breakdown", "popupLeave", "The breakdown window opens." },
        { "Chat line", "chatSummary", "A one-line result in your chat window. Only you see it." },
        { "Streak recap", "streak", "After back-to-back runs with the same group or dungeon." },
    })

    Section(p, "Awards")
    Boxes(p, {
        { "Awards", "showAwards", "Hand out awards. /tlb awards lists them." },
        { "Race", "race", "The loot falls as coins. The last stack still growing wins.", why.race },
    })
    Boxes(p, {
        { "Sounds", "ceremonySound", "While the awards come up.", why.reveal },
        { "Screenshot", "ceremonyScreenshot", "Once they are all shown.", why.reveal },
    })
    -- The reveal again, for the run on show: what /tlb race does.
    local replay = Button(p, "Replay", 80, function()
        local s = ns.ViewedRun and ns.ViewedRun()
        if s then ns.ShowWindow(true, s) end
    end, "The reveal again, for the run on show. Same as /tlb race.")
    live[#live + 1] = function() replay:SetOn((ns.ViewedRun and ns.ViewedRun()) ~= nil) end
end

----------------------------------------------------------------------
-- Page: Tooltips
----------------------------------------------------------------------

do
    local p = NewPage("Tooltips", { "tipPlayers", "tipItems", "tipCats" }, true)

    Section(p, "Players")
    Boxes(p, { { "Runs together", "tipPlayers", "In a player's tooltip: your runs with them." } })

    -- Under the items' switch, the kinds of item that get the line.
    Section(p, "Items")
    Boxes(p, { { "Seen in runs", "tipItems", "In an item's tooltip: how often it dropped in your runs." } })
    local kinds = {}
    for _, cat in ipairs(ns.CATS) do
        if not cat.coins then -- not an item
            kinds[#kinds + 1] = {
                cat.name or cat.short,
                function() return Opt().tipCats[cat.key] ~= false end,
                function(on) Opt().tipCats[cat.key] = on end,
                nil,
                why.tipKinds,
            }
        end
    end
    Grid(p, kinds, 3, 126, 20)
end

----------------------------------------------------------------------
-- Page: Share
----------------------------------------------------------------------

local MAX_SUMMARY = 25 -- players in one summary: more lines at once and chat holds them back

do
    local p = NewPage("Share", { "summaryLines", "summaryLink", "summaryTime", "summaryTotal", "summaryShare",
                                 "summaryGap", "summaryAward" })

    Section(p, "Chat summary", "What the Share window posts as a summary.")
    RowLabel(p, "Players")
    local box = NumberBox(p, ROW_X - 6, "summaryLines", function() return Opt().summaryLines end,
                          function(n) Opt().summaryLines = n end, 1, MAX_SUMMARY)
    box.tipTitle, box.tip = "Players", "Up to " .. MAX_SUMMARY .. "."
    p.y = p.y - ROW_H - 2

    Section(p, "First line")
    Boxes(p, {
        { "Run link", "summaryLink", "Players with the addon can click it." },
        { "Run time", "summaryTime" },
        { "Group total", "summaryTotal" },
    })

    Section(p, "Player lines")
    Boxes(p, {
        { "Share %", "summaryShare" },
        { "Gap to equal split", "summaryGap" },
        { "Award", "summaryAward", nil, why.awards },
    })

    -- What would be posted for the run on show.
    Section(p, "Preview")
    local preview = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", 4, p.y - 2)
    preview:SetWidth(WIDTH - SIDEBAR_W - 54)
    preview:SetJustifyH("LEFT")
    live[#live + 1] = function()
        local s = ns.ViewedRun and ns.ViewedRun()
        local lines = s and not s.example and ns.SummaryLines(s) or {}
        preview:SetText(#lines > 0 and table.concat(lines, "\n") or "No run of yours to show yet.")
    end
end

----------------------------------------------------------------------
-- Page: Runs
----------------------------------------------------------------------

-- How many runs keeping only `limit` would delete: your own beyond it
-- (pinned ones aside), and those shared with you beyond it.
local function RunsOver(limit)
    local own = 0
    for _, s in ipairs(ns.db.history) do
        if not s.pinned then own = own + 1 end
    end
    return math.max(own - limit, 0) + math.max(#ns.db.shared - limit, 0)
end

local function Refresh()
    if o:IsShown() then
        Sync()
    else
        ns.UpdateMinimapButton()
        ns.Rerender()
    end
end

StaticPopupDialogs["THATLUCKYBASTARD_KEEP_FEWER"] = {
    text = ns.NAME .. "\n\nKeep only %s?\n\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, limit)
        Opt().maxHistory = limit
        ns.TrimHistory()
        Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- The confirmations come up over this window, which is on the same level.
local function Confirm(which, a, b, data)
    local dialog = StaticPopup_Show(which, a, b, data)
    if dialog and dialog.Raise then dialog:Raise() end
end

-- A number that would delete runs asks first, then deletes them at once.
local function KeepRuns(limit)
    local over = RunsOver(limit)
    if over == 0 then
        Opt().maxHistory = limit
    else
        Confirm("THATLUCKYBASTARD_KEEP_FEWER", limit == 1 and "1 run" or (limit .. " runs"),
            over == 1 and "The oldest will be deleted now. Pinned runs stay."
                or ("The %d oldest will be deleted now. Pinned runs stay."):format(over), limit)
    end
end

do
    local p = NewPage("Runs", { "trackRaids", "askNewRun" })

    Section(p, "Record")
    Boxes(p, { { "Raids", "trackRaids", "Raids count as runs too." } })
    local get, set = Key("askNewRun")
    Choice(p, "Same dungeon", {
        { "Ask", true, "Going back in: ask if it's a new run. After a death the run always goes on." },
        { "New run", false, "Going back in: always a new run. After a death the run always goes on." },
    }, get, set)

    Section(p, "Keep", "Pinned runs don't count. Lowering the number asks before deleting.")
    RowLabel(p, "Runs")
    local box = NumberBox(p, ROW_X - 6, "maxHistory", function() return Opt().maxHistory end, KeepRuns, 1, 99999)
    box.tipTitle, box.tip = "Runs to keep", "Your own and those shared with you, each up to this number."
    p.y = p.y - ROW_H - 2
    local count = Note(p)
    live[#live + 1] = function()
        local runs, pinned = #ns.db.history, 0
        for _, s in ipairs(ns.db.history) do
            if s.pinned then pinned = pinned + 1 end
        end
        local text = ("You have %d run%s"):format(runs, runs == 1 and "" or "s")
        if pinned > 0 then text = text .. (" (%d pinned)"):format(pinned) end
        if #ns.db.shared > 0 then text = text .. (" and %d shared with you"):format(#ns.db.shared) end
        count:SetText(text .. ".")
    end
end

ns.OPTION_PAGES = pages -- for the tests: each page's name and keys

----------------------------------------------------------------------
-- Defaults: this page, or every page
----------------------------------------------------------------------

-- Puts these keys of db.options back as on a new install ("theme" is the
-- theme, kept outside the options).
local function ResetKeys(keys)
    local x, d = Opt(), ns.OPTION_DEFAULTS
    for _, key in ipairs(keys) do
        if key == "theme" then
            ns.db.theme = "modern"
        elseif type(d[key]) == "table" then
            x[key] = {}
            for k, v in pairs(d[key]) do x[key][k] = v end
        else
            x[key] = d[key]
        end
    end
end

-- Everything back as on a new install, except the number of runs to keep
-- (a lower one would delete runs) and where the minimap button was put.
-- The other button does the page on show alone.
StaticPopupDialogs["THATLUCKYBASTARD_DEFAULTS"] = {
    text = ns.NAME .. "\n\nPut the options back to their defaults?\n\n|cff909090Runs to keep stays as it is.|r",
    button1 = "Every page",
    button3 = "This page",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        local x = Opt()
        local keep, angle = x.maxHistory, x.minimapAngle
        ns.FillDefaults(x, true)
        x.maxHistory, x.minimapAngle = keep, angle
        ns.db.theme = "modern"
        Refresh()
    end,
    OnAlt = function()
        ResetKeys(pages[currentPage].keys)
        Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local defaultsBtn = ns.MakeButton("Defaults", SIDEBAR_W - 20, function()
    Confirm("THATLUCKYBASTARD_DEFAULTS")
end, sidebar)
defaultsBtn:SetPoint("BOTTOM", 0, 10)
for _, face in ipairs({ defaultsBtn.tpl, defaultsBtn.flat }) do
    Tip(face, "Defaults", "This page or every page. Runs to keep stays as it is.")
end
buttons[#buttons + 1] = defaultsBtn

----------------------------------------------------------------------
-- Theme and refresh
----------------------------------------------------------------------

local function StyleBox(b, accent)
    b.box:ClearAllPoints()
    if flat then
        b.box:SetPoint("LEFT", 5, 0)
        b.box:SetSize(14, 14)
        b.box:SetTexCoord(0, 1, 0, 1)
        b.box:SetColorTexture(1, 1, 1, 0.12)
        b.tick:SetSize(8, 8)
        b.tick:SetTexCoord(0, 1, 0, 1)
        b.tick:SetColorTexture(accent[1], accent[2], accent[3], 1)
    else
        b.box:SetPoint("LEFT", 0, 0)
        b.box:SetSize(24, 24)
        b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        b.box:SetTexCoord(0, 1, 0, 1)
        b.tick:SetSize(24, 24)
        b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b.tick:SetTexCoord(0, 1, 0, 1)
    end
end

-- A choice's buttons, side by side from ROW_X: flat buttons in the flat
-- themes, the game's radio buttons in Classic.
local function StyleChoice(c)
    local x = ROW_X
    for _, b in ipairs(c.buttons) do
        local w
        b.text:ClearAllPoints()
        b.box:ClearAllPoints()
        if flat then
            w = b.text:GetStringWidth() + 20
            b.text:SetPoint("CENTER")
            b.box:Hide()
            b.hl:SetColorTexture(1, 1, 1, 0.06)
        else
            w = b.text:GetStringWidth() + 34
            b.text:SetPoint("LEFT", 24, 0)
            b.box:Show()
            b.box:SetPoint("LEFT", 4, 0)
            b.box:SetSize(16, 16)
            b.box:SetTexture("Interface\\Buttons\\UI-RadioButton")
            b.box:SetTexCoord(0, 0.25, 0, 1)
            b.tick:SetSize(16, 16)
            b.tick:SetTexture("Interface\\Buttons\\UI-RadioButton")
            b.tick:SetTexCoord(0.25, 0.5, 0, 1)
            b.hl:SetColorTexture(1, 1, 1, 0)
        end
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, c.y)
        x = x + w + (flat and 2 or 4)
    end
end

local function ApplyTheme()
    local top
    flat, top = ns.ApplyWindowTheme(skins, title)
    local hue = flat and ns.ThemeAccent() or GOLD
    sidebar:ClearAllPoints()
    sidebar:SetPoint("TOPLEFT", 10, top)
    sidebar:SetPoint("BOTTOMLEFT", 10, 12)
    sidebar:SetWidth(SIDEBAR_W)
    if flat then sidebarBg:SetColorTexture(1, 1, 1, 0.03) else sidebarBg:SetColorTexture(0, 0, 0, 0.25) end
    pageArea:ClearAllPoints()
    pageArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 18, -8)
    pageArea:SetPoint("BOTTOMRIGHT", -18, 12)
    for _, b in ipairs(buttons) do b:SetFlat(flat) end

    for i, n in ipairs(navs) do
        local selected = (i == currentPage)
        n.bg:SetColorTexture(1, 1, 1, selected and 0.10 or 0)
        n.bar:SetColorTexture(hue[1], hue[2], hue[3], 1)
        n.bar:SetShown(selected)
        if selected then
            n.text:SetTextColor(flat and 1 or GOLD[1], flat and 1 or GOLD[2], flat and 1 or GOLD[3])
        else
            n.text:SetTextColor(0.72, 0.72, 0.72)
        end
        pages[i]:SetShown(selected)
        local tone = flat and { 1, 1, 1 } or GOLD
        pages[i].title:SetTextColor(tone[1], tone[2], tone[3])
    end

    for _, s in ipairs(sections) do
        s.text:SetTextColor(hue[1], hue[2], hue[3])
        s.line:SetColorTexture(hue[1], hue[2], hue[3], 0.25)
    end
    local accent = ns.ThemeAccent()
    for _, b in ipairs(controls) do
        if b.box and not b.radio then StyleBox(b, accent) end
    end
    for _, c in ipairs(choices) do StyleChoice(c) end

    for _, s in ipairs({ scaleSlider, hueSliders[1], hueSliders[2], hueSliders[3] }) do
        if flat then
            s:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
            local thumb = s:GetThumbTexture()
            thumb:SetSize(8, 16)
            thumb:SetVertexColor(hue[1], hue[2], hue[3])
            s.track:SetColorTexture(1, 1, 1, 0.12)
        else
            s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            local thumb = s:GetThumbTexture()
            thumb:SetSize(32, 32)
            thumb:SetVertexColor(1, 1, 1)
            s.track:SetColorTexture(1, 1, 1, 0.20)
        end
    end
end
function Sync()
    ns.ApplyAccent() -- the accent, or the theme it belongs to, may be what was just chosen
    title:SetText(ns.Title("Options"))
    ApplyTheme()
    for _, b in ipairs(controls) do
        local off = b.why and b.why()
        b:SetEnabled(not off)
        b:SetAlpha(off and 0.4 or 1)
        b:Paint()
    end
    for _, fn in ipairs(live) do fn() end
    -- The accent's own three values count while Custom is the choice.
    local custom = Opt().accentCustom
    local own = ns.ThemeName() == "modern" and Opt().accent == "custom"
    for i, s in ipairs(hueSliders) do
        s:SetValue(math.floor((custom[i] or 0) * 255 + 0.5))
        s:EnableMouse(own)
        s:SetAlpha(own and 1 or 0.4)
        s.label:SetAlpha(own and 1 or 0.4)
    end
    local scale = Opt().scale or 1
    scaleSlider:SetValue(scale)
    scaleValue:SetText(("%d%%"):format(scale * 100 + 0.5))
    ns.UpdateMinimapButton()
    ns.Rerender()
end

-- The Meter page shows the meter beside the options, as the breakdown
-- is shown beside them all; the meter shuts again as the page is left if
-- it was shut before.
local meterOpened = false
local function MeterPreview(on)
    local meter = ThatLuckyBastardMeterFrame
    if not meter then return end
    if on and not meter:IsShown() then
        meter:Show()
        meterOpened = true
    elseif not on and meterOpened then
        meterOpened = false
        meter:Hide()
    end
end

function ShowPage(index)
    currentPage = index
    MeterPreview(o:IsShown() and pages[index].preview == "meter")
    Sync()
end

o:SetScript("OnShow", function() ShowPage(currentPage) end)
o:SetScript("OnHide", function() MeterPreview(false) end)

-- Called when the theme changes from outside the panel (/tlb theme ...).
function ns.SyncOptions()
    if o:IsShown() then Sync() end
end

function ns.ToggleOptions()
    if o:IsShown() then
        o:Hide()
    else
        -- Open the main window too, so changes can be seen as they are made.
        if not ThatLuckyBastardFrame:IsShown() then ns.ShowWindow() end
        o:Show()
    end
end
