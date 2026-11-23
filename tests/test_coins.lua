-- Coins looted from mobs: read from the game's money messages, counted
-- per player at face value, shown as a Coins line, saved and shared with
-- the run. A share of split coins goes to everyone in the group close
-- enough to be seen; coins looted alone go to you alone.
print("\n==== coins ====")
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local o = db.options
o.ticker, o.streak, o.popupLeave, o.race = false, false, false, false

ITEMS[301] = { 3, 50000, 4, 1 } -- 5g at the vendor, bind on pickup
local sword = ItemLink(301, "Sword", 3)
local ME = WORLD.me

local function Player(s, name)
    for _, p in ipairs(ns.Summarize(s).players) do
        if p.name == name then return p end
    end
end
local function Money(s, name) return (s.players[name] or {}).money end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if tostring(t):find(text, 1, true) then return true end
    end
    return false
end

print("==== reading the game's money messages ====")
SlashCmdList.THATLUCKYBASTARD("start")
local solo = db.active
check(solo and solo.manual, "a manual run is started")
Coins("You loot 1 Gold, 5 Silver, 3 Copper")
check(Money(solo, ME) == 10503, "\"You loot 1 Gold, 5 Silver, 3 Copper\" is 10503 copper")
Coins("You loot 27 Copper")
check(Money(solo, ME) == 10530, "coins add up")
Coins("You loot 1 Silver (5 Copper deposited to guild bank)")
check(Money(solo, ME) == 10630, "the guild bank's part is not yours")
Coins("You loot 3|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 2|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
check(Money(solo, ME) == 40830, "amounts drawn as coin icons are read too")
Coins("Someone loots 5 Silver.")
Coins("You are refunded 5 Silver.")
Coins("You loot nothing at all")
check(Money(solo, ME) == 40830, "other money messages are left alone")

local sum = ns.Summarize(solo)
local me = Player(solo, ME)
check(me.money == 40830 and me.market == 40830 and me.vendor == 40830 and me.count == 0,
      "coins count in the totals, at auction and vendor alike, and are no item")
check(me.cats.coins and me.cats.coins.market == 40830 and #me.cats.coins.items == 0, "they are a category with no items")
check(sum.money == 40830 and sum.market == 40830, "and in the run's total")

print("==== shown in the window ====")
TEXTLOG = {}
ns.ShowRun(solo)
check(drew("Coins") and drew(ns.Money(40830)), "the column shows a Coins heading with the amount")
check(not drew("No loot seen"), "a player with only coins has loot")
o.groupByCategory = false
TEXTLOG = {}
ns.Refresh()
RunTimers()
check(drew("Coins") and drew(ns.Money(40830)), "with no categories, a Coins line")
o.groupByCategory, o.useColumns = true, false
TEXTLOG = {}
ns.Refresh()
RunTimers()
check(drew(ns.Money(40830)), "the list shows the total with the coins")
o.useColumns = true

print("==== the options ====")
o.cats.coins = false
me = Player(solo, ME)
check(me.money == 0 and me.market == 0 and not me.cats.coins, "Coins switched off: neither shown nor counted")
o.countHidden = true
me = Player(solo, ME)
check(me.money == 40830 and me.market == 40830 and not me.cats.coins, "hidden but counted: in the totals only")
o.cats.coins, o.countHidden = true, false
local needOnly = ns.Summarize(solo, true)
check(needOnly.market == 0 and needOnly.money == 0, "Need only leaves coins out: none is won on a roll")

print("==== a run of only coins is kept ====")
SlashCmdList.THATLUCKYBASTARD("stop")
check(db.history[1] == solo, "the manual run with nothing but coins is kept")
NOW = NOW + 3600
Coins("You loot 9 Gold")
check(Money(solo, ME) == 40830 and db.active == nil, "coins looted with no run going are not counted")

print("==== a group: shares go to everyone near ====")
WORLD.party = { { "Bryn Ash", "WARRIOR", "TANK" }, { "Cole Dart", "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9001, "Test Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
local run = db.active
check(run and not run.manual and run.players["Bryn Ash"], "a dungeon run with the group")
WORLD.visible = true
Coins("Your share of the loot is 25 Silver.")
check(Money(run, ME) == 2500 and Money(run, "Bryn Ash") == 2500 and Money(run, "Cole Dart") == 2500,
      "a share of split coins: the same to everyone close enough to be seen")
WORLD.visible = false
Coins("Your share of the loot is 10 Copper.")
check(Money(run, ME) == 2510 and Money(run, "Bryn Ash") == 2500, "out of sight: not given a share")
WORLD.visible = true
Coins("You loot 4 Silver")
check(Money(run, ME) == 2910 and Money(run, "Cole Dart") == 2500, "coins looted alone are yours alone")
Coins("Your share of the loot is 2 Silver. (1 Copper deposited to guild bank)")
check(Money(run, ME) == 3110 and Money(run, "Bryn Ash") == 2700, "a split share with a guild part")
Loot(("Bryn Ash receives loot: %s."):format(sword))
local fair = ns.Fairness(ns.Summarize(run))
check(Player(run, "Bryn Ash").market == 50000 + 2700, "items and coins together")
local function firstAt(text, from)
    for i = from or 1, #TEXTLOG do
        if tostring(TEXTLOG[i]):find(text, 1, true) then return i end
    end
end
for _, columns in ipairs({ true, false }) do
    o.groupByCategory, o.useColumns = true, columns
    ns.ShowRun(run)
    RunTimers()
    if not columns then -- the list's players open, with their lines under them
        for _, w in ipairs(FRAMES) do
            local text = rawget(w, "text")
            if type(text) == "table" and text.__text == "Expand all" and w.__scripts.OnClick then
                w.__scripts.OnClick(w, "LeftButton")
            end
        end
    end
    TEXTLOG = {}
    ns.Refresh()
    RunTimers()
    -- In Bryn Ash's lines, who has both.
    local from = firstAt("Bryn Ash") or 1
    local coins, bop = firstAt("Coins", from), firstAt("Bind on Pickup", from) or firstAt("BoP", from)
    check(coins and bop and coins < bop, "Coins come first, above the items ("
          .. (columns and "columns" or "list") .. ")")
end
o.useColumns = true

print("==== /tlb capture keeps money lines ====")
SlashCmdList.THATLUCKYBASTARD("capture")
Coins("You loot 1 Copper")
local captured = false
for _, line in ipairs(db.capture or {}) do
    if line:find("MONEY You loot 1 Copper", 1, true) then captured = true end
end
SlashCmdList.THATLUCKYBASTARD("capture")
check(captured, "the capture records them")

print("==== exported, shared and saved with the run ====")
local csv = ns.ExportRun(run)
check(csv:find("Cole Dart,MAGE,DAMAGER,Coins,,,,0.2700,0.2700,coins,0,0", 1, true) ~= nil, "the CSV has a Coins line per player")

local back = ns.DecodeRun(ns.EncodeRun(run))
check(back and back.players[ME].money == 3111 and back.players["Bryn Ash"].money == 2700
      and back.players["Cole Dart"].money == 2700, "a share code carries each player's coins")
local before = run.players["Cole Dart"].money
run.players["Cole Dart"].money = nil
local older = ns.DecodeRun(ns.EncodeRun(run))
run.players["Cole Dart"].money = before
check(older and older.players["Cole Dart"].money == nil, "a player without coins (an older code) reads as none")

WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
RunTimers()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false)
check(db.history[1] == run and run.recorded, "the run is closed")
Reload()
local saved
for _, v in ipairs(SAVED.history) do
    if v.c and v.c:find("Test Keep", 1, true) then saved = v end
end
check(saved ~= nil and saved.players == nil, "the run with coins is saved packed, as one code")
local loaded = db.history[1]
check(loaded.players[ME].money == 3111 and loaded.players["Bryn Ash"].money == 2700, "and comes back with its coins")
check(Player(loaded, "Bryn Ash").market == 52700, "worth the same after a reload")
