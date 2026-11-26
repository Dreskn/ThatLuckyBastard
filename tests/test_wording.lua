-- Wording (0.8.3): the help, the award rules, the Front page of a run
-- still going and of a dungeon called "The ...", and plurals.
print("\n==== wording ====")
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
local ns = NS
local db = ThatLuckyBastardDB
local o = db.options
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
local function Printed(fn)
    local lines, real = {}, print
    print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    local ok, err = pcall(fn)
    print = real
    if not ok then error(err, 0) end
    return lines
end

print("-- the help")
local help = Printed(function() SlashCmdList.THATLUCKYBASTARD("help") end)
local joined = table.concat(help, "\n")
check(joined:find("/tlb theme modern, classic or receipt", 1, true) ~= nil, "the theme line names the three themes")
local piped = false
for _, line in ipairs(help) do
    -- The chat prefix is coloured; what follows it must hold no colour code.
    local body = line:match("^.-Bastard|r: (.*)$") or line
    if body:find("|", 1, true) then piped = true end
end
check(not piped, "no help line holds a | the game would read as a colour code")
check(not joined:find("/lucky", 1, true) and SLASH_THATLUCKYBASTARD2 == nil, "/lucky is gone, from the help too")

print("-- award rules")
local how = {}
for _, def in ipairs(ns.AwardGuide()) do how[def.key] = def.how end
check(how.dryspell == "Lost 12 or more rolls in a row.", "Dry Spell: " .. tostring(how.dryspell))
check(how.hotstreak == "Won 3 or more rolls in a row, each against another roller.", "Hot Streak: " .. tostring(how.hotstreak))
local bare = {}
for key, text in pairs(how) do
    if text:find("%d+ rolls in a row") then bare[#bare + 1] = key end
end
check(#bare == 0, "no rule gives a bare number of rolls in a row " .. table.concat(bare, ", "))

-- A run built by hand, as in test_awards.
local nextId = 40000
local function NewRun(name, names)
    local s = { name = name, startedAt = NOW - 3600, endedAt = NOW - 600, owner = names[1],
                players = {}, names = {}, log = {}, rollLog = {}, bosses = {}, rollStats = {} }
    for i, who in ipairs(names) do
        s.names[i] = who
        s.players[who] = { class = "MAGE", items = {} }
        s.rollStats[who] = { sum = 0, n = 0, passes = 0 }
    end
    return s
end
local function Index(s, who)
    for i, n in ipairs(s.names) do
        if n == who then return i end
    end
end
local function Give(s, who, vendor, need)
    nextId = nextId + 1
    local e = { link = ItemLink(nextId, "Thing " .. nextId, 2), id = nextId, count = 1, vendor = vendor,
                cat = "uncommon", quality = 2, resolved = true, need = need }
    s.players[who].items[ns.ItemKey(e)] = e
    s.log[#s.log + 1] = ("%d:%d:%d:1"):format((#s.log + 1) * 10, Index(s, who), nextId)
    return e
end

print("-- the Front page")
local MIRA, BORIN = "Mira Vale", "Borin Oak"
-- The paper's texts for `run`. Awards are left out, so the headline is
-- the one about the richest player.
local realAwards = ns.RunAwards
local function Paper(run)
    TEXTLOG = {}
    ns.RunAwards = function() return {} end
    local ok, err = pcall(ns.OpenRunWindow, "paper", run)
    ns.RunAwards = realAwards
    ThatLuckyBastardPaperFrame:Hide()
    if not ok then error(err, 0) end
end
local function Lead()
    for _, t in ipairs(TEXTLOG) do
        if t:find("^A party of") then return t end
    end
    return ""
end

local done = NewRun("The Deadmines", { MIRA, BORIN })
Give(done, MIRA, 30000)
Give(done, BORIN, 10000)
Paper(done)
check(drew("The Deadmines Gazette") and not drew("The The"), "a dungeon called The ... is not The The ... Gazette")
check(Lead():find("emerged from The Deadmines after", 1, true) and Lead():find("took home 75% of it", 1, true),
      "a finished run: the party emerged, and the richest took home their share (" .. Lead() .. ")")
local other = NewRun("Ragefire Chasm", { MIRA })
Give(other, MIRA, 500)
Paper(other)
check(drew("The Ragefire Chasm Gazette"), "other names keep their The")
other.name = nil
Paper(other)
check(drew("The dungeon Gazette"), "and a run with no name has one The")

-- Both headlines come up over a few start times when the run is over;
-- while it goes on, nobody walks out of it.
local walked, walkedGoing = false, false
for i = 1, 12 do
    done.startedAt = NOW - 3600 + i
    Paper(done)
    if drew("WALKS OUT OF") then walked = true end
end
done.endedAt = nil
db.active = done
for i = 1, 12 do
    done.startedAt = NOW - 3600 + i
    Paper(done)
    if drew("WALKS OUT OF") then walkedGoing = true end
end
check(walked and not walkedGoing, "WALKS OUT OF is a headline only once the run is over")
check(drew("MIRA VALE TOPS THE LOOT TABLE IN THE DEADMINES"), "the other headline stands in for it")
local lead = Lead()
check(lead:find("has been in The Deadmines for ", 1, true) and lead:find("so far", 1, true)
      and lead:find("holds 75% of it", 1, true) and not lead:find("emerged", 1, true),
      "a run still going: the party has been in it so far (" .. lead .. ")")
local empty = NewRun("The Stockade", { MIRA, BORIN })
empty.endedAt = nil
db.active = empty
Paper(empty)
check(Lead():find("has been in The Stockade for ", 1, true) and Lead():find("nothing to show for it yet", 1, true),
      "and with no loot yet (" .. Lead() .. ")")
db.active = nil
empty.endedAt = NOW - 600
Paper(empty)
check(Lead():find("emerged from The Stockade after", 1, true) and Lead():find("nothing to show for it.", 1, true),
      "once over, it emerged with nothing (" .. Lead() .. ")")

print("-- plurals")
local one = NewRun("Wailing Caverns", { MIRA, BORIN })
local e = Give(one, MIRA, 2000, 1)
one.rollLog[1] = { k = ns.ItemKey(e), t = 10, w = 1, m = "n", r = "1n55,2p" }
TEXTLOG = {}
ns.ShowAnalysis("rolls", one)
check(drew("1 roll: 1 Need, 0 Greed.") and not drew("1 rolls"), "Analysis › Rolls: 1 roll, not 1 rolls")
e = Give(one, BORIN, 2000)
one.rollLog[2] = { k = ns.ItemKey(e), t = 20, w = 2, m = "g", r = "1g10,2g80" }
TEXTLOG = {}
ns.ShowAnalysis("rolls", one)
check(drew("2 rolls: 1 Need, 1 Greed."), "and 2 rolls")

-- The window shows saved runs only.
local solo = NewRun("Wailing Caverns", { MIRA })
Give(solo, MIRA, 2000)
local pair = NewRun("Wailing Caverns", { MIRA, BORIN })
Give(pair, MIRA, 2000)
Give(pair, BORIN, 1000)
db.history[#db.history + 1] = solo
db.history[#db.history + 1] = pair
o.useColumns, o.showTotals = false, true
TEXTLOG = {}
ns.ShowWindow(false, solo)
check(drew("Equal split (1 player)") and not drew("1 players"), "the list view: Equal split (1 player)")
TEXTLOG = {}
ns.ShowWindow(false, pair)
check(drew("Equal split (2 players)"), "and (2 players)")
o.useColumns = true

if FAILED then error(FAILED .. " check(s) failed") end
print("all checks passed (wording)")
