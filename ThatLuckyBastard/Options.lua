local _, ns = ...

-- Options panel: a list of pages on the left, the selected page on the
-- right. It uses the same skins as the other windows and restyles its own
-- controls to match. An option that does nothing as things stand (the
-- share bar in the Classic theme, say) is greyed out rather than hidden,
-- so that nothing moves as you click.

local GOLD = { 1.00, 0.82, 0.00 }
local WIDTH, HEIGHT = 590, 630
local SIDEBAR_W = 140
local ROW_H = 22
local COL_W = 200 -- width of a column in two-column groups
local PAGE_W = WIDTH - SIDEBAR_W - 46 -- width of the page area

-- The last argument keeps this window at its size whatever the Size
-- option says, so that the slider does not move under the mouse.
local o, ui, title, skins = ns.MakeWindow("ThatLuckyBastardOptionsFrame", WIDTH, HEIGHT, "DIALOG", true, true)
o:SetPoint("CENTER")
title:SetText(ns.Title("Options"))

local sidebar = CreateFrame("Frame", nil, ui)
local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
sidebarBg:SetAllPoints()
local pageArea = CreateFrame("Frame", nil, ui)

local pages, navs, sections, checks = {}, {}, {}, {}
local live = {} -- texts that follow the saved data, rewritten on every sync
local currentPage = 1
local flat = false
local scaleSlider, scaleLabel
local hueSliders, swatch = {}, nil -- the accent's three values, and the colour they make
local Sync

local function Opt() return ns.db.options end

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

-- Grey text of up to two lines under a group. Returns it, for the texts
-- that change.
local function Hint(p, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 4, p.y - 2)
    fs:SetWidth(PAGE_W - 8)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    p.y = p.y - 28
    return fs
end

-- A line of text that introduces the controls under it.
local function Label(p, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, p.y - 4)
    fs:SetText(text)
    p.y = p.y - 18
end

-- Text at the start of a row whose controls come after it, on the same line.
local function RowLabel(p, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, p.y - 5)
    fs:SetText(text)
end

-- A checkbox (or radio button) drawn by the panel itself so it can be
-- restyled per theme. `enabled`, if given, says whether it does anything
-- as things stand; it is greyed out when not. Does not move the page cursor.
local function MakeCheck(p, x, label, get, set, radio, enabled)
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
    b.get, b.radio, b.enabled = get, radio, enabled
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

-- Lays controls out in columns and advances the page cursor.
-- defs = { { label, get, set, enabled }, ... }; columns of `colW` from `x0`.
local function Group(p, defs, columns, radio, colW, x0)
    columns, colW, x0 = columns or 1, colW or COL_W, x0 or 0
    for i, def in ipairs(defs) do
        local col = (i - 1) % columns
        MakeCheck(p, x0 + col * colW, def[1], def[2], def[3], radio, def[4])
        if col == columns - 1 or i == #defs then p.y = p.y - ROW_H end
    end
end

-- On/off switches stored in db.options. keys = { { "Label", "key", enabled }, ... }
local function Toggles(p, keys, columns)
    local defs = {}
    for i, k in ipairs(keys) do
        defs[i] = {
            k[1],
            function() return Opt()[k[2]] end,
            function(on) Opt()[k[2]] = on end,
            k[3],
        }
    end
    Group(p, defs, columns)
end

-- Pick-one group stored in db.options[key]. choices = { { "Label", value }, ... }
local function Choices(p, key, choices, columns, colW, x0)
    local defs = {}
    for i, c in ipairs(choices) do
        defs[i] = {
            c[1],
            function() return Opt()[key] == c[2] end,
            function() Opt()[key] = c[2] end,
        }
    end
    Group(p, defs, columns, true, colW, x0)
end

----------------------------------------------------------------------
-- Page 1: Window
----------------------------------------------------------------------

do
    local p = NewPage("Window", "How the breakdown looks.")

    Section(p, "Theme")
    local defs = {}
    for i, t in ipairs({ { "Modern", "modern" }, { "Classic", "classic" }, { "Receipt", "receipt" } }) do
        defs[i] = {
            t[1],
            function() return (ns.db.theme or "modern") == t[2] end,
            function() ns.db.theme = t[2] end,
        }
    end
    -- Beside the themes, a mode that goes with any of them: a small
    -- window with a card per player (picture, name, award, total).
    local function Columns() return Opt().useColumns end
    local function Full() return not (Opt().useColumns and Opt().mini) end
    MakeCheck(p, 300, "Mini", function() return Opt().mini end, function(on) Opt().mini = on end, false, Columns)
    Group(p, defs, 3, true, 100)

    -- A slider drawn by the panel, restyled per theme like its checkboxes.
    local function Slider(width, x, y)
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

    -- The Modern theme's accent colour: a few to pick from, the player's
    -- class colour, or their own, as three values from 0 to 255. The other
    -- themes have their colours, so it is greyed out in them.
    Section(p, "Color")
    local function Modern() return (ns.db.theme or "modern") == "modern" end
    local hues = {}
    for i, hue in ipairs({ { "Teal", "teal" }, { "Class", "class" }, { "Amber", "amber" }, { "Light", "light" },
                           { "Dark", "dark" } }) do
        hues[i] = { hue[1], function() return Opt().accent == hue[2] end, function() Opt().accent = hue[2] end, Modern }
    end
    Group(p, hues, 5, true, 70)
    MakeCheck(p, 0, "Custom", function() return Opt().accent == "custom" end, function() Opt().accent = "custom" end,
              true, Modern)
    for i, letter in ipairs({ "R", "G", "B" }) do
        local x = 80 + (i - 1) * 98
        local s = Slider(70, x + 14, p.y - 3)
        s.channel = i
        s.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.label:SetPoint("TOPLEFT", x, p.y - 5)
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
    swatch = p:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(16, 16)
    swatch:SetPoint("TOPLEFT", 80 + 3 * 98, p.y - 3)
    p.y = p.y - 26

    Section(p, "Size")
    scaleLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 4, p.y - 2)
    local s = Slider(220, 90, p.y)
    s:SetMinMaxValues(0.6, 1.6)
    s:SetValueStep(0.05)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetScript("OnValueChanged", function(_, value)
        if not ns.db then return end
        value = math.floor(value * 20 + 0.5) / 20
        scaleLabel:SetText(("Scale: %d%%"):format(value * 100 + 0.5))
        if Opt().scale ~= value then
            Opt().scale = value
            ns.Rerender()
        end
    end)
    scaleSlider = s
    p.y = p.y - 26

    Section(p, "Layout")
    Choices(p, "useColumns", { { "One column per player, up to 5", true }, { "Always a list", false } }, 2)
    -- What is about the loot under the players does nothing in mini mode.
    Toggles(p, {
        { "Group items by category", "groupByCategory", Full },
        { "Line up the same item across columns", "alignItems", function() return Opt().useColumns and Full() end },
    })
    RowLabel(p, "Order items by")
    Choices(p, "sortItems", { { "Value", "value" }, { "Name", "name" } }, 2, 90, 110)
    -- Past five players, the others follow the columns on a bench: what
    -- each of them shows there besides their name.
    RowLabel(p, "On the bench")
    local function Bench(label, key)
        return { label, function() return Opt()[key] end, function(on) Opt()[key] = on end, Columns }
    end
    Group(p, { Bench("Picture", "benchPicture"), Bench("Award", "benchAward"), Bench("Gold", "benchValue") },
          3, false, 100, 110)

    Section(p, "Show")
    Toggles(p, {
        { "Item icons", "showIcons", function() return ns.db.theme ~= "receipt" and Full() end }, -- a receipt prints none
        { "Each share, and its gap to an equal split", "showShare", Full },
        { "Share bar", "showBar", function() return ns.db.theme ~= "classic" and Full() end },
        { "Run total and equal split", "showTotals", Full },
        { "Run time, records and averages", "showInsights", Full },
    })

    -- Two saved switches, offered as the three ways they can combine.
    Section(p, "Amounts")
    local function Amounts(silver, copper)
        return function() return Opt().showSilver == silver and (not silver or Opt().showCopper == copper) end,
            function() Opt().showSilver, Opt().showCopper = silver, copper end
    end
    Group(p, {
        { "12g 34s 56c", Amounts(true, true) },
        { "12g 34s", Amounts(true, false) },
        { "12g", Amounts(false, false) },
    }, 3, true, 130)
end

----------------------------------------------------------------------
-- Page 2: Players
----------------------------------------------------------------------

do
    local p = NewPage("Players", "How each player is shown.")

    Section(p, "Picture")
    Choices(p, "portrait", {
        { "2D portrait", "2d" }, { "3D model", "3d" }, { "Class icon", "class" }, { "None", "none" },
    }, 2)
    Hint(p, "Players out of sight or gone from the group show their class icon. "
        .. "3D models show in the column view only.")

    Section(p, "Names")
    Choices(p, "nameStyle", {
        { "As the game shows them", "game" },
        { "Full name", "full" },
        { "First name only", "first" },
    })

    Section(p, "Order")
    Choices(p, "sortPlayers", {
        { "Podium (top looter in the middle)", "podium" },
        { "Loot value", "value" },
        { "Role (tank, healer, damage)", "role" },
        { "Name", "name" },
    })
    p.y = p.y - 6
    Toggles(p, { { "Put me first", "selfFirst", function() return Opt().sortPlayers ~= "podium" end } })
end

----------------------------------------------------------------------
-- Page 3: Loot
----------------------------------------------------------------------

do
    local p = NewPage("Loot", "What counts, and at what price.")

    Section(p, "Price")
    Choices(p, "valueMode", {
        { "Auction price, vendor when there is none", "market" }, { "Vendor price only", "vendor" },
    })
    -- Auction prices as recorded when the loot dropped, or as they are today.
    local function Auction() return Opt().valueMode ~= "vendor" end
    Group(p, {
        { "Historical auction prices", function() return Opt().priceTime ~= "now" end,
          function() Opt().priceTime = "then" end, Auction },
        { "Current auction prices", function() return Opt().priceTime == "now" end,
          function() Opt().priceTime = "now" end, Auction },
    }, 2, true)
    Toggles(p, { { "Vendor totals too", "showVendor", function()
        return Opt().valueMode ~= "vendor" and not (Opt().useColumns and Opt().mini) -- mini mode shows one total
    end } })
    local source = Hint(p, "")
    live[#live + 1] = function()
        local name = ns.PriceSourceName()
        if Opt().valueMode == "vendor" then
            source:SetText("")
        elseif name then
            source:SetText(("Auction prices from %s. Right-click an item in the window to switch its price.")
                :format(name))
        else
            source:SetText("No Auctionator or TradeSkillMaster: vendor prices are used.")
        end
    end

    -- The window's own list of categories, in its order.
    Section(p, "Categories shown")
    local defs = {}
    for i, cat in ipairs(ns.CATS) do
        defs[i] = {
            cat.name or cat.label,
            function() return Opt().cats[cat.key] ~= false end,
            function(on) Opt().cats[cat.key] = on end,
        }
    end
    Group(p, defs, 2)
    Hint(p, "Unticked ones are hidden from the window.")
    local function AnyHidden()
        for _, on in pairs(Opt().cats) do
            if on == false then return true end
        end
        return false
    end
    Toggles(p, { { "Hidden ones still count in totals", "countHidden", AnyHidden } })
end

----------------------------------------------------------------------
-- Page 4: End of run
----------------------------------------------------------------------

do
    local p = NewPage("End of run", "When you leave a dungeon alive.")

    Section(p, "Open")
    Toggles(p, { { "The breakdown", "popupLeave" } })

    Section(p, "Awards")
    Toggles(p, { { "Hand out awards (Ninja, Jackpot and more)", "showAwards" } })
    Hint(p, "/tlb awards lists them all.")

    -- As a run is left, its columns race for their places: that takes
    -- the columns, in podium order. Without the race, the awards come up
    -- one by one.
    Section(p, "The reveal")
    local function CanRace() return Opt().useColumns and not Opt().mini and Opt().sortPlayers == "podium" end
    local function Reveals() return (Opt().race and CanRace()) or Opt().showAwards or false end
    Toggles(p, {
        { "Race", "race", CanRace },
        { "Sounds", "ceremonySound", Reveals },
        { "Screenshot at the end", "ceremonyScreenshot", Reveals },
    })
    Hint(p, "Race: a bar grows for each player and stops at their total. The last one growing wins. In podium order.")

    Section(p, "Also")
    Toggles(p, {
        { "Streak recap after back-to-back runs", "streak" },
        { "A line in my chat window (only I see it)", "chatSummary" },
    })
end

----------------------------------------------------------------------
-- Page 5: While you play
----------------------------------------------------------------------

do
    local p = NewPage("While you play", "Only you see these.")

    -- The notice's switch and its amount, offered as one choice.
    Section(p, "Notices")
    Label(p, "Valuable loot, worth at least:")
    local function Worth(copper)
        return function() return Opt().ticker and Opt().tickerMin == copper end,
            function() Opt().ticker, Opt().tickerMin = true, copper end
    end
    Group(p, {
        { "1g", Worth(10000) }, { "5g", Worth(50000) }, { "25g", Worth(250000) }, { "100g", Worth(1000000) },
        { "Off", function() return not Opt().ticker end, function() Opt().ticker = false end },
    }, 5, true, 70)
    Toggles(p, { { "Someone I've run with joins my group", "familiar" } })

    Section(p, "Tooltips")
    Toggles(p, {
        { "Players: our runs together", "tipPlayers" },
        { "Items: seen in my runs", "tipItems" },
    })
    -- Under the items' switch, the kinds of item that get the line.
    local function ItemLine() return Opt().tipItems end
    local kinds = {}
    for i, cat in ipairs(ns.CATS) do
        kinds[i] = {
            cat.name or cat.label,
            function() return Opt().tipCats[cat.key] ~= false end,
            function(on) Opt().tipCats[cat.key] = on end,
            ItemLine,
        }
    end
    Group(p, kinds, 2, false, 180, 22)

    Section(p, "Bingo")
    Toggles(p, { { "Loot bingo", "bingo" } })
    Hint(p, "A private card each run. Pick a line on it: it wins if it fills.")
end

----------------------------------------------------------------------
-- Page 6: Share
----------------------------------------------------------------------

local MAX_SUMMARY = 25 -- players in one summary: more lines at once and chat holds them back

do
    local p = NewPage("Share", "The summary posted in chat.")

    -- How many players: a small box to type the number in.
    Section(p, "Summary")
    RowLabel(p, "Players")
    local box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    box:SetSize(30, 20)
    box:SetPoint("TOPLEFT", 70, p.y - 1)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Opt().summaryLines))
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText())
        if n then Opt().summaryLines = math.max(1, math.min(math.floor(n), MAX_SUMMARY)) end
        self:SetText(tostring(Opt().summaryLines))
        Sync()
    end)
    live[#live + 1] = function()
        if not box:HasFocus() then box:SetText(tostring(Opt().summaryLines)) end
    end
    p.y = p.y - ROW_H - 2

    Section(p, "First line")
    Toggles(p, {
        { "Run link", "summaryLink" },
        { "Run time", "summaryTime" },
        { "Group total", "summaryTotal" },
    })

    Section(p, "Player lines")
    Toggles(p, {
        { "Share %", "summaryShare" },
        { "Gap to equal split", "summaryGap" },
        { "Award", "summaryAward", function() return Opt().showAwards end },
    })

    -- What would be posted for the run on show.
    Section(p, "Preview")
    local preview = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", 4, p.y - 2)
    preview:SetWidth(PAGE_W - 8)
    preview:SetJustifyH("LEFT")
    live[#live + 1] = function()
        local s = ns.ViewedRun and ns.ViewedRun()
        local lines = s and not s.example and ns.SummaryLines(s) or {}
        preview:SetText(#lines > 0 and table.concat(lines, "\n") or "No run of yours to show yet.")
    end
end

----------------------------------------------------------------------
-- Page 7: General
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
    text = ns.NAME .. "\n\nKeep only %s runs?\n\n%s",
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
        Confirm("THATLUCKYBASTARD_KEEP_FEWER", tostring(limit),
            ("The %d oldest will be deleted now. Pinned runs stay."):format(over), limit)
    end
end

do
    local p = NewPage("General", "What is recorded and kept.")

    Section(p, "Tracking")
    Toggles(p, { { "Track raids too", "trackRaids" } })

    Section(p, "Back in the same dungeon")
    Choices(p, "askNewRun", { { "Ask if it's a new run", true }, { "Always a new run", false } }, 2)
    Hint(p, "After a death, the run always goes on.")

    Section(p, "Runs to keep")
    local defs = {}
    for i, c in ipairs({ { "10", 10 }, { "30", 30 }, { "100", 100 }, { "300", 300 }, { "Unlimited", 99999 } }) do
        defs[i] = {
            c[1],
            function() return Opt().maxHistory == c[2] end,
            function() KeepRuns(c[2]) end,
        }
    end
    Group(p, defs, 5, true, 75)
    local count = Hint(p, "")
    live[#live + 1] = function()
        local runs, pinned = #ns.db.history, 0
        for _, s in ipairs(ns.db.history) do
            if s.pinned then pinned = pinned + 1 end
        end
        local text = ("You have %d run%s"):format(runs, runs == 1 and "" or "s")
        if pinned > 0 then text = text .. (" (%d pinned)"):format(pinned) end
        if #ns.db.shared > 0 then text = text .. (" and %d shared with you"):format(#ns.db.shared) end
        count:SetText(text .. ".\nAbout 25 to 150 KB per run. Pinned runs don't count.")
    end

    Section(p, "Minimap")
    Toggles(p, { { "Minimap button", "showMinimap" } })
end

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------

-- Everything back as on a new install, except the number of runs to keep
-- (a lower one would delete runs) and where the minimap button was put.
StaticPopupDialogs["THATLUCKYBASTARD_DEFAULTS"] = {
    text = ns.NAME .. "\n\nPut every option back to its default?\n\n|cff909090Runs to keep stays as it is.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local x = Opt()
        local keep, angle = x.maxHistory, x.minimapAngle
        ns.FillDefaults(x, true)
        x.maxHistory, x.minimapAngle = keep, angle
        ns.db.theme = "modern"
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
        local accent = ns.ThemeAccent()
        b.tick:SetColorTexture(accent[1], accent[2], accent[3], 1)
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
    defaultsBtn:SetFlat(flat)

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
    for _, b in ipairs(checks) do StyleCheck(b) end

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
    for _, b in ipairs(checks) do
        local on = true
        if b.enabled then on = b.enabled() and true or false end
        b:SetEnabled(on)
        b:SetAlpha(on and 1 or 0.4)
        b.tick:SetShown(b.get() and true or false)
    end
    for _, fn in ipairs(live) do fn() end
    -- The accent's own three values count while Custom is the choice.
    local custom = Opt().accentCustom
    local own = (ns.db.theme or "modern") == "modern" and Opt().accent == "custom"
    for i, s in ipairs(hueSliders) do
        s:SetValue(math.floor((custom[i] or 0) * 255 + 0.5))
        s:EnableMouse(own)
        s:SetAlpha(own and 1 or 0.4)
        s.label:SetAlpha(own and 1 or 0.4)
    end
    swatch:SetColorTexture(custom[1] or 0, custom[2] or 0, custom[3] or 0, 1)
    swatch:SetAlpha(own and 1 or 0.4)
    local scale = Opt().scale or 1
    scaleSlider:SetValue(scale)
    scaleLabel:SetText(("Scale: %d%%"):format(scale * 100 + 0.5))
    ns.UpdateMinimapButton()
    ns.Rerender()
end

o:SetScript("OnShow", Sync)

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
