-- Farms: runs started by hand outside dungeons, on the farm strip. Start,
-- Pause and Stop; the clock leaves pauses out; each pickup drops out under
-- the strip and folds back into the total; coins and the others' loot
-- rise above the totals they go into; the strip splits your total into
-- coins and items; in a group, a switch above it holds the group's total,
-- and a click slides it to solo (yours alone) and back. Quest
-- rewards count, the items received around a turn-in and its gold. A farm goes on through reloads, ends
-- at the logout on a real login; a dungeon sets it aside, and No to the
-- question on the way out ends it at the door (test_aside: the rest). Stopped, it
-- opens on the solo page (or columns with each one's time in the group),
-- without a reveal, awards, bets or Front page. Farms count by zone in
-- Statistics, apart from dungeons; people you farm with count apart too.
-- And notes: one line of your own on any run, kept, never shared.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|r", ""))
end
local function tipHas(text)
    for _, line in ipairs(TIP) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local o = db.options
o.ticker = false
local strip = ns.FarmStrip
local main = ThatLuckyBastardFrame
local me = WORLD.me

ITEMS[300] = { 1, 4000, 7, 0 }   -- cloth, 40s
ITEMS[301] = { 2, 20000, 4, 2 }  -- green BoE, 2g
ITEMS[302] = { 0, 600, 15, 0 }   -- junk, 6s
for id = 303, 309 do ITEMS[id] = { 1, 100, 7, 0 } end
local cloth, green, junk = ItemLink(300, "Runecloth", 1), ItemLink(301, "Green Boots", 2), ItemLink(302, "Broken Fang", 0)

-- The strip's frames on show: its pop-up lines and its rising amounts.
local function Shown(flag)
    local list = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, flag) and w:IsShown() then list[#list + 1] = w end
    end
    return list
end
local function Rising()
    local out = {}
    for _, f in ipairs(strip.floats) do out[#out + 1] = f.fs end
    return out
end
-- Time passes on the strip: GetTime() runs on, while the clock of
-- time(), in whole seconds as in the game, is moved by the test itself.
local anim = 0
function GetTime() return NOW + anim end
local function Tick(dt)
    anim = anim + dt
    strip.__scripts.OnUpdate(strip, dt)
end
local function Total() return Plain(strip.total:GetText()) end

print("-- opening the strip, starting a farm")
WORLD.map = 1452
check(not strip:IsShown(), "the farm strip is shut to begin with")
local mm = ThatLuckyBastardMinimapButton
SHIFT = true
mm.__scripts.OnClick(mm, "LeftButton")
SHIFT = nil
check(strip:IsShown() and not main:IsShown(), "shift-click on the minimap button opens the farm strip, not the window")
mm.__scripts.OnEnter(mm)
check(tipHas("Shift-click: farm tracker"), "its tooltip says so")
check(Plain(strip.clock:GetText()) == "0:00:00" and Total() == "That Lucky Bastard" and strip.main.glyph == "start"
      and not strip.stop:IsShown(), "before a farm: the clock at nought, and only the Start key")
check(strip.__h == 50 and strip.__w == 250 and strip.logo.__points[1][5] == -15 and strip.total.__points[1][5] == -36,
      "two rows: the clock and the keys, then the gold, 250 long")
WORLD.inInstance = true
Fire("PLAYER_ENTERING_WORLD", false, false)
strip.main.__scripts.OnClick(strip.main)
check(ns.ActiveFarm() == nil and db.active and not db.active.manual, "inside a dungeon, Start starts nothing")
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
main:Hide()
strip.main.__scripts.OnClick(strip.main)
RunTimers()
local s = db.active
check(s and s.manual and s.name == "Somewhere" and s.zone == 1452 and ns.ActiveFarm() == s,
      "Start begins a farm, named after the zone and kept under its map")
check(strip.main.glyph == "pause" and strip.stop:IsShown(), "farming: Pause and Stop")

print("-- a pickup drops out, then folds back into the total")
local started = NOW
NOW = NOW + 60
Loot(("You receive loot: %sx%d."):format(cloth, 3))
RunTimers()
local pops = Shown("farmPop")
check(#pops == 1 and Plain(pops[1].label:GetText()) == "3x [Runecloth]" and Plain(pops[1].value:GetText()) == "+1g 20s",
      "it shows how many and what they are worth: " .. Plain(pops[1] and pops[1].label:GetText()))
check(Total() == "-", "the total leaves it out while it is out: " .. Total())
Tick(1)
Loot(("You receive loot: %sx%d."):format(cloth, 3))
RunTimers()
pops = Shown("farmPop")
check(#pops == 1 and Plain(pops[1].label:GetText()) == "6x [Runecloth]" and Plain(pops[1].value:GetText()) == "+2g 40s",
      "the same item again adds to its line")
Tick(2)
check(Total() == "-" and #Shown("farmPop") == 1, "and it stays a while longer")
Tick(1.2)
check(#Shown("farmPop") == 0 and Total() == "2g 40s", "folded back: its worth is in the total: " .. Total())
check(strip.total:GetText():find("|cff40c7b8", 1, true) ~= nil, "which lights up in the accent")
Tick(1)
check(not strip.total:GetText():find("|cff40c7b8", 1, true), "for a moment")
check(Plain(strip.clock:GetText()) == "0:01:00", "the clock, from time(): " .. Plain(strip.clock:GetText()))

print("-- coins rise above the total")
Coins("You loot 1 Gold, 5 Silver")
RunTimers()
local rising = Rising()
check(#rising == 1 and Plain(rising[1]:GetText()) == "+1g 05s" and #Shown("farmPop") == 0,
      "coins get no line: their amount rises above the total")
check(Total() == "2g 40s", "and are left out of it until they are in")
Tick(0.1)
check(rising[1].__points[1][2] == strip.clock and rising[1].__points[1][3] == "RIGHT",
      "rising out of the gold row into the free part of the row above, after the clock")
Tick(1.5)
check(#Rising() == 0 and Total() == "3g 45s", "then they are: " .. Total())
local function Small(fs) return Plain(fs:GetText()) end
check(Small(strip.coins) == "coins 1g" and Small(strip.items) == "items 2g",
      "beside the total, your coins over your items: " .. Small(strip.coins) .. " / " .. Small(strip.items))
check(Small(strip.hour) == "207g/h" and strip.coins.__points[1][2] == strip.total and strip.items.__points[1][2] == strip.coins
      and strip.hour.__points[1][2] == strip.items and Small(strip.group) == "",
      "the gold row: total, coins, items, per hour, one after the other: " .. Small(strip.hour))
check(strip.__w >= 250, "the strip grows when the gold row needs it, never shorter than 250: " .. strip.__w)

print("-- at most five lines out")
for id = 303, 309 do
    Loot(("You receive loot: %s."):format(ItemLink(id, "Thing " .. id, 1)))
end
RunTimers()
Tick(0.2)
local full = 0
for _, p in ipairs(Shown("farmPop")) do
    if (p.__h or 0) >= 25.9 then full = full + 1 end
end
check(#Shown("farmPop") == 7 and full == 5, "seven picked up: five stay, the two oldest fold early")
Tick(4)
check(#Shown("farmPop") == 0, "and all fold in the end")

print("-- quest rewards")
ITEMS[310] = { 2, 15000, 4, 1 } -- a bound ring, 1g 50s
ITEMS[311] = { 1, 500, 0, 0 }    -- a potion, 5s
ITEMS[312] = { 1, 2000, 0, 0 }   -- something bought, 20s
local ring, potion = ItemLink(310, "Ring of Thanks", 2), ItemLink(311, "Small Potion", 1)
local function Has(id)
    for _, e in pairs(s.players[me].items) do
        if e.link:find("item:" .. id .. ":", 1, true) then return e.count end
    end
    return 0
end
Loot(("You receive item: %s."):format(ring))
check(Has(310) == 0, "an item received is not loot: it waits")
Tick(0.5)
Fire("QUEST_TURNED_IN", 77, 450, 25000)
RunTimers()
check(Has(310) == 1, "a quest turned in just after: it was a reward, and counts")
check(s.players[me].money == 10500 + 25000, "the quest's gold counts as coins: " .. s.players[me].money)
rising = Rising()
check(#rising == 1 and Plain(rising[1]:GetText()) == "+2g 50s", "and rises above the total")
Tick(1)
Loot(("You receive item: %sx%d."):format(potion, 2))
RunTimers()
check(Has(311) == 2, "an item received just after a turn-in counts too")
Tick(5)
Loot(("You receive item: %s."):format(ItemLink(312, "Bought Thing", 1)))
Tick(5)
RunTimers()
check(Has(312) == 0, "one received with no turn-in near it (bought, say) does not")
check(Total() == "7g 62s" and Small(strip.coins) == "coins 3g" and Small(strip.items) == "items 4g",
      "the strip has them: " .. Total() .. ", " .. Small(strip.coins) .. " / " .. Small(strip.items))

print("-- pause")
local looted = s.players[me].items
local count = 0
for _, e in pairs(looted) do count = count + e.count end
local before = ns.RunDuration(s)
strip.main.__scripts.OnClick(strip.main)
check(s.pausedAt and strip.main.glyph == "start", "Pause: the key becomes Resume")
NOW = NOW + 600
Loot(("You receive loot: %s."):format(green))
local after = 0
for _, e in pairs(s.players[me].items) do after = after + e.count end
check(after == count and ns.RunDuration(s) == before, "paused, nothing is recorded and the clock stops")
strip.main.__scripts.OnClick(strip.main)
check(not s.pausedAt and s.pausedFor == 600, "Resume: the pause is kept apart (600 s)")

print("-- a group comes and goes")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
Fire("GROUP_ROSTER_UPDATE")
RunTimers()
NOW = NOW + 300
Loot(("%s receives loot: %s."):format("Borin Oak", green))
RunTimers()
rising = Rising()
check(#rising == 1 and Plain(rising[1]:GetText()) == "+2g 00s" and #Shown("farmPop") == 0,
      "what the others get rises as its worth alone")
check(Plain(strip.group:GetText()):find("group", 1, true) ~= nil, "a group total shows beside yours: " .. Plain(strip.group:GetText()))
Tick(0.1)
check(strip.tab:IsShown() and strip.tab.__points[1][1] == "BOTTOMRIGHT" and strip.tab.__points[1][3] == "TOPRIGHT"
      and rising[1].__points[1][2] == strip.group,
      "the group's total is on its tab above the strip, and the others' amounts rise above it")
check(strip.hour.__points[1][2] == strip.items, "the strip keeps to yours")
Tick(1.6)
check(Total() == "7g 62s" and Plain(strip.group:GetText()) == "group 9g", "yours stays yours; the group's has it: "
      .. Total() .. " / " .. Plain(strip.group:GetText()))
strip.main.__scripts.OnClick(strip.main) -- pause
NOW = NOW + 200
strip.main.__scripts.OnClick(strip.main) -- resume
NOW = NOW + 100
WORLD.party = {}
Fire("GROUP_ROSTER_UPDATE")
check(ns.StayTime(s, "Borin Oak") == 400, "time in the group leaves the pause out: " .. ns.StayTime(s, "Borin Oak"))

print("-- reloads go on; a real login ends it at the logout")
Fire("PLAYER_ENTERING_WORLD", false, true)
check(db.active == s, "a reload: the farm goes on")
NOW = NOW + 60
Reload()
db = ThatLuckyBastardDB
local loggedOut = NOW
NOW = NOW + 3600
main:Hide()
Fire("PLAYER_ENTERING_WORLD", true, false)
local farm = db.history[1]
check(db.active == nil and farm.manual and farm.endedAt == loggedOut and not main:IsShown(),
      "a login: the farm ended at the logout, quietly")
check(ns.RunDuration(farm) == loggedOut - started - 800, "its time leaves both pauses out: " .. ns.RunDuration(farm))
check(farm.players[me].time and farm.players["Borin Oak"].time == 400 and farm.players[me].since == nil,
      "everyone's time in the group is kept")

print("-- going into a dungeon sets a farm aside; No ends it at the door")
strip.main.__scripts.OnClick(strip.main)
local second = db.active
NOW = NOW + 60
Loot(("You receive loot: %s."):format(junk))
local door = NOW
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9300, "Farm Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Loot(("You receive loot: %s."):format(junk))
check(ns.FarmAside() == second and ns.ActiveFarm() == nil and db.active and db.active.instanceID == 9300
      and not main:IsShown(), "the farm is set aside, quietly, and the dungeon's run starts")
NOW = NOW + 300
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
RunTimers()
check(strip.ask:IsShown() and Plain(strip.ask:GetText()) == "Add Farm Keep and resume?" and strip.no:IsShown(),
      "out of it, the strip asks: " .. Plain(strip.ask:GetText()))
strip.no.__scripts.OnClick(strip.no)
check(ns.FarmAside() == nil and db.history[1] == second and second.endedAt == door and db.active.instanceID == 9300,
      "No: the farm ended at the door")
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
main:Hide()

print("-- Stop: the solo page")
WORLD.map = 1453
SlashCmdList.THATLUCKYBASTARD("start")
local solo = db.active
check(solo and solo.manual and strip:IsShown(), "/tlb start starts a farm too")
NOW = NOW + 1200
Loot(("You receive loot: %sx%d."):format(cloth, 10))
Loot(("You receive loot: %s."):format(green))
TEXTLOG = {}
strip.stop.__scripts.OnClick(strip.stop)
RunTimers()
check(db.history[1] == solo and main:IsShown() and not ns.Racing(), "Stop opens the window on it, with no race")
local panel
for _, w in ipairs(FRAMES) do
    if rawget(w, "soloPanel") then panel = w end
end
check(panel and panel:IsShown(), "one player: the solo page")
check(drew("Farmed") and drew("20m 00s") and drew("Per hour") and drew("Best item") and drew("Click to write a note"),
      "its figures: time farmed, per hour, best item, the note")
check(drew("30/h") and drew("per hour"), "and each item per hour (10 cloth in 20 minutes)")
check(next(ns.RunAwards(solo, ns.Summarize(solo))) == nil, "a farm has no awards")
local function button(label)
    for _, w in ipairs(FRAMES) do
        if rawget(w, "label") == label and rawget(w, "tpl") and w.__parent ~= nil then return w end
    end
end
check(not button("Front page"):IsShown() and not button("Bet"):IsShown() and button("Farm"):IsShown(),
      "no Front page and no Bet on a farm; the Farm key opens the strip")
check(Plain(main.__name and ThatLuckyBastardFrame and ns.Breakdown.runLabel:GetText()):find("farm", 1, true) ~= nil,
      "its label says farm")
check(strip.main.glyph == "start" and not strip.stop:IsShown() and Total() == "That Lucky Bastard",
      "the strip is ready for the next, with the addon's name where the gold goes")

print("-- a group farm: columns with each one's time")
SlashCmdList.THATLUCKYBASTARD("start")
local duo = db.active
WORLD.party = { { "Sela Marrow", "MAGE", "DAMAGER" } }
Fire("GROUP_ROSTER_UPDATE")
NOW = NOW + 900
Loot(("%s receives loot: %s."):format("Sela Marrow", green))
Loot(("You receive loot: %s."):format(cloth))
TEXTLOG = {}
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
check(db.history[1] == duo and not ns.Racing() and not panel:IsShown(), "two players: columns, and no race")
check(drew("In group 15m 00s"), "each column says how long they were in the group")
check(drew("Farmed"), "the footer says Farmed")
SlashCmdList.THATLUCKYBASTARD("race")
check(ns.Racing(), "/tlb race still plays the race on a group farm")
ns.Breakdown.CancelReveal()
WORLD.party = {}
Fire("GROUP_ROSTER_UPDATE")
check(db.people["Sela Marrow"].farms == 1 and (db.people["Sela Marrow"].runs or 0) == 0,
      "who you farm with counts apart from your runs")

print("-- solo in a group: yours alone")
WORLD.map = 1454
WORLD.party = { { "Tam Vell", "ROGUE", "DAMAGER" } }
Fire("GROUP_ROSTER_UPDATE")
SlashCmdList.THATLUCKYBASTARD("start")
RunTimers()
local alone = db.active
check(alone.players["Tam Vell"] and strip.tab:IsShown() and Plain(strip.group:GetText()):find("^group") ~= nil,
      "in a group, a farm takes the group in; its total on the tab")
local tab = strip.tab
tab.__scripts.OnClick(tab)
RunTimers()
check(alone.solo and alone.players["Tam Vell"] == nil and Plain(strip.group:GetText()) == "group"
      and Plain(strip.soloWord:GetText()) == "solo" and tab.side == "solo" and db.farmStrip.solo,
      "a click on the switch: solo; the others leave the farm, and the group's total goes")
check(tab.thumb.__points[1][2] == tab.slot and tab.thumb.__points[1][4] == 1, "the slider starts at the group's end")
Tick(0.075)
check(tab.thumb.__points[1][4] == 9, "and slides over: " .. tab.thumb.__points[1][4])
Tick(0.2)
check(tab.thumb.__points[1][4] == 17, "to the solo end: " .. tab.thumb.__points[1][4])
NOW = NOW + 600
Loot(("%s receives loot: %s."):format("Tam Vell", green))
Coins("Your share of the loot is 50 Silver.")
Loot(("You receive loot: %s."):format(cloth))
Fire("GROUP_ROSTER_UPDATE")
RunTimers()
check(alone.players["Tam Vell"] == nil and alone.players[me].money == 5000 and #Rising() == 1,
      "their loot is not recorded, nor a share of coins for them; nor are they taken in again")
Tick(5)
main:Hide()
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
check(main:IsShown() and panel:IsShown() and alone.solo == nil, "Stop: the solo page")
check(db.people["Tam Vell"] == nil or (db.people["Tam Vell"].farms or 0) == 0, "and nobody is counted as farmed with")
main:Hide()
SlashCmdList.THATLUCKYBASTARD("start")
RunTimers()
local again = db.active
check(again.solo and again.players["Tam Vell"] == nil, "the next farm starts solo, as the last was set")
tab.__scripts.OnClick(tab)
RunTimers()
check(not again.solo and again.players["Tam Vell"] ~= nil and not db.farmStrip.solo and tab.side == "group"
      and Plain(strip.group:GetText()):find("^group ") ~= nil, "a click again: the group is taken in, its total back")
SlashCmdList.THATLUCKYBASTARD("stop")
RunTimers()
main:Hide()
WORLD.party = {}
Fire("GROUP_ROSTER_UPDATE")

print("-- Statistics: farms by zone, apart from dungeons")
local rec = db.farms[1453]
check(rec and rec.farms == 2 and rec.time == 2100 and rec.mine == 64000 and rec.best == 180000,
      "the zone's figures: two farms, 35 minutes, 6g 40s, best 18g an hour (the solo one)")
check(rec.items["301"] and rec.items["301"].c == 1, "and what you got there")
check(db.farms[1452] and db.farms[1452].farms == 2 and db.farms[1452].best == nil,
      "farms under 15 minutes of clock set no best")
TEXTLOG = {}
ns.ShowBrowse("farms")
check(drew("By zone") and drew("Every farm") and drew("Top loot") and drew("Somewhere"), "a Farms page, by zone")
check(drew("11x [Runecloth]  4g 40s"), "with the loot that brought the most")
TEXTLOG = {}
for _, w in ipairs(FRAMES) do
    if rawget(w, "view") == "farm" then w.tpl.__scripts.OnClick(w.tpl) end
end
check(drew("Click a farm to open it.") and drew("Solo") and drew("2 players"), "and every farm, alone or not")
TEXTLOG = {}
ns.ShowBrowse("runs")
check(drew("Farm Keep") and not drew("Somewhere"), "Runs keeps to dungeons")

print("-- every look")
for _, theme in ipairs({ "classic", "receipt", "modern" }) do
    ns.SetTheme(theme)
    ns.ShowRun(solo)
    SlashCmdList.THATLUCKYBASTARD("start")
    Loot(("You receive loot: %s."):format(green))
    RunTimers()
    Tick(0.1)
    local paper = strip.bg.__color and strip.bg.__color[1] > 0.9
    check(panel:IsShown() and #Shown("farmPop") == 1 and (theme == "receipt") == (paper == true),
          theme .. ": the solo page and the strip draw (paper strip on the Receipt)")
    strip.stop.__scripts.OnClick(strip.stop)
    RunTimers()
    Tick(5)
end

print("-- sharing a farm: pauses and time in the group go along, the note does not")
ns.SetRunNote(farm, "  furbolgs | east camp  ")
check(farm.note == "furbolgs  east camp", "a note: one line, trimmed, no escapes: " .. tostring(farm.note))
local code = ns.EncodeRun(farm)
local back = ns.DecodeRun(code)
check(back and back.manual and back.pausedFor == farm.pausedFor and back.players["Borin Oak"].time == 400
      and ns.RunDuration(back) == ns.RunDuration(farm), "a farm's code keeps it a farm, its pauses and stays")
check(not code:find("furbolgs", 1, true) and back.note == nil, "the note is not in the code")
local record = ns.PackRun(farm)
check(record and record.x and record.x.note == "furbolgs  east camp" and record.x.zone == 1452,
      "but it is saved with the run")
ns.SetRunNote(farm, "")
check(farm.note == nil, "an empty note removes it")
ns.SetRunNote(farm, ("x"):rep(400))
check(#farm.note <= ns.NOTE_MAX * 3, "and a note is kept short")

print("-- writing a note")
ns.ShowRun(farm)
local label = ns.Breakdown.noteLabel
label.__scripts.OnClick(label)
local box = ns.NoteBox
check(box:IsShown() and FOCUSED == box, "a click on the run's label opens a box to type in")
box:SetText("good spot")
box.__scripts.OnEnterPressed(box)
check(farm.note == "good spot" and not box:IsShown() and Plain(ns.Breakdown.runLabel:GetText()):find("good spot", 1, true),
      "Enter keeps it, shown after the label")
label.__scripts.OnClick(label)
box:SetText("nope")
box.__scripts.OnEscapePressed(box)
check(farm.note == "good spot", "Escape lets it go")
TEXTLOG = {}
ns.ShowBrowse("farms")
check(drew("good spot"), "Every farm shows the note")
Reload()
local kept
for _, run in ipairs(ThatLuckyBastardDB.history) do
    if run.startedAt == farm.startedAt then kept = run end
end
check(kept and kept.note == "good spot", "a note is kept from one session to the next")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (farm)")
