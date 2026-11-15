local _, ns = ...

-- Options panel: a list of pages on the left, the selected page on the
-- right. It uses the same three skins as the main window and restyles its
-- own controls to match.

local ACCENT = { 0.25, 0.78, 0.72 }
local GOLD = { 1.00, 0.82, 0.00 }
local WIDTH, HEIGHT = 590, 460
local SIDEBAR_W = 140
local ROW_H = 22
local COL2_X = 200 -- x of the second column in two-column groups
local PAGE_W = WIDTH - SIDEBAR_W - 46 -- width of the page area

local o = CreateFrame("Frame", "FairShareOptionsFrame", UIParent)
o:SetSize(WIDTH, HEIGHT)
o:SetPoint("CENTER")
o:SetFrameStrata("DIALOG")
o:SetMovable(true)
o:EnableMouse(true)
o:SetClampedToScreen(true)
o:RegisterForDrag("LeftButton")
o:SetScript("OnDragStart", o.StartMoving)
o:SetScript("OnDragStop", o.StopMovingOrSizing)
o:Hide()
tinsert(UISpecialFrames, "FairShareOptionsFrame")

local skins = ns.BuildSkins(o, function() o:Hide() end)

local ui = CreateFrame("Frame", nil, o)
ui:SetAllPoints()
ui:SetFrameLevel(o:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetText("FairShare options")

local sidebar = CreateFrame("Frame", nil, ui)
local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
sidebarBg:SetAllPoints()
local pageArea = CreateFrame("Frame", nil, ui)

local pages, navs, sections, checks = {}, {}, {}, {}
local currentPage = 1
local flat = false
local scaleSlider, scaleLabel
local Sync

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

local function NewPage(name, blurb)
    local index = #pages + 1
    local p = CreateFrame("Frame", nil, pageArea)
    p:SetAllPoints()
    p:Hide()
    pages[index] = p

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT")
    p.title:SetText(name)
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 0, -20)
    sub:SetWidth(PAGE_W)
    sub:SetJustifyH("LEFT")
    sub:SetText(blurb)
    p.y = -40

    local n = CreateFrame("Button", nil, sidebar)
    n:SetSize(SIDEBAR_W, 26)
    n:SetPoint("TOPLEFT", 0, -6 - (index - 1) * 28)
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
    n:SetScript("OnClick", function()
        currentPage = index
        Sync()
    end)
    navs[index] = n
    return p
end

-- A titled group of controls with a rule under the title.
local function Section(p, text)
    p.y = p.y - 10
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 0, p.y)
    fs:SetText(text)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, p.y - 16)
    line:SetPoint("TOPRIGHT", 0, p.y - 16)
    line:SetHeight(1)
    sections[#sections + 1] = { text = fs, line = line }
    p.y = p.y - 22
end

local function Hint(p, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 4, p.y - 2)
    fs:SetWidth(PAGE_W - 8)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    p.y = p.y - 28
end

-- A checkbox (or radio button) drawn by the panel itself so it can be
-- restyled per theme. Does not move the page cursor.
local function MakeCheck(p, x, label, get, set, radio)
    local b = CreateFrame("Button", nil, p)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", x, p.y)
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetPoint("CENTER", b.box)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 26, 0)
    b.text:SetText(label)
    b:SetWidth(30 + b.text:GetStringWidth())
    b.get, b.radio = get, radio
    b:SetScript("OnClick", function()
        if radio then set() else set(not get()) end
        Sync()
    end)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.9, 0.9, 0.9) end)
    b.text:SetTextColor(0.9, 0.9, 0.9)
    checks[#checks + 1] = b
    return b
end

-- Lays controls out in one or two columns and advances the page cursor.
-- defs = { { label, get, set }, ... }
local function Group(p, defs, columns, radio)
    columns = columns or 1
    for i, def in ipairs(defs) do
        local col = (i - 1) % columns
        MakeCheck(p, col * COL2_X, def[1], def[2], def[3], radio)
        if col == columns - 1 or i == #defs then p.y = p.y - ROW_H end
    end
end

-- On/off switches stored in db.options. keys = { { "Label", "key" }, ... }
local function Toggles(p, keys, columns)
    local defs = {}
    for i, k in ipairs(keys) do
        defs[i] = {
            k[1],
            function() return ns.db.options[k[2]] end,
            function(on) ns.db.options[k[2]] = on end,
        }
    end
    Group(p, defs, columns)
end

-- Pick-one group stored in db.options[key]. choices = { { "Label", value }, ... }
local function Choices(p, key, choices, columns)
    local defs = {}
    for i, c in ipairs(choices) do
        defs[i] = {
            c[1],
            function() return ns.db.options[key] == c[2] end,
            function() ns.db.options[key] = c[2] end,
        }
    end
    Group(p, defs, columns, true)
end

----------------------------------------------------------------------
-- Page 1: Appearance
----------------------------------------------------------------------

do
    local p = NewPage("Appearance", "How the window looks.")

    Section(p, "Theme")
    local defs = {}
    for i, t in ipairs({ { "Classic", "classic" }, { "Modern", "modern" } }) do
        defs[i] = {
            t[1],
            function() return (ns.db.theme or "classic") == t[2] end,
            function() ns.db.theme = t[2] end,
        }
    end
    Group(p, defs, 1, true)

    Section(p, "Player picture")
    Choices(p, "portrait", {
        { "3D model", "3d" }, { "2D portrait", "2d" }, { "Class icon", "class" }, { "None", "none" },
    }, 2)
    Hint(p, "Models and portraits need the player in your group right now; otherwise the class icon is shown.")

    Section(p, "Size")
    scaleLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 4, p.y - 2)
    local s = CreateFrame("Slider", nil, p)
    s:SetOrientation("HORIZONTAL")
    s:EnableMouse(true)
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", 90, p.y)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(0.6, 1.6)
    s:SetValueStep(0.05)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetScript("OnValueChanged", function(_, value)
        if not ns.db then return end
        value = math.floor(value * 20 + 0.5) / 20
        scaleLabel:SetText(("Scale: %d%%"):format(value * 100 + 0.5))
        if ns.db.options.scale ~= value then
            ns.db.options.scale = value
            ns.Rerender()
        end
    end)
    scaleSlider = s
    p.y = p.y - 26
    Toggles(p, { { "Compact rows", "compact" } })
end

----------------------------------------------------------------------
-- Page 2: Layout
----------------------------------------------------------------------

do
    local p = NewPage("Layout", "How a run is laid out and which details appear.")

    Section(p, "Arrangement")
    Toggles(p, {
        { "One column per player for groups of 5 or fewer", "useColumns" },
        { "Group items by category", "groupByCategory" },
        { "Align the same item across players, to compare line by line", "alignItems" },
    })

    Section(p, "Details to show")
    Toggles(p, {
        { "Vendor value", "showVendor" },
        { "Item icons", "showIcons" },
        { "Share and over/under equal split", "showShare" },
        { "Share bar (Modern theme, column view)", "showBar" },
        { "Total and equal split line", "showTotals" },
    })
end

----------------------------------------------------------------------
-- Page 3: Items and values
----------------------------------------------------------------------

do
    local p = NewPage("Items and values", "What counts, and how it is priced.")

    Section(p, "Categories")
    local defs = {}
    for i, cat in ipairs({
        { "Epic BoE", "epic" }, { "Blue BoE", "rare" }, { "Green BoE", "uncommon" },
        { "Bind on Pickup", "bop" }, { "Quest items", "quest" }, { "Profession materials", "prof" },
        { "Other", "other" }, { "Junk", "junk" },
    }) do
        defs[i] = {
            cat[1],
            function() return ns.db.options.cats[cat[2]] ~= false end,
            function(on) ns.db.options.cats[cat[2]] = on end,
        }
    end
    Group(p, defs, 2)
    Hint(p, "An unticked category is hidden and left out of every total and share.")
    Toggles(p, { { "Hide unticked categories but still count them", "countHidden" } })

    Section(p, "Price")
    Choices(p, "valueMode", {
        { "Auction price, vendor if unknown", "market" }, { "Vendor price only", "vendor" },
    })
    Toggles(p, { { "Show silver", "showSilver" }, { "Show copper", "showCopper" } }, 2)

    Section(p, "Order items by")
    Choices(p, "sortItems", { { "Value", "value" }, { "Name", "name" } }, 2)
end

----------------------------------------------------------------------
-- Page 4: Players
----------------------------------------------------------------------

do
    local p = NewPage("Players", "The order players appear in.")

    Section(p, "Order players by")
    Choices(p, "sortPlayers", {
        { "Role: tank, healer, then damage", "role" },
        { "Podium: top looter in the middle, columns stepped by rank", "podium" },
        { "Loot value, highest first", "value" },
        { "Name", "name" },
    })
    p.y = p.y - 6
    Toggles(p, { { "Always show me first (not in podium order)", "selfFirst" } })

    Section(p, "Names")
    Choices(p, "nameStyle", {
        { "Follow the game's \"My Secondary Name\" setting", "game" },
        { "First and second name", "full" },
        { "First name only", "first" },
    })
end

----------------------------------------------------------------------
-- Page 5: Behaviour
----------------------------------------------------------------------

do
    local p = NewPage("Behaviour", "When FairShare tracks and when it speaks up.")

    Section(p, "Open the window automatically")
    Toggles(p, {
        { "When I leave the instance alive", "popupLeave" },
    })

    Section(p, "Tracking")
    Toggles(p, {
        { "Track raids as well as dungeons", "trackRaids" },
        { "Ask if it is a new run when I come back into the same dungeon", "askNewRun" },
        { "Print a one-line summary in chat when a run ends", "chatSummary" },
    })

    Section(p, "Runs to keep")
    Choices(p, "maxHistory", { { "10", 10 }, { "30", 30 }, { "100", 100 }, { "300", 300 } }, 2)

    Section(p, "Minimap")
    Toggles(p, { { "Show the minimap button", "showMinimap" } })
end

----------------------------------------------------------------------
-- Page 6: Extras
----------------------------------------------------------------------

do
    local p = NewPage("Extras", "The fun parts. Everything here stays on your screen only.")

    Section(p, "End of run")
    Toggles(p, {
        { "Open the podium scene when a run ends", "podiumOnLeave" },
        { "Awards (Ninja, Luckiest, Jackpot and the rest)", "showAwards" },
        { "Play sounds while the awards are revealed", "ceremonySound" },
        { "Take a screenshot once all awards are shown", "ceremonyScreenshot" },
        { "Run time, dungeon records and comparison with my average", "showInsights" },
    })

    Section(p, "During the run")
    Toggles(p, {
        { "Loot bingo: deal a card each run and announce my lines", "bingo" },
        { "Show a notice when someone I have run with joins my group", "familiar" },
        { "Recap when I chain runs with the same group or dungeon", "streak" },
        { "Tooltips: a line about players I have run with", "tipPlayers" },
        { "Tooltips: a line about items seen in my runs", "tipItems" },
        { "Show a notice when someone loots something valuable", "ticker" },
    })
    Hint(p, "A notice appears for a pickup worth at least:")
    p.y = p.y + 10
    Choices(p, "tickerMin", {
        { "1 gold", 10000 }, { "5 gold", 50000 }, { "25 gold", 250000 }, { "100 gold", 1000000 },
    }, 2)
end

----------------------------------------------------------------------
-- Theme and refresh
----------------------------------------------------------------------

local function StyleCheck(b)
    b.box:ClearAllPoints()
    if flat then
        b.box:SetPoint("LEFT", 5, 0)
        b.box:SetSize(14, 14)
        b.box:SetTexCoord(0, 1, 0, 1)
        b.box:SetColorTexture(1, 1, 1, 0.12)
        b.tick:SetSize(8, 8)
        b.tick:SetTexCoord(0, 1, 0, 1)
        b.tick:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    elseif b.radio then
        b.box:SetPoint("LEFT", 4, 0)
        b.box:SetSize(16, 16)
        b.box:SetTexture("Interface\\Buttons\\UI-RadioButton")
        b.box:SetTexCoord(0, 0.25, 0, 1)
        b.tick:SetSize(16, 16)
        b.tick:SetTexture("Interface\\Buttons\\UI-RadioButton")
        b.tick:SetTexCoord(0.25, 0.5, 0, 1)
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

local function ApplyTheme()
    local name = ns.db.theme
    if name ~= "modern" then name = "classic" end
    flat = (name == "modern")
    local hue = flat and ACCENT or GOLD

    local active = skins[name] or skins.classic
    for _, skin in pairs(skins) do skin:SetShown(skin == active) end

    title:ClearAllPoints()
    if flat then
        title:SetFontObject("GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -10)
    else
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOP", 0, -5)
    end

    local top = flat and -46 or -32
    sidebar:ClearAllPoints()
    sidebar:SetPoint("TOPLEFT", 10, top)
    sidebar:SetPoint("BOTTOMLEFT", 10, 12)
    sidebar:SetWidth(SIDEBAR_W)
    if flat then sidebarBg:SetColorTexture(1, 1, 1, 0.03) else sidebarBg:SetColorTexture(0, 0, 0, 0.25) end
    pageArea:ClearAllPoints()
    pageArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 18, -8)
    pageArea:SetPoint("BOTTOMRIGHT", -18, 12)

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
        if flat then pages[i].title:SetTextColor(1, 1, 1) else pages[i].title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end

    for _, s in ipairs(sections) do
        s.text:SetTextColor(hue[1], hue[2], hue[3])
        s.line:SetColorTexture(hue[1], hue[2], hue[3], 0.25)
    end
    for _, b in ipairs(checks) do StyleCheck(b) end

    if flat then
        scaleSlider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
        local thumb = scaleSlider:GetThumbTexture()
        thumb:SetSize(8, 16)
        thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
        scaleSlider.track:SetColorTexture(1, 1, 1, 0.12)
    else
        scaleSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local thumb = scaleSlider:GetThumbTexture()
        thumb:SetSize(32, 32)
        thumb:SetVertexColor(1, 1, 1)
        scaleSlider.track:SetColorTexture(1, 1, 1, 0.20)
    end
end

function Sync()
    ApplyTheme()
    for _, b in ipairs(checks) do
        b.tick:SetShown(b.get() and true or false)
    end
    local scale = ns.db.options.scale or 1
    scaleSlider:SetValue(scale)
    scaleLabel:SetText(("Scale: %d%%"):format(scale * 100 + 0.5))
    ns.UpdateMinimapButton()
    ns.TrimHistory()
    ns.Rerender()
end

o:SetScript("OnShow", Sync)

-- Called when the theme changes from outside the panel (/fs theme ...).
function ns.SyncOptions()
    if o:IsShown() then Sync() end
end

function ns.ToggleOptions()
    if o:IsShown() then
        o:Hide()
    else
        -- Open the main window too, so changes can be seen as they are made.
        if not FairShareFrame:IsShown() then ns.ShowWindow() end
        o:Show()
    end
end
