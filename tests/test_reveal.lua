-- The race: how the breakdown reveals a finished run as it is left, with
-- the columns in podium order. Each player's loot falls into their column
-- as coins, all at the same pace: the smallest stack is done first, and a
-- winner far ahead overflows. The columns then walk to their places and
-- the rest fades in.
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
o.ticker, o.bingo, o.streak = false, false, false
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

-- The coins: the race's plan (Coins.lua), and what each coin is drawn as.
local function Plan() return ns.Coins.Current() end
-- The coins of player `name`, in the order they fall.
local function CoinsOf(name)
    local list = {}
    for _, c in ipairs(Plan().coins) do
        if c.frame.hover.p.name == name then list[#list + 1] = c end
    end
    return list
end
local function DoneAt(name)
    for i, frame in ipairs(Plan().frames) do
        if frame.hover.p.name == name then return Plan().doneAt[i] end
    end
end
-- Where a coin is drawn (its middle, from its column's top left corner,
-- y going down), how tall, how see-through; nil while it is not there.
local function Drawn(c)
    if not c.tex:IsShown() then return nil end
    local p = c.tex.__points[1]
    return { x = p[4], y = -p[5], h = c.tex.__h, alpha = c.tex:GetAlpha(), frame = p[2] }
end
local function Showing(name)
    local n = 0
    for _, c in ipairs(CoinsOf(name)) do
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
local HOLD, PAUSE, WALK, FADE = 0.3, 0.3, 0.6, 0.4 -- the race's parts, in seconds, besides the coins
local G = 1600 -- the coins' gravity
local function Down() return HOLD + Plan().endAt end -- when the last coin is
local function Total() return Down() + PAUSE + WALK + FADE end
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
-- The sounds played, by kind: coins landing, and the fanfare.
local clinks, fanfares, shots = 0, 0, 0
PlaySound = function(kit)
    if kit == 120 then clinks = clinks + 1 elseif kit == 878 then fanfares = fanfares + 1 end
end
Screenshot = function() shots = shots + 1 end

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

print("-- the coins")
local mine, borins = CoinsOf("Mira Vale"), CoinsOf("Borin Oak")
check(#mine == 20 and #borins == 16 and #CoinsOf("Sela Marrow") == 8 and #CoinsOf("Kett Longstride") == 4
      and #CoinsOf("Juno Ash") == 0 and not Plan().overflow,
      "a coin per quarter of the winner's twentieth: 20 for 5g, 16 for 4g, 8 for 2g, 4 for 1g, none for nothing")
At(HOLD / 2)
check(Showing("Mira Vale") == 0 and Col("Juno Ash").place == 0, "a beat before anything moves")
-- One coin, from start to finish.
local first = mine[1]
At(HOLD + first.ts + 0.05)
local a = Drawn(first)
At(HOLD + first.ts + 0.10)
local b = Drawn(first)
check(a and b and math.abs(a.y - (first.y0 + 0.5 * G * 0.05 ^ 2)) < 0.01 and (b.y - a.y) > (a.y - first.y0),
      "a coin falls under gravity, faster and faster")
check(a.frame == me.frame and a.h < 15 or b.h < 15, ("spinning as it falls: seen at %.1f and %.1f of its 15 pixels"):format(a.h, b.h))
At(HOLD + first.tl + 0.03)
local c = Drawn(first)
check(c.y < first.y1 and c.h == 15, "where it lands, it bounces")
At(HOLD + first.th + 0.01)
c = Drawn(first)
check(c.y == first.y1 and c.h == 15 and math.abs(c.x - me.w / 2) <= 1.5, "and settles, in the middle of its column")
local straight = true
for _, coin in ipairs(mine) do
    if math.abs(coin.x1 - me.w / 2) > 1.5 then straight = false end
end
check(math.abs(mine[2].y1 - mine[1].y1 + 5) < 0.001 and math.abs(mine[20].y1 - mine[1].y1 + 95) < 0.001 and straight,
      "each coin 5 pixels above the one before, within a pixel and a half of the middle: a stack")
check(math.abs(first.y1 + 7.5 - (me.h - 6)) < 0.001, "standing on the foot of the column, in sight")
-- Everyone at the same pace.
At(HOLD + 0.45)
check(Showing("Mira Vale") == 5 and Showing("Borin Oak") == 5 and Showing("Sela Marrow") == 5 and Showing("Kett Longstride") == 4,
      "half a second in, five coins each: the same pace for everyone (Kett has only four)")
check(clinks > 0, ("coins clink as they land (%d so far)"):format(clinks))
-- Done one after another, the smallest first.
local doneKett, doneSela, doneBorin, doneMe = DoneAt("Kett Longstride"), DoneAt("Sela Marrow"), DoneAt("Borin Oak"), DoneAt("Mira Vale")
check(DoneAt("Juno Ash") == 0 and doneKett < doneSela and doneSela < doneBorin and doneBorin < doneMe,
      ("done one after another: Juno at once, Kett %.2f, Sela %.2f, Borin %.2f, Mira %.2f s"):format(doneKett, doneSela, doneBorin, doneMe))
At(HOLD + doneSela - 0.01)
check(Col("Sela Marrow").total == "" and Col("Kett Longstride").total == Gold(10000) and Col("Juno Ash").total == "-",
      "a total is not shown while its coins still fall")
At(HOLD + doneSela + 0.01)
local sela = Col("Sela Marrow")
check(sela.total == Gold(20000) and sela.place == 1 and Col("Mira Vale").total == "" and Col("Mira Vale").place == 0,
      "but as the last is down, with the place: the winner's still falling")
At(HOLD + doneBorin + 0.01)
check(Col("Borin Oak").total == Gold(40000) and Col("Mira Vale").total == "", "4g is second; the last stack still growing has won")
check(fanfares == 0, "no fanfare yet")
At(Down() + 0.01)
me = Col("Mira Vale")
check(me.total == Gold(50000) and me.place == 1 and fanfares == 1, "the last coin down: the winner's 5g, with the fanfare")
check(Down() < 3, ("the coins take %.1f seconds"):format(Plan().endAt))
local landed = Drawn(mine[20])
check(landed and landed.alpha == 1 and landed.y == mine[20].y1, "every coin where it fell")

print("-- the walk to the podium")
At(Down() + PAUSE - 0.01)
check(Order() == "Borin Juno Kett Mira Sela" and Col("Mira Vale").drop == 0, "a beat on the result")
local pitch = Col("Juno Ash").x - Col("Borin Oak").x
At(Down() + PAUSE + WALK / 2)
me = Col("Mira Vale")
local kett = Col("Kett Longstride")
check(math.abs(me.x - 2.5 * pitch) < 0.001 and math.abs(kett.x - 1 * pitch) < 0.001,
      "half way, each column is half way to its place")
local walking = Drawn(mine[20])
check(walking and math.abs(walking.alpha - 0.5) < 0.001 and walking.frame == me.frame and walking.y == mine[20].y1,
      "the coins go with their column, half gone")
At(Down() + PAUSE + WALK + 0.001)
me, borin, kett = Col("Mira Vale"), Col("Borin Oak"), Col("Kett Longstride")
check(Order() == "Kett Borin Mira Sela Juno", "they end in podium order: the winner in the middle (" .. Order() .. ")")
check(me.drop == 0 and borin.drop == 14 and kett.drop == 42 and me.h - borin.h == 14,
      "stepping down by place, their feet level")
check(me.loot < 0.01 and Racing() and Drawn(mine[20]).alpha < 0.01, "the loot has yet to show, and the coins are gone")

print("-- the rest fades in")
At(Down() + PAUSE + WALK + FADE / 2)
me = Col("Mira Vale")
check(math.abs(me.loot - 0.5) < 0.001 and math.abs(me.share - 0.5) < 0.001 and me.loot == me.share,
      "half way through, at half strength")
o.ceremonyScreenshot = true
local total = Total()
At(total + 0.01)
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.share == 1 and me.place == 1 and me.total == Gold(50000)
      and (me.award or 1) == 1, ("after %.1f seconds the run is shown as it is"):format(total))
check(Order() == "Kett Borin Mira Sela Juno" and Showing("Mira Vale") == 0, "in podium order, the coins put away")
check(math.abs(me.tint - Col("Borin Oak").tint - 0.04) < 0.0001, "the winner's column a shade brighter, as it is drawn outside a race")
check(Col("Borin Oak").tint == racingTint, "and the others as bright as they were during it")
RunTimers()
check(shots == 1, "and its photo is taken, when the option asks for one")
NOW = began + total + 4
driver.__scripts.OnUpdate(driver, 0.01)
check(not Racing() and shots == 1, "it is run once")
o.ceremonyScreenshot = false

print("-- a winner far ahead")
Reset()
-- I get 5g, Borin 2g, Sela and Kett 1g: two and a half times the next.
s = Run(9120, "Heap Keep", { me = five, ["Borin Oak"] = two, ["Sela Marrow"] = one, ["Kett Longstride"] = one })
began = nil
Leave()
mine = CoinsOf("Mira Vale")
local stack, heap = {}, {}
for _, coin in ipairs(mine) do
    if coin.spill then heap[#heap + 1] = coin else stack[#stack + 1] = coin end
end
check(Plan().overflow and #CoinsOf("Borin Oak") == 20 and #CoinsOf("Sela Marrow") == 10 and #stack == 20 and #heap == 30,
      ("the next one's stack is full at 20; mine is too, and 30 more pour over it (%d)"):format(#heap))
local lastStack = stack[#stack].ts
check(heap[1].ts > lastStack and math.abs(heap[2].ts - heap[1].ts - 0.035) < 0.0001,
      "they come once the stack is full, three times as fast")
check(DoneAt("Mira Vale") > DoneAt("Borin Oak"), "the winner is still the last one done")
me = Col("Mira Vale")
local left, right, highest, inside = 0, 0, math.huge, true
for _, coin in ipairs(heap) do
    if coin.x2 < me.w / 2 - 5 then left = left + 1 elseif coin.x2 > me.w / 2 + 5 then right = right + 1 end
    highest = math.min(highest, coin.y2)
    if coin.x2 - 15 < 0 or coin.x2 + 15 > me.w or coin.y2 + 7.5 * coin.squash > me.h - 6 + 0.001 then inside = false end
end
check(left >= 8 and right >= 8, ("they roll down both sides of the stack (%d left, %d right)"):format(left, right))
check(highest > stack[20].y1 and inside, "into a heap lower than the stack, within the column, on its foot")
local poured = heap[10]
At(HOLD + poured.tl + 0.01)
local onTop = Drawn(poured)
check(onTop and onTop.x == poured.x1 and onTop.y <= poured.y1 and math.abs(poured.y1 + 7.5 - (stack[20].y1 + 2.5)) < 0.001,
      "a poured coin lands on top of the stack")
At(HOLD + poured.th + 0.25 / 2)
local rolling = Drawn(poured)
check(rolling and math.abs(rolling.x - (poured.x1 + poured.x2) / 2) < 0.01 and rolling.y > onTop.y,
      "then rolls off it and down")
At(HOLD + poured.tr + 0.01)
local lying = Drawn(poured)
local flattest, roundest = 1, 0
for _, coin in ipairs(heap) do
    flattest, roundest = math.min(flattest, coin.squash), math.max(roundest, coin.squash)
end
check(lying.x == poured.x2 and lying.y == poured.y2 and math.abs(lying.h - 15 * poured.squash) < 0.001,
      ("and lies on the heap (%.1f pixels tall)"):format(lying.h))
check(flattest < 0.8 and roundest <= 1 and roundest - flattest > 0.2,
      ("the heap's coins lying anyhow, some flatter than others (%.2f to %.2f)"):format(flattest, roundest))
check(Total() < 6.5, ("all in %.1f seconds"):format(Total()))
curtain.__scripts.OnClick(curtain, "LeftButton")
check(Showing("Mira Vale") == 0, "a click puts the heap away with the rest")
Reset()
-- Just under half as much again: no heap.
ITEMS[205] = { 3, 34000, 4, 1 }
s = Run(9121, "Close Keep", { me = five, ["Borin Oak"] = ItemLink(205, "Three and a bit", 3) })
began = nil
Leave()
check(not Plan().overflow and #CoinsOf("Mira Vale") == 20 and #CoinsOf("Borin Oak") == 14,
      "a winner less than half as much again ahead: a full stack, and no more")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
-- Alone with loot among the others: the most of all.
s = Run(9122, "Lone Keep", { me = two })
began = nil
Leave()
check(Plan().overflow and Plan().spill == 36 and #CoinsOf("Borin Oak") == 0, "the only one with loot: the heap is as big as it gets")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
s = Run(9101, "Race Keep")
Leave()
curtain.__scripts.OnClick(curtain, "LeftButton")

print("-- in silence")
o.ceremonySound = false
main:Hide()
began = nil
clinks, fanfares = 0, 0
ns.ShowWindow(true, s)
for step = 1, 60 do At(step * 0.1) end
check(not Racing() and clinks == 0 and fanfares == 0, "with Sounds unticked, the coins fall without a clink, and no fanfare")
o.ceremonySound = true

print("-- a click skips it")
main:Hide()
began = nil
ns.ShowWindow(true, s)
At(1)
check(Racing() and Col("Mira Vale").loot == 0 and Showing("Mira Vale") > 0, "run again, a second in")
fanfares = 0
curtain.__scripts.OnClick(curtain, "LeftButton")
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.total == Gold(50000) and Order() == "Kett Borin Mira Sela Juno",
      "a click on the columns shows the run as it is")
check(Showing("Mira Vale") == 0 and Showing("Borin Oak") == 0, "with no coin left")
check(fanfares == 0, "without the fanfare")

print("-- what the window does meanwhile")
began = nil
ns.ShowWindow(true, s)
At(HOLD + 1.0)
local before = Drawn(CoinsOf("Mira Vale")[6])
ns.Rerender() -- an option changed, say
local after = Drawn(CoinsOf("Mira Vale")[6])
me = Col("Mira Vale")
check(Racing() and me.total == "" and me.loot == 0 and Order() == "Borin Juno Kett Mira Sela"
      and before and after and before.x == after.x and before.y == after.y,
      "a redraw in the middle of the race leaves it, and every coin, where it was")
o.useColumns = false
ns.Rerender()
check(not Racing() and Showing("Mira Vale") == 0, "the list calls it off, and puts the coins away")
o.useColumns = true
ns.Rerender()
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.total == Gold(50000), "and the columns come back as they are")
began = nil
ns.ShowWindow(true, s)
check(Racing(), "racing again")
driver.__scripts.OnHide(driver) -- the window is closed
check(not Racing(), "closing the window calls it off")
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
At(HOLD + 0.45)
check(Showing("Mira Vale") == 5, "and is where it should be when its own time has passed")
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
check(not Racing() and said:find("No race: it takes the Race option", 1, true) ~= nil,
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
At(HOLD + 1)
me = Col("Mira Vale")
local base = Drawn(CoinsOf("Mira Vale")[1])
check(Racing() and me.h < 400 and base and math.abs(base.y + 7.5 - (me.h - 6)) < 0.001,
      ("thirty lines of loot to come: the column races short (%d), its coins in sight under its head"):format(me.h))
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
local coin = CoinsOf("Mira Vale")[1].tex
check(Racing() and me.h == juno.h and me.total == "", "receipts race at one length, so that a long one says nothing")
check(coin:IsDesaturated() and coin.__tint and coin.__tint[1] < 0.7, "the coins printed in ink")
At(Down() + PAUSE + WALK + 0.001)
me, juno = Col("Mira Vale"), Col("Juno Ash")
check(me.h > juno.h and me.drop == 0 and juno.drop == 0, "in place, each is torn off at its own; receipts do not step down")
At(Total() + 0.1)
check(not Racing() and Col("Mira Vale").total == Gold(50000), "and the run is shown as it is")
ns.SetTheme("modern")
Reset()
s = Run(9123, "Gold Keep")
Leave()
check(not CoinsOf("Mira Vale")[1].tex:IsDesaturated() and CoinsOf("Mira Vale")[1].tex.__tint[1] == 1,
      "back in Modern, they are gold again")
curtain.__scripts.OnClick(curtain, "LeftButton")
Reset()
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (reveal)")
