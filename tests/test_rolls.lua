-- Who needed what: the All | Need switch of Analysis > Rolls, which took
-- over from the breakdown's Need only button (0.7.1). Need keeps only the
-- rolls won on Need, and its line says who won how many, worth how much.
print("\n==== rolls: All | Need ====")
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
local H = "|HlootHistory:%d|h[Loot]|h: "
local ME, BRYN, COLE = WORLD.me, "Bryn Ash", "Cole Dart"

ITEMS[501] = { 3, 50000, 4, 1 } -- a blue, bound on pickup: 5g at the vendor
ITEMS[502] = { 2, 10000, 4, 1 } -- a green, bound on pickup: 1g
local swordLink, gemLink = ItemLink(501, "Sword", 3), ItemLink(502, "Gem", 2)

WORLD.party = { { BRYN, "WARRIOR", "TANK" }, { COLE, "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9001, "Test Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
local run = db.active
Loot((H .. "%s has selected Need for: %s"):format(1, BRYN, swordLink))
Loot((H .. "%s won: %s"):format(1, BRYN, swordLink))
Loot(("%s receives loot: %s."):format(BRYN, swordLink))
Loot((H .. "%s has selected Greed for: %s"):format(2, COLE, gemLink))
Loot((H .. "%s won: %s"):format(2, COLE, gemLink))
Loot(("%s receives loot: %s."):format(COLE, gemLink))
RunTimers()

local function Plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The rows of the Rolls tab on show, as the method each roll was won by.
local function Rows()
    local list = {}
    for _, w in ipairs(FRAMES) do
        local roll = rawget(w, "roll")
        if type(roll) == "table" and roll.method and w:IsShown() then list[#list + 1] = roll.method end
    end
    table.sort(list)
    return table.concat(list, " ")
end
-- The switch's two buttons, by value.
local switch = {}
for _, w in ipairs(FRAMES) do
    local v = rawget(w, "value")
    if rawget(w, "isTab") and (v == "all" or v == "need") then switch[v] = w end
end
local function Flip(v) switch[v].tpl.__scripts.OnClick(switch[v].tpl) end
local function Said(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
local function Button(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w end
    end
end

print("-- the breakdown")
ns.ShowRun(run)
RunTimers()
check(Button("Need only") == nil, "the breakdown no longer has a Need only button")
check(Button("Front page") ~= nil and Button("Analysis") ~= nil and Button("Meter") ~= nil, "the other buttons are there")

print("-- All")
TEXTLOG = {}
ns.ShowAnalysis("rolls", run)
check(switch.all and switch.need and switch.all:IsShown() and switch.all.selected and not switch.need.selected,
      "the Rolls tab has an All | Need switch, on All to begin with")
check(Rows() == "greed need" and Said("2 rolls: 1 Need, 1 Greed."), "All: every roll that was won")

print("-- Need")
TEXTLOG = {}
Flip("need")
check(switch.need.selected and not switch.all.selected, "a click switches to Need")
check(Rows() == "need", "Need: only what was won on Need")
check(Said("Need wins: Bryn 1 (5g") and not Said("Cole"), "and who won how many, worth how much")

print("-- kept")
ns.ToggleRunWindow("analysis", run) -- shut
TEXTLOG = {}
ns.ShowAnalysis("rolls", run)
check(switch.need.selected and Rows() == "need", "shut and opened again, it is still on Need")
TEXTLOG = {}
Flip("all")
check(Rows() == "greed need" and Said("2 rolls:"), "and All shows everything again")
Flip("need")

print("-- a run with no rolls")
SlashCmdList.THATLUCKYBASTARD("stop")
WORLD.inInstance, WORLD.party = false, {}
Fire("PLAYER_ENTERING_WORLD", false, false)
SlashCmdList.THATLUCKYBASTARD("start")
Loot(("You receive loot: %s."):format(gemLink))
RunTimers()
TEXTLOG = {}
ns.ShowAnalysis("rolls", db.active)
check(not switch.all:IsShown() and not switch.need:IsShown() and Rows() == ""
      and Said("Nothing has been rolled for in this run."), "nothing to switch: no switch")
SlashCmdList.THATLUCKYBASTARD("stop")

print("-- Need with no Need win")
WORLD.party = { { BRYN, "WARRIOR", "TANK" }, { COLE, "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9003, "Greed Keep"
NOW = NOW + 3600
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
local greedy = db.active
Loot((H .. "%s has selected Greed for: %s"):format(3, COLE, gemLink))
Loot((H .. "%s won: %s"):format(3, COLE, gemLink))
Loot(("%s receives loot: %s."):format(COLE, gemLink))
RunTimers()
TEXTLOG = {}
ns.ShowAnalysis("rolls", greedy)
check(greedy ~= run and switch.need:IsShown() and switch.need.selected and Rows() == ""
      and Said("No Need wins in this run."), "another run, still on Need: it says nobody won on Need")
TEXTLOG = {}
ns.ShowAnalysis("rolls", run)
check(switch.need.selected and Rows() == "need" and Said("Need wins: Bryn 1"), "and back on the first run, its Need win")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (rolls)")
