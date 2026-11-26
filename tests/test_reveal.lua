-- The race: how the breakdown reveals a finished run as it is left, with
-- the columns in podium order. Each player's loot falls into their column,
-- each item as big as its worth, with their gold as coins: first all but
-- the run's three most valuable items, then those three one by one. The
-- totals count up as the pieces land, a faint bar rising behind each pile;
-- the places are shown once the last of the three is down. Then the race
-- fades out, and the run fades in as it is.
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
o.ticker, o.streak = false, false
local main = ThatLuckyBastardFrame

-- Items worth 5g, 4g, 2g and 1g at the vendor (bind on pickup: no auction price).
ITEMS[201] = { 3, 50000, 4, 1 }
ITEMS[202] = { 3, 40000, 4, 1 }
ITEMS[203] = { 3, 20000, 4, 1 }
ITEMS[204] = { 3, 10000, 4, 1 }
local five, four, two, one = ItemLink(201, "Five", 3), ItemLink(202, "Four", 3), ItemLink(203, "Two", 3),
    ItemLink(204, "One", 3)

local function Party(...)
    local list = {}
    for i, name in ipairs({ ... }) do list[i] = { name, "MAGE", "DAMAGER" } end
    return list
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
local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Gold(copper) return Plain(ns.Money(copper)) end

-- The columns on show, from left to right.
local function Cols()
    local list = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "market") and rawget(w, "rows") and w:IsShown() then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.__points[1][2] < b.__points[1][2] end)
    return list
end
-- The column of player `name`: where it is, what its total reads, and
-- how see-through its place and its loot are.
local function Col(name)
    for i, w in ipairs(Cols()) do
        if w.hover.p.name == name then
            return { at = i, x = w.__points[1][2], drop = -w.__points[1][3], h = w.__h, w = w.__w, frame = w,
                     total = w.market:GetAlpha() == 0 and "" or Plain(w.market.__text),
                     place = w.rank:GetAlpha(), loot = w.rows[1]:GetAlpha(), share = w.share:GetAlpha(),
                     tint = w.bg.__color[4], award = w.awardFrame and w.awardFrame:GetAlpha() or nil }
        end
    end
end
local function Order()
    local names = {}
    for i, w in ipairs(Cols()) do names[i] = w.hover.p.name:match("^%S+") end
    return table.concat(names, " ")
end

-- What falls: the race's plan (Coins.lua), and what each piece is drawn as.
local function Plan() return ns.Coins.Current() end
-- The pieces of player `name` (items and coins), in the order they land.
local function PiecesOf(name)
    local list = {}
    for _, c in ipairs(Plan().pieces) do
        if c.frame.hover.p.name == name then list[#list + 1] = c end
    end
    return list
end
local function DoneAt(name)
    for i, frame in ipairs(Plan().frames) do
        if frame.hover.p.name == name then return Plan().doneAt[i] end
    end
end
-- Where a piece is drawn (its middle, from its column's top left corner,
-- y going down), how wide and tall, how see-through, how far turned and its
-- place in the drawing order; nil while it is not there.
local function Drawn(c)
    if not c.box:IsShown() then return nil end
    local p = c.box.__points[1]
    return { x = p[4], y = -p[5], w = c.box.__w, h = c.box.__h, alpha = c.box:GetAlpha(), frame = p[2],
             rot = c.rot, level = c.drawn }
end
local function Showing(name)
    local n = 0
    for _, c in ipairs(PiecesOf(name)) do
        if Drawn(c) then n = n + 1 end
    end
    return n
end

-- What plays the race, and what lies over the columns meanwhile.
local driver, curtain
for _, w in ipairs(FRAMES) do
    if w.__parent == main and w.__scripts.OnUpdate and w.__scripts.OnHide then driver = w end
    if rawget(w, "curtain") then curtain = w end
end
local function Racing() return curtain:IsShown() end
-- The race as it stands `t` seconds after it began: its clock starts
-- with its first frame on screen, which is the first probe after `began`
-- is cleared. (Probes are taken a little past a boundary, never on it:
-- the clock counts in billions of seconds, and is not exact to the last
-- digit.)
local began
local HOLD, PAUSE, OUT, IN = 0.3, 1.5, 0.4, 0.5 -- the race's parts, in seconds, besides the loot
local G = 1600 -- the pieces' gravity
local LEAD, SPAN, FILL, SIZED = 0.45, 1.6, 0.42, 150 -- Coins.lua's
local FINALE_IN, FINALE_GAP, FINALE_OUT, RISE, NOTE = 0.55, 0.75, 0.35, 0.25, 1.1
local MAIN = LEAD + SPAN -- when the first drop ends
local function Down() return HOLD + Plan().endAt end -- when the places are shown
local function Total() return Down() + PAUSE + OUT + IN end
-- How see-through all that scrolls is: the race, then the run.
local function Shade() return ns.Breakdown.content:GetAlpha() end
local function At(t)
    if not began then
        began = NOW
        driver.__scripts.OnUpdate(driver, 0.01)
    end
    NOW = began + t
    driver.__scripts.OnUpdate(driver, 0.01)
end
-- What the addon prints while `fn` runs.
local function Printed(fn)
    local lines, real = {}, print
    print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    local ok, err = pcall(fn)
    print = real
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end
-- The sounds played, by what they are for (Coins.SOUNDS: each name is
-- given an id of its own here), and when; the tension sound has a handle,
-- to stop it with.
local heard, when, stopped, shots = {}, {}, 0, 0
for what, sound in pairs(ns.Coins.SOUNDS) do SOUNDKIT[sound[1]] = "kit " .. what end
PlaySound = function(kit)
    local what = type(kit) == "string" and kit:match("^kit (%a+)$")
    if what then
        heard[what] = (heard[what] or 0) + 1
        when[#when + 1] = { what = what, at = NOW }
    end
    return true, what == "tension" and 4242 or nil
end
StopSound = function(handle) if handle == 4242 then stopped = stopped + 1 end end
local function Heard(what) return heard[what] or 0 end
Screenshot = function() shots = shots + 1 end
-- A column's bar: how high, and the texture (0 while it is not there).
local function BarOf(name)
    local bar = Col(name).frame.raceBar
    if not bar or not bar:IsShown() then return 0 end
    return bar.__h, bar
end

-- A run of five: I get 5g, Borin 4g, Sela 2g, Kett 1g and Juno nothing.
local function Run(id, name, loot)
    WORLD.party = Party("Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash")
    local s = Enter(id, name)
    NOW = NOW + 600
    for who, item in pairs(loot or { me = five, ["Borin Oak"] = four, ["Sela Marrow"] = two, ["Kett Longstride"] = one }) do
        if who == "me" then
            Loot(("You receive loot: %s."):format(item))
        else
            Loot(("%s receives loot: %s."):format(who, item))
        end
    end
    RunTimers()
    return s
end
-- Ends whatever run is going and clears the screen.
local function Reset()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    if db.active then SlashCmdList.THATLUCKYBASTARD("stop") end
    main:Hide()
    NOW = math.floor(NOW) + 3600
end

print("-- the race begins as a run is left")
check(driver ~= nil and curtain ~= nil and not Racing(), "nothing races while no run has ended")
local s = Run(9101, "Race Keep")
began = nil
Leave()
check(main:IsShown() and Racing(), "leaving the run opens the breakdown, with the race on")
check(Order() == "Borin Juno Kett Mira Sela", "the columns start side by side in name order (" .. Order() .. ")")
local me, borin, juno = Col("Mira Vale"), Col("Borin Oak"), Col("Juno Ash")
check(me.total == "" and borin.total == "" and juno.total == "" and me.drop == 0 and borin.drop == 0 and me.h == borin.h,
      "level with one another, no total showing")
check(me.place == 0 and juno.place == 0 and me.loot == 0 and me.share == 0 and (me.award or 0) == 0,
      "with no place, no loot, no share and no award to give the result away")
check(me.tint == borin.tint and me.tint == juno.tint and me.tint > 0, "and no column brighter than another")
check(Showing("Mira Vale") == 0 and Showing("Borin Oak") == 0, "no coin yet")
local racingTint = borin.tint

print("-- the loot falls")
local mine, borins = PiecesOf("Mira Vale"), PiecesOf("Borin Oak")
check(#mine == 1 and #borins == 1 and #PiecesOf("Sela Marrow") == 1 and #PiecesOf("Kett Longstride") == 1
      and #PiecesOf("Juno Ash") == 0 and not mine[1].coin and mine[1].name == "Five",
      "each player's loot falls as itself: one item each here, nothing for Juno")
-- Each item as big as its worth: its area follows its value, the richest
-- pile covering 42% of a 150-pixel room, from 10 to 96 pixels a side.
local sized, sides = true, {}
for _, it in ipairs({ { "Mira Vale", 5 }, { "Borin Oak", 4 }, { "Sela Marrow", 2 }, { "Kett Longstride", 1 } }) do
    local want = math.max(10, math.min(96, math.sqrt(FILL * me.w * SIZED * it[2] / 5)))
    local side = PiecesOf(it[1])[1].side
    if math.abs(side - want) > 0.001 then sized = false end
    sides[#sides + 1] = ("%.0f"):format(side)
end
check(sized, "each item as big as its worth: its area follows its value (" .. table.concat(sides, ", ") .. " pixels a side)")
At(HOLD / 2)
check(Showing("Mira Vale") == 0 and Col("Juno Ash").place == 0, "a beat before anything moves")
-- One item, from start to finish.
local first, light = mine[1], PiecesOf("Kett Longstride")[1]
At(HOLD + first.ts + 0.05)
local a = Drawn(first)
At(HOLD + first.ts + 0.10)
local b = Drawn(first)
check(a and b and math.abs(a.y - (first.y0 + 0.5 * G * 0.05 ^ 2)) < 0.01 and (b.y - a.y) > (a.y - first.y0),
      "an item falls under gravity, faster and faster")
check(a.frame == me.frame and a.w == first.side and a.h == first.side and a.rot ~= b.rot,
      ("turning as it falls (%.3f, then %.3f)"):format(a.rot, b.rot))
At(HOLD + first.ts + 0.02)
check(Drawn(first).alpha > 0.1 and Drawn(first).alpha < 0.6, "it fades into sight as it starts to fall")
check(#first.hops == 0 and #light.hops >= 1,
      ("the heavy 5g item lands with a thud, no bounce; the 1g one bounces (%d times)"):format(#light.hops))
At(HOLD + light.hops[1].at + light.hops[1].len / 2)
check(Drawn(light).y < light.y1 - 1, "where it lands, it bounces")
At(HOLD + light.still + 0.5)
local c = Drawn(light)
check(c.y == light.y1 and c.x == light.x1 and math.abs(c.rot - light.rest) < 0.01, "then rocks still, where it lies")
check(math.abs(first.y1 + first.side / 2 - (me.h - 6)) < 0.001 and first.x1 - first.side / 2 >= 0
      and first.x1 + first.side / 2 <= me.w, "standing on the foot of its column, within it")

print("-- first everything but the three most valuable")
-- From the start again, in order this time (the probes above jump about).
main:Hide()
began = nil
ns.ShowWindow(true, s)
heard, when, stopped = {}, {}, 0
mine = PiecesOf("Mira Vale")
local fin, kettOne = Plan().finale, PiecesOf("Kett Longstride")[1]
check(#fin == 3 and fin[1].name == "Two" and fin[2].name == "Four" and fin[3].name == "Five" and not kettOne.finale,
      "the run's three most valuable items are held back for the end, the third first: Two, Four, Five")
check(kettOne.tl <= MAIN and kettOne.tl >= MAIN - 0.1 and DoneAt("Juno Ash") == 0,
      ("the rest falls first, into every column over the same time (Kett's 1g lands at %.2f s)"):format(kettOne.tl))
check(math.abs(fin[1].tl - (MAIN + FINALE_IN)) < 1e-9 and math.abs(fin[2].tl - fin[1].tl - FINALE_GAP) < 1e-9
      and math.abs(fin[3].tl - fin[2].tl - FINALE_GAP) < 1e-9 and math.abs(Plan().endAt - fin[3].tl - FINALE_OUT) < 1e-9
      and first.tl == fin[3].tl,
      ("then those three one by one, %.2f s apart; the places %.2f s after the last"):format(FINALE_GAP, FINALE_OUT))
At(HOLD + kettOne.tl - 0.01)
check(Col("Kett Longstride").total == "" and BarOf("Kett Longstride") == 0, "no total and no bar before a column's first piece")
At(HOLD + kettOne.tl + RISE / 2)
local counting = Col("Kett Longstride").total
check(counting ~= "" and counting ~= Gold(10000) and Heard("thud") >= 1,
      "an item lands with a thud, and its column's total counts up (" .. counting .. ")")
At(HOLD + kettOne.tl + RISE + 0.01)
local reach = Plan().reach
local kettBar, bar = BarOf("Kett Longstride")
check(Col("Kett Longstride").total == Gold(10000) and Col("Kett Longstride").place == 0,
      "to what it is worth, with no place shown")
check(math.abs(kettBar - reach * 0.2) < 0.001 and bar.__color[4] == 0.1 and math.abs(bar.__color[1] - RAID_CLASS_COLORS.MAGE.r) < 0.01,
      ("behind the pile a faint bar in the player's colour, a fifth of the way up: 1g against the richest's 5g (%.0f pixels)"):format(kettBar))
check(math.abs(reach - (Plan().room - 10)) < 0.001, "(all the way up is the top of the room)")
At(HOLD + fin[1].tl - 0.01)
check(Col("Sela Marrow").total == "" and Col("Mira Vale").total == "" and Showing("Mira Vale") == 0 and Heard("tension") == 1,
      "the finale begins with a tension sound under it; Sela and Mira have nothing yet")
At(HOLD + fin[1].tl + 0.2)
local note = Col("Sela Marrow").frame.raceNote
check(Heard("finale") == 1 and note:IsShown() and note.name.__text == "Two" and Plain(note.worth.__text) == Gold(20000),
      "the first of the three lands with a sound of its own, its name and worth over its column")
At(HOLD + fin[1].tl + RISE + 0.01)
check(Col("Sela Marrow").total == Gold(20000) and Col("Sela Marrow").place == 0 and Col("Kett Longstride").place == 0,
      "Sela's total takes it in; still no place")
At(HOLD + fin[1].tl + NOTE + 0.01)
check(not note:IsShown(), "the name goes after a moment")
At(HOLD + fin[3].tl - 0.01)
check(Col("Borin Oak").total == Gold(40000) and Col("Mira Vale").total == "" and Heard("finale") == 2 and Heard("fanfare") == 0,
      "4g for Borin; Mira, empty until now, has the last to come; no fanfare yet")
At(HOLD + fin[3].tl + RISE + 0.01)
check(Col("Mira Vale").total == Gold(50000) and Col("Mira Vale").place == 0 and Col("Borin Oak").place == 0 and Heard("finale") == 3,
      "Mira's 5g lands last: the totals are final, the places a moment away")
At(Down() + 0.01)
me = Col("Mira Vale")
check(me.place == 1 and Col("Borin Oak").place == 1 and Col("Kett Longstride").place == 1 and Col("Juno Ash").place == 1
      and Col("Juno Ash").total == "-" and Heard("fanfare") == 1 and stopped == 1,
      "then every place at once, with the fanfare; the tension sound stops")
check(math.abs(BarOf("Mira Vale") - reach) < 0.001 and math.abs(BarOf("Borin Oak") - reach * 0.8) < 0.001 and BarOf("Juno Ash") == 0,
      "the winner's bar all the way up, the others as their share of it, none for Juno")
check(Down() < 5.2, ("the loot takes %.1f seconds"):format(Plan().endAt))
local landed = Drawn(mine[1])
check(landed and landed.alpha == 1 and landed.y == mine[1].y1 and landed.x == mine[1].x1, "every piece where it fell")

print("-- the race fades out")
At(Down() + PAUSE - 0.01)
check(PAUSE == 1.5 and Order() == "Borin Juno Kett Mira Sela" and Col("Mira Vale").drop == 0 and Showing("Mira Vale") == 1
      and Drawn(mine[1]).alpha == 1 and Shade() == 1, "the piles stay a second and a half, the columns where they were")
At(Down() + PAUSE + OUT / 2)
me = Col("Mira Vale")
check(math.abs(Shade() - 0.5) < 0.001 and Order() == "Borin Juno Kett Mira Sela" and me.drop == 0 and me.place == 1
      and me.loot == 0 and Drawn(mine[1]).alpha == 1 and Drawn(mine[1]).y == mine[1].y1 and BarOf("Mira Vale") > 0,
      "half way, all of it at half strength, nothing moving: the columns, their places, the piles and the bars")
At(Down() + PAUSE + OUT - 0.01)
check(Racing() and Shade() < 0.05, "then gone")

print("-- the run fades in")
At(Down() + PAUSE + OUT + 0.001)
me, borin = Col("Mira Vale"), Col("Borin Oak")
local kett = Col("Kett Longstride")
check(Order() == "Kett Borin Mira Sela Juno", "it comes back in podium order: the winner in the middle (" .. Order() .. ")")
check(me.drop == 0 and borin.drop == 14 and kett.drop == 42 and me.h - borin.h == 14,
      "stepping down by place, their feet level")
check(Racing() and Shade() < 0.01 and me.loot == 1 and me.share == 1 and me.place == 1 and me.total == Gold(50000),
      "with the loot, the shares and the places, still out of sight")
check(Showing("Mira Vale") == 0 and BarOf("Mira Vale") == 0 and not me.frame.raceNote:IsShown(), "the pile and its bar put away")
At(Down() + PAUSE + OUT + IN / 2)
check(math.abs(Shade() - 0.5) < 0.001 and Col("Mira Vale").loot == 1, "half way in, all of it at half strength")
o.ceremonyScreenshot = true
local total = Total()
At(total + 0.01)
me = Col("Mira Vale")
check(not Racing() and Shade() == 1 and me.loot == 1 and me.share == 1 and me.place == 1 and me.total == Gold(50000)
      and (me.award or 1) == 1, ("after %.1f seconds the run is shown as it is"):format(total))
check(Order() == "Kett Borin Mira Sela Juno" and Showing("Mira Vale") == 0, "in podium order, the pile put away")
check(math.abs(me.tint - Col("Borin Oak").tint - 0.04) < 0.0001, "the winner's column a shade brighter, as it is drawn outside a race")
check(Col("Borin Oak").tint == racingTint, "and the others as bright as they were during it")
RunTimers()
check(shots == 1, "and its photo is taken, when the option asks for one")
NOW = began + total + 4
driver.__scripts.OnUpdate(driver, 0.01)
check(not Racing() and shots == 1, "it is run once")
o.ceremonyScreenshot = false

print("-- a pile, with coins as the filler")
Reset()
-- I get a 5g item and three cheap ones, Borin a 2g item, the others
-- nothing; everyone in sight gets a 30s share, then I get another alone.
ITEMS[207] = { 1, 300, 7, 0 }
ITEMS[208] = { 1, 700, 7, 0 }
ITEMS[209] = { 2, 1500, 7, 0 }
WORLD.party = Party("Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash")
s = Enter(9124, "Coin Keep")
NOW = NOW + 600
for _, item in ipairs({ ItemLink(207, "Three", 1), ItemLink(208, "Seven", 1), ItemLink(209, "Fifteen", 2), five }) do
    Loot(("You receive loot: %s."):format(item))
end
Loot(("Borin Oak receives loot: %s."):format(two))
RunTimers()
WORLD.visible = true
Coins("Your share of the loot is 30 Silver.")
WORLD.visible = false
Coins("Your share of the loot is 30 Silver.")
began = nil
Leave()
local function Split(name)
    local items, coins = {}, {}
    for _, p in ipairs(PiecesOf(name)) do
        if p.coin then coins[#coins + 1] = p else items[#items + 1] = p end
    end
    return items, coins
end
local myItems, myCoins = Split("Mira Vale")
local _, borinCoins = Split("Borin Oak")
local _, selaCoins = Split("Sela Marrow")
local junoItems, junoCoins = Split("Juno Ash")
check(#borinCoins == #selaCoins and #borinCoins == #junoCoins and #junoItems == 0 and #myCoins > #borinCoins,
      ("coins: as many for everyone with the same share (%d), more for me with more gold (%d)"):format(#borinCoins, #myCoins))
check(Plan().room >= 150 and Plan().room <= 260 and Col("Mira Vale").h == Col("Juno Ash").h,
      ("the race takes the room the window has under the heads: %d pixels"):format(Plan().room))
check(#myItems == 4 and myItems[1].name == "Three" and myItems[4].name == "Five" and myItems[4].tl == DoneAt("Mira Vale"),
      "my items land cheapest first, the 5g one at the very end of my column")
check(myItems[3].name == "Fifteen" and myItems[3].finale == 3 and myItems[4].finale == 1 and not myItems[2].finale,
      "the run's best three are mine and Borin's: my 15s one and my 5g one wait for the finale")
local done = myItems[2].tl -- my first drop's last item
local early, late, ahead = math.huge, 0, true
for _, coin in ipairs(myCoins) do
    early, late = math.min(early, coin.tl), math.max(late, coin.tl)
    if coin.tl >= done then ahead = false end
end
check(early < LEAD + SPAN * 0.15 and late > MAIN - 0.35 and ahead,
      ("my coins fall all through the first drop (%.2f to %.2f s), before its last item"):format(early, late))
check(junoCoins[#junoCoins].tl == DoneAt("Juno Ash") and DoneAt("Juno Ash") <= MAIN and DoneAt("Borin Oak") > MAIN,
      "Juno, with only coins, is done with the first drop; Borin has one of the three to come")
local ordered, inside = true, true
for _, name in ipairs({ "Mira Vale", "Borin Oak", "Juno Ash" }) do
    local list, col = PiecesOf(name), Col(name)
    for k, p in ipairs(list) do
        if p.level ~= k or (k > 1 and p.tl < list[k - 1].tl) then ordered = false end
        local tall = p.coin and 15 or p.side
        if p.y1 - tall / 2 < col.h - Plan().room + 4 - 0.001 or p.y1 + tall / 2 > col.h - 6 + 0.001 then inside = false end
    end
end
check(ordered, "each piece drawn over those that landed before it")
check(inside, "every pile within its room, under the head")
-- What is heard: of the pieces that land together, the heaviest; never
-- two sounds of a landing too close together, the coins giving way to the
-- items; each of the three best.
heard, when = {}, {}
for step = 1, math.floor(Down() * 100) do At(step * 0.01) end
local close, last, lastThud = 0, nil, nil
for _, sound in ipairs(when) do
    local at = sound.at
    if sound.what == "clink" and last and at - last < 0.1 - 1e-6 then close = close + 1 end
    if sound.what == "thud" and lastThud and at - lastThud < 0.06 - 1e-6 then close = close + 1 end
    if sound.what == "thud" then lastThud = at end
    if sound.what ~= "tension" and sound.what ~= "fanfare" then last = at end
end
local items = 0
for _, p in ipairs(Plan().pieces) do
    if not p.coin and not p.finale then items = items + 1 end
end
check(Heard("clink") > 0 and Heard("thud") == items and Heard("finale") == 3 and close == 0
      and Heard("clink") + Heard("thud") < #Plan().pieces - 3,
      ("clinks for coins (%d), a thud for each item (%d), fewer sounds than pieces (%d), never two too close; and each of the three best"):format(
          Heard("clink"), Heard("thud"), #Plan().pieces))
check(Col("Mira Vale").total == Gold(50000 + 300 + 700 + 1500 + 6000) and Col("Borin Oak").total == Gold(20000 + 3000),
      "the totals end at what each has: items and coins")
-- A coin, from start to finish: it tumbles, lands nearly flat, gives a
-- little, bounces and rocks still.
local coin = myCoins[#myCoins]
local thinnest, tallest = math.huge, 0
for k = 1, 40 do
    At(HOLD + coin.ts + (coin.tl - coin.ts) * k / 41)
    local d = Drawn(coin)
    thinnest, tallest = math.min(thinnest, d.h), math.max(tallest, d.h)
end
check(thinnest < 8 and tallest > 18 and tallest <= 24,
      ("a coin tumbles over as it falls: from %.1f to %.1f pixels tall (15 lying flat, never quite round)"):format(thinnest, tallest))
At(HOLD + coin.tl - 0.001)
local fall = Drawn(coin)
At(HOLD + coin.tl + 0.001)
local hit = Drawn(coin)
check(fall.h > 11 and fall.h < 20 and hit.h < fall.h,
      ("it comes down nearly flat and gives a little as it hits (%.1f, then %.1f)"):format(fall.h, hit.h))
At(HOLD + coin.still + 0.5)
local still = Drawn(coin)
check(still.y == coin.y1 and math.abs(still.h - 15) < 0.05 and math.abs(still.rot) < 0.01, "then rocks still, flat")
-- Not in step: the same coin in two columns lands at slightly different moments.
local apart = false
for k = 1, 3 do
    if borinCoins[k] and junoCoins[k] and borinCoins[k].tl ~= junoCoins[k].tl then apart = true end
end
check(apart, "the columns drop their coins out of step, a little")
curtain.__scripts.OnClick(curtain, "LeftButton")
check(Showing("Mira Vale") == 0, "a click puts the pile away with the rest")
WORLD.visible = nil
Reset()
-- Nearly level: still done in the right order.
ITEMS[206] = { 3, 49000, 4, 1 }
s = Run(9123, "Near Keep", { me = five, ["Borin Oak"] = ItemLink(206, "Nearly five", 3) })
began = nil
Leave()
check(DoneAt("Borin Oak") < DoneAt("Mira Vale"),
      ("4g 90s against 5g: 4g 90s is done first (%.3f against %.3f s)"):format(DoneAt("Borin Oak"), DoneAt("Mira Vale")))
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
-- Alone with loot among the others: the biggest item there is, at the end.
s = Run(9122, "Lone Keep", { me = two })
began = nil
Leave()
check(#PiecesOf("Borin Oak") == 0 and PiecesOf("Mira Vale")[1].side == math.min(96, math.sqrt(FILL * Col("Mira Vale").w * SIZED))
      and DoneAt("Mira Vale") == MAIN + FINALE_IN and #Plan().finale == 1,
      "the only item there is: as big as it gets, the whole finale on its own")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
-- Stacks: every copy falls on its own, at its share of the stack: up to
-- 30 of one item, 80 pieces a column, the most valuable; copies beyond
-- that still count in the timing.
ITEMS[210] = { 1, 200, 7, 0 }
ITEMS[211] = { 1, 10, 7, 0 }
ITEMS[212] = { 1, 20, 7, 0 }
ITEMS[213] = { 1, 50, 7, 0 }
WORLD.party = Party("Borin Oak")
s = Enter(9125, "Stack Keep")
NOW = NOW + 600
for _, stack in ipairs({ { 210, "Cloth", 5 }, { 211, "Grit", 70 }, { 212, "Sand", 40 }, { 213, "Ore", 40 } }) do
    Loot(("You receive loot: %sx%d."):format(ItemLink(stack[1], stack[2], 1), stack[3]))
end
Loot(("Borin Oak receives loot: %s."):format(one))
RunTimers()
began = nil
Leave()
local count, sized, last = {}, true, 0
for _, p in ipairs(PiecesOf("Mira Vale")) do
    count[p.name] = (count[p.name] or 0) + 1
    if p.name == "Cloth" and p.v ~= 200 then sized = false end
    last = math.max(last, p.tl)
end
check(count.Cloth == 5 and sized, "5 cloth fall as 5 pieces, each at its unit price")
check(count.Ore == 30 and count.Sand == 30 and count.Grit == 15,
      ("40 ore and 40 sand as 30 each, the most of one item; 70 grit as %d, the column's 80 at most"):format(count.Grit or 0))
local total = 5 * 200 + 70 * 10 + 40 * 20 + 40 * 50
At(Down() + 0.01)
check(last == DoneAt("Mira Vale") and Col("Mira Vale").total == Gold(total)
      and math.abs(BarOf("Mira Vale") - Plan().reach * total / 10000) < 0.001,
      "the copies not shown still count: my total and my bar end at the whole stacks' worth (against Borin's 1g)")
local inOrder = true
local list = PiecesOf("Mira Vale")
for k = 2, #list do
    if list[k].tl <= list[k - 1].tl then inOrder = false end
end
check(inOrder and #list == 80, "eighty pieces in one column still land one after another")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
s = Run(9101, "Race Keep")
Leave()
curtain.__scripts.OnClick(curtain, "LeftButton")

print("-- in silence")
o.ceremonySound = false
main:Hide()
began = nil
heard = {}
ns.ShowWindow(true, s)
for step = 1, 90 do At(step * 0.1) end
check(not Racing() and next(heard) == nil, "with Sounds unticked, the loot falls without a sound, and no fanfare")
o.ceremonySound = true

print("-- a click skips it")
main:Hide()
began = nil
ns.ShowWindow(true, s)
At(HOLD + MAIN + FINALE_IN + 0.1)
check(Racing() and Col("Mira Vale").loot == 0 and Showing("Kett Longstride") > 0 and Heard("tension") == 1, "run again, into the finale")
heard, stopped = {}, 0
curtain.__scripts.OnClick(curtain, "LeftButton")
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.total == Gold(50000) and Order() == "Kett Borin Mira Sela Juno",
      "a click on the columns shows the run as it is")
check(Showing("Kett Longstride") == 0 and Showing("Borin Oak") == 0, "with no piece left")
check(Heard("fanfare") == 0 and stopped == 1, "without the fanfare, and the tension sound stops")
check(BarOf("Mira Vale") == 0 and not Col("Sela Marrow").frame.raceNote:IsShown(), "no bar, no name left over")
main:Hide()
began = nil
ns.ShowWindow(true, s)
At(Down() + PAUSE + OUT / 2)
check(Racing() and math.abs(Shade() - 0.5) < 0.001, "run again, half faded out")
curtain.__scripts.OnClick(curtain, "LeftButton")
check(not Racing() and Shade() == 1 and Col("Mira Vale").loot == 1, "a click there shows it all at full strength")

print("-- what the window does meanwhile")
began = nil
ns.ShowWindow(true, s)
local falling = PiecesOf("Kett Longstride")[1]
At(HOLD + (falling.ts + falling.tl) / 2)
local before = Drawn(falling)
ns.Rerender() -- an option changed, say
local after = Drawn(PiecesOf("Kett Longstride")[1])
me = Col("Mira Vale")
check(Racing() and me.total == "" and me.loot == 0 and Order() == "Borin Juno Kett Mira Sela"
      and before and after and before.x == after.x and before.y == after.y,
      "a redraw in the middle of the race leaves it, and every piece, where it was")
o.useColumns = false
ns.Rerender()
check(not Racing() and Showing("Kett Longstride") == 0, "the list calls it off, and puts the pile away")
o.useColumns = true
ns.Rerender()
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.total == Gold(50000), "and the columns come back as they are")
began = nil
ns.ShowWindow(true, s)
At(Down() + PAUSE + OUT + IN / 2)
check(Racing() and math.abs(Shade() - 0.5) < 0.001, "racing again, the run half faded in")
driver.__scripts.OnHide(driver) -- the window is closed
check(not Racing() and Shade() == 1, "closing the window calls it off, nothing left faded")
ns.ShowWindow(false, s)
check(not Racing() and Col("Mira Vale").loot == 1, "opened again by hand, the run is simply shown")

print("-- under a loading screen")
main:Hide()
began = nil
ns.ShowWindow(true, s)
NOW = NOW + 3 -- three seconds pass before the first frame is drawn
At(HOLD / 2)
check(Racing() and Col("Juno Ash").place == 0 and Showing("Mira Vale") == 0,
      "time that passes before the first frame is not the race's: it starts from nothing")
At(HOLD + DoneAt("Kett Longstride") + 0.01)
check(Showing("Kett Longstride") == 1 and Showing("Mira Vale") == 0, "and is where it should be when its own time has passed")
curtain.__scripts.OnClick(curtain, "LeftButton")
NOW = math.floor(NOW) + 1

print("-- played again on request")
main:Hide()
began = nil
local said = Printed(function() SlashCmdList.THATLUCKYBASTARD("race") end)
check(main:IsShown() and Racing() and Col("Mira Vale").total == "" and said == "",
      "/tlb race plays it again for the run on show")
curtain.__scripts.OnClick(curtain, "LeftButton")
o.race = false
said = Printed(function() SlashCmdList.THATLUCKYBASTARD("race") end)
check(not Racing() and said:find("No race: it takes the Race option, columns in podium order (not mini mode), "
          .. "two players and some loot.", 1, true) ~= nil,
      "and says what it takes when there is nothing to run")
o.race = true

print("-- when there is no race")
local function Races()
    main:Hide()
    began = nil
    ns.ShowWindow(true, s)
    local on = Racing()
    if on then curtain.__scripts.OnClick(curtain, "LeftButton") end
    return on
end
check(Races(), "by default there is one")
o.race = false
check(not Races(), "none with the option off")
o.race = true
o.sortPlayers = "value"
check(not Races(), "none in another order than the podium's: there is no podium to walk to")
o.sortPlayers = "podium"
o.useColumns = false
check(not Races(), "none in the list")
o.useColumns = true
check(Races(), "and one again with everything back")
Reset()

-- Alone, or with nothing looted, there is nothing to race for.
WORLD.party = {}
Enter(9102, "Alone Keep")
NOW = NOW + 300
Loot(("You receive loot: %s."):format(five))
RunTimers()
Leave()
check(main:IsShown() and not Racing(), "a run alone opens without a race")
Reset()
WORLD.party = Party("Borin Oak")
local empty = Enter(9103, "Empty Keep")
empty.kills = 1 -- something happened, so the run is worth showing
NOW = NOW + 300
ns.ShowWindow(true, empty)
check(not Racing(), "nor is there one with no loot at all")
Reset()

print("-- a run that ended with the window shut")
o.popupLeave = false
s = Run(9104, "Later Keep")
Leave()
check(not main:IsShown() and not Racing(), "with the breakdown switched off, leaving opens nothing")
began = nil
ns.ToggleWindow()
check(main:IsShown() and Racing(), "the race is run the first time the window is opened on that run")
At(Total() + 0.1)
check(not Racing(), "to its end")
ns.ToggleWindow()
ns.ToggleWindow()
check(main:IsShown() and not Racing(), "and not the second time")
Reset()

-- Back inside before the window was opened: the run is not over.
s = Run(9107, "Again Keep")
Leave()
NOW = NOW + 60
Enter(9107, "Again Keep")
ns.ToggleWindow()
check(db.active == s and main:IsShown() and not Racing(), "back inside, the run opened by hand is shown without a race")
main:Hide()
began = nil
Leave()
ns.ToggleWindow()
check(Racing(), "which waits for the next time it is left")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()

-- The window open on the run all along.
s = Run(9108, "Open Keep")
ns.ShowWindow()
check(main:IsShown() and not Racing(), "with the window open during the run")
Leave()
RunTimers()
check(Racing(), "leaving races in it, though nothing had to open")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()

-- Straight from one dungeon into the next: the window opens on the run
-- in progress as ever, and the one that ended is revealed when stepped
-- back to.
local ended = Run(9109, "First Keep")
NOW = NOW + 60
local nextRun = Enter(9110, "Second Keep")
RunTimers()
check(nextRun ~= ended and db.history[1] == ended and not main:IsShown(), "one run ends as the next starts, with nothing opened")
ns.ToggleWindow()
check(ns.ViewedRun() == nextRun and not Racing(), "the window opens on the run in progress, not on the one that ended")
for _, w in ipairs(FRAMES) do
    local tpl = rawget(w, "tpl")
    if type(tpl) == "table" and tpl.__text == "< Older" then tpl.__scripts.OnClick(tpl) end
end
check(ns.ViewedRun() == ended and Racing(), "stepping back to that one plays its race")
curtain.__scripts.OnClick(curtain, "LeftButton")
ns.ToggleWindow()
ns.ShowRun(ended)
check(not Racing(), "once")
o.popupLeave = true
Reset()

print("-- more than five players")
WORLD.party = Party("Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash", "Extra One")
s = Enter(9105, "Crowd Keep")
NOW = NOW + 600
Loot(("You receive loot: %s."):format(five))
Loot(("%s receives loot: %s."):format("Borin Oak", four))
Loot(("%s receives loot: %s."):format("Sela Marrow", two))
Loot(("%s receives loot: %s."):format("Kett Longstride", one))
Loot(("%s receives loot: %s."):format("Juno Ash", one))
RunTimers()
began = nil
Leave()
local function Seats(alpha)
    local seats = 0
    for _, w in ipairs(FRAMES) do
        if rawget(w, "bench") and w:IsShown() and w:GetAlpha() == alpha then seats = seats + 1 end
    end
    return seats
end
check(Racing() and #Cols() == 5 and #Plan().frames == 5 and Seats(0) == 1 and Seats(1) == 0,
      "the top five race; the sixth, on the bench, is out of sight while they stand tall")
At(Total() + 0.1)
check(not Racing() and #Cols() == 5 and Seats(1) == 1, "the race ends as with five, and the bench is back")
Reset()

print("-- a column much longer than the window")
for id = 300, 329 do ITEMS[id] = { 2, 1000, 4, 1 } end
WORLD.party = Party("Borin Oak", "Sela Marrow")
s = Enter(9111, "Long Keep")
NOW = NOW + 600
for id = 300, 329 do Loot(("You receive loot: %s."):format(ItemLink(id, "Thing " .. id, 2))) end
Loot(("%s receives loot: %s."):format("Borin Oak", four))
RunTimers()
began = nil
Leave()
At(Down() + 0.1)
me = Col("Mira Vale")
local pile, low, high = PiecesOf("Mira Vale"), 0, math.huge
for _, p in ipairs(pile) do
    low, high = math.max(low, p.y1 + p.side / 2), math.min(high, p.y1 - p.side / 2)
end
check(Racing() and me.h < 500 and #pile == 30 and math.abs(low - (me.h - 6)) < 0.001 and high >= me.h - Plan().room + 4 - 0.001,
      ("thirty lines of loot to come: the column races short (%d), all thirty in a pile under its head"):format(me.h))
At(Total() + 0.1)
check(not Racing() and Col("Mira Vale").h > 600 and Showing("Mira Vale") == 0,
      ("and has its own length once the race is over (%d)"):format(Col("Mira Vale").h))
Reset()

print("-- on receipts")
ns.SetTheme("receipt")
s = Run(9106, "Paper Keep")
began = nil
Leave()
me, juno = Col("Mira Vale"), Col("Juno Ash")
local piece = PiecesOf("Mira Vale")[1]
check(Racing() and me.h == juno.h and me.total == "", "receipts race at one length, so that a long one says nothing")
check(piece.tex:IsDesaturated() and piece.tex.__tint and piece.tex.__tint[1] < 0.7 and piece.box.edge.__color[1] < 0.5,
      "the loot printed in ink, its border too")
check(Col("Mira Vale").frame.raceBar.__color[1] < 0.5 and Col("Mira Vale").frame.raceBar.__color[4] == 0.07,
      "and the bars, fainter")
At(HOLD + Plan().finale[1].tl + RISE + 0.01)
local inked = Col("Sela Marrow").frame.market.__text
check(inked ~= "" and not inked:find("|cffffd700", 1, true), "the totals count up in ink (" .. Plain(inked) .. ")")
At(Down() + PAUSE + OUT + 0.001)
me, juno = Col("Mira Vale"), Col("Juno Ash")
check(me.h > juno.h and me.drop == 0 and juno.drop == 0, "in place, each is torn off at its own; receipts do not step down")
At(Total() + 0.1)
check(not Racing() and Col("Mira Vale").total == Gold(50000), "and the run is shown as it is")
ns.SetTheme("modern")
Reset()
s = Run(9123, "Gold Keep")
Leave()
piece = PiecesOf("Mira Vale")[1]
check(not piece.tex:IsDesaturated() and piece.tex.__tint[1] == 1 and piece.box.edge.__color[3] > 0.8,
      "back in Modern, in colour again, with their quality's border")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (reveal)")
