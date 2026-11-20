-- The race: how the breakdown reveals a finished run the first time it
-- is shown, with the columns in podium order. Every total counts up at
-- the same speed, the smallest stops first, the columns then walk to
-- their places and the rest fades in.
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
            return { at = i, x = w.__points[1][2], drop = -w.__points[1][3], h = w.__h, total = Plain(w.market.__text),
                     place = w.rank:GetAlpha(), loot = w.rows[1]:GetAlpha(), share = w.share:GetAlpha(),
                     tint = w.bg.__color[4],
                     award = w.awardFrame and w.awardFrame:GetAlpha() or nil }
        end
    end
end
local function Order()
    local names = {}
    for i, w in ipairs(Cols()) do names[i] = w.hover.p.name:match("^%S+") end
    return table.concat(names, " ")
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
local sounds, shots = 0, 0
PlaySound = function() sounds = sounds + 1 end
Screenshot = function() shots = shots + 1 end

-- A run of five: I get 5g, Borin 4g, Sela 2g, Kett 1g and Juno nothing.
local function Run(id, name)
    WORLD.party = Party("Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash")
    local s = Enter(id, name)
    NOW = NOW + 600
    Loot(("You receive loot: %s."):format(five))
    Loot(("%s receives loot: %s."):format("Borin Oak", four))
    Loot(("%s receives loot: %s."):format("Sela Marrow", two))
    Loot(("%s receives loot: %s."):format("Kett Longstride", one))
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
check(me.total == "-" and borin.total == "-" and me.drop == 0 and borin.drop == 0 and me.h == borin.h,
      "level with one another, every total at nothing")
check(me.place == 0 and juno.place == 0 and me.loot == 0 and me.share == 0 and (me.award or 0) == 0,
      "with no place, no loot, no share and no award to give the result away")
check(me.tint == borin.tint and me.tint == juno.tint and me.tint > 0, "and no column brighter than another")
local racingTint = borin.tint

print("-- the count")
At(0.2)
check(Col("Juno Ash").place == 0 and Col("Mira Vale").total == "-", "a beat before anything moves")
At(0.3 + 3.4 * 0.501) -- half of the count: 2g 50s
me, borin = Col("Mira Vale"), Col("Borin Oak")
local sela, kett = Col("Sela Marrow"), Col("Kett Longstride")
juno = Col("Juno Ash")
check(me.total == Gold(25000) and borin.total == Gold(25000), "the two biggest are level, still counting (" .. me.total .. ")")
check(sela.total == Gold(20000) and kett.total == Gold(10000) and juno.total == "-", "the others have stopped at theirs")
check(sela.place == 1 and kett.place == 1 and juno.place == 1 and me.place == 0 and borin.place == 0,
      "a column that has stopped has its place; one still counting has none")
check(Order() == "Borin Juno Kett Mira Sela" and me.loot == 0, "nobody has moved, and no loot shows")
At(0.3 + 3.4 * 0.901) -- 4g 50s
me, borin = Col("Mira Vale"), Col("Borin Oak")
check(borin.total == Gold(40000) and borin.place == 1 and me.total == Gold(45000) and me.place == 0,
      "the second stops at 4g; the last one still counting is the winner")
check(sounds == 4, "each of the four who stopped ticked (" .. sounds .. ")")
At(0.3 + 3.4 + 0.01)
me = Col("Mira Vale")
check(me.total == Gold(50000) and me.place == 1 and sounds == 5, "the count ends on the winner's 5g, with the fanfare")

print("-- the walk to the podium")
At(0.3 + 3.4 + 0.29)
check(Order() == "Borin Juno Kett Mira Sela" and Col("Mira Vale").drop == 0, "a beat on the result")
local pitch = Col("Juno Ash").x - Col("Borin Oak").x
At(0.3 + 3.4 + 0.3 + 0.3)
me, kett = Col("Mira Vale"), Col("Kett Longstride")
check(math.abs(me.x - 2.5 * pitch) < 0.001 and math.abs(kett.x - 1 * pitch) < 0.001,
      "half way, each column is half way to its place")
At(0.3 + 3.4 + 0.3 + 0.6 + 0.001)
me, borin, kett = Col("Mira Vale"), Col("Borin Oak"), Col("Kett Longstride")
check(Order() == "Kett Borin Mira Sela Juno", "they end in podium order: the winner in the middle (" .. Order() .. ")")
check(me.drop == 0 and borin.drop == 14 and kett.drop == 42 and me.h - borin.h == 14,
      "stepping down by place, their feet level")
check(me.loot < 0.01 and Racing(), "the loot has yet to show")

print("-- the rest fades in")
At(0.3 + 3.4 + 0.3 + 0.6 + 0.2)
me = Col("Mira Vale")
check(math.abs(me.loot - 0.5) < 0.001 and math.abs(me.share - 0.5) < 0.001 and me.loot == me.share,
      "half way through, at half strength")
o.ceremonyScreenshot = true
At(5.0)
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.share == 1 and me.place == 1 and me.total == Gold(50000)
      and (me.award or 1) == 1, "after five seconds the run is shown as it is")
check(Order() == "Kett Borin Mira Sela Juno", "in podium order")
check(math.abs(me.tint - Col("Borin Oak").tint - 0.04) < 0.0001, "the winner's column a shade brighter, as it is drawn outside a race")
check(Col("Borin Oak").tint == racingTint, "and the others as bright as they were during it")
RunTimers()
check(shots == 1, "and its photo is taken, when the option asks for one")
NOW = began + 9
driver.__scripts.OnUpdate(driver, 0.01)
check(not Racing() and shots == 1, "it is run once")
o.ceremonyScreenshot = false

print("-- a click skips it")
main:Hide()
began = nil
ns.ShowWindow(true, s)
At(1)
check(Racing() and Col("Mira Vale").loot == 0, "run again, a second in")
sounds = 0
curtain.__scripts.OnClick(curtain, "LeftButton")
me = Col("Mira Vale")
check(not Racing() and me.loot == 1 and me.total == Gold(50000) and Order() == "Kett Borin Mira Sela Juno",
      "a click on the columns shows the run as it is")
check(sounds == 0, "without the fanfare")

print("-- what the window does meanwhile")
began = nil
ns.ShowWindow(true, s)
At(2)
ns.Rerender() -- an option changed, say
me = Col("Mira Vale")
check(Racing() and me.total == Gold(25000) and me.loot == 0 and Order() == "Borin Juno Kett Mira Sela",
      "a redraw in the middle of the race leaves it where it was")
o.useColumns = false
ns.Rerender()
check(not Racing(), "the list calls it off")
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
At(0.2)
check(Racing() and Col("Juno Ash").place == 0 and Col("Mira Vale").total == "-",
      "time that passes before the first frame is not the race's: it starts from nothing")
At(0.3 + 3.4 * 0.501)
check(Col("Mira Vale").total == Gold(25000) and Col("Sela Marrow").place == 1, "and is half way when half its own time has passed")
curtain.__scripts.OnClick(curtain, "LeftButton")
NOW = math.floor(NOW) + 1

print("-- played again on request")
main:Hide()
began = nil
local said = Printed(function() SlashCmdList.THATLUCKYBASTARD("race") end)
check(main:IsShown() and Racing() and Col("Mira Vale").total == "-" and said == "",
      "/tlb race plays it again for the run on show")
curtain.__scripts.OnClick(curtain, "LeftButton")
o.race = false
said = Printed(function() SlashCmdList.THATLUCKYBASTARD("race") end)
check(not Racing() and said:find("No race: it takes the Race option", 1, true) ~= nil,
      "and says what it takes when there is nothing to run")
o.race = true

print("-- when there is no race")
local function Races(why)
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
local alone = Enter(9102, "Alone Keep")
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
At(5.1)
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
local seats = 0
for _, w in ipairs(FRAMES) do
    if rawget(w, "bench") and w:IsShown() and w:GetAlpha() == 1 then seats = seats + 1 end
end
check(Racing() and #Cols() == 5 and seats == 1, "the top five race; the sixth is on the bench from the start")
At(5.1)
check(not Racing() and #Cols() == 5, "and the race ends as with five")
Reset()

print("-- on receipts")
ns.SetTheme("receipt")
s = Run(9106, "Paper Keep")
began = nil
Leave()
me, juno = Col("Mira Vale"), Col("Juno Ash")
check(Racing() and me.h == juno.h and me.total == "-", "receipts race at one length, so that a long one says nothing")
At(0.3 + 3.4 + 0.3 + 0.6 + 0.001)
me, juno = Col("Mira Vale"), Col("Juno Ash")
check(me.h > juno.h and me.drop == 0 and juno.drop == 0, "in place, each is torn off at its own; receipts do not step down")
At(5.1)
check(not Racing() and Col("Mira Vale").total == Gold(50000), "and the run is shown as it is")
ns.SetTheme("modern")
Reset()
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (reveal)")
