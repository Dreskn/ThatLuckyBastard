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
local lucky = {}
for name, w in pairs(db.people) do
    lucky[name] = w.lucky
    w.mine = nil -- as an older version left it
end
local someone = next(expected())
db.people[someone].value = 1
db.people["Old Pal"] = { runs = 4, value = 100000, lucky = 1, ninja = 0, last = NOW, class = "MAGE" }
db.regularsBoth = nil
Fire("PLAYER_LOGIN")
ok, who = matches(expected())
check(ok, "both totals are rebuilt from the kept runs (" .. tostring(who or "all match") .. ")")
local same = true
for name, n in pairs(lucky) do
    if db.people[name].lucky ~= n then same = false end
end
check(same, "Luckiest and Ninja counts stay as they were")
local pal = db.people["Old Pal"]
check(pal.mine == nil and pal.runs == 4 and pal.value == 100000 and pal.lucky == 1,
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

print("-- a player whose old runs are gone comes back")
WORLD.party = { { "Old Pal", "MAGE", "DAMAGER" } }
SlashCmdList.THATLUCKYBASTARD("start")
Fire("GROUP_ROSTER_UPDATE")
Loot(("%s receives loot: %s."):format("Old Pal", ItemLink(101, "Blue Thing", 3)))
Loot(("You receive loot: %s."):format(ItemLink(100, "Green Gloves", 2)))
SlashCmdList.THATLUCKYBASTARD("stop")
pal = db.people["Old Pal"]
check(pal.runs == 1 and pal.value > 0 and pal.value < 100000 and pal.mine and pal.mine > 0,
      "both totals start again from this run, so they cover the same runs")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (regulars)")
