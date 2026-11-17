local _, ns = ...

-- Three more views of one run:
--   timeline  a chart of every player's running total through the run,
--             in a window of its own (see ns.MakeRunWindow in Show.lua)
--   rolls     every roll that was won: who rolled what
--   numbers   fairness, where the loot came from, roll luck, the streak
--             the run belongs to, today's prices and the award scores
-- Rolls and numbers are tabs of the statistics window, for the run on
-- show in the main window. The figures come from Data.lua.

local PAGE_W = 696 -- the room a page gets: the timeline window's width, less its margins

local function Clock(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function Colored(s, name)
    local p = s.players[name]
    return ns.ClassColored(ns.DisplayName(name), p and p.class)
end

local CHOICE_TEXT = { need = "Need", greed = "Greed", pass = "passed" }

-- "Need 87", "Greed", "passed"
local function RollText(r)
    if r.choice == "pass" or not r.roll then return CHOICE_TEXT[r.choice] end
    return CHOICE_TEXT[r.choice] .. " " .. r.roll
end

-- Adds one roll to the tooltip being built: a line per player.
local function AddRoll(s, roll)
    for _, r in ipairs(roll.rolls) do
        local won = r.name == roll.winner
        GameTooltip:AddDoubleLine(Colored(s, r.name) .. (won and "  |cff40d040won|r" or ""), RollText(r),
                                  1, 1, 1, 1, 1, 1)
    end
end

-- Adds the rolls on one item of a run to the tooltip being built. Used by
-- the main window's item rows.
function ns.AddRollLines(s, itemKey)
    for _, roll in ipairs(ns.RunRolls(s)) do
        if roll.key == itemKey then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rolls", 1, 0.82, 0)
            AddRoll(s, roll)
        end
    end
end

----------------------------------------------------------------------
-- Timeline
----------------------------------------------------------------------

local CHART_W, CHART_H = 470, 330
local PALETTE = {
    { 1.00, 0.82, 0.00 }, { 0.35, 0.65, 1.00 }, { 0.35, 0.85, 0.45 }, { 1.00, 0.40, 0.40 },
    { 0.75, 0.50, 1.00 }, { 0.30, 0.85, 0.85 }, { 1.00, 0.60, 0.20 }, { 0.70, 0.70, 0.70 },
}
local MAX_SERIES = #PALETTE -- one colour per line

local timeline, DrawTimeline
local timelineWin = ns.MakeRunWindow("timeline", "ThatLuckyBastardTimelineFrame", "Timeline", PAGE_W + 24, 510,
    function(s, _, top)
        timeline:ClearAllPoints()
        timeline:SetPoint("TOPLEFT", 12, top)
        timeline:SetPoint("BOTTOMRIGHT", -12, 12)
        DrawTimeline(s)
    end)
timelineWin.frame:SetPoint("CENTER", -30, -10)
timeline = CreateFrame("Frame", nil, timelineWin.ui)

local chart = CreateFrame("Frame", nil, timeline)
chart:SetSize(CHART_W, CHART_H)
chart:SetPoint("TOPLEFT", 64, -44)
local chartBg = chart:CreateTexture(nil, "BACKGROUND")
chartBg:SetAllPoints()
chartBg:SetColorTexture(0, 0, 0, 0.30)

local timelineNote = timeline:CreateFontString(nil, "OVERLAY", "GameFontDisable")
timelineNote:SetPoint("CENTER")
timelineNote:SetWidth(PAGE_W - 80)

local caption = timeline:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
caption:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -22)
caption:SetWidth(PAGE_W - 80)
caption:SetJustifyH("LEFT")

-- Axis texts: value at the top and middle of the chart, time along it.
local function AxisText(point, relPoint, x, y, justify)
    local fs = timeline:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint(point, chart, relPoint, x, y)
    fs:SetJustifyH(justify)
    return fs
end
local yTop = AxisText("RIGHT", "TOPLEFT", -6, 0, "RIGHT")
local yMid = AxisText("RIGHT", "LEFT", -6, 0, "RIGHT")
local xStart = AxisText("TOPLEFT", "BOTTOMLEFT", 0, -5, "LEFT")
local xMid = AxisText("TOP", "BOTTOM", 0, -5, "CENTER")
local xEnd = AxisText("TOPRIGHT", "BOTTOMRIGHT", 0, -5, "RIGHT")

local segments, usedSegments = {}, 0
local function Segment(x1, y1, x2, y2, c, alpha, thickness)
    usedSegments = usedSegments + 1
    local line = segments[usedSegments]
    if not line then
        line = chart:CreateLine(nil, "ARTWORK")
        segments[usedSegments] = line
    end
    line:SetStartPoint("BOTTOMLEFT", chart, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", chart, x2, y2)
    line:SetColorTexture(c[1], c[2], c[3], alpha or 1)
    line:SetThickness(thickness or 2)
    line:Show()
end

local bossTexts = {}
local function BossText(i)
    local fs = bossTexts[i]
    if not fs then
        fs = timeline:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetWordWrap(false)
        bossTexts[i] = fs
    end
    return fs
end

local legend = {}
local function LegendRow(i)
    local row = legend[i]
    if not row then
        row = {}
        row.swatch = timeline:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("TOPLEFT", chart, "TOPRIGHT", 14, -4 - (i - 1) * 32)
        row.name = timeline:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.swatch, "RIGHT", 6, 0)
        row.name:SetWidth(PAGE_W - 64 - CHART_W - 34)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.value = timeline:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        legend[i] = row
    end
    return row
end

local WHITE = { 1, 1, 1 }

function DrawTimeline(s)
    for _, line in ipairs(segments) do line:Hide() end
    for _, fs in ipairs(bossTexts) do fs:Hide() end
    for _, row in ipairs(legend) do
        row.swatch:Hide()
        row.name:Hide()
        row.value:Hide()
    end
    usedSegments = 0

    local data = s and ns.Timeline(s)
    local has = data ~= nil
    chart:SetShown(has)
    caption:SetShown(has)
    yTop:SetShown(has)
    yMid:SetShown(has)
    xStart:SetShown(has)
    xMid:SetShown(has)
    xEnd:SetShown(has)
    timelineNote:SetShown(not has)
    if not has then
        timelineNote:SetText(not s and "No run to show yet."
            or s.example and "Example runs have no timeline."
            or ((s.log or s == ns.db.active) and "Nothing has been picked up in this run."
                or "No timeline: this run was recorded before pickup times were kept."))
        return
    end

    local function X(t) return math.min(t / data.duration, 1) * CHART_W end
    local function Y(v) return v / data.max * CHART_H end

    yTop:SetText(ns.Money(data.max))
    yMid:SetText(ns.Money(data.max / 2))
    xStart:SetText("0:00")
    xMid:SetText(Clock(math.floor(data.duration / 2)))
    xEnd:SetText(Clock(data.duration))
    Segment(0, CHART_H / 2, CHART_W, CHART_H / 2, WHITE, 0.10, 1)
    Segment(0, CHART_H, CHART_W, CHART_H, WHITE, 0.10, 1)

    for i, boss in ipairs(data.bosses) do
        local x = X(boss.t)
        Segment(x, 0, x, CHART_H, WHITE, 0.28, 1)
        local fs = BossText(i)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOM", chart, "TOPLEFT", x, 3 + ((i - 1) % 3) * 11) -- three rows, to keep names apart
        fs:SetText(boss.name or "Boss")
        fs:Show()
    end

    -- The lines, poorest first so that the leaders are drawn on top. Each
    -- is a staircase: flat until a pickup, then straight up. Pickups that
    -- fall on the same pixel are drawn as one step.
    local count = math.min(#data.series, MAX_SERIES)
    caption:SetText("Running totals. Vertical lines are boss kills."
        .. (#data.series > count and ("  The %d richest of %d players."):format(count, #data.series) or ""))
    for i = count, 1, -1 do
        local c = PALETTE[i]
        local px, py = 0, 0
        local points = data.series[i].points
        for k, pt in ipairs(points) do
            local x, y = X(pt.t), Y(pt.v)
            local nextPt = points[k + 1]
            -- Drawn when the next pickup falls in another pixel column.
            if not nextPt or math.floor(X(nextPt.t)) > math.floor(x) then
                if x > px then Segment(px, py, x, py, c) end
                if y > py then Segment(x, py, x, y, c) end
                px, py = x, y
            end
        end
        if CHART_W > px then Segment(px, py, CHART_W, py, c) end
    end

    for i = 1, count do
        local line, row = data.series[i], LegendRow(i)
        local c = PALETTE[i]
        row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        row.name:SetText(ns.ClassColored(ns.DisplayName(line.name), line.class))
        row.value:SetText(ns.Money(line.total))
        row.swatch:Show()
        row.name:Show()
        row.value:Show()
    end
end

----------------------------------------------------------------------
-- Rolls
----------------------------------------------------------------------

local ROLL_ROW_H = 20
local ROLL_COLS = { { "Time", 4, 46 }, { "Item", 54, 200 }, { "Won by", 262, 190 }, { "Others", 460, 206 } }

local rollsPage = CreateFrame("Frame", nil, ns.StatsPageParent)

local rollsSummary = rollsPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rollsSummary:SetPoint("TOPLEFT", 4, -4)
rollsSummary:SetPoint("TOPRIGHT", -4, -4)
rollsSummary:SetJustifyH("LEFT")

local rollsScroll = CreateFrame("ScrollFrame", nil, rollsPage, "UIPanelScrollFrameTemplate")
rollsScroll:SetPoint("TOPLEFT", 0, -46)
rollsScroll:SetPoint("BOTTOMRIGHT", -22, 0)
local rollsContent = CreateFrame("Frame", nil, rollsScroll)
rollsContent:SetSize(PAGE_W - 24, 1)
rollsScroll:SetScrollChild(rollsContent)

for _, col in ipairs(ROLL_COLS) do
    local h = rollsPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("BOTTOMLEFT", rollsScroll, "TOPLEFT", col[2], 4)
    h:SetText(col[1])
end

local rollRows = {}
local rollsRun -- the run the rows belong to

local function RollRowOnEnter(self)
    local roll = self.roll
    if not roll or not rollsRun then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then
        GameTooltip:SetHyperlink(self.link)
    else
        GameTooltip:AddLine("Item " .. roll.key)
    end
    GameTooltip:AddLine(" ")
    AddRoll(rollsRun, roll)
    GameTooltip:Show()
end

local function GetRollRow(i)
    local r = rollRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, rollsContent)
    r:SetHeight(ROLL_ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROLL_ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROLL_ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    if i % 2 == 0 then -- every other row lightly shaded
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.035)
    end
    r.cells = {}
    for k, col in ipairs(ROLL_COLS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", col[2], 0)
        fs:SetWidth(col[3])
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        r.cells[k] = fs
    end
    r:SetScript("OnEnter", RollRowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rollRows[i] = r
    return r
end

local function DrawRolls(s)
    rollsRun = s
    local rolls = ns.RunRolls(s)
    local need = 0
    for _, roll in ipairs(rolls) do
        if roll.method == "need" then need = need + 1 end
    end
    if #rolls == 0 then
        rollsSummary:SetText("|cff909090" .. ((s.log or s.example or s == ns.db.active)
            and "Nothing has been rolled for in this run."
            or "No roll sheet: this run was recorded before rolls were kept in full.") .. "|r")
    else
        rollsSummary:SetText(("%d rolls: %d Need, %d Greed.   |cff909090Hover a line for every roll.|r")
            :format(#rolls, need, #rolls - need))
    end

    for i, roll in ipairs(rolls) do
        local r = GetRollRow(i)
        local e = ns.RollItem(s, roll)
        r.roll, r.link = roll, e and e.link
        local winnerRoll, others = nil, {}
        for _, x in ipairs(roll.rolls) do
            if x.name == roll.winner then
                winnerRoll = x
            elseif x.choice == "pass" then
                others[#others + 1] = ns.FirstName(x.name) .. " passed"
            else
                -- A choice other than the winning one is named: a Greed
                -- against a Need was never in the race.
                local tag = x.choice ~= roll.method and (" " .. CHOICE_TEXT[x.choice]) or ""
                others[#others + 1] = ns.FirstName(x.name) .. tag .. (x.roll and (" " .. x.roll) or "")
            end
        end
        r.cells[1]:SetText(Clock(roll.t))
        r.cells[2]:SetText(e and e.link or ("Item " .. roll.key))
        r.cells[3]:SetText(Colored(s, roll.winner) .. "  |cffb0b0b0"
            .. (winnerRoll and RollText(winnerRoll) or CHOICE_TEXT[roll.method]) .. "|r")
        r.cells[4]:SetText(table.concat(others, ", "))
        r:Show()
    end
    for i = #rolls + 1, #rollRows do rollRows[i]:Hide() end
    rollsContent:SetHeight(math.max(#rolls * ROLL_ROW_H, 1))
end

----------------------------------------------------------------------
-- Numbers
----------------------------------------------------------------------

local numbersPage = CreateFrame("Frame", nil, ns.StatsPageParent)

local numbersScroll = CreateFrame("ScrollFrame", nil, numbersPage, "UIPanelScrollFrameTemplate")
numbersScroll:SetPoint("TOPLEFT", 0, -2)
numbersScroll:SetPoint("BOTTOMRIGHT", -22, 30)
local numbersContent = CreateFrame("Frame", nil, numbersScroll)
numbersContent:SetSize(PAGE_W - 24, 1)
numbersScroll:SetScrollChild(numbersContent)

local numbersRun
local exportBtn = ns.MakeButton("Export this run", 130, function()
    if numbersRun then ns.ShowExport("run", numbersRun) end
end, numbersPage)
exportBtn:SetPoint("BOTTOMLEFT", 0, 0)
local exportHint = numbersPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportHint:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
exportHint:SetText("As text, for a spreadsheet.")

local numberTexts = {}
local SMALL_CHANGE = 100 -- copper: a price change below this is not worth a line
local FITS_SHOWN = 4     -- award fits listed per player

local function Percent(part, whole)
    return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0
end

-- The page as a list of { head = true, text } and { text } entries.
local function NumberLines(s)
    local lines = {}
    local function head(text) lines[#lines + 1] = { head = true, text = text } end
    local function line(text) lines[#lines + 1] = { text = text } end
    local function note(text) lines[#lines + 1] = { text = "|cff909090" .. text .. "|r" } end

    local sum = ns.Summarize(s)
    local over = not ns.InProgress(s)

    local fair = ns.Fairness(sum)
    if fair then
        head("Fairness")
        local text = ("%d / 100."):format(fair)
        local rec = s.instanceID and ns.db.records[s.instanceID]
        if rec and (rec.fairRuns or 0) >= 2 then
            text = text .. ("  Your average here: %d, over %d runs."):format(
                rec.fairSum / rec.fairRuns + 0.5, rec.fairRuns)
        end
        line(text)
        note("100: everyone got the same. 0: one player took everything.")
    end

    local src = ns.Sources(s)
    if src and src.total > 0 then
        head("Loot by source")
        line(("After a boss kill:  %s  (%d%%)"):format(ns.Money(src.boss), Percent(src.boss, src.total)))
        line(("Profession materials:  %s  (%d%%)"):format(ns.Money(src.mats), Percent(src.mats, src.total)))
        line(("Trash and the rest:  %s  (%d%%)"):format(ns.Money(src.trash), Percent(src.trash, src.total)))
        note(("Boss loot: anything picked up within %d seconds of a kill."):format(ns.BOSS_WINDOW))
    end

    local luck = ns.RunLuck(s)
    if next(luck) then
        head("Roll luck")
        for _, p in ipairs(sum.players) do
            local l = luck[p.name]
            if l then
                local text = ("%s:  %d %s, %.1f expected, %d won  (%s)"):format(
                    Colored(s, p.name), l.rolls, l.rolls == 1 and "roll" or "rolls", l.expected, l.wins,
                    ns.Signed(l.wins - l.expected))
                local st = s.rollStats and s.rollStats[p.name]
                if st and (st.n or 0) > 0 then
                    text = text .. ("   |cff909090avg roll %d|r"):format(st.sum / st.n + 0.5)
                end
                line(text)
            end
        end
        note("Expected: each roll entered counts as one in the number of players who could win it.")
    end

    local streak = ns.Streak(s)
    if streak then
        head("Streak")
        local text = ns.StreakLabel(streak) .. (".  Together so far: %s"):format(ns.Money(streak.total))
        if streak.duration >= ns.MIN_TIMED_RUN then
            text = text .. ("  in %s  (%s an hour)"):format(ns.Duration(streak.duration),
                ns.Money(streak.total * 3600 / streak.duration))
        end
        line(text .. ".")
        for i, row in ipairs(streak.standings) do
            local part = ""
            if row.runs < streak.count then
                part = ("  |cff909090(%d of the %d runs)|r"):format(row.runs, streak.count)
            end
            line(("%d.  %s   %s   %d%%%s"):format(i, ns.ClassColored(ns.DisplayName(row.name), row.class),
                ns.Money(row.value), Percent(row.value, streak.total), part))
        end
        note(("In a row: started within %d minutes of the end of the last, with the same group or in the same dungeon.")
            :format(ns.STREAK_GAP / 60))
    end

    local price = over and ns.Reprice(s) or nil
    if price and price.was > 0 then
        head("At today's prices")
        local change = (price.now - price.was) / price.was * 100
        local text = ("%s today, %s when looted"):format(ns.Money(price.now), ns.Money(price.was))
        if math.abs(change) >= 1 then
            text = text .. ("  (%s%+.0f%%|r)"):format(change > 0 and "|cff40d040" or "|cffe05050", change)
        end
        line(text .. ".")
        if price.mover and math.abs(price.mover.now - price.mover.was) >= SMALL_CHANGE then
            line(("Biggest change:  %s  from %s to %s"):format(price.mover.link, ns.Money(price.mover.was),
                ns.Money(price.mover.now)))
        end
    end

    local awards = ns.RunAwards(s, sum)
    if next(awards) then
        local scores = ns.AwardScores(s, sum)
        head("Award scores")
        for _, p in ipairs(sum.players) do
            local parts = {}
            for i, score in ipairs(scores[p.name] or {}) do
                if i <= FITS_SHOWN then parts[#parts + 1] = ("%s %.2f"):format(score.title, score.fit) end
            end
            line(("%s:  |cffffd100%s|r   |cff909090%s|r"):format(Colored(s, p.name),
                awards[p.name] and awards[p.name].title or "-",
                #parts > 0 and ("fits: " .. table.concat(parts, ", ")) or "nothing fitted"))
        end
        note("0.3 just qualifies, 1 is remarkable, 2 extraordinary.")
    end

    if #lines == 0 then
        note("Nothing to show for this run yet.")
    end
    return lines
end

local function DrawNumbers(s)
    numbersRun = s
    local lines = NumberLines(s)
    local width = PAGE_W - 40
    local y = 4
    for i, item in ipairs(lines) do
        local fs = numberTexts[i]
        if not fs then
            fs = numbersContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            numberTexts[i] = fs
        end
        fs:SetFontObject(item.head and "GameFontNormalLarge" or "GameFontHighlight")
        fs:SetText(item.text)
        fs:ClearAllPoints()
        if item.head and i > 1 then y = y + 14 end
        fs:SetPoint("TOPLEFT", 6, -y)
        fs:SetWidth(width)
        y = y + fs:GetStringHeight() + (item.head and 6 or 4)
        fs:Show()
    end
    for i = #lines + 1, #numberTexts do numberTexts[i]:Hide() end
    numbersContent:SetHeight(y + 10)
    exportBtn:SetFlat(ns.db.theme == "modern")
end

ns.AddStatsPage("rolls", rollsPage, DrawRolls)
ns.AddStatsPage("numbers", numbersPage, DrawNumbers)
