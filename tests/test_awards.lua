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

print("-- several holders, numbered ranks and shared ties")
check(ns.AwardHolders(5) == 1 and ns.AwardHolders(6) == 2 and ns.AwardHolders(10) == 2
      and ns.AwardHolders(11) == 3 and ns.AwardHolders(40) == 3,
      "an award goes to 1 player in a party, 2 in a group of up to ten, 3 beyond")

-- A group of `n` with no classes or roles, everyone with one item: player
-- i's is worth loot(i), or a little more than the player before.
local function Group(n, loot)
    local names = {}
    for i = 1, n do names[i] = ("R%02d"):format(i) end
    local run = NewRun(names)
    for i, name in ipairs(names) do
        run.players[name].class = nil
        local worth = loot and loot(i) or 4000 + i * 900
        if worth > 0 then Give(run, name, { vendor = worth }) end
    end
    return run, names
end
-- Each player's title, how many players have each title, and the awards.
local function Titles(run)
    local awards = ns.Awards(run, ns.Summarize(run))
    local title, count = {}, {}
    for name, a in pairs(awards) do
        title[name] = a.title
        count[a.title] = (count[a.title] or 0) + 1
    end
    return title, count, awards
end

-- Twelve players, four of them generous to different degrees.
local raid, R = Group(12)
raid.rollStats[R[1]].passes, raid.rollStats[R[2]].passes = 8, 6
raid.rollStats[R[3]].passes, raid.rollStats[R[4]].passes = 4, 3
local title, count = Titles(raid)
check(title[R[1]] == "The Saint" and title[R[2]] == "The Saint II" and title[R[3]] == "The Saint III",
      ("three Saints in a group of twelve, numbered by fit (%s, %s, %s)"):format(
          tostring(title[R[1]]), tostring(title[R[2]]), tostring(title[R[3]])))
check(not title[R[4]]:find("Saint", 1, true) and Score(raid, R[4], "The Saint") ~= nil,
      "the fourth qualifies too, and moves on to something else (" .. title[R[4]] .. ")")
-- The same four in a group of eight: two holders. In a party: one.
local eight, E8 = Group(8)
eight.rollStats[E8[3]].passes, eight.rollStats[E8[5]].passes, eight.rollStats[E8[7]].passes = 8, 6, 4
title = Titles(eight)
check(title[E8[3]] == "The Saint" and title[E8[5]] == "The Saint II" and not title[E8[7]]:find("Saint", 1, true),
      "two Saints in a group of eight")
local party, P5 = Group(5)
party.rollStats[P5[2]].passes, party.rollStats[P5[4]].passes = 8, 6
title = Titles(party)
check(title[P5[2]] == "The Saint" and not title[P5[4]]:find("Saint", 1, true), "one Saint in a party of five")

-- Equal fits share a place: three players who each rolled a 100 are all
-- "Natural 100", with no number. A fourth finds the award full.
raid, R = Group(12)
for _, i in ipairs({ 2, 4, 6, 8 }) do
    local st = raid.rollStats[R[i]]
    st.sum, st.n, st.high, st.low = 100, 1, 100, 100
end
title, count = Titles(raid)
check(count["Natural 100"] == 3 and not count["Natural 100 II"] and title[R[2]] ~= "Natural 100",
      ("three Natural 100s, none numbered; the poorest of the four goes without (%s)"):format(tostring(title[R[2]])))

-- Two players nothing can tell apart share an award, even in a party:
-- before, the one whose name came first had it.
local tie = NewRun({ "Abe", "Cat", "Zed" })
Roll(tie, "Abe", "n", { Abe = 50, Cat = "p", Zed = "p" }, { vendor = 20000 })
Roll(tie, "Zed", "n", { Zed = 50, Cat = "p", Abe = "p" }, { vendor = 20000 })
Give(tie, "Cat", { vendor = 20000 })
local _, _, tied = Titles(tie)
check(tied.Abe.title == "Ninja" and tied.Zed.title == "Ninja" and tied.Abe.place == 1 and tied.Zed.place == 1,
      ("Abe and Zed, identical, are both the Ninja (%s, %s)"):format(tied.Abe.title, tied.Zed.title))
-- Equal fits, different loot: no sharing in a party, the richer has it.
local two = Group(5)
two.rollStats["R01"].high, two.rollStats["R01"].n, two.rollStats["R01"].sum = 100, 1, 100
two.rollStats["R04"].high, two.rollStats["R04"].n, two.rollStats["R04"].sum = 100, 1, 100
title, count = Titles(two)
check(count["Natural 100"] == 1 and title["R04"] == "Natural 100", "two 100s in a party: one Natural 100, to the richer")

-- The best of the group, and the next: the text says where each stands.
raid, R = Group(8)
Roll(raid, R[2], "n", { [R[2]] = 80, [R[3]] = 20 }, { vendor = 60000 })
Roll(raid, R[5], "n", { [R[5]] = 80, [R[3]] = 20 }, { vendor = 40000 })
local _, _, ninjas = Titles(raid)
check(ninjas[R[2]].title == "Ninja" and ninjas[R[2]].text == "Most value won on Need rolls"
      and ninjas[R[5]].title == "Ninja II" and ninjas[R[5]].text == "2nd most value won on Need rolls",
      ("Ninja and Ninja II in a group of eight (%s: %s / %s: %s)"):format(ninjas[R[2]].title, ninjas[R[2]].text,
          ninjas[R[5]].title, ninjas[R[5]].text))
-- Only the Ninja of the run counts towards a player's Ninja tally.
ThatLuckyBastardDB.people = {}
ThatLuckyBastardDB.active = raid
SlashCmdList.THATLUCKYBASTARD("stop")
local people = ThatLuckyBastardDB.people
check(people[R[2]] and people[R[2]].ninja == 1 and people[R[5]] and people[R[5]].ninja == 0,
      "the tally counts the Ninja, not Ninja II")

print("-- contested rolls only, for Hot Streak and the dice")
local alone = NewRun({ MIRA, BORIN, SELA, KETT })
for _ = 1, 4 do Roll(alone, KETT, "g", { [KETT] = 50, [MIRA] = "p", [BORIN] = "p", [SELA] = "p" }) end
check(not Score(alone, KETT, "Hot Streak"), "four wins nobody rolled against are no Hot Streak")
-- Borin needs alone and rolls low; Mira greeds on the same items and
-- rolls high. Neither number decided anything.
local idle = NewRun({ MIRA, BORIN, SELA, KETT })
for i = 1, 6 do
    local e = Give(idle, BORIN, { need = 1 })
    idle.rollLog[#idle.rollLog + 1] = { k = ns.ItemKey(e), t = i * 10, w = 2, m = "n", r = "2n" .. (5 + i) .. ",1g" .. (90 + i) }
    idle.rollStats[BORIN].sum, idle.rollStats[BORIN].n = idle.rollStats[BORIN].sum + 5 + i, i
    idle.rollStats[MIRA].sum, idle.rollStats[MIRA].n = idle.rollStats[MIRA].sum + 90 + i, i
end
check(not Score(idle, BORIN, "Cursed Dice") and not Score(idle, MIRA, "Loaded Dice"),
      "numbers that decided nothing earn no dice award")
-- Sela and Kett both need, six times: those numbers count.
local dice = NewRun({ MIRA, BORIN, SELA, KETT })
for i = 1, 6 do Roll(dice, SELA, "n", { [SELA] = 90 + i, [KETT] = 4 + 2 * i, [MIRA] = "p", [BORIN] = "p" }) end
local _, _, diced = Titles(dice)
check(Score(dice, SELA, "Loaded Dice") and Score(dice, KETT, "Cursed Dice"), "numbers from a contest do")
check(diced[KETT].key == "colddice" and diced[KETT].text == "Average roll of 11 over 6 contested rolls",
      ("the text says they were contested rolls (%s: %s)"):format(diced[KETT].title, tostring(diced[KETT].text)))
-- The bar: two standard deviations from what chance gives, over five
-- contested rolls at least. An average of 60 over 15 rolls used to do.
local function Dice(number, times)
    local run = NewRun({ MIRA, BORIN, SELA, KETT })
    for _ = 1, times do Roll(run, SELA, "n", { [SELA] = number, [KETT] = 50, [MIRA] = "p", [BORIN] = "p" }) end
    return Score(run, SELA, "Loaded Dice"), Score(run, KETT, "Cursed Dice")
end
local at60, kett = Dice(60, 15)
check(not at60 and not kett, "an average of 60 over 15 rolls is no longer Loaded Dice; 50 is nothing either")
check(near(Dice(66, 15), 0.3 + 0.7 * (15.5 * math.sqrt(15) / 28.87 - 2)), "an average of 66 over 15 rolls just qualifies (0.36)")
check(not Dice(99, 4) and Dice(99, 5), "four rolls are too few, whatever they were; five will do")
-- A run recorded before the roll log keeps the average of every number.
local olddice = NewRun({ MIRA, BORIN, SELA })
Give(olddice, MIRA, { vendor = 3000 })
Give(olddice, BORIN, { vendor = 2000 })
olddice.rollLog = nil
olddice.rollStats[BORIN] = { sum = 60, n = 6, passes = 0, high = 15, low = 5 }
check(Score(olddice, BORIN, "Cursed Dice"), "a run without a roll log still gets its dice awards")

print("-- titles from lore, and for roles, classes and bosses")
local NAMES = { "T One", "T Two", "H One", "H Two", "D Hunter", "D Mage", "D Magus", "D Idle" }
local function Titled()
    local run = NewRun(NAMES)
    local setup = { { "WARRIOR", "TANK", 20000 }, { "WARRIOR", "TANK", 4000 }, { "PRIEST", "HEALER", 9000 },
                    { "PRIEST", "HEALER", 3000 }, { "HUNTER", "DAMAGER", 0 }, { "MAGE", "DAMAGER", 12000 },
                    { "MAGE", "DAMAGER", 6000 }, { "MAGE", "DAMAGER", 0 } }
    for i, name in ipairs(NAMES) do
        run.players[name].class, run.players[name].role = setup[i][1], setup[i][2]
        if setup[i][3] > 0 then Give(run, name, { vendor = setup[i][3] }) end
    end
    return run
end
local big = Titled()
-- The hunter wins on Need, six times, against the second tank.
for _ = 1, 6 do Roll(big, "D Hunter", "n", { ["D Hunter"] = 70, ["T Two"] = 30 }, { vendor = 500 }) end
local _, _, got = Titles(big)
check(near(Score(big, "D Hunter", "Hunter Loot"), 0.35 + 0.2 * (6 - 6 / 8)) and got["D Hunter"].title == "Hunter Loot",
      "Hunter Loot: a hunter who won on Need, the stronger the more they won beyond an even share (1.40)")
check(near(Score(big, "T One", "Tank Tax"), 0.3 + 0.7 * (20000 / 12000 - 1.5) / 1.5),
      "Tank Tax: the tank with 1.67 times the tanks' average (0.38)")
check(not Score(big, "T Two", "Tank Tax"), "the other tank has no Tank Tax")
check(near(Score(big, "H One", "Healer's Tip"), 0.3), "Healer's Tip: 1.5 times the healers' average just qualifies")
check(near(Score(big, "D Mage", "Top DPS"), 0.3 + 0.7 * (12000 / 5250 - 1.5) / 1.5)
      and near(Score(big, "D Mage", "Class Act"), 0.3 + 0.7 * 0.5 / 1.5) and not Score(big, "D Magus", "Top DPS"),
      "Top DPS and Class Act: far above the damage dealers' and the mages' average; a little above is not enough")
check(near(Score(big, "D Idle", "AFK"), 1.1) and got["D Idle"].title == "AFK",
      "AFK: nothing picked up, nothing rolled on (" .. got["D Idle"].title .. ")")
check(near(Score(big, "D Idle", "Class Clown"), 1), "Class Clown: a mage far below the mages' average")
check(near(Score(big, "T Two", "50 DKP Minus"), 0.3 + 0.7 * (6 - 6 / 8 - 3) / 5) and not Score(big, "T One", "50 DKP Minus"),
      "50 DKP Minus: lost six rolls where the group's average is under one (0.62)")
check(near(Score(big, "T Two", "Need Before Greed"), 0.3 + 0.7 * (6 - 12 / 8 - 2) / 4)
      and near(Score(big, "D Hunter", "Need Before Greed"), 0.3 + 0.7 * (6 - 12 / 8 - 2) / 4),
      "Need Before Greed: chose Need six times, win or lose, where the average is 1.5 (0.74)")
check(got["H One"].title == "Healer's Tip" and got["H One"].text == "50% above the healers' average",
      ("the title says how far above (%s: %s)"):format(got["H One"].title, tostring(got["H One"].text)))
check(got["D Mage"].title == "Jackpot II" and got["D Mage"].text == "2nd best single item of the run",
      ("the second best item of a group of eight is Jackpot II, and says so (%s: %s)"):format(
          got["D Mage"].title, tostring(got["D Mage"].text)))
check(got["H Two"].key == "empty" and got["H Two"].text == "2nd least loot of the group",
      ("with the poorest away, Empty Pockets goes to the next and says so (%s: %s)"):format(
          got["H Two"].title, tostring(got["H Two"].text)))
-- They are for parties too. One Need win makes a hunter's Hunter Loot.
local small = NewRun({ MIRA, BORIN, SELA, KETT, "Juno Ash" })
small.players[KETT].class = "HUNTER"
Give(small, MIRA, { vendor = 9000 })
Roll(small, KETT, "n", { [KETT] = 70, [BORIN] = 30 })
check(near(Score(small, KETT, "Hunter Loot"), 0.35 + 0.2 * (1 - 1 / 5)) and not Score(small, BORIN, "Hunter Loot"),
      "a party's hunter who won on Need fits Hunter Loot (0.51 for the run's one Need win); nobody else does")

-- Boss's Pet: one player per boss.
local bossy = Titled()
bossy.bosses = { { t = 1000, name = "Big Bad" }, { t = 2000, name = "Bigger Bad" } }
Give(bossy, "H Two", { vendor = 9000, t = 1010 })
Give(bossy, "T Two", { vendor = 1000, t = 1020 })
Give(bossy, "D Magus", { vendor = 5000, t = 2030 })
check(near(Score(bossy, "H Two", "Boss's Pet"), 0.39) and near(Score(bossy, "T Two", "Boss's Pet"), 0.31)
      and near(Score(bossy, "D Magus", "Boss's Pet"), 0.4),
      "Boss's Pet: by share of each boss's loot, just above the consolation prizes (0.39, 0.31, 0.40)")
local _, _, pets = Titles(bossy)
check(pets["H Two"].title == "Boss's Pet" and pets["H Two"].text == "Most loot from Big Bad",
      ("the boss's biggest looter is its pet, and the text names the boss (%s: %s)"):format(
          pets["H Two"].title, tostring(pets["H Two"].text)))
check(pets["T Two"].key ~= "bosspet", "one pet per boss: the other looter of that boss moves on (" .. pets["T Two"].title .. ")")
check(pets["D Hunter"].title == "AFK" and pets["D Idle"].title == "AFK", "two players who did nothing are both AFK")
check(pets["D Magus"].title == "Top DPS" and pets["D Magus"].text == "91% above the damage dealers' average",
      ("a better award comes first: the second boss's only looter is Top DPS (%s: %s)"):format(
          pets["D Magus"].title, tostring(pets["D Magus"].text)))
-- In a party an award has one holder, so there is one Boss's Pet in all,
-- however many bosses there were.
local function Pets(n)
    local names = {}
    for i = 1, n do names[i] = ("B%02d"):format(i) end
    local run = NewRun(names)
    run.bosses = { { t = 1000, name = "Big Bad" }, { t = 2000, name = "Bigger Bad" }, { t = 3000, name = "Biggest Bad" } }
    for i, name in ipairs(names) do
        run.players[name].class = nil
        if i <= 3 then Give(run, name, { vendor = 5000, t = i * 1000 + 10 }) end -- one boss each
    end
    local found = 0
    for _, a in pairs(ns.Awards(run, ns.Summarize(run))) do
        if a.key == "bosspet" then found = found + 1 end
    end
    return found
end
local inParty, inRaid = Pets(5), Pets(8)
check(inParty == 1 and inRaid >= 2, ("one Boss's Pet in a party, one per boss in a bigger group (%d, %d)"):format(inParty, inRaid))

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
check(#guide == 50, ("50 entries in the guide (%d)"):format(#guide))
-- A consolation prize can go to a player who is not the best of the group
-- at it (the best may hold a better award), so its rule must not say so.
local superlative = {}
for _, def in ipairs(guide) do
    if def.group == "consolation" and def.how:find("the most", 1, true) then superlative[#superlative + 1] = def.title end
end
check(#superlative == 0, "no consolation rule claims 'the most' (" .. table.concat(superlative, ", ") .. ")")
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
check(drew("Moments") and drew("Consolation") and drew("Heartbreak") and drew("Tank Tax") and drew("Last Call"),
      "Statistics > Awards lists them, with Moments and Consolation apart")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (awards)")
