-- Loot bingo: a card is dealt as a run starts, the player bets on one
-- line of it while none of that line's squares is ticked, and the line
-- wins if it fills before the run is over.
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
o.ticker, o.streak, o.popupLeave = false, false, false
local window = ThatLuckyBastardBingoFrame

ITEMS[100] = { 2, 1500, 4, 2 }   -- green BoE
ITEMS[101] = { 3, 9000, 4, 2 }   -- blue BoE
ITEMS[105] = { 4, 90000, 2, 2 }  -- epic BoE
local green, blue, epic = ItemLink(100, "Green Gloves", 2), ItemLink(101, "Blue Blade", 3), ItemLink(105, "Purple Thing", 4)

local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Enter(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    return db.active
end
local function Stop()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    if db.active then SlashCmdList.THATLUCKYBASTARD("stop") end
    NOW = NOW + 3600
end

-- The notices put on screen: "title / text".
local notices = {}
local realNotice = ns.Notice
ns.Notice = function(title, text, ...)
    notices[#notices + 1] = Plain(title) .. " / " .. tostring(text)
    return realNotice(title, text, ...)
end
local function Noticed(what)
    local count = 0
    for _, n in ipairs(notices) do
        if n:find(what, 1, true) then count = count + 1 end
    end
    return count
end

-- The card's window: its markers by line (rows 1 to 4, columns 5 to 8,
-- diagonals 9 and 10), its sixteen squares, and the texts it has drawn.
local marks, cells = {}, {}
local function OnCard(w) -- not a control of the options, say
    while w and w ~= ThatLuckyBastardBingoFrame do w = rawget(w, "__parent") end
    return w ~= nil
end
for _, w in ipairs(FRAMES) do
    if rawget(w, "mark") then marks[w.mark] = w end
    if rawget(w, "tick") and rawget(w, "bg") and rawget(w, "text") and OnCard(w) then cells[#cells + 1] = w end
end
local function Drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
local function Open() -- the card, drawn afresh
    window:Hide()
    TEXTLOG = {}
    ns.ToggleBingo()
end
local function Gold(cell) -- whether a square is drawn as part of the line picked
    local c = cells[cell].bg.__color
    return c[1] == 1 and c[2] == 0.82
end
local function Pickable()
    local list = {}
    for n = 1, 10 do
        if marks[n].can then list[#list + 1] = n end
    end
    return table.concat(list, " ")
end
-- A card whose lines the test knows:
--   boss1    blue     epic      died
--   green    greens3  quest     junk5
--   mats20   mats50   items100  item1g
--   item10g  total5g  total25g  junk10
local function Card()
    return { keys = { "boss1", "blue", "epic", "died", "green", "greens3", "quest", "junk5", "mats20", "mats50",
                      "items100", "item1g", "item10g", "total5g", "total25g", "junk10" }, done = {} }
end

print("-- a card as the run starts")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" } }
local s = Enter(9201, "Bingo Keep")
check(s.bingo == nil, "nothing yet on the way in")
RunTimers()
check(s.bingo ~= nil and #s.bingo.keys == 16 and s.bingo.pick == nil and s.bingo.lines == nil,
      "a second later the run has its card of sixteen squares, with no line picked")
check(Noticed("Loot bingo / Pick your line: /tlb bingo") == 1 and #notices == 1, "and a notice says to pick a line")
check(#marks == 10 and #cells == 16, "the card has ten markers, one per line, around sixteen squares")

print("-- picking a line")
s.bingo = Card()
Open()
check(Drew("Bingo Keep:  pick your line") and Pickable() == "1 2 3 4 5 6 7 8 9 10",
      "with nothing ticked, any of the ten lines can be picked")
Loot(("%s receives loot: %s."):format("Borin Oak", green))
RunTimers()
check(s.bingo.done.green == true and Pickable() == "1 3 4 6 7 8 9 10",
      "a green drops: its row and its column have started, and can no longer be picked (" .. Pickable() .. ")")
marks[2].__scripts.OnClick(marks[2], "LeftButton")
check(s.bingo.pick == nil and db.bingo == nil or (db.bingo.picked == 0 and s.bingo.pick == nil),
      "a click on a line that has started picks nothing")
marks[1].__scripts.OnEnter(marks[1])
check(TIP[1] == "Pick this line" and not Gold(1), "hovering a marker says what a click does")
marks[1].__scripts.OnLeave(marks[1])
TEXTLOG = {}
marks[1].__scripts.OnClick(marks[1], "LeftButton")
check(s.bingo.pick == 1 and db.bingo.picked == 1 and db.bingo.won == 0, "a click picks the top row")
check(Drew("Bingo Keep:  your line, 0 of 4") and Gold(1) and Gold(4) and not Gold(5),
      "the card shows it: its four squares in gold, none ticked yet")
check(Pickable() == "", "the pick is for good: no other line can be picked")
marks[3].__scripts.OnClick(marks[3], "LeftButton")
ns.BingoPick(9)
check(s.bingo.pick == 1 and db.bingo.picked == 1, "a click on another marker changes nothing")

print("-- winning")
Fire("ENCOUNTER_END", 70, "Boss", 1, 4, 1)
Loot(("You receive loot: %s."):format(blue))
Loot(("%s receives loot: %s."):format("Sela Marrow", epic))
TEXTLOG = {}
RunTimers()
check(s.bingo.done.boss1 and s.bingo.done.blue and s.bingo.done.epic and not s.bingo.done.died,
      "a boss, a blue and an epic: three of the row's four")
check(Drew("your line, 3 of 4") and not s.bingo.won and Noticed("BINGO") == 0, "three of four is not a win")
-- Meanwhile the second column fills (blue, greens3, mats50, total5g):
-- nobody picked it.
s.bingo.done.greens3, s.bingo.done.mats50, s.bingo.done.total5g = true, true, true
Loot(("You receive loot: %s."):format(green))
RunTimers()
check(not s.bingo.won and Noticed("BINGO") == 0, "a full line that was not picked wins nothing")
TEXTLOG = {}
Fire("PLAYER_DEAD")
RunTimers()
check(s.bingo.done.died == true and s.bingo.won == true and db.bingo.won == 1, "dying ticks the fourth square: the line is won")
check(Noticed("BINGO! / Your line is complete.") == 1, "and announced, once")
check(Drew("Bingo Keep:  Bingo!") and Drew("Lines won: 1 of 1"), "the card says so, and counts it")
Loot(("You receive loot: %s."):format(green))
RunTimers()
check(Noticed("BINGO") == 1 and db.bingo.won == 1, "later loot does not announce it again")

print("-- once the run is over")
Stop()
local done = db.history[1]
check(done == s and done.bingo.pick == 1 and done.bingo.won == true, "the finished run keeps its card, pick and win")
Open()
check(Drew("Bingo Keep:  Bingo!") and Pickable() == "" and Gold(2), "its card can still be looked at, not played")
ns.BingoPick(3)
check(done.bingo.pick == 1 and db.bingo.picked == 1, "nothing can be picked on it")
local saved = Reload()
db, o = saved, saved.options
check(db.history[1].bingo.pick == 1 and db.history[1].bingo.won == true and db.bingo.picked == 1 and db.bingo.won == 1,
      "the card and the count survive logging out")
window:Hide()

print("-- a run without a pick, and one picked too late")
notices = {}
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
s = Enter(9202, "Late Keep")
ns.ToggleBingo() -- opened before the card was dealt: it is dealt there and then
check(s.bingo ~= nil and #notices == 0, "opening the card deals it, without a notice to say it exists")
RunTimers()
check(#notices == 0, "nor is there one afterwards")
s.bingo = Card()
-- One square on each row and column, and one on the other diagonal.
for _, key in ipairs({ "boss1", "greens3", "items100", "junk10", "died" }) do s.bingo.done[key] = true end
Open()
check(Drew("Late Keep:  every line has started") and Pickable() == "", "once every line has a ticked square, it is too late to pick")
ns.BingoPick(1)
check(s.bingo.pick == nil and db.bingo.picked == 1, "and nothing is picked")
Loot(("You receive loot: %s."):format(green)) -- a run with no loot is not kept
RunTimers()
Stop()
Open()
check(Drew("Late Keep:  no line picked"), "its card says that no line was picked")
window:Hide()

print("-- cards from before lines were picked")
db.history[1].bingo = { keys = Card().keys, done = { boss1 = true, blue = true, epic = true, died = true }, lines = 1 }
Open()
check(Drew("Late Keep:  no line picked") and not Gold(1) and cells[1].tick:IsShown(),
      "a card of an earlier version shows its ticks, with no line picked")
check(Pickable() == "" and marks[2].tip == nil,
      "and offers none: its run is over, though three of its rows have no tick (" .. Pickable() .. ")")
window:Hide()

print("-- a group that comes after the card")
local function GroupSquares(card)
    local count = 0
    for _, key in ipairs(card.keys) do
        if key == "everyone" or key == "shared" or key == "needwin" or key == "youwin" or key == "twowins"
                or key == "greed3" or key == "pass" or key == "high" or key == "low" then
            count = count + 1
        end
    end
    return count
end
notices = {}
WORLD.party = {}
s = Enter(9204, "Early Keep")
RunTimers()
local first = s.bingo
check(first.solo == true and GroupSquares(first) == 0, "entering alone, the card is one for a player on their own")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" } }
Fire("GROUP_ROSTER_UPDATE")
RunTimers()
check(s.bingo ~= first and s.bingo.solo == nil and #s.bingo.keys == 16 and GroupSquares(s.bingo) >= 4,
      "the group forms: the run gets a card for a group, with its roll squares (" .. GroupSquares(s.bingo) .. ")")
check(Noticed("Loot bingo") == 1, "without a second notice")
local group = s.bingo
WORLD.party[3] = { "Kett Longstride", "HUNTER", "DAMAGER" }
Fire("GROUP_ROSTER_UPDATE")
RunTimers()
check(s.bingo == group, "a group's card is not dealt again when someone joins")
Loot(("You receive loot: %s."):format(green))
RunTimers()
Stop()
-- A line picked while alone is a pick: the card stays.
WORLD.party = {}
s = Enter(9205, "Alone First Keep")
RunTimers()
first = s.bingo
ns.BingoPick(1)
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
Fire("GROUP_ROSTER_UPDATE")
RunTimers()
check(first.pick == 1 and s.bingo == first, "a card with a line picked on it is kept as it is when the group forms")
Loot(("You receive loot: %s."):format(green))
RunTimers()
Stop()

print("-- a pick that is no line")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
s = Enter(9206, "Odd Keep")
RunTimers()
s.bingo = Card()
s.bingo.pick = 11
local ok = pcall(function()
    Open()
    Loot(("You receive loot: %s."):format(blue))
    RunTimers()
end)
check(ok and Drew("Odd Keep:  pick your line") and not Gold(1), "a card whose pick is not one of the ten lines is shown as unpicked")
s.bingo.pick = "2"
ok = pcall(function() Open(); ns.BingoCheck(); RunTimers() end)
check(ok and Drew("Odd Keep:  pick your line"), "so is one whose pick is not a number")
ns.BingoPick(3)
check(s.bingo.pick == 3, "and a line can be picked on it")
window:Hide()
Stop()

print("-- switched off")
o.bingo = false
notices = {}
WORLD.party = {}
s = Enter(9203, "Quiet Keep")
Loot(("You receive loot: %s."):format(green))
RunTimers()
check(s.bingo == nil and #notices == 0, "with bingo off, no card is dealt and nothing is said")
o.bingo = true
Stop()
ns.Notice = realNotice

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (bingo)")
