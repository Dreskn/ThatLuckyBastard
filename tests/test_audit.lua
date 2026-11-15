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

Fire("ADDON_LOADED", "FairShare")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = FairShareDB
db.options.ticker = false

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
check(not FairShareFrame:IsShown() and not FairShareShowFrame:IsShown(), "stepping in and out with no loot opens nothing")
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
check(FairShareFrame:IsShown(), "leaving with loot opens the window")
NOW = NOW + 900
enter(1, "Keep")
StaticPopupDialogs.FAIRSHARE_NEW_RUN.OnAccept()
check(db.active ~= first and db.history[1] == first, "answering Yes starts a new run")
check(first.endedAt == leftAt, "the old run ended when it was left, not when the question was answered")
check(first.rolls == nil and first.lastSeen == nil and select(2, next(mine.items)).lastAt == nil,
      "working data is dropped from a closed run")

print("==== /fs stop inside a dungeon ====")
local second = db.active
SlashCmdList.FAIRSHARE("stop")
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
SlashCmdList.FAIRSHARE("start")
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
FairShareFrame:Hide()
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

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (audit regressions)")
