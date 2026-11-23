-- Mini mode: a small window with a card per player (picture, name, award,
-- total) under the title bar, and nothing else: no columns, no loot, no
-- rows of buttons. Up to five cards, an arrow after them only when there
-- are more players, and a window exactly as wide as that. In every theme.
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
local main = ThatLuckyBastardFrame

ITEMS[201] = { 3, 50000, 4, 1 }
ITEMS[202] = { 3, 40000, 4, 1 }
ITEMS[203] = { 3, 20000, 4, 1 }
ITEMS[204] = { 3, 10000, 4, 1 }
ITEMS[205] = { 3, 5000, 4, 1 }
local LOOT = { ItemLink(202, "Four", 3), ItemLink(203, "Two", 3), ItemLink(204, "One", 3), ItemLink(205, "Half", 3) }
local five = ItemLink(201, "Five", 3)

local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- A finished run: I get 5g, and of `others` the first gets 4g, the second
-- 2g, the third 1g and the rest 50s each.
local function Run(id, name, others)
    WORLD.party = {}
    for i, other in ipairs(others) do WORLD.party[i] = { other, "MAGE", "DAMAGER" } end
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    NOW = NOW + 600
    Loot(("You receive loot: %s."):format(five))
    for i, other in ipairs(others) do
        Loot(("%s receives loot: %s."):format(other, LOOT[math.min(i, #LOOT)]))
    end
    RunTimers()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    SlashCmdList.THATLUCKYBASTARD("stop")
    main:Hide()
    NOW = NOW + 3600
    return db.history[1]
end

-- The columns on show.
local function Cols()
    local n = 0
    for _, w in ipairs(FRAMES) do
        if rawget(w, "market") and rawget(w, "rows") and w:IsShown() then n = n + 1 end
    end
    return n
end
-- The cards on show, from left to right, and what each one shows.
local function Cards()
    local cards = {}
    for _, w in ipairs(FRAMES) do
        if rawget(w, "bench") and w:IsShown() then
            cards[#cards + 1] = {
                who = w.p.name, x = w.__points[1][2], y = -w.__points[1][3], w = w.__w, h = w.__h,
                picture = w.portrait:IsShown(),
                title = w.title:IsShown() and Plain(w.title.__text) or nil,
                gold = w.gold:IsShown() and Plain(w.gold.__text) or nil,
            }
        end
    end
    table.sort(cards, function(a, b) return a.x < b.x end)
    return cards
end
local function Who()
    local names = {}
    for i, card in ipairs(Cards()) do names[i] = card.who:match("^%S+") end
    return table.concat(names, " ")
end
-- The arrows: the one that ends the row of cards, and its mirror at the
-- top of the list.
local function Arrow(field)
    for _, w in ipairs(FRAMES) do
        if rawget(w, field) and w:IsShown() then
            return { label = Plain(w.text.__text), x = w.__points[1][2], w = w.__w,
                     click = function() w.__scripts.OnClick(w, "LeftButton") end }
        end
    end
end
-- A button of the window, by its label: whether it is on show.
local function Button(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w:IsShown() end
    end
    error("no button labelled " .. label)
end
-- The cogwheel that opens the options.
local function Cog()
    for _, w in ipairs(FRAMES) do
        if rawget(w, "cog") == true then return w end -- (the window itself has a field of that name)
    end
end
-- Where it is: its corner, how far in from it, and its size.
local function Place(w)
    local p = w.__points[1]
    return ("%s %d %d, %dx%d"):format(p[1], p[2], p[3], w.__w, w.__h)
end
-- How many buttons the addon's windows have under one label.
local function Labelled(label)
    local n = 0
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then n = n + 1 end
    end
    return n
end
local BUTTONS = { "Need only", "Front page", "Analysis", "Share", "< Older", "Newer >", "Delete",
                  "Statistics" }
local function Buttons()
    local n = 0
    for _, label in ipairs(BUTTONS) do
        if Button(label) then n = n + 1 end
    end
    return n
end
local function Drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end
-- The last text written that names the run: the window's title.
local function Title(run)
    for i = #TEXTLOG, 1, -1 do
        local t = Plain(TEXTLOG[i])
        if t:find(run, 1, true) and t:find("|T", 1, true) then return t end
    end
    return ""
end
local function Draw()
    TEXTLOG = {}
    ns.Rerender()
end
-- A card, the gap after it, the arrow, the window's two margins; and the
-- room the title bar takes above the cards, with the margin under them.
local CARD, GAP, ARROW, MARGINS = 104, 6, 64, 24
local ABOVE = { modern = 46, classic = 30, receipt = 46 }
local function Row(cards, arrow) -- how wide the window is around that many cards
    return cards * (CARD + GAP) - GAP + (arrow and GAP + ARROW or 0) + MARGINS
end
local function Size() return main:GetWidth() .. "x" .. main:GetHeight() end
-- No empty space: the row starts at the window's margin and ends at it.
local function Flush()
    local cards, arrow = Cards(), Arrow("more")
    local last = arrow or cards[#cards]
    return cards[1].x == 0 and last.x + last.w == main:GetWidth() - MARGINS
end

local s = Run(9601, "Mini Keep", { "Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash" })
ns.ShowRun(s)
local FULL = Size()

print("-- the full window, for comparison")
Draw()
check(Cols() == 5 and #Cards() == 0 and Buttons() == #BUTTONS and Drew("Equal split") and main.full == nil,
      "five columns, the footer and every button, in a window of " .. FULL)
check(Title("Mini Keep"):find("That Lucky Bastard", 1, true) ~= nil, "titled with the addon's name and the dungeon's")
local cog = Cog()
local FOOT = "BOTTOMRIGHT -24 10, 22x22"
check(cog ~= nil and cog:IsShown() and Place(cog) == FOOT,
      "with a cogwheel at its foot, right of Statistics (" .. (cog and Place(cog) or "none") .. ")")
check(cog.icon.__w == 16 and Labelled("Options") == 0, "in place of the Options button, which is gone")
check(not cog.face:IsShown() and not cog.edge:IsShown() and not cog.icon:IsDesaturated(),
      "the bare gear, with nothing behind it")
cog.__scripts.OnClick(cog, "LeftButton")
check(ThatLuckyBastardOptionsFrame:IsShown(), "which opens the options")
cog.__scripts.OnEnter(cog)
check(TIP[1] == "Options", "and says so under the mouse")
ns.ToggleOptions()

print("-- mini, five players")
o.mini = true
Draw()
local cards = Cards()
check(Cols() == 0 and #cards == 5, "in place of the columns, five cards: one per player")
check(Who() == "Mira Borin Sela Kett Juno", "side by side, the biggest total first (" .. Who() .. ")")
local whole = true
for _, card in ipairs(cards) do
    if not (card.picture and card.title and card.gold) then whole = false end
end
check(whole and cards[1].gold == Plain(ns.Money(50000)) and cards[5].gold == Plain(ns.Money(5000)),
      "each with its picture, its award and its total")
check(not Drew("Equal split") and not Drew("Fairness") and not Drew("Five"), "and no loot and no footer")
check(Buttons() == 0 and Arrow("more") == nil, "the window has none of its buttons, and no arrow: all five are there")
check(cog:IsShown() and Place(cog) == "TOPRIGHT -34 -7, 22x22", "but the cogwheel, now in the title bar beside the cross")
cog.__scripts.OnClick(cog, "LeftButton")
check(ThatLuckyBastardOptionsFrame:IsShown(), "which opens the options, where mini mode is switched off")
ns.ToggleOptions()
check(not ThatLuckyBastardOptionsFrame:IsShown() and #Cards() == 5, "and leaves the mini window as it was")
local h = cards[1].h + ABOVE.modern + 12
check(main:GetWidth() == Row(5) and main:GetHeight() == h and h < 160,
      ("it is as big as its cards: %s, from %s"):format(Size(), FULL))
check(Flush(), "with no empty space beside them")
check(Title("Mini Keep") ~= "" and not Title("Mini Keep"):find("That Lucky Bastard", 1, true),
      "its title is the dungeon's name alone")
local small = Size()
main.__scripts.OnDragStop(main)
check(db.window.w .. "x" .. db.window.h == FULL, "the size kept for the next session is its own, not the mini one")

print("-- what the options say")
o.benchPicture, o.benchAward, o.benchValue = false, false, false
Draw()
cards = Cards()
check(cards[1].picture and cards[1].title and cards[1].gold, "the bench's own options are not the mini window's")
o.benchPicture, o.benchAward, o.benchValue = true, true, true
o.showAwards = false
Draw()
check(Cards()[1].title == nil and Cards()[1].gold ~= nil and main:GetHeight() == h - 13, "without awards, cards have none and are shorter")
o.showAwards = true
o.portrait = "none"
Draw()
check(not Cards()[1].picture and Cards()[1].title ~= nil and main:GetHeight() < h, "without pictures too")
o.portrait = "2d"
o.sortPlayers = "name"
Draw()
check(Who() == "Borin Juno Kett Mira Sela", "ordered by name when that is the order chosen (" .. Who() .. ")")
o.sortPlayers = "podium"
Draw()
check(Size() == small, "back as it was")

print("-- in every theme")
ns.SetTheme("classic")
Draw()
check(#Cards() == 5 and Cols() == 0 and Buttons() == 0 and Flush()
      and main:GetHeight() == Cards()[1].h + ABOVE.classic + 12, "Classic: five cards under its lower title bar (" .. Size() .. ")")
check(cog:IsShown() and Place(cog) == "TOPRIGHT -26 -2, 18x18" and cog.icon.__w == 14 and not cog.icon:IsDesaturated(),
      "its cogwheel smaller and nearer the corner, as its title bar is (" .. Place(cog) .. ")")
ns.SetTheme("receipt")
Draw()
check(#Cards() == 5 and Cols() == 0 and Buttons() == 0 and Flush()
      and main:GetHeight() == Cards()[1].h + ABOVE.receipt + 12, "Receipt: five tickets (" .. Size() .. ")")
check(cog:IsShown() and Place(cog) == "TOPRIGHT -34 -7, 22x22" and not cog.icon:IsDesaturated()
      and rawget(cog, "bg") == nil, "and its cogwheel beside the cross: the same icon, on no key (" .. Place(cog) .. ")")
ns.SetTheme("modern")
Draw()

print("-- fewer players")
local four = Run(9602, "Four Keep", { "Borin Oak", "Sela Marrow", "Kett Longstride" })
ns.ShowRun(four)
check(#Cards() == 4 and Arrow("more") == nil and main:GetWidth() == Row(4) and Flush(),
      "four players: four cards and no arrow, in a narrower window (" .. Size() .. ")")
local two = Run(9603, "Duo Keep", { "Borin Oak" })
ns.ShowRun(two)
check(#Cards() == 2 and Arrow("more") == nil and main:GetWidth() == Row(2) and Flush(),
      "two players: two cards (" .. Size() .. ")")
WORLD.party = {}
local solo = Run(9604, "Solo Keep", {})
ns.ShowRun(solo)
check(#Cards() == 1 and Arrow("more") == nil and main:GetWidth() == 150 and Cards()[1].x == (150 - MARGINS - CARD) / 2,
      "alone: one card, in the middle of the narrowest window there is (" .. Size() .. ")")

print("-- more than five players")
local seven = Run(9605, "Crowd Keep", { "Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash", "Extra One", "Extra Two" })
ns.ShowRun(seven)
local arrow = Arrow("more")
check(#Cards() == 5 and Who() == "Mira Borin Sela Kett Extra", "seven players: the top five on cards (" .. Who() .. ")")
check(arrow ~= nil and arrow.label == "List\n2 more", "and an arrow that counts the other two")
check(main:GetWidth() == Row(5, true) and Flush(), "the window is wider by the arrow, and no more (" .. Size() .. ")")
local six = Run(9606, "Six Keep", { "Borin Oak", "Sela Marrow", "Kett Longstride", "Juno Ash", "Extra One" })
ns.ShowRun(six)
check(#Cards() == 5 and Arrow("more") and Arrow("more").label == "List\n1 more", "six players: five cards, and one more")
ns.SetTheme("receipt")
Draw()
check(Arrow("more").label == "LIST\n1 MORE", "on the till key, in the Receipt theme")
ns.SetTheme("modern")
ns.ShowRun(seven)

print("-- to the list and back")
Arrow("more").click()
check(#Cards() == 0 and Cols() == 0 and Buttons() == #BUTTONS and Size() == FULL and main.full == nil,
      "the arrow shows the run as a list, in the full window with its buttons")
check(Title("Crowd Keep"):find("That Lucky Bastard", 1, true) ~= nil and cog:IsShown() and Place(cog) == FOOT,
      "under its full title, the cogwheel back at its foot")
local back = Arrow("back")
check(back ~= nil and back.label == "Columns" and o.mini == true, "where the Columns arrow leads back")
back.click()
check(#Cards() == 5 and Buttons() == 0 and main:GetWidth() == Row(5, true), "to the mini window")
o.useColumns = false
Draw()
check(#Cards() == 0 and Buttons() == #BUTTONS and Size() == FULL and Arrow("back") == nil,
      "with Always a list chosen there is no mini window: every run is a list")
o.useColumns = true
Draw()

print("-- the switch, in one step")
-- The game works out the scroll area's new size at some point of a draw
-- that resizes the window, or just after it, and says so. Whenever that
-- is, one draw must leave the window right, and ask for no other.
ns.ShowRun(s)
local content
for _, w in ipairs(FRAMES) do
    if rawget(w, "bench") and w:IsShown() then content = w.__parent end
end
local scroll = content.__parent
local function Told(width) scroll.__scripts.OnSizeChanged(scroll, width) end
local function Spread() -- how far right the columns reach
    local reach = 0
    for _, w in ipairs(FRAMES) do
        if rawget(w, "market") and rawget(w, "rows") and w:IsShown() then
            reach = math.max(reach, w.__points[1][2] + w.__w)
        end
    end
    return reach
end
RunTimers() -- whatever was waiting to be drawn
Told(main:GetWidth() - MARGINS)
check(content:GetWidth() == Row(5) - MARGINS and #TIMERS == 0, "told the width it was drawn for, the mini window asks for no second draw")
-- Told a stale width in the middle of each draw, as the game may.
local realAwards, stale = ns.RunAwards, nil
ns.RunAwards = function(...)
    Told(stale)
    return realAwards(...)
end
o.mini = false
stale = Row(5) - 26 -- the scroll area's in the full window's margins, the window still mini-sized
Draw()
check(Size() == FULL and content:GetWidth() == 780 - 26 and math.abs(Spread() - content:GetWidth()) < 0.01,
      ("to the full window in one draw: its size, and its columns across its whole width (%d of %d)"):format(
          Spread(), content:GetWidth()))
check(#TIMERS == 0, "with no second draw asked for")
o.mini = true
stale = 780 - MARGINS -- the scroll area's in the mini window's margins, the window still full-sized
Draw()
check(Size() == small and #Cards() == 5 and Flush() and content:GetWidth() == Row(5) - MARGINS,
      "to the mini window in one draw: its size, and its cards flush with it")
check(#TIMERS == 0, "with no second draw asked for either")
ns.RunAwards = realAwards
-- A window dragged wider is another matter.
o.mini = false
Draw()
Told(900)
check(content:GetWidth() == 900 and #TIMERS == 1, "a width the window was not drawn for is taken, and drawn for")
RunTimers()
check(content:GetWidth() == 780 - 26, "(the draw lays out for the window as it is)")
o.mini = true
Draw()

print("-- no race")
local curtain
for _, w in ipairs(FRAMES) do
    if rawget(w, "curtain") then curtain = w end
end
main:Hide()
ns.ShowWindow(true, s)
check(main:IsShown() and not curtain:IsShown() and #Cards() == 5 and Size() == small,
      "a run left with mini on is shown on its cards, with no race")

print("-- the dungeon's short name")
local zf = Run(209, "Zul'Farrak", { "Borin Oak", "Sela Marrow" })
ns.ShowRun(zf)
Draw()
local zfTitle = Title("ZF")
check(zfTitle:match("|t%s*(.-)$") == "ZF", "the title names the dungeon the way players do (" .. zfTitle .. ")")
o.mini = false
Draw()
check(Title("Zul'Farrak"):find("That Lucky Bastard", 1, true) ~= nil, "the full window keeps its full name")
o.mini = true
ns.ShowRun(s)
Draw()

print("-- switched off")
o.mini = false
Draw()
check(Cols() == 5 and #Cards() == 0 and Buttons() == #BUTTONS and Drew("Equal split") and Size() == FULL
      and main.full == nil, "the columns, the footer, the buttons and the window's size are back")
check(not curtain:IsShown(), "and the reveal that mini mode had no use for is not played now")
check(cog:IsShown() and Place(cog) == FOOT, "the cogwheel is back at the foot of the window")
main:Hide()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (mini)")
