-- The Example addon (0.8.3): its runs are built like finished runs, with
-- pickup times, boss kills, rolls and coins, so every window shows them
-- as it shows a real run. Nothing of them is saved.
print("\n==== example runs ====")
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
local ns = NS
local db = ThatLuckyBastardDB
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

-- Every item the examples name exists here: trade goods worth a little,
-- and the drops that matter, as they are in the game.
setmetatable(ITEMS, { __index = function(_, id) return { 1, 50 + id % 400, 7, 0 } end })
ITEMS[873] = { 4, 30000, 2, 2 }       -- Staff of Jordan, epic BoE
ITEMS[1482] = { 3, 8000, 2, 2 }       -- Shadowfang, blue BoE
for _, id in ipairs({ 7230, 5201, 5191, 7720, 7723 }) do ITEMS[id] = { 3, 4000, 2, 1 } end -- dungeon BoP
for _, id in ipairs({ 4865, 7073, 7074 }) do ITEMS[id] = { 0, 30, 15, 0 } end             -- junk
for _, id in ipairs({ 17069, 18203, 16863, 18822, 17105, 17103, 16867, 17077, 17076, 18814, 17063, 17102 }) do
    ITEMS[id] = { 4, 50000, 2, 1 }    -- Molten Core, epic BoP
end
ITEMS[14513] = { 4, 20000, 9, 2 }     -- a pattern, BoE
ITEMS[13036] = { 3, 15000, 2, 2 }     -- Assassination Blade, blue BoE

local file = io.open(TEST_DIR .. "/../ThatLuckyBastard_Example/Example.lua", "r")
local source = file:read("*a")
file:close()
LoadAddonFile("Example.lua", source)
local runs = ns.exampleRuns
check(#runs == 3 and runs[1].name == "The Deadmines" and runs[2].name == "Scarlet Monastery"
      and runs[3].name == "Molten Core", "three example runs")
check(#runs[1].log == 0, "their loot waits for the price addons")
RunTimers()

local want = {
    { minutes = 52, players = 5, bosses = 7, rolls = 5 },
    { minutes = 38, players = 5, bosses = 3, rolls = 2 },
    { minutes = 178, players = 40, bosses = 10, rolls = 14 },
}
for i, s in ipairs(runs) do
    local w = want[i]
    print("-- " .. s.name)
    local players, classes = 0, true
    for _, p in pairs(s.players) do
        players = players + 1
        if not (p.class and p.role) then classes = false end
    end
    check(players == w.players and classes, players .. " players, each with a class and a role")
    check(ns.RunDuration(s) == w.minutes * 60, "a run of " .. w.minutes .. " minutes")
    check(#s.bosses == w.bosses and s.kills == w.bosses, #s.bosses .. " boss kills")

    -- Every pickup points to an item of its player.
    local found = 0
    for _, line in ipairs(s.log) do
        local t, who, id = line:match("^(%d+):(%d+):(%d+):%d+$")
        local p = s.players[s.names[tonumber(who)]]
        for _, e in pairs(p and p.items or {}) do
            if e.id == tonumber(id) and tonumber(t) <= ns.RunDuration(s) then found = found + 1 end
        end
    end
    check(#s.log > 0 and found == #s.log, #s.log .. " pickups, each of an item its player has")

    -- Every roll was won by the highest Need, or the highest Greed when
    -- nobody chose Need, with numbers from 1 to 100.
    local rolls, fair = ns.RunRolls(s), true
    for _, roll in ipairs(rolls) do
        local top = roll.rolls[1]
        if top.name ~= roll.winner or top.choice ~= roll.method then fair = false end
        for _, r in ipairs(roll.rolls) do
            if r.roll and (r.roll < 1 or r.roll > 100) then fair = false end
        end
        if not ns.RollItem(s, roll) then fair = false end
    end
    check(#rolls == w.rolls and fair, #rolls .. " rolls, each won by the right roll, on an item its winner has")

    local timeline = ns.Timeline(s)
    check(timeline and #timeline.bosses == w.bosses and timeline.duration == w.minutes * 60,
          "a timeline, with its bosses")
    local sources = ns.Sources(s)
    check(sources and sources.boss > 0 and sources.trash + sources.mats > 0, "loot from bosses and from the rest")
    local sum = ns.Summarize(s)
    check(sum.money > 0 and sum.market > sum.money, "coins, and loot worth more")

    -- Every window opens on it as on a real run.
    TEXTLOG = {}
    ns.ShowAnalysis("timeline", s)
    check(not drew("no timeline") and not drew("Nothing has been picked up"), "Analysis › Timeline draws it")
    TEXTLOG = {}
    ns.ShowAnalysis("rolls", s)
    check(drew(("%d rolls"):format(w.rolls)), "Analysis › Rolls lists its rolls")
    TEXTLOG = {}
    ns.ShowAnalysis("numbers", s)
    ns.OpenRunWindow("paper", s)
    local lead = false
    for _, t in ipairs(TEXTLOG) do
        if t:find("^A party of %d+ emerged from .- after ") then lead = true end
    end
    check(lead, "the Front page says how long the party was inside")
    ThatLuckyBastardPaperFrame:Hide()
end

print("-- awards")
local function Awards(s)
    local out = {}
    for name, award in pairs(ns.RunAwards(s, ns.Summarize(s))) do out[award.key] = name end
    return out
end
local deadmines = Awards(runs[1])
local fromRolls = 0
for _, key in ipairs({ "ninja", "lucky", "nat100", "snakeeyes", "heartbreak", "photo", "hunterloot" }) do
    if deadmines[key] then fromRolls = fromRolls + 1 end
end
check(fromRolls >= 3, fromRolls .. " Deadmines awards come from the rolls")
check(deadmines.heartbreak == "Thorgrim", "the tank's 97 against the rogue's 98 is a Heartbreak")
check(Awards(runs[2]).afk == "Quietmage", "the mage who did nothing in Scarlet Monastery is AFK")
local raid = ns.Awards(runs[3], ns.Summarize(runs[3]))
local numbered, pet = false, false
for _, award in pairs(raid) do
    if award.title:find(" II") then numbered = true end
    if award.key == "bosspet" then pet = true end
end
check(numbered and pet, "Molten Core has numbered awards and a Boss's Pet")

print("-- the windows")
db.options.useColumns = true
ns.ShowWindow(true, runs[1])
check(ns.Racing(), "the race runs on The Deadmines")
RunTimers()
ns.ShowWindow(false, runs[3])
check(ThatLuckyBastardFrame:IsShown(), "the main window shows the raid")
ns.ToggleMeter()
check(ThatLuckyBastardMeterFrame and ThatLuckyBastardMeterFrame:IsShown(), "and so does the meter")
ns.ToggleMeter()

print("-- nothing is saved")
local saved = false
for _, s in ipairs(ns.AllRuns()) do
    if s.example then saved = true end
end
check(not saved and #db.history == 0, "example runs are in neither your runs nor your statistics")

if FAILED then error(FAILED .. " check(s) failed") end
print("all checks passed (example)")
