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

print("-- more than five players: columns for the top five, the others on cards under them")
-- A button by its label: its outer frame (shown or hidden with it), and
-- a click on it.
local function Button(label)
    for _, w in ipairs(FRAMES) do
        local text = rawget(w, "text")
        if type(text) == "table" and text.__text == label and w.__scripts.OnClick and not rawget(w, "more")
                and not rawget(w, "back") then
            return rawget(w, "__parent"), w
        end
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
-- The cards of the bench, as drawn, from left to right: whose each is,
-- where it is and how big, and what it shows (nil for a line left out).
local function Seats()
    local seats = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "bench") and w:IsShown() then
            seats[#seats + 1] = {
                who = w.p.name, x = w.__points[1][2], y = -w.__points[1][3], w = w.__w, h = w.__h,
                picture = w.portrait:IsShown(), name = Plain(w.name.__text),
                title = w.title:IsShown() and Plain(w.title.__text) or nil,
                gold = w.gold:IsShown() and Plain(w.gold.__text) or nil,
            }
        end
    end
    table.sort(seats, function(a, b) return a.x < b.x end)
    return seats
end
-- The arrow at the end of the bench, when it is on show.
local function More()
    for _, w in ipairs(FRAMES) do
        if rawget(w, "more") and w:IsShown() then
            return { label = Plain(w.text.__text), hidden = w.hidden, x = w.__points[1][2], y = -w.__points[1][3],
                     w = w.__w, h = w.__h, click = function() w.__scripts.OnClick(w, "LeftButton") end }
        end
    end
end
-- Its mirror at the top of the list, when it is on show: the arrow back
-- to the columns.
local function Back()
    for _, w in ipairs(FRAMES) do
        if rawget(w, "back") and w:IsShown() then
            return { label = Plain(w.text.__text), x = w.__points[1][2], y = -w.__points[1][3], h = w.__h,
                     click = function() w.__scripts.OnClick(w, "LeftButton") end }
        end
    end
end
-- How far down the list's first line starts.
local function FirstLine()
    local top
    for _, w in ipairs(FRAMES) do
        if rawget(w, "line") and w:IsShown() and w.__points and w.__points[1] then
            local y = -w.__points[1][3]
            if not top or y < top then top = y end
        end
    end
    return top
end
-- The line under the Podium's stage: the text that names `name`.
local function PodiumLine(name)
    for _, text in ipairs(TEXTLOG) do
        local plain = Plain(text)
        if plain:find(name .. " ", 1, true) then return plain end
    end
end
local WIDTH -- how wide the window's contents are: read off the first card's parent, below
local CARD, GAP, ARROW = 104, 6, 64 -- a card, the gap after it, the arrow

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
for _, w in ipairs(FRAMES) do
    if rawget(w, "bench") then WIDTH = rawget(w, "__parent"):GetWidth() end
end
local seats, more = Seats(), More()
local junoAward = ns.Awards(six, ns.Summarize(six))["Juno Ash"].title
check(Count(six) == 6 and #seats == 1 and seats[1].who == "Juno Ash" and more ~= nil and not Shown("Expand all"),
      "six players: still the columns, and the sixth by loot has a card under them")
check(seats[1].picture and seats[1].name == "Juno Ash" and seats[1].title == junoAward
      and seats[1].gold == Plain(ns.Money(300)),
      ("a card shows a picture, then the name, the award and the loot value (%s / %s / %s)"):format(
          seats[1].name, tostring(seats[1].title), tostring(seats[1].gold)))
check(more.label == "List" and more.hidden == 0 and more.y == seats[1].y and more.h == seats[1].h
      and more.x == seats[1].x + CARD + GAP,
      "the row ends with the arrow, as tall as the cards; with everyone on show it says List")
check(seats[1].x == (WIDTH - (CARD + GAP) - ARROW) / 2, "the row is centred under the columns")
check(drew("Equal split  " .. Plain(ns.Money(100800 / 6))), "the equal split is still among all six")
check(drew("60%  +4g 32s"), "and so is each column's gap to it: the richest is 4g 32s above a sixth of the loot")
-- Whatever order the columns are in, the bench is for the lowest by loot.
o.sortPlayers = "name"
Draw(six)
check(#Seats() == 1 and Seats()[1].who == "Juno Ash", "sorted by name, the bench still seats the sixth by loot")
o.sortPlayers = "podium"

-- The options say what a card shows; a card is as tall as what it holds.
local full = seats[1].h
o.benchAward = false
Draw(six)
check(Seats()[1].title == nil and Seats()[1].gold ~= nil and Seats()[1].h == full - 13, "without the award")
o.benchAward, o.benchValue = true, false
Draw(six)
check(Seats()[1].gold == nil and Seats()[1].title == junoAward and Seats()[1].h == full - 13, "without the loot value")
o.benchValue, o.benchPicture = true, false
Draw(six)
check(not Seats()[1].picture and Seats()[1].h < full - 30, "without the picture")
o.benchPicture, o.portrait = true, "none"
Draw(six)
check(not Seats()[1].picture, "nor with pictures switched off for the whole window")
o.portrait = "2d"
Draw(six)

-- The arrow: this run as a list, and the option untouched.
More().click()
local back = Back()
check(back ~= nil and Shown("Expand all") and More() == nil and o.useColumns == true,
      "the arrow shows this run as a list, without changing the option")
check(back and back.label == "Columns" and back.x == 4 and FirstLine() >= back.y + back.h,
      "at the top of the list its mirror leads back: an arrow and Columns, with the list starting under it")
TEXTLOG = {}
ns.Rerender()
RunTimers()
check(#Seats() == 0 and drew("Juno Ash") and drew("Pim Sorrel"), "in the list everyone has a line, and there is no bench")
Draw(made[3])
check(Back() == nil and More() == nil and not Shown("Expand all") and #Seats() == 0,
      "another run, of five or fewer, keeps its columns and has neither arrow nor bench")
Draw(six)
check(Back() ~= nil and More() == nil, "coming back to the run, it is still a list")
Back().click()
check(More() ~= nil and Back() == nil and #Seats() == 1, "Columns brings its columns and its bench back")
o.useColumns = false
Draw(six)
check(More() == nil and Back() == nil and Shown("Expand all"),
      "with Always a list chosen there is no arrow: every run is a list")
o.useColumns = true

-- The Podium window: the top five on the podium, the others named below.
TEXTLOG = {}
ns.OpenRunWindow("podium", six)
RunTimers()
check(PodiumLine("Juno Ash") == "Juno Ash " .. junoAward .. " " .. Plain(ns.Money(300)),
      "the Podium names the sixth under the stage, with award and loot value (" .. tostring(PodiumLine("Juno Ash")) .. ")")
podium:Hide()

-- A raid of forty: five columns, and of the thirty-five others as many
-- cards as one row holds; the arrow says how many are left.
local raid = { name = "Raid Keep", startedAt = NOW - 9000, endedAt = NOW - 600, owner = WORLD.me, players = {} }
for i = 1, 40 do
    raid.players[("Raider %02d"):format(i)] = { class = "MAGE", items = { x = {
        link = ItemLink(2000 + i, "Thing", 2), count = 1, vendor = 1000 * (41 - i), cat = "uncommon", quality = 2,
        resolved = true } } }
end
table.insert(db.history, 1, raid)
local ok = pcall(Draw, raid)
seats, more = Seats(), More()
local fits = math.floor((WIDTH - ARROW) / (CARD + GAP))
check(ok and #seats == fits and seats[1].who == "Raider 06" and seats[fits].who == ("Raider %02d"):format(5 + fits),
      ("a raid of forty: five columns, and the next %d by loot on cards"):format(fits))
check(more and more.label == "List\n" .. (35 - fits) .. " more" and more.hidden == 35 - fits,
      "the arrow says List, and under it how many more there are: " .. tostring(more and more.label):gsub("\n", " / "))
local row, apart = true, true
for i, seat in ipairs(seats) do
    if seat.y ~= seats[1].y or seat.w ~= CARD or seat.h ~= seats[1].h then row = false end
    if i > 1 and seats[i - 1].x + seats[i - 1].w > seat.x then apart = false end
end
check(row and apart and more.y == seats[1].y and more.x >= seats[fits].x + CARD and more.x + more.w <= WIDTH,
      "one row, card after card, the arrow last, and nothing past the edge of the window")
check(seats[1].x == (WIDTH - fits * (CARD + GAP) - ARROW) / 2, "the row is centred")
more.click()
check(Back() ~= nil and #Seats() == 0, "the arrow leads to the list, where all forty have a line")
Back().click()

-- On paper: a ticket printed in ink, the arrow on a till key.
ns.SetTheme("receipt")
Draw(raid)
seats, more = Seats(), More()
check(#seats == fits and seats[1].name == "RAIDER 06" and more.label == "LIST\n" .. (35 - fits) .. " MORE",
      ("in the Receipt theme names are printed in capitals, and so is the key (%s, %s)"):format(
          seats[1].name, (more.label:gsub("\n", " / "))))
more.click()
check(Back() and Back().label == "COLUMNS", "and so is the key that leads back")
Back().click()
ns.SetTheme("classic")
Draw(raid)
check(#Seats() == fits and More().label == "List\n" .. (35 - fits) .. " more", "the Classic theme has them too")
ns.SetTheme("modern")
Draw(raid)

TEXTLOG = {}
ns.OpenRunWindow("podium", raid)
RunTimers()
local line = PodiumLine("Raider 13") or ""
check(line:find("Raider 06 ", 1, true) and not line:find("Raider 14", 1, true) and line:find("and 27 more", 1, true),
      "its Podium names eight of them and counts the other twenty-seven")
TEXTLOG = {}
ns.OpenRunWindow("podium", made[3])
RunTimers()
check(PodiumLine("Raider 13") == nil and not drew("more"), "and names nobody under a run of five or fewer")
podium:Hide()

-- The example addon's raid has forty players, so that it shows all of this.
local file = io.open(TEST_DIR .. "/../ThatLuckyBastard_Example/Example.lua", "r")
local source = file:read("*a")
file:close()
LoadAddonFile("Example.lua", source)
RunTimers()
local example = ns.exampleRuns[#ns.exampleRuns]
local players = 0
for _ in pairs(example.players) do players = players + 1 end
Draw(example)
check(players == 40 and #Seats() == fits and More() and More().label == "List\n" .. (35 - fits) .. " more",
      ("the example raid: %d players, %d cards, and an arrow that counts the rest"):format(players, #Seats()))
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (lifecycle)")
