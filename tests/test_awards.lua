-- Awards: the moments (odd things the dice did) and the consolation
-- prizes, which go to players nothing else fits.
print("\n==== awards: moments and consolation ====")
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
local ns = NS
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

-- A run built by hand: players, items, a pickup log and a roll log.
local nextId = 30000
local function NewRun(names)
    local s = { name = "Award Keep", startedAt = NOW - 3600, endedAt = NOW - 600, owner = names[1],
                players = {}, names = {}, log = {}, rollLog = {}, bosses = {}, rollStats = {} }
    for i, name in ipairs(names) do
        s.names[i] = name
        s.players[name] = { class = "MAGE", items = {} }
        s.rollStats[name] = { sum = 0, n = 0, passes = 0 }
    end
    return s
end
local function Index(s, name)
    for i, n in ipairs(s.names) do
        if n == name then return i end
    end
end
-- Gives `name` an item, and logs its pickup.
local function Give(s, name, o)
    o = o or {}
    nextId = nextId + 1
    local q = o.quality or 2
    local e = { link = ItemLink(nextId, "Thing " .. nextId, q), id = nextId, count = 1, vendor = o.vendor or 2000,
                ah = o.ah, cat = o.cat or "uncommon", quality = q, resolved = true, need = o.need, greed = o.greed }
    s.players[name].items[ns.ItemKey(e)] = e
    s.log[#s.log + 1] = ("%d:%d:%d:1"):format(o.t or (#s.log + 1) * 10, Index(s, name), nextId)
    return e
end
-- A roll won by `winner`, on Need ("n") or Greed ("g"): `rolls` gives each
-- player's number, or "p" for a pass. The winner gets the item.
local function Roll(s, winner, method, rolls, o)
    o = o or {}
    o.need, o.greed = method == "n" and 1 or nil, method == "g" and 1 or nil
    local e = Give(s, winner, o)
    local parts = {}
    for _, name in ipairs(s.names) do
        local v, st = rolls[name], s.rollStats[name]
        if v == "p" then
            parts[#parts + 1] = Index(s, name) .. "p"
            st.passes = st.passes + 1
        elseif v then
            parts[#parts + 1] = Index(s, name) .. method .. v
            st.sum, st.n = st.sum + v, st.n + 1
            st.high, st.low = math.max(st.high or 0, v), math.min(st.low or 101, v)
        end
    end
    s.rollLog[#s.rollLog + 1] = { k = ns.ItemKey(e), t = #s.rollLog * 10, w = Index(s, winner), m = method,
                                  r = table.concat(parts, ",") }
end
local function Score(s, name, title)
    for _, f in ipairs(ns.AwardScores(s, ns.Summarize(s))[name] or {}) do
        if f.title == title then return f.fit end
    end
end
local function near(a, b) return a and math.abs(a - b) < 0.01 end

print("-- moments")
local MIRA, BORIN, SELA, KETT = "Mira Vale", "Borin Oak", "Sela Marrow", "Kett Longstride"
local s = NewRun({ MIRA, BORIN, SELA, KETT })
Roll(s, BORIN, "n", { [BORIN] = 99, [SELA] = 97, [MIRA] = 40, [KETT] = "p" })
Roll(s, KETT, "n", { [KETT] = 54, [MIRA] = 53, [BORIN] = "p", [SELA] = "p" })
Roll(s, MIRA, "n", { [MIRA] = 4, [BORIN] = 2, [SELA] = "p", [KETT] = "p" })
Roll(s, BORIN, "n", { [BORIN] = 77, [SELA] = 10, [MIRA] = "p", [KETT] = "p" })
Roll(s, BORIN, "n", { [BORIN] = 77, [KETT] = 30, [MIRA] = "p", [SELA] = "p" })
Roll(s, BORIN, "n", { [BORIN] = 60, [MIRA] = 20, [SELA] = "p", [KETT] = "p" })
Roll(s, BORIN, "n", { [BORIN] = 88, [MIRA] = 31, [SELA] = "p", [KETT] = "p" })
Roll(s, BORIN, "n", { [BORIN] = 65, [MIRA] = 12, [SELA] = "p", [KETT] = "p" })
Roll(s, SELA, "n", { [SELA] = 70, [KETT] = 21, [MIRA] = "p", [BORIN] = "p" }, { vendor = 50, quality = 0, cat = "junk" })
Roll(s, KETT, "g", { [KETT] = 33, [MIRA] = "p", [BORIN] = "p", [SELA] = "p" })

check(near(Score(s, SELA, "Heartbreak"), 0.65), "Heartbreak: lost with a 97 (0.65)")
check(near(Score(s, KETT, "Photo Finish"), 0.4), "Photo Finish: won 54 to 53")
check(near(Score(s, MIRA, "Lowball"), 0.475), "Lowball: won with a 4 against a 2")
check(not Score(s, KETT, "Lowball"), "a win nobody else rolled on is no Lowball")
check(near(Score(s, BORIN, "Deja Vu"), 0.5), "Deja Vu: 77 twice in a row")
check(near(Score(s, BORIN, "Hot Streak"), 0.3 + 0.7 * 2 / 3), "Hot Streak: 5 rolls won in a row")
check(near(Score(s, MIRA, "Nemesis"), 0.3), "Nemesis: lost 4 of 5 rolls against Borin")
check(not Score(s, SELA, "Nemesis"), "losing twice to someone is no Nemesis")
check(near(Score(s, SELA, "Overkill"), 0.4), "Overkill: a Need win worth 50c")
check(Score(s, KETT, "Leftovers") and Score(s, KETT, "Leftovers") < 0.3, "Leftovers: a win nobody else rolled on, below 0.3")

-- Two players and two rolls on things worth next to nothing: nothing but
-- the moments fits them.
local duo = NewRun({ MIRA, BORIN })
Give(duo, MIRA, { vendor = 5000 })
Roll(duo, BORIN, "n", { [BORIN] = 99, [MIRA] = 97 }, { vendor = 1 })
Roll(duo, BORIN, "n", { [BORIN] = 54, [MIRA] = 53 }, { vendor = 1 })
local awards = ns.Awards(duo, ns.Summarize(duo))
check(awards[MIRA].key == "heartbreak" and awards[MIRA].text == "Lost a roll with a 97" and awards[MIRA].link ~= nil,
      "Heartbreak names the number and the item: " .. tostring(awards[MIRA].text))
check(awards[BORIN].key == "photo" and awards[BORIN].text == "Won a roll 54 to 53",
      "Photo Finish gives the score: " .. tostring(awards[BORIN].text))
awards = ns.Awards(s, ns.Summarize(s))
check(awards[BORIN].key == "ninja" and awards[KETT].key == "lucky",
      "the awards come first: Ninja and Luckiest still beat Hot Streak and Photo Finish")

print("-- a long losing run")
local ANN, BOB, CAT = "Ann One", "Bob Two", "Cat Three"
local d = NewRun({ ANN, BOB, CAT })
for i = 1, 13 do
    Roll(d, BOB, "n", { [BOB] = 50 + i, [ANN] = i, [CAT] = "p" }, { vendor = 3000 })
end
check(near(Score(d, ANN, "Dry Spell"), 0.3 + 0.7 / 8), "Dry Spell: 13 rolls lost in a row")
check(Score(d, ANN, "Nemesis") and Score(d, ANN, "Nemesis") > 1, "Nemesis: all 13 lost to the same player")
check(not Score(d, CAT, "Dry Spell"), "passing is not losing")

print("-- consolation")
-- Five players, ten Greed rolls with ordinary numbers, two wins each in
-- turn: an even, unremarkable run, the kind that used to make Tourists.
local quiet = NewRun({ "P One", "P Two", "P Three", "P Four", "P Five" })
for i, name in ipairs(quiet.names) do
    Give(quiet, name, { vendor = 4000 + i, t = i * 10 })
end
for k = 1, 10 do
    local winner = quiet.names[(k - 1) % 5 + 1]
    local rolls = {}
    for j, name in ipairs(quiet.names) do
        rolls[name] = name == winner and 70 + k or 30 + (k * 3 + j * 7) % 34
    end
    Roll(quiet, winner, "g", rolls, { vendor = 900 + k })
end
local qsum = ns.Summarize(quiet)
local qawards = ns.Awards(quiet, qsum)
local tourists, consolation = 0, 0
for _, p in ipairs(qsum.players) do
    if qawards[p.name].key == "tourist" then tourists = tourists + 1 end
end
local groups = {}
for _, def in ipairs(ns.AwardGuide()) do groups[def.title] = def.group end
local below = true
for _, list in pairs(ns.AwardScores(quiet, qsum)) do
    for _, f in ipairs(list) do
        if groups[f.title] == "consolation" then
            consolation = consolation + 1
            if f.fit >= 0.3 or f.fit < 0.1 then below = false end
        end
    end
end
check(tourists == 0, "a quiet run of five: nobody is a Tourist")
check(consolation > 0 and below, "consolation prizes score between 0.1 and 0.3")
check(qawards["P Two"].key ~= "runnerup" or qawards["P Two"].text == "Second most loot", "Runner-up says what it is for")
local firstTo
for name, a in pairs(qawards) do
    if a.key == "firstdibs" then firstTo = name end
end
check(firstTo == nil or firstTo == "P One", "First Dibs can only go to whoever picked up first")
-- The best of the group gets each prize, unless they have a better award.
local busy = NewRun({ ANN, BOB, CAT })
Give(busy, ANN, { vendor = 5000 })
Give(busy, BOB, { vendor = 5000 })
Give(busy, CAT, { vendor = 5000 })
for _, r in ipairs({ { ANN, 40, 30, 20 }, { ANN, 41, 31, 21 }, { ANN, 42, 32, 22 }, { ANN, 43, 33, 23 },
                     { BOB, 34, 44, 24 }, { BOB, 35, 45, 25 } }) do
    Roll(busy, r[1], "g", { [ANN] = r[2], [BOB] = r[3], [CAT] = r[4] }, { vendor = 10 })
end
local fits = ns.AwardScores(busy, ns.Summarize(busy))
local function fitOf(name, title)
    for _, f in ipairs(fits[name] or {}) do
        if f.title == title then return f.fit end
    end
end
check(near(fitOf(ANN, "Collector"), 0.25) and near(fitOf(BOB, "Collector"), 0.175),
      "the most wins scores 0.25, half as many 0.175")

-- Every one of them makes the Front page.
for _, run in ipairs({ s, d, quiet }) do
    TEXTLOG = {}
    local drawn = pcall(ns.OpenRunWindow, "paper", run)
    local all = drawn
    for _, name in ipairs(run.names) do
        -- A story starts with the player's name.
        local who, storied = ns.DisplayName(name), false
        for _, t in ipairs(TEXTLOG) do
            if t:sub(1, #who) == who and #t > 40 then storied = true end
        end
        all = all and storied
    end
    check(all, ("the Front page has a story for each of the %d players"):format(#run.names))
end

print("-- runs without logs")
local old = NewRun({ ANN, BOB })
Give(old, ANN, { vendor = 9000 })
Give(old, BOB, { vendor = 1000 })
old.log, old.rollLog, old.names = nil, nil, nil
local ok, oldAwards = pcall(ns.Awards, old, ns.Summarize(old))
check(ok and oldAwards[ANN] and oldAwards[BOB], "an old run without a roll or pickup log still gets its awards")

print("-- the guide")
local guide = ns.AwardGuide()
local order, seen, long = {}, {}, {}
for _, def in ipairs(guide) do
    local g = def.group or "award"
    if order[#order] ~= g then order[#order + 1] = g end
    seen[def.key] = true
    if #def.how > 90 or not def.icon then long[#long + 1] = def.title end
end
check(table.concat(order, ",") == "award,moment,consolation" and guide[#guide].key == "tourist",
      "awards, then moments, then consolation, Tourist last (" .. table.concat(order, ",") .. ")")
check(#guide == 40, ("40 entries in the guide (%d)"):format(#guide))
check(#long == 0, "every rule fits on one line, every award has an icon " .. table.concat(long, ", "))
-- Every award has a story on the Front page.
local f = io.open(TEST_DIR .. "/../ThatLuckyBastard/Show.lua", "r")
local src = f:read("*a")
f:close()
local block = src:match("local STORIES = (%b{})")
local missing = {}
for _, def in ipairs(guide) do
    if not block:find("\n    " .. def.key .. " = {", 1, true) then missing[#missing + 1] = def.key end
end
check(#missing == 0, "every award has a Front page story " .. table.concat(missing, ", "))
TEXTLOG = {}
ns.ShowBrowse("awards")
check(drew("Moments") and drew("Consolation") and drew("Heartbreak") and drew("Last Call"),
      "Statistics > Awards lists them under Moments and Consolation")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (awards)")
