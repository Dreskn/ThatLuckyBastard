-- When a run ends and whose run it is: coming back to life outside,
-- groups that change or are replaced, the dungeon's earlier runs, and
-- historical against current prices.
print("\n==== lifecycle: deaths, groups, earlier runs, prices ====")
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find(text, 1, true) then return true end
    end
    return false
end

-- Auction prices, by item id: the tests move them.
local PRICES = {}
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
    return PRICES[tonumber(link:match("item:(%d+)"))]
end } } }

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local main, podium = ThatLuckyBastardFrame, ThatLuckyBastardPodiumFrame

ITEMS[100] = { 2, 1500, 4, 2 }  -- green BoE
ITEMS[101] = { 3, 9000, 4, 2 }  -- blue BoE
ITEMS[103] = { 0, 300, 15, 0 }  -- junk
local green, blue, junk = ItemLink(100, "Green Gloves", 2), ItemLink(101, "Blue Blade", 3), ItemLink(103, "Broken Fang", 0)

local function Party(...)
    local list = {}
    for i, name in ipairs({ ... }) do list[i] = { name, "MAGE", "DAMAGER" } end
    return list
end
local OLD = { "Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash" }
local NEW = { "Stranger One", "Stranger Two", "Stranger Three", "Stranger Four" }

local function Enter(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    return db.active
end
local function Leave()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
end
local function Regroup(...)
    WORLD.party = Party(...)
    Fire("GROUP_ROSTER_UPDATE")
end
-- Ends whatever run is going and clears the screen.
local function Reset()
    WORLD.inInstance, WORLD.dead = false, false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    if db.active then SlashCmdList.THATLUCKYBASTARD("stop") end
    main:Hide()
    podium:Hide()
    NOW = NOW + 3600
end
local function Count(s)
    local n = 0
    for _ in pairs(s.players) do n = n + 1 end
    return n
end
local function Has(s, names)
    for _, name in ipairs(names) do
        if s.players[name] then return true end
    end
    return false
end

print("-- alive again outside the dungeon")
WORLD.party = Party(unpack(OLD))
local s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
Loot(("%s receives loot: %s."):format("Borin Oak", green))
WORLD.dead = true
Leave()
check(s.leftAt ~= nil and s.leftDead and not main:IsShown() and not podium:IsShown(), "leaving dead opens nothing")
Fire("PLAYER_ALIVE") -- released: a ghost at the graveyard
check(s.leftDead and not main:IsShown(), "a ghost outside may still be on the way back: nothing yet")
WORLD.dead = false
Fire("PLAYER_UNGHOST")
check(main:IsShown() and podium:IsShown() and not s.leftDead,
      "alive again outside: the window and the podium open, as on leaving alive")
main:Hide()
podium:Hide()
Fire("PLAYER_ALIVE")
check(not main:IsShown() and not podium:IsShown(), "a second event for the same return to life does nothing")
local asked = #POPUPS
NOW = NOW + 60
Enter(9001, "Test Keep")
check(#POPUPS == asked + 1 and POPUPS[#POPUPS].which == "THATLUCKYBASTARD_NEW_RUN" and db.active == s,
      "walking back in alive asks whether it is a new run")
Reset()

-- The usual way back: in as a ghost, alive again inside.
s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
WORLD.dead = true
Leave()
asked = #POPUPS
NOW = NOW + 90
Enter(9001, "Test Keep")
WORLD.dead = false
Fire("PLAYER_UNGHOST")
check(db.active == s and not s.leftAt and #POPUPS == asked and not main:IsShown(),
      "running back in as a ghost goes on with the run: no question, no window")
Reset()

print("-- players replaced, and another group")
WORLD.party = Party(unpack(OLD))
s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
Loot(("%s receives loot: %s."):format("Borin Oak", green))
Regroup("Borin Oak", "Sela Marrow", "Kett Longstride", "Pim Sorrel") -- Juno left, Pim joined
NOW = NOW + 60
Loot(("%s receives loot: %s."):format("Pim Sorrel", green))
check(db.active == s and Count(s) == 6 and s.players["Juno Ash"] and s.players["Pim Sorrel"],
      "one player replaced: the same run, with six players")
-- The queue pops inside: a whole new group, before the loading screen.
NOW = NOW + 600
local runs = #db.history
Regroup(unpack(NEW))
check(db.history[1] == s and #db.history == runs + 1 and Count(s) == 6 and not Has(s, NEW),
      "a different group is not added: the run is closed as it was")
check(db.active ~= s and db.active.instanceID == 9001 and Has(db.active, NEW) and main:IsShown(),
      "what follows is a new run with the new group, and the old one is shown")
main:Hide()
podium:Hide()
runs = #db.history
NOW = NOW + 5
local next9002 = Enter(9002, "Other Keep")
check(#db.history == runs and next9002.instanceID == 9002 and Has(next9002, NEW) and Count(next9002) == 5,
      "the empty run in between is dropped; the next dungeon starts with the new group")
-- One friend queues along: one in four is the same, so it is another group.
NOW = NOW + 300
Loot(("You receive loot: %s."):format(green))
Regroup("Stranger One", "New One", "New Two", "New Three")
check(db.active ~= next9002 and db.history[1] == next9002 and not Has(next9002, { "New One", "New Two", "New Three" }),
      "the next queue with one friend along is another group too")
Reset()

-- Two of four stay: by the same rule that is the same group, as when two
-- players are replaced. Whoever joined in the last moments and did nothing
-- is dropped when the run closes.
WORLD.party = Party(unpack(OLD))
s = Enter(9001, "Test Keep")
NOW = NOW + 600
Loot(("You receive loot: %s."):format(blue))
Regroup("Borin Oak", "Sela Marrow", "Late One", "Late Two")
check(db.active == s and Count(s) == 7, "half the group stays: the same run for now")
NOW = NOW + 5
Loot(("%s receives loot: %s."):format("Late One", junk))
NOW = NOW + 5
Enter(9002, "Other Keep")
check(db.history[1] == s and not s.players["Late Two"] and s.players["Late One"] and Count(s) == 6,
      "closing it drops the late joiner who did nothing, and keeps the one who looted")
check(s.players["Juno Ash"] ~= nil, "a player from the start who got nothing stays")
check(s.group == nil and s.players["Borin Oak"].joined == nil, "what was only kept to tell groups apart is not saved")
Reset()

-- Coming back within twenty minutes.
WORLD.party = Party(unpack(OLD))
s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
Leave()
main:Hide()
podium:Hide()
NOW = NOW + 300
asked = #POPUPS
Enter(9001, "Test Keep")
check(db.active == s and #POPUPS == asked + 1, "back with the same group: the question, as before")
Leave()
main:Hide()
podium:Hide()
NOW = NOW + 300
asked = #POPUPS
WORLD.party = Party(unpack(NEW))
local again = Enter(9001, "Test Keep")
check(again ~= s and #POPUPS == asked and db.history[1] == s and not Has(s, NEW) and Has(again, NEW),
      "back with another group: a new run, without asking, and the old one untouched")
Reset()

-- Left dead, back alive with another group.
WORLD.party = Party(unpack(OLD))
s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
WORLD.dead = true
Leave()
WORLD.dead = false
NOW = NOW + 600
WORLD.party = Party(unpack(NEW))
again = Enter(9001, "Test Keep")
check(again ~= s and db.history[1] == s and not Has(s, NEW), "a run left dead is not handed to another group either")
Reset()

-- A run recorded on another character of the account.
WORLD.party = Party(unpack(OLD))
s = Enter(9001, "Test Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))
s.owner = "Someone Else"
Regroup("Borin Oak", "Sela Marrow", "Kett Longstride", "Alt Friend")
check(not s.players["Alt Friend"], "the group of another character is not added to its run")
s.owner = WORLD.me
Reset()

print("-- the dungeon's earlier runs")
WORLD.party = Party(unpack(OLD))
ITEMS[110] = { 2, 10000, 4, 2 }
ITEMS[111] = { 2, 20000, 4, 2 }
ITEMS[112] = { 2, 60000, 4, 2 }
local made = {}
for i, id in ipairs({ 110, 111, 112 }) do
    local run = Enter(9010, "Record Keep")
    NOW = NOW + 600
    Loot(("You receive loot: %s."):format(ItemLink(id, "Trophy " .. id, 2)))
    Reset()
    made[i] = run
end
local function Insights(run) return ns.RunInsights(run, ns.Summarize(run)) end
local first, second, third = Insights(made[1]), Insights(made[2]), Insights(made[3])
check(first.priorRuns == 0 and first.groupPct == nil, "the first run of a dungeon has nothing to be compared with")
check(second.priorRuns == 1 and second.earlier and math.abs(second.groupPct - 100) < 0.01,
      "the second is compared with the first alone, although a third came after: twice as much")
check(third.priorRuns == 2 and third.earlier and math.abs(third.groupPct - 300) < 0.01,
      "the third with the average of the two before it")
ns.ShowRun(made[2])
TEXTLOG = {}
ns.Rerender()
RunTimers()
check(drew("(1 earlier run)"), "the window says so: 1 earlier run")
-- A run counted before that was kept: compared with every other run.
made[2].stats.prior, made[2].stats.avgGroup, made[2].stats.avgMine = nil, nil, nil
local old = Insights(made[2])
check(old.priorRuns == 2 and not old.earlier and math.abs(old.groupPct - (20000 - 35000) / 35000 * 100) < 0.01,
      "a run counted before that was kept is compared with the others, and says other")
TEXTLOG = {}
ns.Rerender()
RunTimers()
check(drew("(2 other runs)"), "the window says so: 2 other runs")
main:Hide()

print("-- historical and current prices")
local o = db.options
PRICES[100] = 50000
WORLD.party = Party(unpack(OLD))
s = Enter(9020, "Price Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(green))
Reset()
PRICES[100] = 80000
check(o.priceTime == "then" and ns.Summarize(s).market == 50000, "by default a run keeps the prices recorded when it was looted")
o.priceTime = "now"
check(ns.Summarize(s).market == 80000, "with current prices, it is valued at the auction price of today")
PRICES[100] = 90000
check(ns.Summarize(s).market == 80000, "today's price is not asked for again right away")
NOW = NOW + 301
check(ns.Summarize(s).market == 90000, "but it is after five minutes")
local price = ns.Reprice(s)
check(price and price.was == 50000 and price.now == 90000, "At today's prices still compares the recorded value with today's")
PRICES[100] = nil
NOW = NOW + 301
check(ns.Summarize(s).market == 50000, "no price today: the recorded one stands")
PRICES[100] = 90000
NOW = NOW + 301
o.valueMode = "vendor"
check(ns.Summarize(s).market == 1500, "vendor prices only: neither is used")
o.valueMode = "market"
-- A run shared with you keeps its owner's prices.
local gift = { name = "Gift Keep", startedAt = NOW - 5000, endedAt = NOW - 4000, sharedBy = "Kind Soul",
               players = { ["Kind Soul"] = { items = { g = { link = green, count = 1, vendor = 1500, ah = 50000,
                                                             cat = "uncommon", quality = 2, resolved = true } } } } }
check(ns.Summarize(gift).market == 50000, "a run shared with you keeps its owner's prices")
check(ns.Summarize(s).market == 90000, "while yours follows today's")
-- Nothing of it reaches the saved file.
local function Stored()
    for _, run in ipairs(db.history) do
        for _, p in pairs(run.players) do
            for _, e in pairs(p.items) do
                if e.now ~= nil then return true end
            end
        end
    end
    return false
end
local before = Stored()
Fire("PLAYER_LOGOUT")
check(before and not Stored(), "today's prices are dropped when logging out")
o.priceTime = "then"
check(ns.Summarize(s).market == 50000, "and back to historical prices")

print("-- more than five players: columns for the top five, a bench for the others")
-- A button by its label: its outer frame (shown or hidden with it), and
-- a click on it.
local function Button(label)
    for _, w in ipairs(FRAMES) do
        local text = rawget(w, "text")
        if type(text) == "table" and text.__text == label and w.__scripts.OnClick then return rawget(w, "__parent"), w end
    end
end
local function Click(label)
    local _, w = Button(label)
    if w then w.__scripts.OnClick(w, "LeftButton") end
    return w ~= nil
end
local function Shown(label)
    local outer = Button(label)
    return outer ~= nil and outer:IsShown()
end
local function Draw(run)
    ns.ShowRun(run)
    TEXTLOG = {}
    ns.Rerender()
    RunTimers()
end
local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- Was exactly this written (colours aside)? For a word a title could hold too.
local function wrote(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t) == text then return true end
    end
    return false
end

o.priceTime, o.useColumns = "then", true
PRICES[100] = nil
WORLD.party = Party(unpack(OLD))
local six = Enter(9030, "Crowd Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(blue))                       -- 9000
Loot(("%s receives loot: %s."):format("Borin Oak", ItemLink(110, "Trophy 110", 2)))   -- 10000
Loot(("%s receives loot: %s."):format("Sela Marrow", ItemLink(111, "Trophy 111", 2))) -- 20000
Loot(("%s receives loot: %s."):format("Kett Longstride", green))   -- 1500
Loot(("%s receives loot: %s."):format("Juno Ash", junk))           -- 300
Regroup("Borin Oak", "Sela Marrow", "Kett Longstride", "Pim Sorrel")
NOW = NOW + 60
Loot(("%s receives loot: %s."):format("Pim Sorrel", ItemLink(112, "Trophy 112", 2)))  -- 60000
Reset()
Draw(six)
check(Count(six) == 6 and wrote("Bench") and Shown("List") and not Shown("Expand all"),
      "six players: still the columns, with a bench and its List button")
check(drew("6. Juno Ash") and not drew("5. ") and not drew("6. Pim Sorrel"),
      "the bench seats whoever comes after the top five: the sixth by loot, with their place")
check(drew("Equal split  " .. Plain(ns.Money(100800 / 6))), "the equal split is still among all six")
check(drew("60%  +4g 32s"), "and so is each column's gap to it: the richest is 4g 32s above a sixth of the loot")
-- Whatever order the columns are in, the bench is for the lowest by loot.
o.sortPlayers = "name"
Draw(six)
check(drew("6. Juno Ash") and not drew("6. Sela Marrow"), "sorted by name, the bench still seats the sixth by loot")
o.sortPlayers = "podium"
Draw(six)
-- The List button: this run as a list, and the option untouched.
check(Click("List") and Shown("Columns") and Shown("Expand all") and not Shown("List") and o.useColumns == true,
      "List shows this run as a list, without changing the option")
TEXTLOG = {}
ns.Rerender()
RunTimers()
check(not wrote("Bench") and not drew("6. Juno Ash") and drew("Juno Ash") and drew("Pim Sorrel"),
      "in the list everyone has a line, and there is no bench")
Draw(made[3])
check(not Shown("Columns") and not Shown("List") and not Shown("Expand all"),
      "another run, of five or fewer, keeps its columns and has neither button")
Draw(six)
check(Shown("Columns") and not Shown("List"), "coming back to the run, it is still a list")
check(Click("Columns") and Shown("List") and not Shown("Columns"), "Columns brings its columns and its bench back")
o.useColumns = false
Draw(six)
check(not Shown("List") and not Shown("Columns") and Shown("Expand all"),
      "with Always a list chosen there is neither button: every run is a list")
o.useColumns = true

-- The Podium window: the top five on the podium, the others named below.
TEXTLOG = {}
ns.OpenRunWindow("podium", six)
RunTimers()
check(drew("6. Juno Ash"), "the Podium names the sixth under the stage")
TEXTLOG = {}
ns.OpenRunWindow("podium", made[3])
RunTimers()
check(not drew("6. "), "and nobody for a run of five or fewer")
podium:Hide()

-- A raid of forty: five columns, thirty-five seats; the Podium names
-- eight of them and counts the rest.
local raid = { name = "Raid Keep", startedAt = NOW - 9000, endedAt = NOW - 600, owner = WORLD.me, players = {} }
for i = 1, 40 do
    raid.players[("Raider %02d"):format(i)] = { class = "MAGE", items = { x = {
        link = ItemLink(2000 + i, "Thing", 2), count = 1, vendor = 1000 * (41 - i), cat = "uncommon", quality = 2,
        resolved = true } } }
end
table.insert(db.history, 1, raid)
local ok = pcall(Draw, raid)
local seats = 0
for _, text in ipairs(TEXTLOG) do
    if Plain(text):match("^%d+%. Raider %d%d  ") then seats = seats + 1 end
end
check(ok and seats == 35 and drew("6. Raider 06") and drew("40. Raider 40") and Shown("List"),
      ("a raid of forty: five columns and thirty-five seats on the bench (%d)"):format(seats))
TEXTLOG = {}
ns.OpenRunWindow("podium", raid)
RunTimers()
check(drew("13. Raider 13") and not drew("14. Raider 14") and drew("and 27 more"),
      "its Podium names eight on the bench and counts the other twenty-seven")
podium:Hide()
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (lifecycle)")
