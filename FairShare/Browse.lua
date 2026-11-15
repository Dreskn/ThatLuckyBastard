local _, ns = ...

-- The statistics panel: tables over everything that has been recorded.
--   dungeons  averages per dungeon: loot, time, per hour, fairness
--   records   your best figures per dungeon
--   runs      every run that is kept; click one to open it
--   luck      rolls entered, wins expected and wins had, per player
--   regulars  people you have run with, and how they fared
--   drops     what dropped in your runs, and how often
--   roles     how shares turn out by role and class
--   search    find an item in past runs: when it dropped and who got it
--   awards    what every award means
--
-- Each page is a table: a one-line description, a list of columns and a
-- function returning rows. A row is
--   { cells = { text, ... },      what is shown
--     keys = { value, ... },      what each column sorts by (optional)
--     link = item link for the tooltip, run = run to open on click }
-- or { note = text } for a message. Pages whose rows have keys can be
-- sorted by clicking a column title.

local WIDTH, HEIGHT = 900, 480
local TAB_W = 92
local ROW_H = 18
local MAX_ROWS = 300
local MAX_COLS = 8
local MIN_QUERY = 2 -- letters needed before the item search runs

local b = CreateFrame("Frame", "FairShareBrowseFrame", UIParent)
b:SetSize(WIDTH, HEIGHT)
b:SetPoint("CENTER", 0, -30)
b:SetFrameStrata("DIALOG")
b:SetMovable(true)
b:EnableMouse(true)
b:SetClampedToScreen(true)
b:RegisterForDrag("LeftButton")
b:SetScript("OnDragStart", b.StartMoving)
b:SetScript("OnDragStop", b.StopMovingOrSizing)
b:Hide()
tinsert(UISpecialFrames, "FairShareBrowseFrame")

local skins = ns.BuildSkins(b, function() b:Hide() end)

local ui = CreateFrame("Frame", nil, b)
ui:SetAllPoints()
ui:SetFrameLevel(b:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")

local mode = "dungeons"
local sortCol, sortDesc = {}, {} -- per page: the column sorted by, and its direction
local Refresh

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

local function DateText(t)
    return t and date("%Y-%m-%d %H:%M", t) or "-"
end

local function Matches(text, query)
    return (text or ""):lower():find(query, 1, true) ~= nil
end

-- "+1.6" in green, "-0.8" in red
local function Signed(v)
    if math.abs(v) < 0.05 then return "0.0" end
    return ("%s%+.1f|r"):format(v > 0 and "|cff40d040" or "|cffe05050", v)
end

local PAGES = {}

-- width 0 = takes whatever is left
PAGES.dungeons = {
    title = "Dungeons",
    blurb = "Averages per dungeon. Click a column title to sort: \"Group / hour\" is the one to pick a dungeon by.",
    cols = {
        { "Dungeon", 0 }, { "Runs", 50, "RIGHT" }, { "Avg group", 100, "RIGHT" }, { "Avg yours", 100, "RIGHT" },
        { "Avg time", 75, "RIGHT" }, { "Group / hour", 100, "RIGHT" }, { "Yours / hour", 100, "RIGHT" },
        { "Fairness", 70, "RIGHT" },
    },
    defaultSort = 6,
    rows = function()
        local rows = {}
        for _, rec in pairs(ns.db.records) do
            local runs = math.max(rec.runs or 0, 1)
            local timed = (rec.tTime or 0) > 0
            local perHour = timed and rec.tGroup * 3600 / rec.tTime or nil
            local minePerHour = timed and rec.tMine * 3600 / rec.tTime or nil
            local avgTime = timed and rec.tTime / rec.tRuns or nil
            local fair = (rec.fairRuns or 0) > 0 and rec.fairSum / rec.fairRuns or nil
            rows[#rows + 1] = {
                cells = {
                    rec.name or "?",
                    tostring(rec.runs or 0),
                    ns.Money(rec.sumGroup / runs),
                    ns.Money(rec.sumMine / runs),
                    avgTime and ns.Duration(math.floor(avgTime)) or "-",
                    perHour and ns.Money(perHour) or "-",
                    minePerHour and ns.Money(minePerHour) or "-",
                    fair and ("%d / 100"):format(fair + 0.5) or "-",
                },
                keys = { rec.name or "?", rec.runs or 0, rec.sumGroup / runs, rec.sumMine / runs,
                         avgTime, perHour, minePerHour, fair },
            }
        end
        if #rows == 0 then
            return { { note = "Nothing yet. Dungeons appear here once a run in them is over." } }
        end
        return rows
    end,
}

PAGES.records = {
    title = "Records",
    blurb = "Your best figures per dungeon. Fastest only compares runs with the most boss kills seen there.",
    cols = {
        { "Dungeon", 0 }, { "Runs", 50, "RIGHT" }, { "Richest run", 100, "RIGHT" },
        { "Your best", 100, "RIGHT" }, { "Biggest item", 250 }, { "Fastest", 80, "RIGHT" },
    },
    rows = function()
        local list = {}
        for _, rec in pairs(ns.db.records) do list[#list + 1] = rec end
        if #list == 0 then
            return { { note = "No records yet. They are set when a dungeon run is over." } }
        end
        table.sort(list, function(x, y) return (x.name or "") < (y.name or "") end)
        local rows = {}
        for i, rec in ipairs(list) do
            rows[i] = {
                link = rec.jackpotLink,
                cells = {
                    rec.name or "?",
                    tostring(rec.runs),
                    ns.Money(rec.bestGroup),
                    ns.Money(rec.bestMine),
                    rec.jackpotLink and (rec.jackpotLink .. "  " .. ns.Money(rec.jackpot)) or "-",
                    rec.fastest and ns.Duration(rec.fastest) or "-",
                },
                keys = { rec.name or "?", rec.runs, rec.bestGroup, rec.bestMine, rec.jackpot, rec.fastest },
            }
        end
        return rows
    end,
}

PAGES.runs = {
    title = "Runs",
    blurb = "Every run that is kept. Click one to open it.",
    filter = "dungeon or player",
    cols = {
        { "Date", 120 }, { "Dungeon", 0 }, { "Time", 70, "RIGHT" }, { "Group", 95, "RIGHT" },
        { "Yours", 95, "RIGHT" }, { "Share", 55, "RIGHT" }, { "Fairness", 65, "RIGHT" }, { "Top looter", 150 },
    },
    rows = function(query)
        query = (query or ""):lower()
        local rows = {}
        for _, s in ipairs(ns.AllRuns()) do
            local wanted = query == "" or Matches(s.name, query)
            if not wanted then
                for name in pairs(s.players) do
                    if Matches(name, query) then wanted = true end
                end
            end
            if wanted then
                local sum = ns.Summarize(s)
                local mine, top = 0, nil
                for _, p in ipairs(sum.players) do
                    if p.name == ns.playerName then mine = p.market end
                    if p.rank == 1 then top = p end
                end
                local duration = ns.RunDuration(s)
                local fair = ns.Fairness(sum)
                local share = sum.market > 0 and mine / sum.market * 100 or 0
                rows[#rows + 1] = {
                    run = s,
                    cells = {
                        DateText(s.startedAt),
                        s.name or "Run",
                        duration and ns.Duration(duration) or "-",
                        ns.Money(sum.market),
                        ns.Money(mine),
                        ("%d%%"):format(share + 0.5),
                        fair and tostring(fair) or "-",
                        top and ns.ClassColored(ns.DisplayName(top.name), top.class) or "-",
                    },
                    keys = { s.startedAt or 0, s.name or "Run", duration, sum.market, mine, share, fair,
                             top and top.name or "" },
                }
            end
        end
        if #rows == 0 then
            return { { note = query == "" and "No run recorded yet." or "No run matches." } }
        end
        return rows
    end,
}

PAGES.luck = {
    title = "Luck",
    blurb = "Expected wins: each roll entered counts as one in the number of players who could win it. "
        .. "Counted from now on.",
    cols = {
        { "Player", 0 }, { "Rolls entered", 100, "RIGHT" }, { "Expected wins", 110, "RIGHT" },
        { "Wins", 60, "RIGHT" }, { "Difference", 90, "RIGHT" }, { "Average roll", 100, "RIGHT" },
        { "Numbers seen", 100, "RIGHT" },
    },
    rows = function()
        local rows = {}
        local function add(label, who, sortName)
            local rolls, rollN = who.rolls or 0, who.rollN or 0
            if rolls == 0 and rollN == 0 then return end
            local expected, wins = who.expected or 0, who.wins or 0
            local avg = rollN > 0 and who.rollSum / rollN or nil
            rows[#rows + 1] = {
                cells = {
                    label,
                    rolls > 0 and tostring(rolls) or "-",
                    rolls > 0 and ("%.1f"):format(expected) or "-",
                    rolls > 0 and tostring(wins) or "-",
                    rolls > 0 and Signed(wins - expected) or "-",
                    avg and ("%.1f"):format(avg) or "-",
                    rollN > 0 and tostring(rollN) or "-",
                },
                keys = { sortName, rolls, expected, wins, rolls > 0 and wins - expected or nil, avg, rollN },
            }
        end
        add("|cffffd100You|r", ns.db.me, "")
        for name, who in pairs(ns.db.people) do
            add(ns.ClassColored(ns.DisplayName(name), who.class), who, name)
        end
        if #rows == 0 then
            return { { note = "Nothing yet. This fills up from the next run in which loot is rolled for." } }
        end
        return rows
    end,
}

PAGES.regulars = {
    title = "Regulars",
    blurb = "People you have run with. Only you can see this.",
    cols = {
        { "Player", 0 }, { "Runs together", 110, "RIGHT" }, { "Avg loot / run", 120, "RIGHT" },
        { "Luckiest", 80, "RIGHT" }, { "Ninja", 70, "RIGHT" }, { "Last run", 130, "RIGHT" },
    },
    defaultSort = 2,
    rows = function()
        local rows = {}
        for name, who in pairs(ns.db.people) do
            local avg = who.value / math.max(who.runs, 1)
            rows[#rows + 1] = {
                cells = {
                    ns.ClassColored(ns.DisplayName(name), who.class),
                    tostring(who.runs),
                    ns.Money(avg),
                    who.lucky > 0 and tostring(who.lucky) or "-",
                    who.ninja > 0 and tostring(who.ninja) or "-",
                    DateText(who.last),
                },
                keys = { name, who.runs, avg, who.lucky, who.ninja, who.last or 0 },
            }
        end
        if #rows == 0 then
            return { { note = "Nobody yet. People appear here once a run with them is over." } }
        end
        return rows
    end,
}

PAGES.drops = {
    title = "Drops",
    blurb = "What dropped in your runs, and in how many of them.",
    filter = "dungeon or item",
    cols = {
        { "Dungeon", 150 }, { "Item", 0 }, { "Seen in", 100, "RIGHT" }, { "Of runs", 60, "RIGHT" },
        { "Count", 60, "RIGHT" }, { "Avg value", 95, "RIGHT" }, { "Last to", 140 },
    },
    defaultSort = 4,
    rows = function(query)
        query = (query or ""):lower()
        local rows = {}
        for instanceID, drops in pairs(ns.db.drops) do
            local rec = ns.db.records[instanceID]
            local dungeon = rec and rec.name or "?"
            local runs = math.max(ns.db.dropRuns[instanceID] or 0, 1)
            local wholeDungeon = query == "" or Matches(dungeon, query)
            for id, d in pairs(drops) do
                if wholeDungeon or Matches(d.name, query) then
                    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[d.q or 1]
                    local pct = d.n / runs * 100
                    local value = d.c > 0 and d.v / d.c or 0
                    rows[#rows + 1] = {
                        link = "item:" .. id,
                        cells = {
                            dungeon,
                            (colour and colour.hex or "|cffffffff") .. (d.name or "?") .. "|r",
                            ("%d of %d runs"):format(d.n, runs),
                            ("%d%%"):format(pct + 0.5),
                            tostring(d.c),
                            ns.Money(value),
                            d.by and ns.DisplayName(d.by) or "-",
                        },
                        keys = { dungeon, d.name or "?", d.n, pct, d.c, value, d.by or "" },
                    }
                end
            end
        end
        if #rows == 0 then
            return { { note = query == "" and "Nothing yet. Items appear here once a dungeon run is over."
                                           or "Nothing matches." } }
        end
        return rows
    end,
}

local ROLE_NAMES = { { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "Damage" }, { "NONE", "No role set" } }

PAGES.roles = {
    title = "Roles",
    blurb = "How loot shares turn out by role and class, against an equal share (100%). Groups of 3 or more.",
    cols = { { "", 220 }, { "Players counted", 130, "RIGHT" }, { "Average share", 0 } },
    rows = function()
        local rows = {}
        local function add(label, row)
            local avg = row.rel / row.n * 100
            local colour = avg >= 105 and "|cff40d040" or (avg <= 95 and "|cffe05050" or "|cffffffff")
            rows[#rows + 1] = { cells = {
                label, tostring(row.n), ("    %s%d%%|r of an equal share"):format(colour, avg + 0.5),
            } }
        end
        for _, role in ipairs(ROLE_NAMES) do
            local row = ns.db.roles[role[1]]
            if row and row.n > 0 then add(role[2], row) end
        end
        if #rows == 0 then
            return { { note = "Nothing yet. This fills up as runs are completed." } }
        end
        rows[#rows + 1] = { note = "" }
        local classes = {}
        for class, row in pairs(ns.db.classes) do
            if row.n > 0 then classes[#classes + 1] = { class = class, row = row } end
        end
        table.sort(classes, function(x, y)
            local ax, ay = x.row.rel / x.row.n, y.row.rel / y.row.n
            if ax ~= ay then return ax > ay end
            return x.class < y.class
        end)
        for _, c in ipairs(classes) do
            local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class] or c.class
            add(ns.ClassColored(name, c.class), c.row)
        end
        return rows
    end,
}

PAGES.search = {
    title = "Find item",
    blurb = "",
    filter = "item name",
    cols = {
        { "Date", 120 }, { "Dungeon", 170 }, { "Player", 160 }, { "Item", 0 }, { "Value", 95, "RIGHT" },
    },
    rows = function(query)
        query = (query or ""):lower()
        if #query < MIN_QUERY then
            return { { note = "Type at least two letters of an item's name." } }
        end
        local rows = {}
        for _, s in ipairs(ns.AllRuns()) do -- newest first already
            for name, p in pairs(s.players) do
                for _, e in pairs(p.items) do
                    if #rows < MAX_ROWS and ns.ItemName(e):lower():find(query, 1, true) then
                        rows[#rows + 1] = {
                            link = e.link, run = s,
                            cells = {
                                DateText(s.startedAt),
                                s.name or "Run",
                                ns.ClassColored(ns.DisplayName(name), p.class),
                                (e.count > 1 and (e.count .. "x ") or "") .. e.link,
                                ns.Money(ns.EntryMarket(e)),
                            },
                            keys = { s.startedAt or 0, s.name or "Run", name, ns.ItemName(e), ns.EntryMarket(e) },
                        }
                    end
                end
            end
        end
        if #rows == 0 then
            return { { note = "Nothing found in the runs that are kept." } }
        end
        return rows
    end,
}

PAGES.awards = {
    title = "Awards",
    blurb = "Every player gets one award: the one that fits them best. The further from normal, the stronger the fit.",
    cols = { { "Award", 150 }, { "Goes to the player who...", 0 } },
    rows = function()
        local rows = {
            { note = "An award goes to one player only, so the others get their next best. "
                  .. "Ninja and Luckiest count for more." },
        }
        for _, award in ipairs(ns.AwardGuide()) do
            rows[#rows + 1] = { cells = {
                ("|TInterface\\Icons\\%s:14:14|t  |cffffd100%s|r"):format(award.icon, award.title),
                award.how,
            } }
        end
        return rows
    end,
}

local PAGE_ORDER = { "dungeons", "records", "runs", "luck", "regulars", "drops", "roles", "search", "awards" }

----------------------------------------------------------------------
-- Controls
----------------------------------------------------------------------

local tabs = {}
for i, key in ipairs(PAGE_ORDER) do
    local tab = ns.MakeButton(PAGES[key].title, TAB_W, function()
        mode = key
        ui.search:SetText("") -- a filter belongs to the page it was typed on
        Refresh()
    end, ui)
    if i > 1 then tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0) end
    tabs[i] = tab
end

-- Second line: what the page is about, or its filter box.
local blurb = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
blurb:SetJustifyH("LEFT")
blurb:SetWordWrap(false)

local search = CreateFrame("EditBox", nil, ui, "InputBoxTemplate")
search:SetSize(220, 20)
search:SetAutoFocus(false)
ui.search = search
search:SetScript("OnTextChanged", function() if b:IsShown() then Refresh() end end)
search:SetScript("OnEnterPressed", search.ClearFocus)
search:SetScript("OnEscapePressed", search.ClearFocus)

local exportBtn = ns.MakeButton("Export all runs", 120, function() ns.ShowExport("all") end, ui)

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 46, 1)
scroll:SetScrollChild(content)

-- Column titles: the text, and a button over it for sorting.
local headers, headerButtons = {}, {}
for i = 1, MAX_COLS do
    headers[i] = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers[i]:SetWordWrap(false)
    local hb = CreateFrame("Button", nil, ui)
    hb:SetHeight(16)
    hb:SetScript("OnClick", function()
        if not hb.sortable then return end
        if sortCol[mode] == i then
            sortDesc[mode] = not sortDesc[mode]
        else
            sortCol[mode], sortDesc[mode] = i, true -- biggest first is what one usually wants
        end
        Refresh()
    end)
    headerButtons[i] = hb
end

local rows = {}

local function RowOnEnter(self)
    if self.link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        if self.run then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to open this run.", 0.6, 0.8, 1)
        end
        GameTooltip:Show()
    end
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.cells = {}
    for k = 1, MAX_COLS do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        r.cells[k] = fs
    end
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self)
        if self.run then ns.ShowRun(self.run) end
    end)
    rows[i] = r
    return r
end

-- Puts a row's font string at horizontal position x with the given width.
local function PlaceCell(fs, parent, x, width, justify)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function ApplyTheme()
    local flat = ns.db.theme == "modern"
    local active = flat and skins.modern or skins.classic
    for _, skin in pairs(skins) do skin:SetShown(skin == active) end

    title:ClearAllPoints()
    if flat then
        title:SetFontObject("GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -10)
    else
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOP", 0, -5)
    end

    local top = flat and -46 or -30
    tabs[1]:ClearAllPoints()
    tabs[1]:SetPoint("TOPLEFT", 12, top)
    for _, tab in ipairs(tabs) do tab:SetFlat(flat) end
    exportBtn:SetFlat(flat)

    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", 18, top - 27)
    exportBtn:ClearAllPoints()
    exportBtn:SetPoint("TOPRIGHT", -14, top - 26)

    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, top - 72)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    for _, h in ipairs(headers) do
        if flat then h:SetTextColor(0.60, 0.63, 0.68) else h:SetTextColor(1, 0.82, 0) end
    end
end

-- Rows with sort keys, ordered by the chosen column; messages stay on
-- top. Empty values go last whichever way the column is sorted.
local function Sorted(data, col, desc)
    local notes, sortable = {}, {}
    for _, row in ipairs(data) do
        if row.keys then
            row.order = #sortable + 1
            sortable[#sortable + 1] = row
        else
            notes[#notes + 1] = row
        end
    end
    table.sort(sortable, function(x, y)
        local kx, ky = x.keys[col], y.keys[col]
        if kx == ky then return x.order < y.order end
        if kx == nil then return false end
        if ky == nil then return true end
        if type(kx) ~= type(ky) then kx, ky = tostring(kx), tostring(ky) end
        if desc then return kx > ky end
        return kx < ky
    end)
    for _, row in ipairs(sortable) do notes[#notes + 1] = row end
    return notes
end

function Refresh()
    ApplyTheme()
    local page = PAGES[mode]
    title:SetText("FairShare - Statistics - " .. page.title)
    for i, key in ipairs(PAGE_ORDER) do tabs[i]:SetOn(key ~= mode) end

    -- Second line: the filter box with a hint beside it, or the description.
    search:SetShown(page.filter ~= nil)
    blurb:ClearAllPoints()
    if page.filter then
        blurb:SetPoint("LEFT", search, "RIGHT", 10, 0)
        blurb:SetText("Filter: " .. page.filter .. (page.blurb ~= "" and ("      " .. page.blurb) or ""))
    else
        blurb:SetPoint("LEFT", search, "LEFT", -4, 0)
        blurb:SetText(page.blurb)
    end
    blurb:SetPoint("RIGHT", exportBtn, "LEFT", -10, 0)

    local data = page.rows(search:GetText())
    local sortable = false
    for _, row in ipairs(data) do
        if row.keys then sortable = true end
    end
    if sortable then
        if not sortCol[mode] and page.defaultSort then
            sortCol[mode], sortDesc[mode] = page.defaultSort, true
        end
        if sortCol[mode] then data = Sorted(data, sortCol[mode], sortDesc[mode]) end
    end
    if #data > MAX_ROWS then
        for i = #data, MAX_ROWS + 1, -1 do data[i] = nil end
        data[#data + 1] = { note = ("Showing the first %d rows. Use the filter to narrow it down."):format(MAX_ROWS) }
    end

    -- Column positions: fixed widths, and one column that takes the rest.
    local total = content:GetWidth()
    local gap, fixed = 8, 0
    for _, col in ipairs(page.cols) do fixed = fixed + col[2] end
    local flexible = math.max(total - fixed - gap * (#page.cols - 1) - 8, 60)
    local xs, widths = {}, {}
    local x = 4
    for k, col in ipairs(page.cols) do
        widths[k] = col[2] > 0 and col[2] or flexible
        xs[k] = x
        x = x + widths[k] + gap
    end

    for k = 1, MAX_COLS do
        local col = page.cols[k]
        local hb = headerButtons[k]
        if col then
            local label = col[1]
            if sortable and sortCol[mode] == k then
                label = label .. (sortDesc[mode] and " |TInterface\\Buttons\\Arrow-Down-Up:11|t"
                                                  or " |TInterface\\Buttons\\Arrow-Up-Up:11|t")
            end
            headers[k]:ClearAllPoints()
            headers[k]:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", xs[k], 4)
            headers[k]:SetWidth(widths[k])
            headers[k]:SetJustifyH(col[3] or "LEFT")
            headers[k]:SetText(label)
            headers[k]:Show()
            hb.sortable = sortable
            hb:ClearAllPoints()
            hb:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", xs[k], 2)
            hb:SetWidth(widths[k])
            hb:SetShown(sortable)
        else
            headers[k]:Hide()
            hb:Hide()
        end
    end

    for i, row in ipairs(data) do
        local r = GetRow(i)
        r.link, r.run = row.link, row.run
        for k = 1, MAX_COLS do
            local fs, col = r.cells[k], page.cols[k]
            if row.note then
                -- A message: one cell across the whole row.
                if k == 1 then
                    PlaceCell(fs, r, 4, total - 8, "LEFT")
                    fs:SetText("|cff909090" .. row.note .. "|r")
                    fs:Show()
                else
                    fs:Hide()
                end
            elseif col then
                PlaceCell(fs, r, xs[k], widths[k], col[3])
                fs:SetText(row.cells[k] or "")
                fs:Show()
            else
                fs:Hide()
            end
        end
        r:EnableMouse(row.link ~= nil or row.run ~= nil)
        r:Show()
    end
    for i = #data + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(#data * ROW_H, 1))
end

b:SetScript("OnShow", function() Refresh() end)

-- page: one of the page names at the top of this file. query: text for
-- the page's filter box.
function ns.ShowBrowse(page, query)
    if PAGES[page] then mode = page end
    if query and query ~= "" then search:SetText(query) end
    if b:IsShown() then
        Refresh()
    else
        b:Show()
    end
    b:Raise() -- it may be opened from the run details, which sit at the same level
    if mode == "search" then search:SetFocus() end
end
