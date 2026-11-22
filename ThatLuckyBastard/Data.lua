local _, ns = ...

-- Figures worked out from recorded runs, for the statistics panel, the
-- run windows and the tooltips. Nothing here draws anything.
--
-- Two kinds of figures:
--   * about one run, worked out when asked for: timeline, roll sheet,
--     luck, fairness, loot by source, streak, today's prices, export;
--   * long-term ones, added up once per run when it is closed
--     (CommitStats), because old runs are trimmed from the history:
--     time and fairness per dungeon (in db.records), drops per dungeon
--     (db.drops), shares by role and class (db.roles, db.classes), and
--     roll luck (db.me for you, db.people for the others).

local BOSS_WINDOW = 90   -- seconds after a boss kill during which loot counts as boss loot
local STREAK_GAP = 1800  -- seconds: a run starting later than this after the one before is not "in a row"
local SAME_GROUP = 0.6   -- of the smaller group must be the same people for "the same group"...
local SAME_GROUP_MIN = 2 -- ...and never fewer than this many, unless that is the whole group (a duo)
local MIN_ROLE_GROUP = 3 -- players needed before a run counts towards shares by role and class
ns.BOSS_WINDOW, ns.STREAK_GAP = BOSS_WINDOW, STREAK_GAP
local CHOICES = { n = "need", g = "greed", p = "pass" }
local CHOICE_ORDER = { need = 1, greed = 2, pass = 3 }

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Is this item counted in the totals, given the category options? (An
-- item in a hidden category is, when "count hidden categories" is on.)
local function Counted(e)
    local o = ns.db.options
    return e.count > 0 and (o.cats[e.cat] ~= false or o.countHidden)
end

-- Every real run, newest first: the one in progress, then the history.
function ns.AllRuns()
    local runs = {}
    if ns.db.active then runs[1] = ns.db.active end
    for _, s in ipairs(ns.db.history) do runs[#runs + 1] = s end
    return runs
end

function ns.Ordinal(n)
    local last, lastTwo = n % 10, n % 100
    if last == 1 and lastTwo ~= 11 then return n .. "st" end
    if last == 2 and lastTwo ~= 12 then return n .. "nd" end
    if last == 3 and lastTwo ~= 13 then return n .. "rd" end
    return n .. "th"
end

----------------------------------------------------------------------
-- Pickups: the run's log, decoded
----------------------------------------------------------------------

-- Returns the pickups in order, as { t = seconds since the start, name,
-- e = item entry, count, value }, or nil for a run recorded without a
-- log. Items that the options leave out of the totals are left out here.
local function Pickups(s)
    if not s.log or not s.names then return end
    local byId = {}
    for name, p in pairs(s.players) do
        local map = {}
        for _, e in pairs(p.items) do
            if e.id then map[e.id] = e end
        end
        byId[name] = map
    end
    local out = {}
    for _, text in ipairs(s.log) do
        local t, who, id, count = text:match("^(%d+):(%d+):(%d+):(%d+)$")
        local name = who and s.names[tonumber(who)]
        local e = name and byId[name] and byId[name][tonumber(id)]
        if e and Counted(e) then
            count = tonumber(count)
            ns.MarkPrice(s, e)
            out[#out + 1] = { t = tonumber(t), name = name, e = e, count = count,
                              value = ns.EntryMarket(e) / e.count * count }
        end
    end
    return out
end
ns.Pickups = Pickups -- for the awards

-- Where a pickup came from: "mats" for profession materials; of the rest,
-- "boss" when picked up shortly after a boss kill (then also which boss:
-- its place in s.bosses), else "trash". That is a rule of thumb, not a
-- fact from the game.
function ns.PickupSource(s, pick)
    if pick.e.cat == "prof" then return "mats" end
    for i, boss in ipairs(s.bosses or {}) do
        if boss.t and pick.t >= boss.t and pick.t - boss.t <= BOSS_WINDOW then return "boss", i end
    end
    return "trash"
end

-- Each player's running total through the run, for the chart. Returns
--   { series = { { name, class, total, points = { { t, v }, ... } }, ... },
--     duration, max, bosses = { { t, name }, ... } }
-- with the series ordered richest first, or nil when there is no log.
function ns.Timeline(s)
    local pickups = Pickups(s)
    if not pickups or #pickups == 0 then return end
    local byName, series = {}, {}
    local last = 0
    for _, pick in ipairs(pickups) do
        local line = byName[pick.name]
        if not line then
            line = { name = pick.name, class = s.players[pick.name].class, total = 0, points = {} }
            byName[pick.name] = line
            series[#series + 1] = line
        end
        line.total = line.total + pick.value
        line.points[#line.points + 1] = { t = pick.t, v = line.total }
        if pick.t > last then last = pick.t end
    end
    table.sort(series, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    local bosses = {}
    for _, boss in ipairs(s.bosses or {}) do
        if boss.t then bosses[#bosses + 1] = boss end -- early versions did not time them
    end
    return {
        series = series,
        duration = math.max(ns.RunDuration(s) or 0, last, 1),
        max = math.max(series[1].total, 1),
        bosses = bosses,
    }
end

-- The run's loot by where it came from (see ns.PickupSource): { boss,
-- mats, trash, total }, in copper, or nil when there is no log.
function ns.Sources(s)
    local pickups = Pickups(s)
    if not pickups or #pickups == 0 then return end
    local out = { boss = 0, mats = 0, trash = 0, total = 0 }
    for _, pick in ipairs(pickups) do
        local source = ns.PickupSource(s, pick)
        out[source] = out[source] + pick.value
        out.total = out.total + pick.value
    end
    return out
end

----------------------------------------------------------------------
-- Rolls: the run's roll log, decoded
----------------------------------------------------------------------

-- Returns every roll that was won, in order:
--   { key = item key, t, winner, method = "need" or "greed",
--     rolls = { { name, choice = "need" / "greed" / "pass", roll }, ... } }
-- with the rolls ordered Need, Greed, pass, and highest number first.
function ns.RunRolls(s)
    local out = {}
    if not s.rollLog or not s.names then return out end
    for _, rec in ipairs(s.rollLog) do
        local roll = { key = rec.k, t = rec.t or 0, winner = s.names[rec.w],
                       method = rec.m == "n" and "need" or "greed", rolls = {} }
        for who, code, num in (rec.r or ""):gmatch("(%d+)(%a)(%d*)") do
            local name = s.names[tonumber(who)]
            if name and CHOICES[code] then
                roll.rolls[#roll.rolls + 1] = { name = name, choice = CHOICES[code], roll = tonumber(num) }
            end
        end
        table.sort(roll.rolls, function(a, b)
            if a.choice ~= b.choice then return CHOICE_ORDER[a.choice] < CHOICE_ORDER[b.choice] end
            if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
            return a.name < b.name
        end)
        if roll.winner then out[#out + 1] = roll end
    end
    return out
end

-- The item entry a roll was about: the winner's, or anyone's copy of the
-- same item when the winner's pickup was not seen. May be nil.
function ns.RollItem(s, roll)
    local winner = s.players[roll.winner]
    for _, e in pairs(winner and winner.items or {}) do
        if ns.ItemKey(e) == roll.key then return e end
    end
    for _, p in pairs(s.players) do
        for _, e in pairs(p.items) do
            if ns.ItemKey(e) == roll.key then return e end
        end
    end
end

-- Roll luck in one run: for every roll a player entered, their chance
-- was one in the number of players who could win it (those who chose
-- Need when anyone did, everyone who chose Greed otherwise). Adding the
-- chances up gives the wins they could expect. Returns
--   [name] = { rolls, expected, wins }
function ns.RunLuck(s)
    local out = {}
    local function row(name)
        local r = out[name]
        if not r then
            r = { rolls = 0, expected = 0, wins = 0 }
            out[name] = r
        end
        return r
    end
    for _, roll in ipairs(ns.RunRolls(s)) do
        local needers, entered = 0, 0
        for _, r in ipairs(roll.rolls) do
            if r.choice == "need" then needers = needers + 1 end
            if r.choice ~= "pass" then entered = entered + 1 end
        end
        for _, r in ipairs(roll.rolls) do
            if r.choice ~= "pass" then
                local theirs = row(r.name)
                theirs.rolls = theirs.rolls + 1
                local inRace = needers == 0 or r.choice == "need"
                theirs.expected = theirs.expected + (inRace and 1 / (needers > 0 and needers or entered) or 0)
                if r.name == roll.winner then theirs.wins = theirs.wins + 1 end
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Fairness
----------------------------------------------------------------------

-- How evenly a run's loot was split, from 0 (one player took everything)
-- to 100 (everyone got the same). It is the Gini coefficient, a standard
-- measure of inequality, turned upside down. Nil for fewer than two
-- players or a run with nothing of value.
function ns.Fairness(sum)
    local n = #sum.players
    if n < 2 or sum.market <= 0 then return end
    local spread = 0
    for _, a in ipairs(sum.players) do
        for _, b in ipairs(sum.players) do
            spread = spread + math.abs(a.market - b.market)
        end
    end
    local gini = spread / (2 * n * sum.market)   -- 0 .. (n - 1) / n
    return math.floor(100 * (1 - gini * n / (n - 1)) + 0.5)
end

----------------------------------------------------------------------
-- Today's prices
----------------------------------------------------------------------

-- A run valued at the auction prices of today, against the prices
-- recorded when it was looted. Returns { was, now, mover = { link, was,
-- now } } (mover: the item whose total changed most; may be absent), or
-- nil when no auction prices are in use.
function ns.Reprice(s)
    if ns.db.options.valueMode == "vendor" or not ns.HasPriceSource() then return end
    local out = { was = 0, now = 0 }
    local biggest = 0
    for _, p in pairs(s.players) do
        for _, e in pairs(p.items) do
            if Counted(e) and not e.ignored then
                ns.MarkPrice(s, e)
                local was = ns.EntryRecorded(e)
                local unit = e.vendor
                if ns.CanAuction(e) and not e.noAH then
                    -- No price today says nothing: the recorded one stands.
                    unit = ns.TodaysPrice(e.link) or e.ah or e.vendor
                end
                local now = unit * e.count
                out.was, out.now = out.was + was, out.now + now
                if math.abs(now - was) > biggest then
                    biggest = math.abs(now - was)
                    out.mover = { link = e.link, was = was, now = now }
                end
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Streaks: runs in a row with the same group or in the same dungeon
----------------------------------------------------------------------

-- The other players of a run, as a set, and how many they are.
local function Others(s)
    local set, n = {}, 0
    local me = ns.Me(s)
    for name in pairs(s.players) do
        if name ~= me then
            set[name] = true
            n = n + 1
        end
    end
    return set, n
end

-- Mostly the same people (see SAME_GROUP at the top of the file). A run
-- played alone is with no group.
local function SameGroup(a, b)
    local setA, nA = Others(a)
    local setB, nB = Others(b)
    local smaller = math.min(nA, nB)
    if smaller == 0 then return false end
    local shared = 0
    for name in pairs(setA) do
        if setB[name] then shared = shared + 1 end
    end
    return shared >= math.min(smaller, math.max(SAME_GROUP_MIN, math.ceil(smaller * SAME_GROUP)))
end

local function EndOf(s)
    return s.endedAt or s.leftAt or s.lastSeen or s.startedAt or 0
end

-- The streak a run belongs to, looking back from it: earlier runs, each
-- followed within STREAK_GAP of its end by the next, that were all with
-- the same group as this run, or all in the same dungeon. Returns
-- nil for a run on its own, otherwise
--   { runs = { this run, the one before, ... }, count, kind = "group",
--     "dungeon" or "both", total, mine, duration,
--     standings = { { name, class, value, runs }, ... } richest first }
function ns.Streak(s)
    if s.example or not s.startedAt then return end
    local all = ns.AllRuns()
    local index
    for i, run in ipairs(all) do
        if run == s then index = i end
    end
    if not index then return end

    local chain = { s }
    local group, dungeon = true, true
    for i = index + 1, #all do
        local older, newer = all[i], chain[#chain]
        if not older.startedAt or newer.startedAt - EndOf(older) > STREAK_GAP then break end
        local g = group and SameGroup(s, older)
        local d = dungeon and s.instanceID ~= nil and s.instanceID == older.instanceID
        if not (g or d) then break end
        group, dungeon = g, d
        chain[#chain + 1] = older
    end
    if #chain < 2 then return end

    local out = { runs = chain, count = #chain, total = 0, mine = 0, duration = 0, standings = {},
                  kind = (group and dungeon and "both") or (group and "group") or "dungeon" }
    local byName = {}
    for _, run in ipairs(chain) do
        local sum = ns.Summarize(run)
        out.total = out.total + sum.market
        out.duration = out.duration + (ns.RunDuration(run) or 0)
        for _, p in ipairs(sum.players) do
            local row = byName[p.name]
            if not row then
                row = { name = p.name, class = p.class, value = 0, runs = 0 }
                byName[p.name] = row
                out.standings[#out.standings + 1] = row
            end
            row.value, row.runs = row.value + p.market, row.runs + 1
            row.class = row.class or p.class
            if p.name == ns.Me(run) then out.mine = out.mine + p.market end
        end
    end
    table.sort(out.standings, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    return out
end

-- "3rd run in a row with this group"
function ns.StreakLabel(streak)
    local where = streak.runs[1].name or "this dungeon"
    local tail = "with this group"
    if streak.kind == "dungeon" then
        tail = "in " .. where
    elseif streak.kind == "both" then
        tail = "in " .. where .. " with this group"
    end
    return ns.Ordinal(streak.count) .. " run in a row " .. tail
end

-- On-screen notice when a run that extends a streak ends.
function ns.StreakNotice(s)
    if not ns.db.options.streak or not ns.Notice then return end
    local streak = ns.Streak(s)
    if not streak then return end
    local parts = {}
    for i = 1, math.min(3, #streak.standings) do
        local row = streak.standings[i]
        parts[i] = ns.DisplayName(row.name) .. " " .. ns.Money(row.value)
    end
    ns.Notice(ns.StreakLabel(streak), "So far:  " .. table.concat(parts, "   "),
              "Interface\\Icons\\INV_Misc_PocketWatch_01")
end

----------------------------------------------------------------------
-- Long-term figures, added up once per run
----------------------------------------------------------------------

local function Bump(tbl, key, value)
    local row = tbl[key]
    if not row then
        row = { n = 0, rel = 0 }
        tbl[key] = row
    end
    row.n, row.rel = row.n + 1, row.rel + value
end

-- Called when a run is closed, after its dungeon records were updated.
-- `sum` is a full summary of the run.
function ns.CommitStats(s, sum)
    if s.statted or s.example then return end
    s.statted = true
    local db = ns.db
    local n = #sum.players

    -- Time, hourly figures and fairness per dungeon. The hourly figures
    -- have their own sums, so that runs recorded before they existed do
    -- not skew them.
    local me = ns.Me(s)
    local rec = s.instanceID and db.records[s.instanceID]
    if rec then
        local duration = ns.RunDuration(s)
        if duration and duration >= ns.MIN_TIMED_RUN then
            local mine = 0
            for _, p in ipairs(sum.players) do
                if p.name == me then mine = p.market end
            end
            rec.tRuns = (rec.tRuns or 0) + 1
            rec.tTime = (rec.tTime or 0) + duration
            rec.tGroup = (rec.tGroup or 0) + sum.market
            rec.tMine = (rec.tMine or 0) + mine
        end
        local fair = ns.Fairness(sum)
        if fair then
            rec.fairRuns = (rec.fairRuns or 0) + 1
            rec.fairSum = (rec.fairSum or 0) + fair
        end
    end

    -- Shares by role and class, each measured against an equal share.
    if n >= MIN_ROLE_GROUP and sum.market > 0 then
        local equal = sum.market / n
        for _, p in ipairs(sum.players) do
            Bump(db.roles, p.role or "NONE", p.market / equal)
            if p.class then Bump(db.classes, p.class, p.market / equal) end
        end
    end

    -- Drops per dungeon: in how many runs an item was seen, how many of
    -- it, what it was worth, and who got it last. The worth is the price
    -- recorded at the time (auction if known, else vendor; vendor for
    -- junk), whatever the pricing options say today: it is kept for good.
    if s.instanceID then
        local drops = db.drops[s.instanceID]
        if not drops then
            drops = {}
            db.drops[s.instanceID] = drops
        end
        db.dropRuns[s.instanceID] = (db.dropRuns[s.instanceID] or 0) + 1
        local seen = {}
        for name, p in pairs(s.players) do
            for _, e in pairs(p.items) do
                if e.count > 0 then
                    local id = ns.ItemKey(e)
                    local d = drops[id]
                    if not d then
                        d = { n = 0, c = 0, v = 0 }
                        drops[id] = d
                    end
                    if not seen[id] then
                        seen[id] = true
                        d.n = d.n + 1
                    end
                    d.c = d.c + e.count
                    local unit = ns.VendorByDefault(e) and e.vendor or e.ah or e.vendor or 0
                    d.v = d.v + unit * e.count
                    d.name, d.q = ns.ItemName(e), ns.Quality(e)
                    local at = e.lastAt or s.startedAt or 0
                    if not d.at or at >= d.at then d.at, d.by = at, name end
                end
            end
        end
    end

    -- Roll luck, for you and for the people you run with.
    local function account(name)
        if name == me then return db.me end
        return db.people[name]
    end
    for name, luck in pairs(ns.RunLuck(s)) do
        local who = account(name)
        if who then
            who.rolls = (who.rolls or 0) + luck.rolls
            who.expected = (who.expected or 0) + luck.expected
            who.wins = (who.wins or 0) + luck.wins
        end
    end
    for name, st in pairs(s.rollStats or {}) do
        local who = account(name)
        if who and (st.n or 0) > 0 then
            who.rollSum = (who.rollSum or 0) + st.sum
            who.rollN = (who.rollN or 0) + st.n
        end
    end
end

-- For the item tooltip: in how many of your runs an item was seen, over
-- every dungeon, and who got it last. Returns runs, name; or nothing.
function ns.ItemSeen(id)
    local key = tostring(id)
    local runs, at, by = 0, -1, nil
    for _, drops in pairs(ns.db.drops) do
        local d = drops[key]
        if d then
            runs = runs + d.n
            if (d.at or 0) > at then at, by = d.at or 0, d.by end
        end
    end
    if runs > 0 then return runs, by end
end

----------------------------------------------------------------------
-- Export, as comma-separated text for a spreadsheet
----------------------------------------------------------------------

local function Csv(...)
    local fields = { ... }
    for i = 1, select("#", ...) do
        local text = tostring(fields[i] == nil and "" or fields[i])
        if text:find('[,"\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
        fields[i] = text
    end
    return table.concat(fields, ",")
end

-- Copper as gold with decimals: 123456 -> "12.3456"
local function Gold(copper)
    return ("%.4f"):format((copper or 0) / 10000)
end

local function RunDate(s)
    return s.startedAt and ns.DateText(s.startedAt) or ""
end

-- One line per player and item of a run.
function ns.ExportRun(s)
    local lines = { Csv("Date", "Dungeon", "Player", "Class", "Role", "Item", "Item ID", "Count",
                        "Unit value (gold)", "Total (gold)", "Vendor total (gold)", "Category",
                        "Won on Need", "Won on Greed", "Note") }
    -- Every item that counts towards the totals, so that the lines add up
    -- to them: that includes hidden categories when those are counted, and
    -- each player's share of a split item.
    local sum = ns.Summarize(s)
    for _, p in ipairs(sum.players) do
        local items = {}
        for _, e in ipairs(p.held) do items[#items + 1] = e end
        table.sort(items, function(a, b)
            local va, vb = ns.EntryMarket(a), ns.EntryMarket(b)
            if va ~= vb then return va > vb end
            return a.link < b.link
        end)
        for _, e in ipairs(items) do
            local total = ns.EntryMarket(e)
            local note = (e.ignored and "Ignored") or (e.away and "Given away")
                or ((e.ways or 1) > 1 and ("Split %d ways"):format(e.ways)) or (e.from and ("Given by " .. e.from))
            lines[#lines + 1] = Csv(RunDate(s), s.name, p.name, p.class, p.role, ns.ItemName(e), ns.ItemKey(e),
                                    e.count, Gold(total / e.count), Gold(total), Gold(ns.EntryVendor(e)),
                                    e.cat, e.from and 0 or e.need or 0, e.from and 0 or e.greed or 0, note)
        end
        if p.money > 0 then
            lines[#lines + 1] = Csv(RunDate(s), s.name, p.name, p.class, p.role, "Coins", "", "", "",
                                    Gold(p.money), Gold(p.money), "coins", 0, 0)
        end
    end
    return table.concat(lines, "\n")
end

-- One line per player of every run that is kept.
function ns.ExportAll()
    local lines = { Csv("Date", "Dungeon", "Minutes", "Players", "Fairness", "Player", "Class", "Role",
                        "Items", "Value (gold)", "Share %", "Won on Need (gold)", "Won on Greed (gold)",
                        "Award") }
    for _, s in ipairs(ns.AllRuns()) do
        local sum = ns.Summarize(s)
        local awards = ns.RunAwards(s, sum)
        local duration = ns.RunDuration(s)
        local fair = ns.Fairness(sum)
        for _, p in ipairs(sum.players) do
            lines[#lines + 1] = Csv(RunDate(s), s.name, duration and math.floor(duration / 60 + 0.5), #sum.players,
                                    fair, p.name, p.class, p.role, p.count, Gold(p.market),
                                    sum.market > 0 and ("%.1f"):format(p.market / sum.market * 100) or "0",
                                    Gold(p.needValue), Gold(p.greedValue),
                                    awards[p.name] and awards[p.name].title)
        end
    end
    return table.concat(lines, "\n")
end
