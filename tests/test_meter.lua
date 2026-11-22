-- The meter: a window of its own with a bar per player, the most loot
-- first, that keeps up with the loot of the run in progress. Bars glide
-- to their new length and rows slide when someone overtakes.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

RAID_CLASS_COLORS.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
RAID_CLASS_COLORS.MAGE = { r = 0.25, g = 0.78, b = 0.92 }
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local o = db.options
o.ticker, o.streak, o.bingo, o.popupLeave = false, false, false, false
local main, meter = ThatLuckyBastardFrame, ThatLuckyBastardMeterFrame

-- Worth 5g, 4g, 2g and 1g at the vendor (bind on pickup: no auction price).
ITEMS[201] = { 3, 50000, 4, 1 }
ITEMS[202] = { 3, 40000, 4, 1 }
ITEMS[203] = { 3, 20000, 4, 1 }
ITEMS[204] = { 3, 10000, 4, 1 }
local five, four, two, one = ItemLink(201, "Five", 3), ItemLink(202, "Four", 3), ItemLink(203, "Two", 3),
    ItemLink(204, "One", 3)

local function Plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Gold(c) return Plain(ns.MoneyPlain(c)) end
local function Enter(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    RunTimers()
    return db.active
end
local function Leave()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    RunTimers()
end
local function Stop()
    if db.active then SlashCmdList.THATLUCKYBASTARD("stop") end
    main:Hide()
    NOW = NOW + 3600
end
local function Picks(who, link)
    Loot(who == "me" and ("You receive loot: %s."):format(link) or ("%s receives loot: %s."):format(who, link))
    RunTimers()
end

-- The meter's rows on show, top to bottom (by where they are going).
local function Rows()
    local list = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "meterRow") and w:IsShown() then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.ty < b.ty end)
    return list
end
local function Row(name)
    for _, r in ipairs(Rows()) do
        if r.p.name == name then return r end
    end
end
local function Order()
    local names = {}
    for i, r in ipairs(Rows()) do names[i] = r.p.name:match("^%S+") end
    return table.concat(names, " ")
end
local clock
for _, w in ipairs(FRAMES) do
    if rawget(w, "meterClock") then clock = w end
end
local function Tick(dt) clock.__scripts.OnUpdate(clock, dt) end
local function Settle() for _ = 1, 40 do Tick(0.05) end end
-- The meter's title, as last written: what follows its logo.
local function Title()
    for i = #TEXTLOG, 1, -1 do
        local t = TEXTLOG[i]
        if t:sub(1, 2) == "|T" and not t:find("Bastard|r", 1, true) then return (Plain(t):gsub("^|T.-|t%s*", "")) end
    end
    return ""
end
local function Drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
local PITCH = 22
local TOP = 22 + 2 -- the slim title bar and the line under it

print("-- opening it")
local escapes = false
for _, name in ipairs(UISpecialFrames) do
    if name == "ThatLuckyBastardMeterFrame" then escapes = true end
end
check(not meter:IsShown() and not escapes, "the meter is shut to begin with, and Escape leaves it alone")
TEXTLOG = {}
SlashCmdList.THATLUCKYBASTARD("meter")
check(meter:IsShown() and #Rows() == 0 and Drew("No run yet.") and Title():find("Meter", 1, true),
      "/tlb meter opens it; with no run at all, it says so")
check(meter:GetWidth() == 270 and meter:GetHeight() == TOP + 4 + 5 * PITCH - 2 + 12,
      ("as tall as five rows to begin with (%dx%d)"):format(meter:GetWidth(), meter:GetHeight()))
SlashCmdList.THATLUCKYBASTARD("meter")
check(not meter:IsShown(), "and a second time shuts it")
local meterBtn
for _, w in ipairs(FRAMES) do
    local tpl = rawget(w, "tpl")
    if type(tpl) == "table" and tpl.__text == "Meter" then meterBtn = tpl end
end
check(meterBtn ~= nil, "the main window has a Meter button")
meterBtn.__scripts.OnClick(meterBtn)
check(meter:IsShown(), "which opens it too")

print("-- a run in progress")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { "Kett Longstride", "HUNTER", "DAMAGER" } }
TEXTLOG = {}
local run = Enter(9701, "Meter Keep")
check(#Rows() == 4 and Title() == "Meter Keep  live", "it shows the run as it starts: four rows, and 'live' (" .. Title() .. ")")
local blank = true
for _, r in ipairs(Rows()) do
    if r.tw ~= 0 or r.bar:IsShown() or Plain(r.value.__text) ~= "-" or r.share.__text ~= "" then blank = false end
end
check(blank, "with no loot yet, no bars, no totals and no shares")

print("-- the loot coming in")
check(not main:IsShown(), "the main window is shut")
Picks("Borin Oak", four)
local borin = Row("Borin Oak")
check(Order():match("^Borin") and borin.tw == 1 and Plain(borin.value.__text) == Gold(40000) and borin.share.__text == "100%",
      "Borin picks up 4g: he leads, his bar to be full, his total and share shown at once")
check(borin.w == 0, "his bar has yet to grow")
Tick(0.05)
check(borin.w > 0.3 and borin.w < 0.5 and borin.bar:IsShown(), ("it grows (%.2f of the way)"):format(borin.w))
Settle()
check(borin.w == 1 and borin.bar.__w == 270 - 8, "and settles at the full width of the row")
local before = Row("Mira Vale").y
Picks("me", five)
local me = Row("Mira Vale")
borin = Row("Borin Oak")
check(Order():match("^Mira Borin") and me.ty == 0 and borin.ty == PITCH, "a 5g pickup: I overtake him")
check(me.y == before and borin.y == 0, "but nobody has moved yet")
Tick(0.05)
check(me.y < before and me.y > 0 and borin.y > 0 and borin.y < PITCH, "the two rows slide past each other")
Settle()
check(me.y == 0 and borin.y == PITCH and math.abs(borin.w - 0.8) < 0.001 and me.w == 1,
      "and end in their new places, his bar now four fifths of mine")
check(me.share.__text == "56%" and borin.share.__text == "44%" and me.rank.__text == "1" and borin.rank.__text == "2",
      "shares and ranks follow")
Picks("Sela Marrow", two)
Picks("Kett Longstride", one)
Settle()
check(Order() == "Mira Borin Sela Kett" and math.abs(Row("Kett Longstride").w - 0.2) < 0.001,
      "everyone in their place: " .. Order())

print("-- the run over")
TEXTLOG = {}
Leave()
Tick(1)
local awards = ns.RunAwards(run, ns.Summarize(run))
local all = next(awards) ~= nil
for _, r in ipairs(Rows()) do
    local a = awards[r.p.name]
    if not (a and Plain(r.label.__text):find(a.title, 1, true)) then all = false end
end
check(all and Title() == "Meter Keep", "leaving, the run is over: no more 'live', and each award beside its name")
Row("Mira Vale").__scripts.OnEnter(Row("Mira Vale"))
local tip = Plain(table.concat(TIP, " / "))
check(tip:find("Mira Vale", 1, true) and tip:find("5g 00s   42% of the loot", 1, true) and tip:find(awards["Mira Vale"].title, 1, true)
      and tip:find("Click to open this run.", 1, true), "a row's tooltip: name, total and share, the award and its rule")
Stop()
Row("Borin Oak").__scripts.OnClick(Row("Borin Oak"))
check(main:IsShown() and ns.ViewedRun() == run, "a click on a row opens the run in the main window")
main:Hide()

print("-- the run on show")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
local second = Enter(9702, "Second Keep")
Picks("Borin Oak", two)
Leave()
Stop()
Tick(1)
check(Order() == "Borin Mira" and Title() == "Second Keep", "with no run going, it shows the latest: " .. Order())
Settle()
check(Row("Borin Oak").w == 1, "(where Borin's bar is full)")
ns.ShowRun(run)
check(Order() == "Mira Borin Sela Kett" and Row("Borin Oak").w == 0 and Row("Mira Vale").w == 0,
      "the main window shows another: so does the meter, every bar from nothing")
Settle()
check(Row("Mira Vale").w == 1, "growing again")
main:Hide()
Tick(1)
check(Order() == "Borin Mira", "the main window shut, back to the latest")

print("-- the themes")
ns.ShowRun(run)
main:Hide()
Settle()
local function Look(name)
    local r = Row(name)
    return r.bar.__texture, r.bar.__color, r.bar.__tint, r.bg.__color
end
local tex, color = Look("Borin Oak")
check(tex == nil and color[1] == 0.78 and color[4] == 0.6, "Modern: a flat bar in the class colour")
ns.SetTheme("classic")
local tint
tex, color, tint = Look("Borin Oak")
check(tex == "Interface\\TargetingFrame\\UI-StatusBar" and tint[1] == 0.78 and tint[2] == 0.61,
      "Classic: the game's own bar, in the class colour")
check(meter:GetHeight() == TOP + 4 + 5 * PITCH - 2 + 12, "the window keeps its size")
ns.SetTheme("receipt")
local bg
tex, color, tint, bg = Look("Borin Oak")
check(bg[1] == ns.PAPER[1] and color[1] == ns.INK[1] and color[4] == 0.16 and Plain(Row("Borin Oak").label.__text):find("BORIN OAK", 1, true),
      "Receipt: a strip of paper, the bar in light ink, the name in capitals")
ns.SetTheme("modern")

print("-- more players than fit")
WORLD.party = {}
for i = 1, 8 do WORLD.party[i] = { "Raider " .. i, "MAGE", "DAMAGER" } end
local raid = Enter(9703, "Crowd Keep")
for i = 1, 8 do Picks("Raider " .. i, one) end
Picks("me", five)
local scroll = Row("Mira Vale").__parent.__parent
check(#Rows() == 9 and scroll.__scroll == 0, "nine players: nine rows, five of them in sight")
scroll.__scripts.OnMouseWheel(scroll, -1)
check(scroll.__scroll == PITCH, "the mouse wheel scrolls down a row")
for _ = 1, 10 do scroll.__scripts.OnMouseWheel(scroll, -1) end
check(scroll.__scroll == 4 * PITCH, "down to the last, and no further")
for _ = 1, 10 do scroll.__scripts.OnMouseWheel(scroll, 1) end
check(scroll.__scroll == 0, "and back up to the first")
scroll.__scripts.OnMouseWheel(scroll, -2)
meter:SetHeight(TOP + 4 + 9 * PITCH - 2 + 12)
ns.Rerender()
check(scroll.__scroll == 0, "made taller for nine, there is nothing to scroll")
meter:SetHeight(TOP + 4 + 5 * PITCH - 2 + 12)
Leave()
Stop()

print("-- what a row shows")
-- An option of the panel, by its label; the `nth` with that label (the
-- meter's Award and Share are the second: the breakdown's come first).
local function control(label, nth)
    local seen = 0
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "get") and type(t) == "table" and t.__text == label then
            seen = seen + 1
            if seen == (nth or 1) then return w end
        end
    end
    error("no option labelled " .. label)
end
local function click(label, nth)
    local b = control(label, nth)
    b.__scripts.OnClick(b)
end
local function ticked(label, nth) return control(label, nth).get() and true or false end
local function greyed(label, nth) return not control(label, nth):IsEnabled() end
ns.ToggleOptions()
check(ticked("Rank") and ticked("Share", 2) and ticked("Award", 2) and not ticked("Open on entering")
      and not ticked("Close on leaving"),
      "Options > Meter: Rank, Share and Award ticked; opening and shutting left to you")
ns.ShowRun(run)
main:Hide()
Settle()
local function Mine() return Row("Mira Vale") end
check(Mine().rank:IsShown() and Mine().share:IsShown() and Mine().label.__points[1][2] == 22
      and Plain(Mine().label.__text):find(awards["Mira Vale"].title, 1, true), "a row shows all three to begin with")
click("Rank")
check(o.meterRank == false and not Mine().rank:IsShown() and Mine().label.__points[1][2] == 6,
      "without the rank, the name moves up to the edge")
click("Share", 2)
check(o.meterShare == false and not Mine().share:IsShown() and Mine().value.__points[1][2] == -4,
      "without the share, the total moves up to the other")
click("Award", 2)
check(o.meterAward == false and not Plain(Mine().label.__text):find(awards["Mira Vale"].title, 1, true)
      and Plain(Mine().label.__text):find("Mira Vale", 1, true), "without the award, the name stands alone")
click("Rank")
click("Share", 2)
click("Award", 2)
check(Mine().rank:IsShown() and Mine().share:IsShown() and Mine().label.__points[1][2] == 22
      and Mine().value.__points[1][2] == Mine().share and Plain(Mine().label.__text):find(awards["Mira Vale"].title, 1, true),
      "ticked again, all three are back")
click("Awards")
check(greyed("Award", 2) and not greyed("Rank"), "with no awards handed out, Award is greyed out")
click("Awards")

print("-- opening and shutting by itself")
meter:Hide()
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
Enter(9704, "Plain Keep")
check(not meter:IsShown(), "unticked, a run starting leaves the meter shut")
Picks("me", two)
Stop()
click("Open on entering")
local auto = Enter(9705, "Auto Keep")
check(o.meterOpen and meter:IsShown(), "with Open on entering ticked, it opens as a run starts")
Picks("me", two)
Leave()
check(meter:IsShown(), "and stays open as you leave")
click("Close on leaving")
NOW = NOW + 30
Enter(9705, "Auto Keep")
Leave()
check(o.meterClose and not meter:IsShown(), "with Close on leaving ticked, it shuts as you leave")
NOW = NOW + 30
Enter(9705, "Auto Keep")
check(db.active == auto and meter:IsShown(), "going back in, the run goes on, and the meter opens again")
meter:Hide()
Fire("PLAYER_ENTERING_WORLD", false, false) -- a loading screen inside the dungeon, or a /reload
RunTimers()
check(db.active == auto and not meter:IsShown(), "shut by hand inside, it stays shut through a loading screen")
meter:Show()
click("Open on entering")
meter:Hide()
Leave()
NOW = NOW + 30
Enter(9705, "Auto Keep")
check(db.active == auto and not meter:IsShown(), "with only Close on leaving ticked, it does not open by itself")
meter:Show()
Leave()
check(not meter:IsShown(), "but shuts as you leave all the same")
click("Close on leaving")
Stop()
ns.ToggleOptions()
meter:Show()

print("-- the title bar")
local mtitle = rawget(meter, "meterTitle")
local function Crosses(win)
    local list = {}
    for _, w in ipairs(FRAMES) do
        local p = rawget(w, "__parent")
        if w.__kind == "Button" and p and rawget(p, "__parent") == win and rawget(w, "__w") then
            list[#list + 1] = w.__w .. "x" .. w.__h
        end
    end
    table.sort(list)
    return table.concat(list, " ")
end
ns.Rerender()
local tp = mtitle.__points[1]
check(mtitle.__font == "GameFontHighlight" and tp[1] == "LEFT" and tp[3] == "TOPLEFT" and tp[4] == 8 and tp[5] == -11
      and mtitle.__justify == "LEFT"
      and scroll.__points[1][2] == 4 and scroll.__points[1][3] == -TOP - 4,
      "Modern: a slim title bar, 22 high, a smaller title in the middle of it, the rows close under it")
check(Crosses(meter) == "12x12 18x18 20x16" and Crosses(main):find("24x24", 1, true) and Crosses(main):find("24x22", 1, true)
      and not Crosses(main):find("18x18", 1, true),
      "a smaller cross than the other windows' (" .. Crosses(meter) .. ")")
local plain, _, plainTitle, plainSkins = ns.MakeWindow("ThatLuckyBastardPlainTest", 300, 200, "HIGH", false)
local _, plainTop = ns.ApplyWindowTheme(plainSkins, plainTitle)
check(plainTop == -46 and plainTitle.__font == "GameFontHighlightLarge" and plainTitle.__points[1][1] == "TOPLEFT"
      and Crosses(plain) == "24x22 24x24", "the other windows keep their full bar")
ns.SetTheme("receipt")
tp = mtitle.__points[1]
check(mtitle.__font == "ThatLuckyBastardReceiptTitleSmall" and tp[1] == "LEFT" and tp[5] == -11 and scroll.__points[1][3] == -TOP - 4,
      "Receipt: the same slim bar, the title in the till's type, smaller")
ns.SetTheme("classic")
check(mtitle.__font == "GameFontNormal" and mtitle.__points[1][1] == "TOP" and scroll.__points[1][3] == -34
      and mtitle.__justify == "CENTER",
      "Classic: the game's own title bar, as it was")
ns.SetTheme("modern")

print("-- the dungeon's short name")
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
local curly = string.char(226, 128, 153)
for _, n in ipairs({
    { 349, "Maraudon", "Mara" },
    { 36, "Die Todesminen", "DM" },                      -- by its ID, in another language
    { 9711, "The Stockade", "Stocks" },                  -- by its name, "The" aside
    { 9712, "Krol" .. curly .. "dok Stronghold", "KDS" }, -- a curly apostrophe
    { 9713, "Krol'Dok Stronghold", "KDS" },              -- a straight one, and another case
    { 9714, "Excavation Site: Wetlands", "ESW" },
    { 9715, "Shaper's Terrace", "Terrace" },
    { 429, "Dire Maul", "Dire Maul" },                   -- DM is the Deadmines
    { 9716, "Meter Keep", "Meter Keep" },                -- not one of them
}) do
    TEXTLOG = {}
    Enter(n[1], n[2])
    check(Title() == n[3] .. "  live", ("%s: %s (%s)"):format(n[2], n[3], Title()))
end
Leave()
Stop()

print("-- kept from one session to the next")
meter:ClearAllPoints()
meter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
meter:SetSize(300, 220)
meter.__scripts.OnDragStop(meter)
check(db.meter.w == 300 and db.meter.h == 220 and db.meter.point ~= nil, "moved or sized, it notes where and how big")
local saved = Reload()
db = saved
check(SAVED.meter.shown == true and saved.meter.w == 300, "logging out while it is open, it notes that too")
meter:Hide()
meter:SetSize(10, 10)
Fire("PLAYER_LOGIN")
check(meter:IsShown() and meter:GetWidth() == 300 and meter:GetHeight() == 220, "at login it is open again, as big as it was")
meter:Hide()
Fire("PLAYER_LOGOUT")
check(SAVED.meter.shown == nil, "shut at logout, it stays shut")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (meter)")
