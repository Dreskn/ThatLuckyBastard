local _, ns = ...

-- Loot bingo: a private game played during a run. Each run deals a 4x4
-- card of things that might happen ("a blue item drops", "someone
-- passes", "you die"), and squares tick themselves off as the run goes.
-- The player bets on one line of it, a row, a column or a diagonal. A
-- line can be picked as long as none of its squares is ticked; the pick
-- is for good, and the line wins if it fills before the run is over.
--
-- The card is stored with the run as
--   s.bingo = { keys = { 16 square keys }, done = { [key] = true },
--               pick = the line picked (its place in LINES), won = true,
--               solo = true for a card dealt to a player on their own }
-- A square that has been ticked stays ticked. db.bingo counts the lines
-- picked and the lines won, over all runs.

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

-- A run with someone else in it. Squares about the group, and all the
-- roll squares, cannot be ticked alone and are not dealt then.
local function InGroup(s)
    return next(s.players, (next(s.players))) ~= nil
end

local SQUARES = {
    { key = "green",    text = "A green BoE drops",        check = function(c) return c.greens >= 1 end },
    { key = "greens3",  text = "3 green BoEs drop",        check = function(c) return c.greens >= 3 end },
    { key = "blue",     text = "A blue item drops",        check = function(c) return c.quality[3] == true end },
    { key = "epic",     text = "An epic drops",            check = function(c) return c.quality[4] == true end },
    { key = "quest",    text = "A quest item drops",       check = function(c) return c.quest >= 1 end },
    { key = "junk10",   text = "10 greys looted",          check = function(c) return c.junk >= 10 end },
    { key = "junk5",    text = "One player: 5 greys",      check = function(c) return c.junkOne >= 5 end },
    { key = "mats20",   text = "One player: 20 materials", check = function(c) return c.matsOne >= 20 end },
    { key = "mats50",   text = "50 materials looted",      check = function(c) return c.mats >= 50 end },
    { key = "items100", text = "100 items looted",         check = function(c) return c.items >= 100 end },
    { key = "item1g",   text = "An item worth 1g or more", check = function(c) return c.bestValue >= GOLD end },
    { key = "item10g",  text = "An item worth 10g or more", check = function(c) return c.bestValue >= 10 * GOLD end },
    { key = "total5g",  text = "Group loot reaches 5g",    check = function(c) return c.sum.market >= 5 * GOLD end },
    { key = "total25g", text = "Group loot reaches 25g",   check = function(c) return c.sum.market >= 25 * GOLD end },
    { key = "everyone", text = "Everyone loots something", available = InGroup,
      check = function(c) return c.n >= 2 and c.looters == c.n end },
    { key = "shared",   text = "An item everyone got",     available = InGroup,
      check = function(c) return c.shared end },
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
    { key = "greed3",   rolls = true, text = "3 Greed wins",          check = function(c) return c.greedWins >= 3 end },
    { key = "pass",     rolls = true, text = "Someone passes",         check = function(c) return c.passes >= 1 end },
    { key = "high",     rolls = true, text = ("A roll of %d or more"):format(ns.HIGH_ROLL),
      check = function(c) return c.s.rollHigh == true end },
    { key = "low",      rolls = true, text = ("A roll of %d or less"):format(ns.LOW_ROLL),
      check = function(c) return c.s.rollLow == true end },
}

local BY_KEY = {}
for _, square in ipairs(SQUARES) do BY_KEY[square.key] = square end

-- Everything the squares look at, gathered once per check.
local function Context(s)
    local sum = ns.Summarize(s)
    local me = ns.Me(s)
    local c = {
        s = s, sum = sum, n = 0, items = 0,
        junk = 0, junkOne = 0, mats = 0, matsOne = 0, greens = 0, quest = 0,
        quality = {}, bestValue = 0, looters = 0,
        needWins = 0, greedWins = 0, winsOne = 0, passes = 0,
        myItems = 0, myWins = 0,
        kills = s.kills or 0, deaths = s.myDeaths or 0,
        duration = ns.RunDuration(s) or 0,
    }
    -- What was looted is counted from the run itself, not from the summary:
    -- a category hidden in the options must still tick its squares.
    local holders = {} -- [item key] = how many players have it
    for name, p in pairs(s.players) do
        local count, junk, mats, mine = 0, 0, 0, {}
        for _, e in pairs(p.items) do
            if e.count > 0 then
                count = count + e.count
                if e.cat == "junk" then
                    junk = junk + e.count
                elseif e.cat == "prof" then
                    mats = mats + e.count
                elseif e.cat == "uncommon" then
                    c.greens = c.greens + e.count
                elseif e.cat == "quest" then
                    c.quest = c.quest + e.count
                end
                c.quality[ns.Quality(e)] = true
                mine[ns.ItemKey(e)] = true
            end
        end
        c.n, c.items = c.n + 1, c.items + count
        c.junk, c.junkOne = c.junk + junk, math.max(c.junkOne, junk)
        c.mats, c.matsOne = c.mats + mats, math.max(c.matsOne, mats)
        if count > 0 then c.looters = c.looters + 1 end
        if name == me then c.myItems = count end
        for key in pairs(mine) do holders[key] = (holders[key] or 0) + 1 end
    end
    -- Values and roll wins are taken as the window shows them.
    for _, p in ipairs(sum.players) do
        local wins = p.needWins + p.greedWins
        c.bestValue = math.max(c.bestValue, p.bestValue)
        c.needWins, c.greedWins = c.needWins + p.needWins, c.greedWins + p.greedWins
        c.winsOne = math.max(c.winsOne, wins)
        if p.name == me then c.myWins = wins end
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
    if InGroup(s) then take(rolls, ROLL_SQUARES) end
    take(plain, SIZE * SIZE - #keys)
    for i = #keys, 2, -1 do -- shuffle
        local j = rand(i)
        keys[i], keys[j] = keys[j], keys[i]
    end
    return { keys = keys, done = {}, solo = not InGroup(s) or nil }
end

-- The lines a player can pick, as lists of cell indexes (1 to 16, left
-- to right, top to bottom): the four rows, then the four columns, then
-- the two diagonals. A card remembers its pick by its place here.
local LINES = {}
do
    local d1, d2 = {}, {}
    for i = 1, SIZE do
        local row, col = {}, {}
        for j = 1, SIZE do
            row[j] = (i - 1) * SIZE + j
            col[j] = (j - 1) * SIZE + i
        end
        LINES[i], LINES[SIZE + i] = row, col
        d1[i] = (i - 1) * SIZE + i
        d2[i] = (i - 1) * SIZE + (SIZE - i + 1)
    end
    LINES[2 * SIZE + 1], LINES[2 * SIZE + 2] = d1, d2
end

-- How many squares of line `n` are ticked.
local function Ticked(card, n)
    local count = 0
    for _, index in ipairs(LINES[n]) do
        if card.done[card.keys[index]] then count = count + 1 end
    end
    return count
end

-- The line a card has picked, when it is one of LINES. A pick this
-- version cannot place (a damaged file, a card of another version)
-- counts as none.
local function Picked(card)
    return LINES[card.pick] and card.pick or nil
end

-- The lines picked and the lines won, over all runs.
local function Tally()
    local db = ns.db
    db.bingo = db.bingo or { picked = 0, won = 0 }
    return db.bingo
end

----------------------------------------------------------------------
-- The card window
----------------------------------------------------------------------

local GRID_W = SIZE * CELL_W + (SIZE - 1) * GAP
local GRID_H = SIZE * CELL_H + (SIZE - 1) * GAP
-- The markers lines are picked with stand around the grid: one at the
-- start of each row, one above each column, one at each top corner for
-- the diagonal that starts there.
local MARK, MARK_ROOM = 12, 22 -- a marker's size, and the room markers take beside the grid
local ICON = "Interface\\Icons\\INV_Misc_Dice_02"

-- Not closed by Escape: the card is meant to stay open during a run. On
-- the same level as the addon's other windows, in front when it opens.
local frame, ui, title, skins = ns.MakeWindow("ThatLuckyBastardBingoFrame", GRID_W + 28 + 2 * MARK_ROOM,
    GRID_H + 140, "HIGH", false)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)

local status = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local grid = CreateFrame("Frame", nil, ui)
grid:SetSize(GRID_W, GRID_H)
local tallyText = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tallyText:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -8)

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

local Draw, Pick
local hovered -- the line whose marker the mouse is on

local marks = {}
for n = 1, #LINES do
    local m = CreateFrame("Button", nil, grid)
    m.mark = n
    m:SetSize(MARK, MARK)
    if n <= SIZE then
        m:SetPoint("RIGHT", cells[(n - 1) * SIZE + 1], "LEFT", -6, 0)
    elseif n <= 2 * SIZE then
        m:SetPoint("BOTTOM", cells[n - SIZE], "TOP", 0, 6)
    elseif n == 2 * SIZE + 1 then
        m:SetPoint("BOTTOMRIGHT", cells[1], "TOPLEFT", -6, 6)
    else
        m:SetPoint("BOTTOMLEFT", cells[SIZE], "TOPRIGHT", 6, 6)
    end
    m.bg = m:CreateTexture(nil, "ARTWORK")
    m.bg:SetAllPoints()
    -- Hovering a marker shows its line on the card; a click picks it.
    m:SetScript("OnEnter", function(self)
        hovered = self.mark
        Draw()
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip)
            GameTooltip:Show()
        end
    end)
    m:SetScript("OnLeave", function()
        hovered = nil
        GameTooltip:Hide()
        Draw()
    end)
    m:SetScript("OnClick", function(self) Pick(self.mark) end)
    marks[n] = m
end

-- The run whose card is on show: the one in progress, else the run on
-- show in the main window.
local function CardRun()
    local s = ns.db.active
    if s then return s end
    s = ns.ViewedRun()
    if s and s.bingo then return s end
end

function Draw()
    local _, top = ns.ApplyWindowTheme(skins, title)
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", 14, top)
    grid:ClearAllPoints()
    grid:SetPoint("TOPLEFT", 14 + MARK_ROOM, top - 20 - MARK_ROOM)
    frame:SetHeight(GRID_H - top + 34 + MARK_ROOM + 18)

    local s = CardRun()
    local card = s and s.bingo
    title:SetText(ns.Title("Loot bingo"))
    local tally = Tally()
    tallyText:SetText(tally.picked > 0 and ("Lines won: %d of %d"):format(tally.won, tally.picked) or "")
    if not card then
        status:SetText("No card yet. One is dealt when a run starts.")
        grid:Hide()
        return
    end
    grid:Show()

    -- A line can be picked on the card of the run in progress, once, and
    -- only while none of its squares is ticked.
    local pick = Picked(card)
    local live = s == ns.db.active and not pick
    local open = 0
    for n, m in ipairs(marks) do
        m.can = live and Ticked(card, n) == 0
        if n == pick then
            m.bg:SetColorTexture(1.00, 0.82, 0.00, 1)
            m.tip = "Your line"
        elseif m.can then
            open = open + 1
            m.bg:SetColorTexture(1.00, 0.82, 0.00, hovered == n and 0.95 or 0.50)
            m.tip = "Pick this line"
        else
            m.bg:SetColorTexture(1, 1, 1, 0.10)
            m.tip = live and "Already started" or nil
        end
    end
    local mine, preview = {}, {}
    for _, index in ipairs(LINES[pick] or {}) do mine[index] = true end
    if hovered and marks[hovered].can then
        for _, index in ipairs(LINES[hovered]) do preview[index] = true end
    end

    for index, cell in ipairs(cells) do
        local key = card.keys[index]
        local square = key and BY_KEY[key]
        local done = key and card.done[key]
        cell.text:SetText(square and square.text or "")
        cell.tick:SetShown(done == true)
        if mine[index] then
            cell.bg:SetColorTexture(1.00, 0.82, 0.00, done and 0.45 or 0.16) -- the line picked
            cell.text:SetTextColor(1, 1, 1)
        elseif done then
            cell.bg:SetColorTexture(0.25, 0.78, 0.40, 0.30)
            cell.text:SetTextColor(1, 1, 1)
        elseif preview[index] then
            cell.bg:SetColorTexture(1, 1, 1, 0.18) -- the line a click would pick
            cell.text:SetTextColor(1, 1, 1)
        else
            cell.bg:SetColorTexture(1, 1, 1, 0.07)
            cell.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end

    local text
    if pick and card.won then
        text = "|cffffd100Bingo!|r"
    elseif pick then
        text = ("your line, %d of %d"):format(Ticked(card, pick), SIZE)
    elseif s ~= ns.db.active then
        text = "no line picked"
    elseif open > 0 then
        text = "pick your line"
    else
        text = "every line has started"
    end
    status:SetText((s.name or "Run") .. ":  " .. text)
end

frame:SetScript("OnShow", Draw)

-- Bets on line `n` of the card of the run in progress.
function Pick(n)
    local s = ns.db.active
    local card = s and s.bingo
    if not card or Picked(card) or not LINES[n] or Ticked(card, n) > 0 then return end
    card.pick = n
    local tally = Tally()
    tally.picked = tally.picked + 1
    ns.PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    if frame:IsShown() then Draw() end
end
ns.BingoPick = Pick

----------------------------------------------------------------------
-- Checking
----------------------------------------------------------------------

-- `quiet`: the card is being opened, which is no time to say it exists.
local function Evaluate(quiet)
    local s = ns.db.active
    if not s then return end
    local dealt = not s.bingo
    -- A card dealt before the group was there has no square that takes a
    -- group. Until a line is picked on it, the group gets a card of its
    -- own: squares tick from what the run holds, so none is lost.
    local late = not dealt and s.bingo.solo and not Picked(s.bingo) and InGroup(s)
    if dealt or late then s.bingo = NewCard(s) end
    local card = s.bingo

    local c = Context(s)
    for _, key in ipairs(card.keys) do
        local square = BY_KEY[key]
        if square and not card.done[key] and square.check(c) then
            card.done[key] = true
        end
    end

    local pick = Picked(card)
    if pick and not card.won and Ticked(card, pick) == SIZE then
        card.won = true
        local tally = Tally()
        tally.won = tally.won + 1
        ns.Notice("|cffffd100BINGO!|r", "Your line is complete.", ICON)
        ns.PlayKit("IG_QUEST_LIST_COMPLETE", 878)
    elseif dealt and not quiet and not frame:IsShown() then
        -- A new card: lines close as their squares tick, so say so now.
        ns.Notice("Loot bingo", "Pick your line: /tlb bingo", ICON)
    end
    if frame:IsShown() then Draw() end
end

-- Called whenever something happened in the run, and when one starts.
-- Checks are grouped: at most one a second.
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
        if ns.db.options.bingo then Evaluate(true) end -- deals the card if the run has none yet
        frame:Show()
        frame:Raise()
    end
end

ns.OnRerender(function()
    if frame:IsShown() then Draw() end
end)
