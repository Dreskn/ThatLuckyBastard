local _, ns = ...

-- Loot bingo: a private game played during a run. Each run deals a 4x4
-- card of things that might happen ("a blue item drops", "someone
-- passes", "you die"). Squares tick themselves off as the run goes, and
-- a completed row, column or diagonal is announced on screen.
--
-- The card is stored with the run as
--   s.bingo = { keys = { 16 square keys }, done = { [key] = true }, lines = n }
-- A square that has been ticked stays ticked.

local SIZE = 4
local CELL_W, CELL_H, GAP = 92, 54, 4
local ROLL_SQUARES = 4 -- how many of the 16 squares are about rolls
local GOLD = 10000     -- copper

----------------------------------------------------------------------
-- Squares. check(c) gets the figures gathered by Context below and must
-- only ever go from false to true as a run progresses.
--   rolls = true   the square is about Need / Greed rolls
--   available(s)   optional: whether the square can be dealt for run s
----------------------------------------------------------------------

local SQUARES = {
    { key = "green",    text = "A green BoE drops",        check = function(c) return c.greens >= 1 end },
    { key = "greens3",  text = "3 green BoEs drop",        check = function(c) return c.greens >= 3 end },
    { key = "blue",     text = "A blue item drops",        check = function(c) return c.bestQuality >= 3 end },
    { key = "epic",     text = "An epic drops",            check = function(c) return c.bestQuality >= 4 end },
    { key = "quest",    text = "A quest item drops",       check = function(c) return c.quest >= 1 end },
    { key = "junk10",   text = "10 greys looted",          check = function(c) return c.junk >= 10 end },
    { key = "junk5",    text = "One player: 5 greys",      check = function(c) return c.junkOne >= 5 end },
    { key = "mats20",   text = "One player: 20 materials", check = function(c) return c.matsOne >= 20 end },
    { key = "mats50",   text = "50 materials looted",      check = function(c) return c.mats >= 50 end },
    { key = "items100", text = "100 items looted",         check = function(c) return c.sum.count >= 100 end },
    { key = "item1g",   text = "An item worth 1g or more", check = function(c) return c.bestValue >= GOLD end },
    { key = "item10g",  text = "An item worth 10g or more", check = function(c) return c.bestValue >= 10 * GOLD end },
    { key = "total5g",  text = "Group loot reaches 5g",    check = function(c) return c.sum.market >= 5 * GOLD end },
    { key = "total25g", text = "Group loot reaches 25g",   check = function(c) return c.sum.market >= 25 * GOLD end },
    { key = "everyone", text = "Everyone loots something", check = function(c) return c.n >= 2 and c.looters == c.n end },
    { key = "shared",   text = "An item everyone got",     check = function(c) return c.shared end },
    { key = "mine10",   text = "You loot 10 items",        check = function(c) return c.myItems >= 10 end },
    { key = "time20",   text = "20 minutes in",            check = function(c) return c.duration >= 1200 end },
    { key = "boss1",    text = "First boss down",          check = function(c) return c.kills >= 1 end },
    { key = "boss3",    text = "3 bosses down",            check = function(c) return c.kills >= 3 end },
    { key = "died",     text = "You die",                  check = function(c) return c.deaths >= 1 end },
    { key = "average",  text = "Beat your average for this dungeon",
      check = function(c) return c.average ~= nil and c.sum.market > c.average end,
      available = function(s)
          local rec = s.instanceID and ns.db.records[s.instanceID]
          return rec ~= nil and rec.runs > 0
      end },

    { key = "needwin",  rolls = true, text = "Someone wins on Need",   check = function(c) return c.needWins >= 1 end },
    { key = "youwin",   rolls = true, text = "You win a roll",         check = function(c) return c.myWins >= 1 end },
    { key = "twowins",  rolls = true, text = "One player wins 2 rolls", check = function(c) return c.winsOne >= 2 end },
    { key = "greed3",   rolls = true, text = "3 Greed wins",           check = function(c) return c.greedWins >= 3 end },
    { key = "pass",     rolls = true, text = "Someone passes",         check = function(c) return c.passes >= 1 end },
    { key = "high",     rolls = true, text = "A roll of 95 or more",   check = function(c) return c.s.rollHigh == true end },
    { key = "low",      rolls = true, text = "A roll of 5 or less",    check = function(c) return c.s.rollLow == true end },
}

local BY_KEY = {}
for _, square in ipairs(SQUARES) do BY_KEY[square.key] = square end

-- Everything the squares look at, gathered once per check.
local function Context(s)
    local sum = ns.Summarize(s)
    local c = {
        s = s, sum = sum, n = #sum.players,
        junk = 0, junkOne = 0, mats = 0, matsOne = 0, greens = 0, quest = 0,
        bestValue = 0, bestQuality = 0, looters = 0,
        needWins = 0, greedWins = 0, winsOne = 0, passes = 0,
        myItems = 0, myWins = 0,
        kills = s.kills or 0, deaths = s.myDeaths or 0,
        duration = ns.RunDuration(s) or 0,
    }
    local holders = {} -- [item key] = how many players have it
    for _, p in ipairs(sum.players) do
        local junk = p.cats.junk and p.cats.junk.count or 0
        local mats = p.cats.prof and p.cats.prof.count or 0
        local wins = p.needWins + p.greedWins
        c.junk, c.junkOne = c.junk + junk, math.max(c.junkOne, junk)
        c.mats, c.matsOne = c.mats + mats, math.max(c.matsOne, mats)
        c.greens = c.greens + (p.cats.uncommon and p.cats.uncommon.count or 0)
        c.quest = c.quest + (p.cats.quest and p.cats.quest.count or 0)
        c.bestValue = math.max(c.bestValue, p.bestValue)
        c.bestQuality = math.max(c.bestQuality, p.bestQuality)
        c.needWins, c.greedWins = c.needWins + p.needWins, c.greedWins + p.greedWins
        c.winsOne = math.max(c.winsOne, wins)
        if p.count > 0 then c.looters = c.looters + 1 end
        if p.name == ns.playerName then c.myItems, c.myWins = p.count, wins end

        local mine = {}
        for _, e in ipairs(p.all.items) do mine[ns.ItemKey(e)] = true end
        for key in pairs(mine) do holders[key] = (holders[key] or 0) + 1 end
    end
    if c.n >= 2 then
        for _, count in pairs(holders) do
            if count == c.n then c.shared = true end
        end
    end
    for _, st in pairs(s.rollStats or {}) do c.passes = c.passes + (st.passes or 0) end

    -- Your average for this dungeon, as it stood before this run.
    local rec = s.instanceID and ns.db.records[s.instanceID]
    if rec and rec.runs > 0 and not s.recorded then c.average = rec.sumGroup / rec.runs end
    return c
end

-- Deals a card. The same run always gets the same card: the shuffle is
-- derived from the run's start time.
local function NewCard(s)
    local seed = (s.startedAt or 1) % 2147483646 + 1
    local function rand(n)
        seed = (seed * 48271) % 2147483647
        return seed % n + 1
    end

    local plain, rolls = {}, {}
    for _, square in ipairs(SQUARES) do
        if not square.available or square.available(s) then
            local pool = square.rolls and rolls or plain
            pool[#pool + 1] = square.key
        end
    end

    local keys = {}
    local function take(pool, count)
        for _ = 1, count do
            if #pool == 0 then return end
            keys[#keys + 1] = table.remove(pool, rand(#pool))
        end
    end
    take(rolls, ROLL_SQUARES)
    take(plain, SIZE * SIZE - #keys)
    for i = #keys, 2, -1 do -- shuffle
        local j = rand(i)
        keys[i], keys[j] = keys[j], keys[i]
    end
    return { keys = keys, done = {}, lines = 0 }
end

-- Every row, column and diagonal, as lists of cell indexes (1 to 16,
-- left to right, top to bottom).
local LINES = {}
do
    local d1, d2 = {}, {}
    for i = 1, SIZE do
        local row, col = {}, {}
        for j = 1, SIZE do
            row[j] = (i - 1) * SIZE + j
            col[j] = (j - 1) * SIZE + i
        end
        LINES[#LINES + 1] = row
        LINES[#LINES + 1] = col
        d1[i] = (i - 1) * SIZE + i
        d2[i] = (i - 1) * SIZE + (SIZE - i + 1)
    end
    LINES[#LINES + 1] = d1
    LINES[#LINES + 1] = d2
end

-- Returns how many lines are complete, and the set of cells in them.
local function CompletedLines(card)
    local count, cells = 0, {}
    for _, line in ipairs(LINES) do
        local full = true
        for _, index in ipairs(line) do
            if not card.done[card.keys[index]] then full = false end
        end
        if full then
            count = count + 1
            for _, index in ipairs(line) do cells[index] = true end
        end
    end
    return count, cells
end

----------------------------------------------------------------------
-- The card window
----------------------------------------------------------------------

local GRID_W = SIZE * CELL_W + (SIZE - 1) * GAP
local GRID_H = SIZE * CELL_H + (SIZE - 1) * GAP

local frame = CreateFrame("Frame", "FairShareBingoFrame", UIParent)
frame:SetSize(GRID_W + 28, GRID_H + 100)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

local skins = ns.BuildSkins(frame, function() frame:Hide() end)

local ui = CreateFrame("Frame", nil, frame)
ui:SetAllPoints()
ui:SetFrameLevel(frame:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local status = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local grid = CreateFrame("Frame", nil, ui)
grid:SetSize(GRID_W, GRID_H)

local cells = {}
for index = 1, SIZE * SIZE do
    local row, col = math.floor((index - 1) / SIZE), (index - 1) % SIZE
    local cell = CreateFrame("Frame", nil, grid)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", col * (CELL_W + GAP), -row * (CELL_H + GAP))
    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints()
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("CENTER")
    cell.text:SetWidth(CELL_W - 8)
    cell.tick = cell:CreateTexture(nil, "OVERLAY")
    cell.tick:SetSize(14, 14)
    cell.tick:SetPoint("TOPRIGHT", -2, -2)
    cell.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    cells[index] = cell
end

-- The run whose card is on show: the one in progress, else the run on
-- show in the main window.
local function CardRun()
    local s = ns.db.active
    if s then return s end
    s = ns.ViewedRun()
    if s and s.bingo then return s end
end

local function Draw()
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
    local top = flat and -46 or -32
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", 14, top)
    grid:ClearAllPoints()
    grid:SetPoint("TOPLEFT", 14, top - 20)
    frame:SetHeight(GRID_H - top + 34)

    local s = CardRun()
    local card = s and s.bingo
    title:SetText(ns.Title("Loot bingo"))
    if not card then
        status:SetText("No card yet. One is dealt when a run starts.")
        grid:Hide()
        return
    end
    grid:Show()

    local lines, inLine = CompletedLines(card)
    local ticked = 0
    for index, cell in ipairs(cells) do
        local key = card.keys[index]
        local square = key and BY_KEY[key]
        local done = key and card.done[key]
        if done then ticked = ticked + 1 end
        cell.text:SetText(square and square.text or "")
        cell.tick:SetShown(done == true)
        if inLine[index] then
            cell.bg:SetColorTexture(1.00, 0.82, 0.00, 0.35) -- part of a completed line
            cell.text:SetTextColor(1, 1, 1)
        elseif done then
            cell.bg:SetColorTexture(0.25, 0.78, 0.40, 0.30)
            cell.text:SetTextColor(1, 1, 1)
        else
            cell.bg:SetColorTexture(1, 1, 1, 0.07)
            cell.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    local where = s.name or "Run"
    if lines > 0 then
        status:SetText(("%s:  %d of %d squares,  |cffffd100%d %s|r"):format(
            where, ticked, SIZE * SIZE, lines, lines == 1 and "line" or "lines"))
    else
        status:SetText(("%s:  %d of %d squares"):format(where, ticked, SIZE * SIZE))
    end
end

frame:SetScript("OnShow", Draw)

----------------------------------------------------------------------
-- Checking
----------------------------------------------------------------------

local function Evaluate()
    local s = ns.db.active
    if not s then return end
    s.bingo = s.bingo or NewCard(s)
    local card = s.bingo

    local c = Context(s)
    for _, key in ipairs(card.keys) do
        local square = BY_KEY[key]
        if square and not card.done[key] and square.check(c) then
            card.done[key] = true
        end
    end

    local lines = CompletedLines(card)
    if lines > card.lines then
        card.lines = lines
        local ticked = 0
        for _ in pairs(card.done) do ticked = ticked + 1 end
        local text
        if ticked >= SIZE * SIZE then
            text = "Full card!"
        elseif lines == 1 then
            text = "You completed a line."
        else
            text = ("%d lines completed."):format(lines)
        end
        ns.Notice("|cffffd100BINGO!|r", text, "Interface\\Icons\\INV_Misc_Dice_02")
        ns.PlayKit("IG_QUEST_LIST_COMPLETE", 878)
    end
    if frame:IsShown() then Draw() end
end

-- Called whenever something happened in the run. Checks are grouped: at
-- most one a second.
local pending = false
function ns.BingoCheck()
    if pending or not ns.db.options.bingo then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        Evaluate()
    end)
end

function ns.ToggleBingo()
    if frame:IsShown() then
        frame:Hide()
    else
        if ns.db.options.bingo then Evaluate() end -- deals the card if the run has none yet
        frame:Show()
    end
end
