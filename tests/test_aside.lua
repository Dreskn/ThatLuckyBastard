-- A farm and the dungeons on the way: going into a dungeon sets the farm
-- aside, its clock waiting at the door, the strip with only Stop. Out of
-- it, alive, the strip opens and asks "Add <dungeon> and resume?". Yes:
-- the farm goes on, the dungeon's time on its clock and your share of it
-- as one line (on the strip, the solo page, the columns, in codes and in
-- the saved file), while the zone's figures leave it out; the dungeon's
-- run is filed away, and the window stays on it. No, Stop, a login or
-- another farm: the farm ends at the door. Back inside, the question
-- waits; left dead, it waits until you are alive; two dungeons before an
-- answer give two lines; a pause ends at the door.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|r", ""))
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
local function tipHas(text)
    for _, line in ipairs(TIP) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
db.options.ticker = false
local strip, main, me = ns.FarmStrip, ThatLuckyBastardFrame, WORLD.me

ITEMS[300] = { 1, 4000, 7, 0 }  -- cloth, 40s
ITEMS[301] = { 2, 20000, 4, 2 } -- green BoE, 2g
local cloth, green = ItemLink(300, "Runecloth", 1), ItemLink(301, "Green Boots", 2)

local anim = 0
function GetTime() return NOW + anim end
local function Tick(dt)
    anim = anim + dt
    strip.__scripts.OnUpdate(strip, dt)
end
local function Small(fs) return Plain(fs:GetText()) end
local function Clock() return Plain(strip.clock:GetText()) end
local function Fmt(seconds)
    return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end
local function Enter(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    RunTimers()
end
local function Leave()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    RunTimers()
end
local function Mine(s)
    for _, p in ipairs(ns.Summarize(s).players) do
        if p.name == ns.Me(s) then return p end
    end
end
local function Start()
    SlashCmdList.THATLUCKYBASTARD("start")
    RunTimers()
    return db.active
end
local function Where(s)
    for i, run in ipairs(db.history) do
        if run == s then return i end
    end
end

print("-- a farm, then a dungeon: the farm waits at the door")
WORLD.map = 1460
local farm = Start()
local start = NOW
NOW = NOW + 60
Loot(("You receive loot: %sx%d."):format(cloth, 3))
RunTimers()
Tick(4)
NOW = NOW + 600
local door = NOW
Enter(9400, "Stratholme")
local dungeon = db.active
check(ns.FarmAside() == farm and ns.ActiveFarm() == nil and dungeon.instanceID == 9400 and farm.asideAt == door,
      "going in sets the farm aside; the dungeon's run starts")
check(not strip.main:IsShown() and strip.stop:IsShown() and Plain(strip.total:GetText()) == "1g 20s"
      and Clock() == "0:11:00" and not strip.ask:IsShown(),
      "the strip shows the farm as it stood at the door, with only Stop: " .. Clock())
TIP = {}
strip.__scripts.OnEnter(strip)
check(tipHas("Set aside for a dungeon."), "its tooltip says why")
NOW = NOW + 900
Loot(("You receive loot: %s."):format(green))
Coins("You loot 3 Gold")
Fire("QUEST_TURNED_IN", 5, 100, 10000)
RunTimers()
Tick(2)
local items = 0
for _ in pairs(farm.players[me].items) do items = items + 1 end
check(Clock() == "0:11:00" and items == 1 and (farm.players[me].money or 0) == 0 and Mine(dungeon).market > 0,
      "inside, the dungeon's run records; the farm nothing, and its clock waits")

print("-- a reload inside keeps it aside")
db = Reload()
Fire("PLAYER_ENTERING_WORLD", false, true)
RunTimers()
farm, dungeon = db.farmAside, db.active
check(farm and farm.asideAt == door and farm.startedAt == start and dungeon and dungeon.instanceID == 9400,
      "after a reload: the farm still aside, the dungeon's run going on")

print("-- out of it: the strip asks")
strip:Hide()
main:Hide()
NOW = NOW + 300
Leave()
check(main:IsShown() and ns.ViewedRun() == dungeon, "the dungeon's window opens, as ever")
check(strip:IsShown() and strip.ask:IsShown() and Plain(strip.ask:GetText()) == "Add Stratholme and resume?"
      and strip.yes:IsShown() and strip.no:IsShown() and not strip.total:IsShown(),
      "the strip opens, and asks in place of the gold row: " .. Plain(strip.ask:GetText()))
check(not strip.stop:IsShown() and not strip.main:IsShown() and strip.no.__points[1][5] == -36
      and strip.yes.__points[1][2] == strip.no, "with Yes and No at its right end, and no other key")
check(strip.__w >= 250 + 0 and strip.__w >= #("Add Stratholme and resume?") * 6, "as long as the question needs: " .. strip.__w)

print("-- back in, it waits; out again, it asks again")
NOW = NOW + 120
Enter(9400, "Stratholme")
check(not strip.ask:IsShown() and strip.stop:IsShown() and not strip.yes:IsShown() and db.active == dungeon,
      "back inside the same run: no question, Stop again")
NOW = NOW + 600
Loot(("You receive loot: %s."):format(green))
RunTimers()
strip:Hide()
main:Hide()
Leave()
check(strip:IsShown() and strip.ask:IsShown(), "out again: the strip opens and asks again")

print("-- Yes: the farm goes on, with the dungeon in it")
NOW = NOW + 60
local share, spent = Mine(dungeon), ns.RunDuration(dungeon)
strip.yes.__scripts.OnClick(strip.yes)
RunTimers()
local line = farm.dungeons and farm.dungeons[1]
check(db.active == farm and ns.ActiveFarm() == farm and ns.FarmAside() == nil and not farm.asideAt,
      "the farm is the one going on again")
check(line and #farm.dungeons == 1 and line.name == "Stratholme" and line.m == math.floor(share.market + 0.5)
      and line.v == math.floor(share.vendor + 0.5) and line.t == spent and line.m == 70000,
      "one line for the dungeon: your share of it (7g) and its time")
check(db.history[1] == dungeon and dungeon.endedAt == dungeon.leftAt, "the dungeon's run is over, filed away")
check(main:IsShown() and ns.ViewedRun() == dungeon, "the window stays on the dungeon")
check(Clock() == Fmt(NOW - start), "the clock has the dungeon's time in it: " .. Clock())
check(strip.main.glyph == "pause" and strip.stop:IsShown() and not strip.ask:IsShown() and strip.total:IsShown(),
      "the strip is a farm's again")
Tick(0.1)
check(Small(strip.dungeons) == "dungeons 7g" and strip.hour.__points[1][2] == strip.dungeons
      and Plain(strip.total:GetText()) == "8g 20s",
      "your total has it, and the dungeons are a small figure of their own: " .. Plain(strip.total:GetText())
      .. ", " .. Small(strip.dungeons))
local cols = ns.Breakdown.BuildColumnLines(ns.Summarize(farm), db.options)
check(Plain(cols[1][1] and cols[1][1].label) == "Stratholme" and Plain(cols[1][1].value) == "7g 00s",
      "in the breakdown, one line, before the loot")

print("-- Stop: the solo page, and the zone's figures without the dungeon")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
Tick(4)
TEXTLOG = {}
strip.stop.__scripts.OnClick(strip.stop)
RunTimers()
check(db.history[1] == farm and main:IsShown() and ns.ViewedRun() == farm, "Stop: the farm, on its page")
check(drew("In dungeons") and drew(ns.Duration(spent)) and drew("Stratholme"),
      "the solo page: the time in dungeons, and the dungeon's line with the loot")
local rec = db.farms[1460]
local mine = Mine(farm)
check(rec and rec.farms == 1 and rec.mine == mine.market - mine.dungeon and rec.mine == 16000
      and rec.time == ns.RunDuration(farm) - spent, "the zone's figures leave the dungeon out, its gold and its time")

print("-- codes and the saved file carry the dungeons")
local back = ns.DecodeRun(ns.EncodeRun(farm))
local d = back and back.dungeons and back.dungeons[1]
check(d and #back.dungeons == 1 and d.name == "Stratholme" and d.m == line.m and d.v == line.v and d.t == line.t,
      "a farm's code carries its dungeons")
check(Mine(back).market == mine.market, "and its total with them")
local record = ns.PackRun(farm)
check(record and not (record.x and record.x.dungeons) and ns.UnpackRun(record).dungeons[1].m == line.m,
      "the saved file packs them with the rest")
db = Reload()
Fire("PLAYER_ENTERING_WORLD", false, true)
local kept
for _, run in ipairs(db.history) do
    if run.startedAt == start and run.manual then kept = run end
end
check(kept and kept.dungeons and kept.dungeons[1].m == line.m, "and they are kept from one session to the next")
main:Hide()

print("-- Stop inside: the farm ends at the door, and shows")
local second = Start()
NOW = NOW + 60
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
local door2 = NOW
Enter(9401, "Scholomance")
NOW = NOW + 300
strip.stop.__scripts.OnClick(strip.stop)
RunTimers()
check(ns.FarmAside() == nil and second.endedAt == door2 and main:IsShown() and ns.ViewedRun() == second
      and db.active.instanceID == 9401, "Stop: ended where you went in, shown; the dungeon's run goes on")
Leave()
main:Hide()

print("-- a login ends it at the door")
local third = Start()
local thirdStart = NOW
NOW = NOW + 60
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
local door3 = NOW
Enter(9400, "Stratholme")
NOW = NOW + 600
db = Reload()
NOW = NOW + 3600
Fire("PLAYER_ENTERING_WORLD", true, false)
RunTimers()
third = nil
for _, run in ipairs(db.history) do
    if run.startedAt == thirdStart and run.manual then third = run end
end
check(db.farmAside == nil and third and third.endedAt == door3, "a login: the farm ended at the door, quietly")
Leave()
main:Hide()

print("-- another farm, the question unanswered: the one set aside ends at the door")
local fourth = Start()
NOW = NOW + 60
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
local door4 = NOW
Enter(9402, "Live Keep")
local dungeon4 = db.active
NOW = NOW + 300
Loot(("You receive loot: %s."):format(green))
Leave()
main:Hide()
check(strip.ask:IsShown(), "asked")
local fifth = Start()
check(fifth and fifth.manual and fifth ~= fourth and fourth.endedAt == door4 and Where(dungeon4) == 1 and Where(fourth) == 2,
      "a new farm: the other ended at the door, filed after the dungeon it waited through")
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
main:Hide()

print("-- left dead, it waits until you are alive; two dungeons, two lines")
local sixth = Start()
NOW = NOW + 60
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
Enter(9403, "Dead Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(green))
WORLD.dead = true
Leave()
check(ns.AsideAsk() == nil and not strip.ask:IsShown(), "left dead: no question yet")
WORLD.dead = false
Fire("PLAYER_ALIVE")
RunTimers()
check(ns.AsideAsk() == sixth and strip.ask:IsShown() and Plain(strip.ask:GetText()) == "Add Dead Keep and resume?",
      "alive outside: it asks")
main:Hide()
NOW = NOW + 60
Enter(9404, "Second Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(green))
Leave()
check(Plain(strip.ask:GetText()) == "Add 2 dungeons and resume?", "another dungeon before an answer: " .. Plain(strip.ask:GetText()))
strip.yes.__scripts.OnClick(strip.yes)
RunTimers()
check(db.active == sixth and #sixth.dungeons == 2 and sixth.dungeons[1].name == "Dead Keep"
      and sixth.dungeons[2].name == "Second Keep", "Yes: a line for each, in order")
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
main:Hide()

print("-- a pause ends at the door")
local seventh = Start()
NOW = NOW + 60
Loot(("You receive loot: %s."):format(cloth))
RunTimers()
strip.main.__scripts.OnClick(strip.main) -- pause
NOW = NOW + 100
Enter(9405, "Paused Keep")
check(seventh.pausedAt == nil and seventh.pausedFor == 100, "the pause ends at the door")
NOW = NOW + 300
Leave()
strip.yes.__scripts.OnClick(strip.yes)
check(db.active == seventh and not seventh.pausedAt and strip.main.glyph == "pause",
      "Yes: the farm runs again")
check(seventh.dungeons and seventh.dungeons[1].m == 0 and seventh.dungeons[1].t == 300 and Small(strip.dungeons) == "",
      "a dungeon with nothing of yours still has its line, for its time; the strip has no figure for it")
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (aside)")
