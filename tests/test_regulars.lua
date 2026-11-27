-- Regulars: for each player you run with, their loot and yours over the
-- same runs, rebuilt once from the kept runs when the update arrives.
Include("test_run.lua")
print("\n==== regulars: their loot and yours ====")
local ns = NS
local db = ThatLuckyBastardDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t:find(text, 1, true) then return true end
    end
    return false
end
local function tipHas(text)
    for _, line in ipairs(TIP) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-- What the kept runs say: each player's loot, and yours in the same runs.
local function expected()
    local out = {}
    for _, s in ipairs(db.history) do
        local sum = ns.Summarize(s)
        local me, mine = ns.Me(s), 0
        for _, p in ipairs(sum.players) do
            if p.name == me then mine = p.market end
        end
        for _, p in ipairs(sum.players) do
            if p.name ~= me then
                local t = out[p.name] or { runs = 0, value = 0, mine = 0 }
                out[p.name] = t
                t.runs, t.value, t.mine = t.runs + 1, t.value + p.market, t.mine + mine
            end
        end
    end
    return out
end
local function matches(want)
    for name, t in pairs(want) do
        local who = db.people[name]
        if not (who and who.runs == t.runs and math.abs(who.value - t.value) < 1
                and who.mine and math.abs(who.mine - t.mine) < 1) then
            return false, name
        end
    end
    return next(want) ~= nil
end

print("-- each run")
local ok, who = matches(expected())
check(ok, "a run adds each player's loot and yours beside it (" .. tostring(who or "all match") .. ")")

print("-- the update arrives")
-- Each player's award counts, as text, to compare.
local function Counts(who)
    local keys = {}
    for key, n in pairs(who.awards or {}) do keys[#keys + 1] = key .. "=" .. n end
    table.sort(keys)
    return table.concat(keys, " ")
end
local before = {}
for name, w in pairs(db.people) do
    before[name] = Counts(w)
    w.mine = nil -- as an older version left it
end
local someone = next(expected())
db.people[someone].value = 1
db.people["Old Pal"] = { runs = 4, value = 100000, awards = { lucky = 1 }, last = NOW, class = "MAGE" }
db.regularsBoth = nil
Fire("PLAYER_LOGIN")
ok, who = matches(expected())
check(ok, "both totals are rebuilt from the kept runs (" .. tostring(who or "all match") .. ")")
local same = next(before) ~= nil
for name, counts in pairs(before) do
    if Counts(db.people[name]) ~= counts then same = false end
end
check(same, "award counts stay as they were")
local pal = db.people["Old Pal"]
check(pal.mine == nil and pal.runs == 4 and pal.value == 100000 and pal.awards.lucky == 1,
      "a player whose runs are all gone keeps their figures, with yours unknown")
db.people[someone].value = 7
Fire("PLAYER_LOGIN")
check(db.people[someone].value == 7, "the rebuild happens once")
db.people[someone].value = expected()[someone].value

print("-- where it shows")
TEXTLOG = {}
ns.ShowBrowse("regulars")
check(drew("Theirs") and drew("Yours") and drew("Difference") and drew("Old Pal"),
      "Statistics > Regulars: Theirs, Yours and Difference")
db.options.useColumns = true
WORLD.inInstance = false
ns.ShowRun(db.history[1])
-- The hover area over a column's picture and name (a button: the bench's
-- cards, which also hold a player, are frames).
local hover
for _, w in ipairs(FRAMES) do
    local p = rawget(w, "p")
    if not hover and w.__kind == "Button" and type(p) == "table" and p.name == someone and w.__scripts.OnEnter then
        hover = w
    end
end
TIP = {}
hover.__scripts.OnEnter(hover)
check(tipHas("Runs together") and tipHas("Their loot: ") and tipHas("Yours: "),
      "a player's tooltip in the window gives both totals")
local real = db.people[someone].awards
db.people[someone].awards = { hoarder = 3, jackpot = 2, ninja = 1, afk = 1 }
TIP = {}
hover.__scripts.OnEnter(hover)
check(tipHas("Awards: Hoarder x3, Jackpot x2, AFK x1") and not tipHas("Ninja x1"),
      "and the three awards they had most often, the most frequent first")
db.people[someone].awards = real

print("-- every award counts alike")
-- What the kept runs say: how many times each player had each award.
local function Tally()
    local out = {}
    for _, s in ipairs(db.history) do
        for name, a in pairs(ns.Awards(s, ns.Summarize(s))) do
            if name ~= ns.Me(s) then
                out[name] = out[name] or {}
                out[name][a.key] = (out[name][a.key] or 0) + 1
            end
        end
    end
    return out
end
local function Agrees(want, except)
    if next(want) == nil then return false end
    for name, keys in pairs(want) do
        for key, n in pairs(keys) do
            local expect = except and except(name, key, n) or n
            if ((db.people[name] or {}).awards or {})[key] ~= expect then return false, name .. " " .. key end
        end
    end
    return true
end
local want = Tally()
local agrees, which = Agrees(want)
check(agrees, "each run closed adds every player's award to their count, whichever it is (" .. tostring(which or "all") .. ")")
-- The update that counts every award alike: the kept runs are counted
-- again, once. Old Ninja and Luckiest counts covered deleted runs too.
local first = next(want)
for _, w in pairs(db.people) do w.awards, w.lastAward = nil, nil end
db.people[first].ninja, db.people[first].lucky = 5, 0
db.people["Old Pal"].lucky = 2
db.awardsCounted = nil
Fire("PLAYER_LOGIN")
agrees, which = Agrees(want, function(name, key, n) return (name == first and key == "ninja") and math.max(n, 5) or n end)
check(agrees and db.people[first].awards.ninja == math.max(want[first].ninja or 0, 5),
      "counted again from the kept runs, an old Ninja count kept where it is the higher (" .. tostring(which or "all") .. ")")
check(db.people[first].ninja == nil and db.people[first].lucky == nil and db.people[first].awards.lucky == (want[first].lucky),
      "the old Ninja and Luckiest counts are gone, folded in with the rest")
check(db.people["Old Pal"].awards.lucky == 2, "a player whose runs are all gone keeps an old Luckiest count, as an award like any other")
local kept = db.people[first].awards.ninja
db.people[first].awards.ninja = 99
Fire("PLAYER_LOGIN")
check(db.people[first].awards.ninja == 99, "the count is made once")
db.people[first].awards.ninja = kept
-- Where it shows: the player's own tooltip, and Regulars.
TIP = {}
local realGetUnit = GameTooltip.GetUnit
function GameTooltip:GetUnit() return first, "party1" end
local realName = GetUnitName
GetUnitName = function(unit, ...) if unit == "party1" then return first end return realName(unit, ...) end
TOOLTIP_HOOKS[Enum.TooltipDataType.Unit](GameTooltip, {})
GameTooltip.GetUnit, GetUnitName = realGetUnit, realName
local top = ns.TopAwards(db.people[first], 1)[1]
check(#TIP == 1 and TIP[1]:find(("   %s x%d"):format(top.title, top.count), 1, true) ~= nil
      and select(2, TIP[1]:gsub(" x%d", "")) == 1,
      "the player's tooltip names the one award they had most often: " .. tostring(TIP[1]))
TEXTLOG = {}
ns.ShowBrowse("regulars")
local function exact(text)
    for _, x in ipairs(TEXTLOG) do
        if x == text then return true end
    end
    return false
end
check(exact("Most often") and drew(("%s x%d"):format(top.title, top.count)) and not exact("Luckiest") and not exact("Ninja"),
      "Regulars has a Most often column in place of Luckiest and Ninja")
check(drew("Luckiest x2"), "where an old Luckiest count shows like any award")
local tied = { awards = { hoarder = 2, jackpot = 2, ninja = 1 }, lastAward = "jackpot" }
check(ns.AwardsText(tied, 3) == "Jackpot x2, Hoarder x2, Ninja x1", "on a tie, the one they had last comes first")
tied.lastAward = "ninja"
check(ns.AwardsText(tied, 2) == "Hoarder x2, Jackpot x2", "then by title: " .. ns.AwardsText(tied, 2))

print("-- a player whose old runs are gone comes back")
WORLD.party = { { "Old Pal", "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9101, "Pal Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
Loot(("%s receives loot: %s."):format("Old Pal", ItemLink(101, "Blue Thing", 3)))
Loot(("You receive loot: %s."):format(ItemLink(100, "Green Gloves", 2)))
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
SlashCmdList.THATLUCKYBASTARD("stop")
pal = db.people["Old Pal"]
check(pal.runs == 1 and pal.value > 0 and pal.value < 100000 and pal.mine and pal.mine > 0,
      "both totals start again from this run, so they cover the same runs")

print("-- a farm together counts apart")
local value = pal.value
NOW = NOW + 600
SlashCmdList.THATLUCKYBASTARD("start")
Fire("GROUP_ROSTER_UPDATE")
Loot(("%s receives loot: %s."):format("Old Pal", ItemLink(101, "Blue Thing", 3)))
NOW = NOW + 300
SlashCmdList.THATLUCKYBASTARD("stop")
check(pal.farms == 1 and pal.runs == 1 and pal.value == value and pal.last == db.history[1].startedAt,
      "a farm adds to their farms, not to their runs or loot, and is the last time you met")
TEXTLOG = {}
ns.ShowBrowse("regulars")
check(drew("Farms"), "Regulars has a Farms column")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (regulars)")
