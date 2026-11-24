-- Bets: call the lucky bastard. A small card as a dungeon run starts, once
-- there are two; players added as they join until calls close (the first
-- roll, the first green or better item, the first boss); the same card
-- with the result once the run is left; one tally of calls right. Chat
-- only through Say it, when clicked.
print("\n==== bets ====")
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
o.ticker, o.streak, o.race = false, false, false
local H = "|HlootHistory:%d|h[Loot]|h: "
local ME, BRYN, COLE, DAX = WORLD.me, "Bryn Ash", "Cole Dart", "Dax Reed"
local card = ThatLuckyBastardBetFrame

ITEMS[601] = { 0, 100, 15, 0 }    -- a grey: 1s
ITEMS[602] = { 2, 20000, 4, 2 }   -- a green BoE: 2g
ITEMS[603] = { 3, 50000, 4, 1 }   -- a blue: 5g
local grey, green, blue = ItemLink(601, "Tooth", 0), ItemLink(602, "Belt", 2), ItemLink(603, "Sword", 3)

local function Plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The name buttons on show, top to bottom and left to right, as "Mira Bryn".
local function Names()
    local list = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "betName") and w:IsShown() and card:IsShown() then list[#list + 1] = w end
    end
    table.sort(list, function(a, b)
        local pa, pb = a.__points[1], b.__points[1]
        if pa[3] ~= pb[3] then return pa[3] > pb[3] end -- (x and y, as the harness keeps them)
        return pa[2] < pb[2]
    end)
    local out = {}
    for i, w in ipairs(list) do out[i] = w.name:match("^%S+") end
    return table.concat(out, " "), list
end
local function NameButton(first)
    local _, list = Names()
    for _, w in ipairs(list) do
        if w.name:match("^%S+") == first then return w end
    end
end
local function Call(first)
    local b = NameButton(first)
    if b then b.__scripts.OnClick(b) end
    return b ~= nil
end
local function Said(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
local function SayIt()
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == "Say it" and w.__parent and w:IsShown() then
            CHAT_SENT = {}
            w.tpl.__scripts.OnClick(w.tpl)
            return CHAT_SENT[1]
        end
    end
end
local function Join(...)
    WORLD.party = {}
    for i, m in ipairs({ ... }) do WORLD.party[i] = m end
    Fire("GROUP_ROSTER_UPDATE")
end
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
local function Filed()
    NOW = NOW + 1300 -- past the time a run can be resumed
    Fire("PLAYER_ENTERING_WORLD", false, false)
end
local bryn, cole, dax = { BRYN, "WARRIOR", "TANK" }, { COLE, "MAGE", "DAMAGER" }, { DAX, "ROGUE", "DAMAGER" }

print("-- the card")
local run = Enter(9101, "Bet Keep")
check(run and not card:IsShown(), "alone in a dungeon: no card")
TEXTLOG = {}
Join(bryn)
check(card:IsShown() and Names() == "Mira Bryn" and Said("Who's the lucky bastard?") and Said("Calls close at the first roll."),
      "a second player: the card opens, you first, with a call to make")
Join(bryn, cole)
check(Names() == "Mira Bryn Cole", "players are added as they join")
check(card:GetWidth() < 450 and card:GetHeight() < 100, ("small: %dx%d"):format(card:GetWidth(), card:GetHeight()))

print("-- a call")
TEXTLOG = {}
check(Call("Cole") and run.bet.pick == COLE and Said("Your call: Cole"), "a click calls them")
check(NameButton("Cole").text.__text:find("UI-RaidTargetingIcon_1", 1, true) ~= nil, "their name gets a star on the card")
local said = SayIt()
check(said and said[1] == "I'm calling Cole Dart as That Lucky Bastard." and said[2] == "PARTY", "Say it tells the party")
CHAT_SENT = {}
RunTimers()
check(not card:IsShown() and #CHAT_SENT == 0, "the card goes a moment later, and nothing was posted by itself")
TEXTLOG = {}
ns.ShowRun(run)
RunTimers()
local starred = false
for _, t in ipairs(TEXTLOG) do
    if t:find("UI-RaidTargetingIcon_1", 1, true) and Plain(t):find("Cole", 1, true) then starred = true end
end
check(starred, "a star beside your call in the window")
TEXTLOG = {}
ns.ToggleMeter()
RunTimers()
local inMeter = false
for _, t in ipairs(TEXTLOG) do
    if t:find("UI-RaidTargetingIcon_1", 1, true) and Plain(t):find("Cole", 1, true) then inMeter = true end
end
check(inMeter, "and in the meter")
ns.ToggleMeter()
Join(bryn)
check(run.bet.pick == nil, "a call on someone who left is no call")
Join(bryn, cole)
ns.ToggleBet(run)
check(card:IsShown() and Names() == "Mira Bryn Cole", "the Bet button opens the card again")
Call("Cole")
check(run.bet.pick == COLE, "called again")

print("-- calls close")
Loot(("%s receives loot: %s."):format(BRYN, grey))
check(not run.bet.closed, "a grey: still open")
Loot(("%s receives loot: %s."):format(BRYN, green))
check(run.bet.closed and not card:IsShown(), "a green: calls are closed, and the card goes")
run.bet.closed = nil
Loot((H .. "%s has selected Greed for: %s"):format(1, BRYN, blue))
check(run.bet.closed, "so does the first roll")
run.bet.closed = nil
Fire("START_LOOT_ROLL", 1, 60)
check(run.bet.closed, "or the game's roll window")
run.bet.closed = nil
Fire("ENCOUNTER_END", 70, "Boss", 1, 5, 1)
check(run.bet.closed, "or the first boss")
ns.BetPick(run, BRYN)
check(run.bet.pick == COLE, "closed: no new call")
Join(bryn, cole, dax)
TEXTLOG = {}
ns.ToggleBet(run)
check(card:IsShown() and Names() == "" and Said("You called Cole Dart. Calls are closed."),
      "who joins now is too late; the card shows your call")
ns.ToggleBet(run)

print("-- the result")
Loot(("%s receives loot: %s."):format(COLE, blue))
Loot(("%s receives loot: %s."):format(ME, grey))
TEXTLOG = {}
Leave()
check(not card:IsShown(), "left: the race comes first")
RunTimers()
check(card:IsShown() and Said("Called it! Cole Dart is the lucky bastard: 5g 00s, 71% of the loot.")
      and Said("Calls right: 1 of 1."), "then the card: called it")
said = SayIt()
check(said and said[1] == "Called it! Cole Dart is That Lucky Bastard: 5g 00s (71%).", "Say it posts the result")
card:Hide()
Filed()
check(db.bets and db.bets.calls == 1 and db.bets.right == 1 and db.history[1] == run, "filed: counted once")
check(run.bet.pick == COLE and run.bet.scored and run.bet.offered == nil and run.bet.closed == nil,
      "and the run keeps only its call")

print("-- a miss")
WORLD.party = {}
local second = Enter(9102, "Miss Keep")
Join(bryn, cole)
Call("Bryn")
Loot(("%s receives loot: %s."):format(COLE, blue))
Loot(("%s receives loot: %s."):format(BRYN, green))
TEXTLOG = {}
Leave()
RunTimers()
check(Said("Cole Dart is the lucky bastard") and Said("Your call, Bryn Ash, came 2nd.") and Said("Calls right: 1 of 2."),
      "a miss: who it was, where your call came")
said = SayIt()
check(said and said[1]:find("^I called Bryn Ash %(2nd%)%. Cole Dart is That Lucky Bastard") ~= nil, "Say it owns up")
card:Hide()
Filed()
check(db.bets.calls == 2 and db.bets.right == 1, "counted: 1 of 2")
TEXTLOG = {}
ns.ToggleBet(run)
check(Said("Called it!") and Said("Calls right: 1 of 2."), "an older run's card shows its result, not counted again")
ns.ToggleBet(run)

print("-- a tie at the top")
WORLD.party = {}
local tie = Enter(9103, "Tie Keep")
Join(bryn, cole)
Call("Cole") -- tied with Bryn, who comes first by name
Loot(("%s receives loot: %s."):format(BRYN, blue))
Loot(("%s receives loot: %s."):format(COLE, blue))
TEXTLOG = {}
Leave()
RunTimers()
check(Said("Called it! Cole Dart is the lucky bastard"), "your call shares the top: called it, and named")
card:Hide()
Filed()

print("-- a raid")
WORLD.raid = true
WORLD.party = {}
local raid = Enter(9104, "Raid Keep")
local members = {}
for i = 1, 11 do members[i] = { "Raider" .. i .. " X", "PRIEST", "HEALER", math.ceil((i + 1) / 5) } end
Join(unpack(members))
local names, list = Names()
local rows = {}
for _, w in ipairs(list) do rows[w.__points[1][3]] = (rows[w.__points[1][3]] or 0) + 1 end
local counts = {}
for _, n in pairs(rows) do counts[#counts + 1] = n end
table.sort(counts)
check(#list == 12 and table.concat(counts, " ") == "2 5 5", "a raid: one row per raid group (" .. names .. ")")
check(card:GetHeight() > 100 and card:GetWidth() < 450, "taller, as wide")
card:Hide()
WORLD.raid = false
Leave()
Filed()

print("-- no card")
WORLD.party = {}
SlashCmdList.THATLUCKYBASTARD("start")
Join(bryn)
check(not card:IsShown() and db.active and db.active.manual and db.active.bet == nil, "no bets on a run tracked by hand")
SlashCmdList.THATLUCKYBASTARD("stop")
o.bets = false
WORLD.party = {}
local off = Enter(9105, "Off Keep")
Join(bryn)
check(not card:IsShown() and off.bet == nil, "bets switched off: no card")
local betBtn
for _, w in ipairs(FRAMES) do
    local tpl = rawget(w, "tpl")
    if type(tpl) == "table" and tpl.__text == "Bet" then betBtn = w end
end
ns.ShowRun(run)
RunTimers()
check(betBtn and not betBtn:IsShown(), "and no Bet button")
o.bets = true
ns.Rerender()
check(betBtn:IsShown(), "back on: the button is back")
Leave()
Filed()

print("-- kept")
local saved = Reload()
db = saved
local kept
for _, s in ipairs(db.history) do
    if s.name == "Bet Keep" then kept = s end
end
check(kept and kept.bet and kept.bet.pick == COLE and db.bets.calls == 3 and db.bets.right == 2,
      "after a reload: the call, and the tally")
for _, theme in ipairs({ "classic", "receipt", "modern" }) do
    ns.SetTheme(theme)
    ns.ToggleBet(kept)
    ns.ToggleBet(kept)
end
check(true, "the card draws in every theme")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (bets)")
