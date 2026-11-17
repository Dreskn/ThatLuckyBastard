-- Regression tests for faults found in the pre-release audit: run
-- boundaries, roll messages, statistics that must not be skewed, and the
-- bingo card.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local H = "|HlootHistory:%d|h[Loot]|h: "
local function enter(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
end
local function leave()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
end

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
db.options.ticker = false

print("==== defaults ====")
check(db.theme == "modern" and db.options.portrait == "2d" and db.options.sortPlayers == "podium",
      "a new install starts in the Modern theme, with 2D portraits and players in podium order")
db.theme = "classic"
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(db.theme == "classic", "a player who chose Classic keeps it")
db.theme = "modern"

ITEMS[100] = { 2, 1500, 4, 2 }   -- green BoE
ITEMS[103] = { 0, 300, 15, 0 }   -- junk
ITEMS[104] = { 3, 12000, 2, 1 }  -- blue BoP
ITEMS[105] = { 4, 90000, 2, 2 }  -- epic BoE
local green, junk, blue, epic = ItemLink(100, "Green Gloves", 2), ItemLink(103, "Broken Fang", 0),
    ItemLink(104, "Boss Mace", 3), ItemLink(105, "Purple Thing", 4)
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { "Kett Longstride", "HUNTER", "DAMAGER" } }

print("==== run boundaries ====")
enter(1, "Keep")
local first = db.active
leave()
check(not ThatLuckyBastardFrame:IsShown() and not ThatLuckyBastardPodiumFrame:IsShown(), "stepping in and out with no loot opens nothing")
NOW = NOW + 30
enter(1, "Keep")
check(db.active == first, "coming straight back continues the run")

-- The same item before and after a level-up is one entry.
Loot(("You receive loot: %s."):format(green))
Loot(("You receive loot: %s."):format((green:gsub(":38:1489:", ":39:1489:"))))
local mine = first.players["Mira Vale"]
local entries = 0
for _ in pairs(mine.items) do entries = entries + 1 end
check(entries == 1 and select(2, next(mine.items)).count == 2, "an item looted before and after a level-up is one entry of 2")

print("==== roll messages ====")
Loot((H .. "Everyone passed on: %s"):format(5, junk))
check(not (first.rollStats and first.rollStats["Everyone"]) and next(first.rolls or {}) == nil,
      "'Everyone passed' is not a player called Everyone, and closes the roll")
Loot((H .. "%s automatically passed on: %s because he cannot loot that item."):format(6, "Borin Oak", blue))
Loot((H .. "%s passed on: %s"):format(6, "Kett Longstride", blue))
Loot((H .. "Greed Roll - %d for %s by %s"):format(6, 54, blue, "Sela Marrow"))
Loot((H .. "Greed Roll - %d for %s by %s"):format(6, 54, blue, "Sela Marrow"))
local st = first.rollStats
check(st["Borin Oak automatically"] == nil and not (st["Borin Oak"] and st["Borin Oak"].passes > 0),
      "an automatic pass is not a chosen pass, nor a player called 'Borin Oak automatically'")
check(st["Kett Longstride"].passes == 1, "a chosen pass counts")
check(st["Sela Marrow"].n == 1, "a roll number reported twice counts once")
Loot((H .. "%s won: %s"):format(6, "Sela Marrow", blue))
Loot(("%s receives loot: %s."):format("Sela Marrow", blue))
local sheet = ns.RunRolls(first)
local passers = 0
for _, r in ipairs(sheet[1].rolls) do
    if r.choice == "pass" then passers = passers + 1 end
end
check(#sheet == 1 and passers == 2, "the roll sheet lists both passes, automatic and chosen")

print("==== boss kills ====")
Fire("ENCOUNTER_END", 55, "Big Boss", 1, 4, 1)
Fire("ENCOUNTER_END", 55, "Big Boss", 1, 4, 1)
Fire("ENCOUNTER_END", 56, "Other Boss", 1, 4, 1)
Fire("ENCOUNTER_END", 57, "Wiped On", 1, 4, 0)
check(first.kills == 2 and #first.bosses == 2, "the same boss twice counts once; a wipe does not count")

print("==== answering 'new run?' late ====")
NOW = NOW + 600
leave()
local leftAt = NOW
check(ThatLuckyBastardFrame:IsShown(), "leaving with loot opens the window")
NOW = NOW + 900
enter(1, "Keep")
StaticPopupDialogs.THATLUCKYBASTARD_NEW_RUN.OnAccept()
check(db.active ~= first and db.history[1] == first, "answering Yes starts a new run")
check(first.endedAt == leftAt, "the old run ended when it was left, not when the question was answered")
check(first.rolls == nil and first.lastSeen == nil and select(2, next(mine.items)).lastAt == nil,
      "working data is dropped from a closed run")

print("==== /tlb stop inside a dungeon ====")
local second = db.active
SlashCmdList.THATLUCKYBASTARD("stop")
check(db.active ~= nil and db.active ~= second, "tracking goes on with a new run")

print("==== logging back in the next day, still inside ====")
Loot(("You receive loot: %s."):format(junk))
local third = db.active
NOW = NOW + 300
Fire("PLAYER_LOGOUT")
local seen = NOW
NOW = NOW + 86400
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(db.history[1] == third and third.endedAt == seen, "the old run ended when it was last seen")
check(ns.RunDuration(third) < 3600, "and is not a day long (" .. ns.RunDuration(third) .. " s)")
check(db.active ~= nil and db.active ~= third, "a new run started")

print("==== logging out inside, back in outside a minute later ====")
Loot(("You receive loot: %s."):format(junk))
local fourth = db.active
Fire("PLAYER_LOGOUT")
NOW = NOW + 60
WORLD.inInstance = false
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(db.active == fourth and fourth.leftAt ~= nil, "the run is left, not closed: it can still be resumed")

print("==== another character of the account ====")
local before = db.records[1].sumMine
WORLD.me = "Alt Two"
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(db.active == nil and db.history[1] == fourth, "the main's run is closed when an alt logs in")
check(db.records[1].sumMine > before, "its loot is counted as the main's own")
check(db.people["Mira Vale"] == nil, "and the main is not filed among the people the alt has run with")
WORLD.me = "Mira Vale"
Fire("PLAYER_LOGIN")

print("==== a manual run forgotten over a logout ====")
SlashCmdList.THATLUCKYBASTARD("start")
Loot(("You receive loot: %s."):format(junk))
Fire("PLAYER_LOGOUT")
NOW = NOW + 7 * 86400
WORLD.inInstance = true
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(db.active ~= nil and not db.active.manual and db.active.instanceID == 1, "is closed at login, and the dungeon run starts")

print("==== people met once, long ago ====")
db.people["Old Timer"] = { runs = 1, value = 1, lucky = 0, ninja = 0, last = NOW - 200 * 86400 }
db.people["Old Friend"] = { runs = 9, value = 1, lucky = 0, ninja = 0, last = NOW - 200 * 86400 }
Fire("PLAYER_LOGIN")
check(db.people["Old Timer"] == nil and db.people["Old Friend"] ~= nil, "are forgotten; regulars are not")

print("==== the window ====")
db.options.showSilver, db.options.showCopper = false, true
check(ns.MoneyPlain(123405) == "12g", "silver off, copper on: 12g 34s 05c reads 12g, not 12g 05c (" .. ns.MoneyPlain(123405) .. ")")
check(ns.MoneyPlain(3405) == "34s 05c" and ns.MoneyPlain(5) == "5c", "smaller amounts still show their largest unit")
db.options.showSilver = true

-- The window stays on the run it shows when a new run starts.
leave()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false) -- long gone: closed
ns.ShowRun(first)
check(ns.ViewedRun() == first, "showing an old run")
enter(2, "Other Place")
ns.Rerender()
check(ns.ViewedRun() == first, "it is still on show after a new run started")
ThatLuckyBastardFrame:Hide()
check(ns.ViewedRun() == db.active, "with the window closed, 'the run on show' is the latest")

-- Lowering the number of runs to keep does not delete anything at once.
local kept = #db.history
db.options.maxHistory = 1
ns.ToggleOptions()
ns.ToggleOptions()
check(#db.history == kept and kept > 1, "choosing a lower number of runs to keep deletes nothing by itself (" .. kept .. " runs)")
db.options.maxHistory = 30

print("==== bingo ====")
db.options.cats.junk = false -- hidden categories must still tick their squares
local run = db.active
run.bingo = { keys = { "junk10", "blue", "epic", "boss1", "green", "greens3", "quest", "junk5", "mats20", "mats50",
                       "items100", "item1g", "item10g", "total5g", "total25g", "died" },
              done = {}, lines = 0 }
local notices = 0
local realNotice = ns.Notice
ns.Notice = function(title, ...)
    if title:find("BINGO", 1, true) then notices = notices + 1 end
    return realNotice(title, ...)
end
Loot(("%s receives loot: %sx%d."):format("Borin Oak", junk, 10))
Loot(("You receive loot: %s."):format(epic))
RunTimers()
check(run.bingo.done.junk10 == true, "'10 greys looted' ticks although junk is hidden in the window")
check(run.bingo.done.epic == true and not run.bingo.done.blue, "an epic ticks 'an epic drops' but not 'a blue item drops'")
Fire("ENCOUNTER_END", 70, "Boss", 1, 4, 1)
Loot(("You receive loot: %s."):format(blue))
RunTimers()
check(run.bingo.done.boss1 and run.bingo.done.blue and run.bingo.lines == 1, "the top row is complete: one line")
check(notices == 1, "announced once (" .. notices .. ")")
for _ = 1, 3 do
    Loot(("You receive loot: %s."):format(junk))
    RunTimers()
end
ns.ToggleBingo(); ns.ToggleBingo()
check(notices == 1, "and not again on later loot or on opening the card")
ns.Notice = realNotice
db.options.cats.junk = true

-- A card dealt for a solo run has nothing that needs a group.
WORLD.party = {}
leave()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false)
enter(3, "Alone")
Loot(("You receive loot: %s."):format(junk))
RunTimers()
local solo, groupOnly = db.active.bingo, 0
for _, key in ipairs(solo and solo.keys or {}) do
    if key == "everyone" or key == "shared" or key == "needwin" or key == "youwin" or key == "twowins"
            or key == "greed3" or key == "pass" or key == "high" or key == "low" then
        groupOnly = groupOnly + 1
    end
end
check(solo ~= nil and #solo.keys == 16 and groupOnly == 0, "a solo card has 16 squares, none of which needs a group")

print("==== junk: vendor price by default, auction on a right-click ====")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 5000 end } } }
ITEMS[110] = { 0, 40, 15, 0 }   -- a grey item nobody has looted yet
ITEMS[111] = { 2, 900, 4, 2 }   -- a green BoE, likewise
Loot(("You receive loot: %s."):format(ItemLink(110, "Chipped Tooth", 0)))
Loot(("You receive loot: %s."):format(ItemLink(111, "Green Belt", 2)))
local grey, greenBelt
for _, e in pairs(db.active.players["Mira Vale"].items) do
    if ns.ItemKey(e) == "110" then grey = e elseif ns.ItemKey(e) == "111" then greenBelt = e end
end
local function value(e)
    ns.Summarize(db.active) -- works out which price each item uses
    return ns.EntryMarket(e)
end
check(grey and grey.cat == "junk" and grey.ah == 5000, "a grey item's auction price is recorded")
check(value(grey) == 40, "but it is worth its vendor price by default")
check(greenBelt and value(greenBelt) == 5000, "a green BoE is worth its auction price by default")
check(ns.ToggleAuctionPrice(db.active, grey) and value(grey) == 5000, "a right-click switches the grey to its auction price")
check(ns.ToggleAuctionPrice(db.active, greenBelt) and value(greenBelt) == 900, "and the green to its vendor price")
ns.ToggleAuctionPrice(db.active, grey)
ns.ToggleAuctionPrice(db.active, greenBelt)
check(value(grey) == 40 and value(greenBelt) == 5000, "another right-click on each puts them back")
Auctionator = nil

-- Which of two windows is in front: the higher strata, then the one
-- raised last.
local STRATA = { MEDIUM = 1, HIGH = 2, DIALOG = 3, FULLSCREEN_DIALOG = 4 }
local function inFront(a, b)
    local sa, sb = STRATA[a.__strata] or 0, STRATA[b.__strata] or 0
    if sa ~= sb then return sa > sb end
    return (a.__raised or 0) > (b.__raised or 0)
end
-- Whether a text was drawn since TEXTLOG was last emptied.
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t == text then return true end
    end
    return false
end
-- Clicks the main window's button with this label.
local function click(label, button)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == label and w.__scripts.OnClick then
            w.__scripts.OnClick(w, button or "LeftButton")
            return true
        end
    end
    return false
end

print("==== item search: each item at the price it has in its run ====")
local alone = db.active
leave()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false) -- long gone: closed, and its working notes dropped
check(db.history[1] == alone and grey.noAH == nil, "the run with the grey item is closed")
TEXTLOG = {}
ns.ShowBrowse("search", "Chipped")
check(drew(ns.Money(40)) and not drew(ns.Money(5000)), "the grey item is listed at its vendor price, not its auction price")

print("==== a right-click on a price redraws every window ====")
ns.ShowRun(alone)
ns.ShowBrowse("search", "Green Belt")
local beltRow
for _, w in ipairs(FRAMES) do
    local line = rawget(w, "line")
    if type(line) == "table" and line.e == greenBelt and w.__scripts.OnClick then beltRow = w end
end
-- The value the item search shows for the green belt.
local function searchValue()
    for _, w in ipairs(FRAMES) do
        local cells = rawget(w, "cells")
        if cells and rawget(w, "link") == greenBelt.link and w:IsShown() then return cells[5].__text end
    end
end
check(searchValue() == ns.Money(5000), "the item search shows the green at its auction price")
if beltRow then beltRow.__scripts.OnClick(beltRow, "RightButton") end
check(beltRow ~= nil and searchValue() == ns.Money(900), "a right-click in the main window: the search shows its vendor price at once")
ns.ToggleAuctionPrice(alone, greenBelt)

print("==== statistics: a run opened from them comes to the front ====")
local browse = ThatLuckyBastardBrowseFrame
ns.ShowRun(first)
check(inFront(ThatLuckyBastardFrame, browse), "the run is in front of the statistics")
ns.ShowBrowse("dungeons")
check(inFront(browse, ThatLuckyBastardFrame), "and the statistics in front of it when opened again")
ns.ToggleOptions()
check(inFront(ThatLuckyBastardOptionsFrame, browse) and inFront(ThatLuckyBastardOptionsFrame, ThatLuckyBastardFrame),
      "the options stay in front of both")
ns.ToggleOptions()
ThatLuckyBastardBingoFrame:Hide()
ns.ToggleBingo()
check(inFront(ThatLuckyBastardBingoFrame, ThatLuckyBastardFrame) and inFront(ThatLuckyBastardBingoFrame, browse),
      "the bingo card opens in front of the main window and the statistics")
ns.ToggleBingo()

print("==== the buttons that open a window close it too ====")
local podiumWin, paperWin, timelineWin = ThatLuckyBastardPodiumFrame, ThatLuckyBastardPaperFrame, ThatLuckyBastardTimelineFrame
podiumWin:Hide()
browse:Hide()
ns.ShowRun(first)
check(click("Podium") and podiumWin:IsShown(), "Podium opens its window")
check(click("Front page") and paperWin:IsShown() and podiumWin:IsShown(), "Front page opens its own, beside it")
check(click("Timeline") and timelineWin:IsShown(), "so does Timeline")
check(click("Podium") and not podiumWin:IsShown() and click("Front page") and not paperWin:IsShown()
      and click("Timeline") and not timelineWin:IsShown(), "a second click closes each one")
check(click("Statistics") and browse:IsShown(), "Statistics opens")
check(click("Statistics") and not browse:IsShown(), "and a second click closes it")

print("==== rolls and numbers: statistics tabs that follow the run on show ====")
local function onShow(s)
    return ("The run on show in the main window: %s, %s."):format(s.name, ns.DateText(s.startedAt))
end
ns.ShowBrowse("dungeons")
TEXTLOG = {}
check(click("Rolls") and drew(onShow(first)), "the Rolls tab is about the run on show")
local another = db.history[1] ~= first and db.history[1] or db.history[2]
TEXTLOG = {}
ns.ShowRun(another)
check(drew(onShow(another)), "and follows the main window to another run")
TEXTLOG = {}
check(click("Numbers") and drew(onShow(another)), "so does the Numbers tab")
TEXTLOG = {}
check(click("Dungeons") and not drew(onShow(another)), "the other tabs are about all your runs, as before")
browse:Hide()

print("==== a queue that pops inside a dungeon ====")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { "Kett Longstride", "HUNTER", "DAMAGER" } }
local notices = 0
ns.Notice = function(title, ...)
    if title:find("in a row", 1, true) then notices = notices + 1 end
    return realNotice(title, ...)
end
enter(10, "Queue One")
local q1 = db.active
Loot(("You receive loot: %s."):format(green))
Loot(("%s receives loot: %s."):format("Borin Oak", epic))
ThatLuckyBastardFrame:Hide()
ThatLuckyBastardPodiumFrame:Hide()
NOW = NOW + 600
enter(11, "Queue Two") -- straight from one dungeon into the next
RunTimers()
check(db.active ~= q1 and db.active.instanceID == 11 and db.history[1] == q1 and q1.endedAt == NOW,
      "the first run ends as the second one starts")
check(ThatLuckyBastardFrame:IsShown() and ThatLuckyBastardPodiumFrame:IsShown(), "the window and the podium open, as on leaving")
check(ns.ViewedRun() == q1, "on the run that just ended, not the new empty one")

print("==== the streak notice, once per run ====")
local q2 = db.active
Loot(("You receive loot: %s."):format(green))
NOW = NOW + 600
leave()
check(notices == 1, "leaving the second run with the same group: a streak notice")
NOW = NOW + 60
enter(11, "Queue Two") -- back in, to repair say
check(db.active == q2, "coming back continues the run")
ThatLuckyBastardFrame:Hide()
NOW = NOW + 60
leave()
check(ThatLuckyBastardFrame:IsShown() and notices == 1, "leaving again opens the window, but no second notice")
ns.Notice = realNotice

print("==== a duo is a group ====")
local function runOf(name, id, start, others)
    local players = { ["Mira Vale"] = { items = {} } }
    for _, n in ipairs(others) do players[n] = { items = {} } end
    return { name = name, instanceID = id, owner = "Mira Vale", startedAt = start, endedAt = start + 500, players = players }
end
local duo1, duo2 = runOf("Duo A", 20, NOW - 2000, { "Pal Friend" }), runOf("Duo B", 21, NOW - 1400, { "Pal Friend" })
table.insert(db.history, 1, duo1)
table.insert(db.history, 1, duo2)
local streak = ns.Streak(duo2)
check(streak and streak.kind == "group" and streak.count == 2, "two runs in a row with the same partner are a streak")
duo1.players = { ["Mira Vale"] = { items = {} } }
duo2.players = { ["Mira Vale"] = { items = {} } }
check(ns.Streak(duo2) == nil, "two runs alone in different dungeons are not")
table.remove(db.history, 1)
table.remove(db.history, 1)

print("==== roll wins whose item never came ====")
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false)
enter(12, "Roll Keep")
local rolls = db.active
Loot((H .. "%s has selected Need for: %s"):format(40, "Borin Oak", blue))
Loot((H .. "%s won: %s"):format(40, "Borin Oak", blue)) -- and the mace never reaches his bags
Loot((H .. "%s has selected Need for: %s"):format(41, "Sela Marrow", epic))
Loot((H .. "%s won: %s"):format(41, "Sela Marrow", epic))
NOW = NOW + 2
Loot(("%s receives loot: %s."):format("Sela Marrow", epic)) -- this one does, a moment later
NOW = NOW + 600
Loot(("%s receives loot: %s."):format("Borin Oak", blue)) -- another mace, picked up later
local function entry(name, id)
    for _, e in pairs(rolls.players[name].items) do
        if ns.ItemKey(e) == id then return e end
    end
end
check(entry("Sela Marrow", "105").need == 1, "a win whose loot line follows is tagged as won on Need")
check(entry("Borin Oak", "104").need == nil, "a later pickup of an item whose win was never looted is not")

print("==== switching to the list view stops the award reveal ====")
local shots = 0
local realScreenshot = Screenshot
Screenshot = function() shots = shots + 1 end
db.options.ceremonyScreenshot = true
ThatLuckyBastardPodiumFrame:Hide()
TIMERS = {}
ns.ShowWindow(true, q1)
RunTimers()
check(shots == 1, "a reveal left to finish takes its screenshot")
TIMERS = {}
ns.ShowWindow(true, q1)
db.options.useColumns = false
ns.Rerender()
RunTimers()
check(shots == 1, "one cut short by the list view takes none")
db.options.useColumns, db.options.ceremonyScreenshot = true, false
Screenshot = realScreenshot

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (audit regressions)")
