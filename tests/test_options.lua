-- The options panel: its pages, the choices that stand for two saved
-- switches, the tooltips and what is greyed out when it does nothing (and
-- why), the boxes typed in, the runs to keep, the Defaults button, the
-- meter shown beside its page, Replay, the size of the windows, and loot
-- bingo gone.
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

local function InOptions(w)
    while w and w ~= ThatLuckyBastardOptionsFrame do w = rawget(w, "__parent") end
    return w ~= nil
end
-- An option of the panel, by its label; the `nth` one with that label
-- (the first unless said: the loot categories are also the kinds of item
-- a tooltip line is for).
local function control(label, nth)
    local seen = 0
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "get") and (rawget(w, "label") == label or (type(t) == "table" and t.__text == label)) then
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
-- What its tooltip says, line by line after its name.
local function tip(label, nth)
    local b = control(label, nth)
    TIP = {}
    b.__scripts.OnEnter(b)
    local lines = TIP
    b.__scripts.OnLeave(b)
    return table.concat(lines, " / ")
end
-- A page's name in the list on the left.
local function nav(name)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == name and not rawget(w, "get") and InOptions(w) and w.__scripts.OnClick then
            return w
        end
    end
end
local function open(name) nav(name).__scripts.OnClick(nav(name)) end
-- A box to type a number in, by the option it sets.
local function box(key)
    for _, w in ipairs(FRAMES) do
        if w.__kind == "EditBox" and rawget(w, "key") == key and InOptions(w) then return w end
    end
end
local function type_in(key, text)
    local b = box(key)
    b:SetText(text)
    b.__scripts.OnEditFocusLost(b)
end
-- A button made by ns.MakeButton, by its label.
local function button(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w end
    end
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t:find(text, 1, true) then return true end
    end
    return false
end

print("-- defaults")
check(o.showSilver and not o.showCopper and ns.MoneyPlain(123456) == "12g 34s",
      "a new install writes amounts as 12g 34s (" .. ns.MoneyPlain(123456) .. ")")
o.showSilver, o.showCopper = false, true
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(o.showCopper == false, "silver off with copper on, which the options no longer offer, becomes 12g")
o.showSilver = true

ns.ToggleOptions()
check(ThatLuckyBastardOptionsFrame:IsShown() and ThatLuckyBastardFrame:IsShown(), "the options open, with the main window")

print("-- pages and wording")
local names = {}
for i, p in ipairs(ns.OPTION_PAGES) do names[i] = p.name end
check(table.concat(names, ", ") == "Look, Breakdown, Meter, Loot, During a run, End of run, Tooltips, Share, Runs",
      "nine pages, named after what you see: " .. table.concat(names, ", "))
local navsFound = true
for _, name in ipairs(names) do navsFound = navsFound and nav(name) ~= nil end
check(navsFound and nav("While you play") == nil and nav("General") == nil and nav("Window") == nil,
      "each listed on the left; the old pages are gone")
-- Every saved option on one page, for its Defaults; but the number of
-- runs to keep (a lower one deletes runs), the minimap button's place and
-- the Share window's own choice.
local home, twice, unplaced = {}, {}, {}
for _, p in ipairs(ns.OPTION_PAGES) do
    for _, key in ipairs(p.keys) do
        if home[key] then twice[#twice + 1] = key end
        home[key] = p.name
    end
end
for key in pairs(ns.OPTION_DEFAULTS) do
    if not home[key] and key ~= "maxHistory" and key ~= "minimapAngle" and key ~= "shareMode" then
        unplaced[#unplaced + 1] = key
    end
end
check(#twice == 0 and #unplaced == 0 and home.theme == "Look",
      "every option is on one page, and one only (twice: " .. table.concat(twice, " ") .. "; nowhere: "
      .. table.concat(unplaced, " ") .. ")")
for _, label in ipairs({
    "Modern", "Classic", "Receipt", "TLB", "Class", "Custom", "12g 34s 56c", "12g 34s", "12g",
    "Minimap button", "Columns", "List", "Mini", "2D", "3D", "None", "Game", "Full", "First", "Podium", "Loot", "Role",
    "Name", "Me first", "Share", "Share bar", "Vendor total", "Value", "Icons", "Group by category", "Line up", "Picture",
    "Award", "Gold", "Run total", "Run stats", "Rank", "Open on entering", "Close on leaving", "Auction", "Vendor",
    "When looted", "Today", "Epic BoE", "Bind on Pickup", "Professions", "Coins", "Quest items", "Hidden still count",
    "Valuable loot", "Familiar face", "Bets", "Open breakdown", "Chat line", "Streak recap", "Awards", "Race",
    "Sounds", "Screenshot", "Runs together", "Seen in runs", "Run link", "Run time", "Group total", "Share %",
    "Gap to equal split", "Raids", "Ask", "New run",
}) do
    control(label) -- errors if missing
end
check(box("tickerMin") and box("summaryLines") and box("maxHistory"), "every option is there under its new name, and three boxes")
check(ticked("Open breakdown") and ticked("Race") and ticked("Valuable loot") and ticked("12g 34s") and ticked("Ask")
      and ticked("2D") and ticked("Podium") and ticked("Columns") and ticked("TLB") and ticked("Modern")
      and box("maxHistory"):GetText() == "300" and box("tickerMin"):GetText() == "5",
      "the defaults are chosen")

print("-- a choice is not a box")
local choiceB, boxB = control("Columns"), control("Group by category")
check(not choiceB.box:IsShown() and choiceB.under:IsShown() and not control("List").under:IsShown()
      and boxB.box:IsShown() and boxB.tick:IsShown(),
      "in Modern, a choice is a row of buttons, the chosen one marked; a switch is a box")
click("Classic")
check(choiceB.box:IsShown() and choiceB.tick:IsShown() and not choiceB.under:IsShown()
      and choiceB:GetWidth() > control("List"):GetWidth(),
      "in Classic, the game's radio buttons, each as wide as its label")
click("Modern")
check(tip("Podium") == "Top looter in the middle." and tip("Group by category"):find("each under its heading", 1, true),
      "each option says what it does under the mouse (" .. tip("Podium") .. ")")
check(tip("Rank") == "" and #TIP == 0, "where its name says it all, there is no tooltip")

print("-- the end of a run")
check(not nav("The podium") and o.podiumOnLeave == nil, "the podium window's choices are gone")
click("Open breakdown")
check(o.popupLeave == false and not greyed("Race") and not greyed("Sounds"),
      "the breakdown can stay shut: the reveal waits for the first time it is opened")
click("Open breakdown")
click("Race")
check(o.race == false and o.popupLeave and not greyed("Sounds"), "without the race, the awards are revealed one by one")
click("Awards")
check(not o.showAwards and greyed("Sounds") and greyed("Screenshot"),
      "and without awards either, nothing is: the sound and the screenshot are greyed out")
check(tip("Sounds") == "While the awards come up. / Awards and Race are off.", "and say why: " .. tip("Sounds"))
click("Race")
check(o.race and not greyed("Sounds"), "the race alone is a reveal")
click("Awards")

print("-- what the podium window's switch becomes")
local function Migrated(window, podium)
    o.popupLeave, o.podiumOnLeave, o.race = window, podium, nil
    Fire("ADDON_LOADED", "ThatLuckyBastard")
    return o.podiumOnLeave == nil and o.popupLeave, o.race
end
local window, race = Migrated(true, true)
check(window == true and race == true, "the breakdown and the podium: the breakdown, with the race")
window, race = Migrated(false, true)
check(window == true and race == true, "the podium alone: the breakdown opens in its place, with the race")
window, race = Migrated(true, false)
check(window == true and race == false, "the breakdown alone: as it was, without the race")
window, race = Migrated(false, false)
check(window == false and race == false, "nothing: still nothing")
o.popupLeave, o.race = true, true
ns.SyncOptions()

print("-- money")
click("12g")
check(not o.showSilver and not o.showCopper and ns.MoneyPlain(123456) == "12g", "12g: gold only")
click("12g 34s 56c")
check(o.showSilver and o.showCopper and ns.MoneyPlain(123456) == "12g 34s 56c" and not ticked("12g"),
      "12g 34s 56c: all three (" .. ns.MoneyPlain(123456) .. ")")
click("12g 34s")

print("-- the valuable loot notice")
type_in("tickerMin", "25")
check(o.ticker and o.tickerMin == 250000 and box("tickerMin"):GetText() == "25", "its amount is typed in gold: 25g")
type_in("tickerMin", "0")
check(o.tickerMin == 10000, "1g at the least")
type_in("tickerMin", "")
check(o.tickerMin == 10000 and box("tickerMin"):GetText() == "1", "an empty box keeps the amount")
click("Valuable loot")
check(o.ticker == false and o.tickerMin == 10000 and box("tickerMin"):GetAlpha() == 0.4,
      "the notice can be switched off; its amount is kept, greyed out")
TIP = {}
box("tickerMin").__scripts.OnEnter(box("tickerMin"))
check(TIP[#TIP] == "Valuable loot is off.", "and says why under the mouse")
click("Valuable loot")
type_in("tickerMin", "5")
check(o.ticker and o.tickerMin == 50000 and box("tickerMin"):GetAlpha() == 1, "switched on again")

print("-- greyed out when it does nothing, and why")
check(not greyed("Line up"), "lining items up works in the columns")
click("List")
check(o.useColumns == false and o.mini == false and greyed("Line up") and tip("Line up"):find("Columns layout only.", 1, true),
      "but not in the list, and says so")
check(greyed("Race") and tip("Race"):find("Needs the Columns layout (Breakdown).", 1, true), "nor does the race")
check(greyed("Picture") and greyed("Gold"), "nor the bench, which follows the columns")
click("Columns")
check(not greyed("Race") and not greyed("Picture"), "which are back with them")
-- Mini mode keeps the player, their total and their award: what is about
-- the rest does nothing while it is on.
local rest = { "Share", "Share bar", "Vendor total", "Value", "Icons", "Group by category", "Line up",
               "Picture", "Award", "Gold", "Run total", "Run stats" }
local function Greyed()
    local n = 0
    for _, label in ipairs(rest) do
        if greyed(label) then n = n + 1 end
    end
    return n
end
check(not ticked("Mini") and Greyed() == 0, "Mini is not the layout to begin with, and nothing is greyed out for it")
click("Mini")
check(o.mini == true and o.useColumns == true and ticked("Mini") and not ticked("Columns") and Greyed() == #rest,
      "chosen, it is the columns' mini mode; the " .. #rest .. " options about what it leaves out are greyed out ("
      .. Greyed() .. ")")
check(tip("Run total"):find("Not in the Mini layout.", 1, true) ~= nil, "saying why")
check(not greyed("Podium") and not greyed("2D") and not greyed("Game"),
      "those about the players and their order are not")
check(greyed("Race"), "the race is, which takes columns")
click("List")
check(Greyed() == 4 and greyed("Line up") and greyed("Picture") and o.mini == false,
      "in the list they count again, but for lining items up and the bench")
click("Columns")
check(o.mini == false and Greyed() == 0 and not greyed("Race"), "and in the columns, everything is back")
check(not greyed("Share bar"), "the share bar works in Modern")
click("Classic")
check(db.theme == "classic" and greyed("Share bar") and tip("Share bar"):find("Not in the Classic theme.", 1, true),
      "but not in Classic")
click("Modern")
check(greyed("Me first") and tip("Me first"):find("Not with Podium order.", 1, true), "putting me first does nothing in podium order")
click("Loot")
check(o.sortPlayers == "value" and not greyed("Me first"), "it works in any other")
check(greyed("Race") and tip("Race"):find("Needs Podium order (Breakdown).", 1, true), "where there is no podium to race for")
click("Podium")
click("Vendor")
check(o.valueMode == "vendor" and greyed("Vendor total"), "vendor totals mean nothing with vendor prices only")
check(greyed("When looted") and greyed("Today") and tip("Today"):find("Value is set to Vendor.", 1, true),
      "nor does the day of an auction price")
click("Auction")
check(o.priceTime == "then" and not greyed("When looted") and greyed("Today")
      and tip("Today"):find("No Auctionator or TradeSkillMaster.", 1, true),
      "with no addon giving auction prices, there are no prices of today to choose")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return nil end } } }
click("Auction")
check(o.priceTime == "then" and not greyed("Today"), "auction prices are the recorded ones unless chosen otherwise")
click("Today")
check(o.priceTime == "now", "current prices can be chosen")
click("When looted")
check(o.priceTime == "then", "and recorded ones again")
Auctionator = nil
check(greyed("Hidden still count"), "with every category shown, nothing is hidden to count")
click("Junk")
check(o.cats.junk == false and not greyed("Hidden still count"), "unticking one makes it count")
click("Junk")

print("-- the kinds of item with a tooltip line")
local kinds = { "Epic BoE", "Blue BoE", "Green BoE", "Bind on Pickup", "Professions", "Other", "Junk", "Quest items" }
local on, off = {}, {}
for _, label in ipairs(kinds) do
    local list = ticked(label, 2) and on or off
    list[#list + 1] = label
end
check(table.concat(on, ", ") == "Epic BoE, Blue BoE, Green BoE, Bind on Pickup"
      and table.concat(off, ", ") == "Professions, Other, Junk, Quest items",
      "under the items' switch, one box per category: the BoE ones and Bind on Pickup are ticked")
click("Junk", 2)
check(o.tipCats.junk == true and o.cats.junk == true and ticked("Junk", 2), "ticking one is its own setting, not the window's")
click("Junk", 2)
click("Epic BoE", 2)
check(o.tipCats.epic == false and o.cats.epic == true, "and so is unticking one")
click("Epic BoE", 2)
check(not greyed("Epic BoE", 2), "they count while the line is on")
-- What they do: an item seen in past runs gets its line if its kind is ticked.
ITEMS[100] = { 2, 1500, 4, 2 }   -- green BoE
ITEMS[103] = { 0, 300, 15, 0 }   -- junk
db.drops[9001] = {
    ["100"] = { n = 2, c = 2, v = 3000, q = 2, name = "Green Gloves", at = NOW, by = "Borin Oak" },
    ["103"] = { n = 5, c = 9, v = 2700, q = 0, name = "Broken Fang", at = NOW, by = "Borin Oak" },
    ["999"] = { n = 1, c = 1, v = 100, q = 1, name = "Never seen since", at = NOW, by = "Borin Oak" },
}
local function Tip(id)
    TIP = {}
    TOOLTIP_HOOKS[Enum.TooltipDataType.Item](GameTooltip, { id = id })
    return TIP[1]
end
check(Tip(100) ~= nil and #TIP == 1 and Tip(100):find("Seen in 2 runs", 1, true) ~= nil and Tip(103) == nil,
      "a green has its line; junk has none (" .. tostring(Tip(100)) .. ")")
click("Junk", 2)
check(Tip(103) ~= nil and Tip(103):find("Seen in 5 runs", 1, true) ~= nil, "junk has it once its box is ticked")
click("Junk", 2)
click("Green BoE", 2)
check(Tip(100) == nil, "and a green loses it when its box is unticked")
click("Green BoE", 2)
check(Tip(999) == nil, "an item the game cannot tell the kind of gets none")
click("Seen in runs")
check(o.tipItems == false and greyed("Epic BoE", 2) and greyed("Quest items", 2) and not greyed("Epic BoE"),
      "with the line switched off altogether they are greyed out")
check(tip("Epic BoE", 2) == "Seen in runs is off.", "saying why")
check(Tip(100) == nil, "and no item has it")
click("Seen in runs")
check(Tip(100) ~= nil, "until it is switched on again")
db.drops[9001] = nil

print("-- where prices come from")
TEXTLOG = {}
ns.SyncOptions()
check(drew("No Auctionator or TradeSkillMaster: vendor prices."), "says when no addon gives auction prices")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return nil end } } }
TEXTLOG = {}
ns.SyncOptions()
local named = false
for _, t in ipairs(TEXTLOG) do named = named or t == "Auctionator" end
check(named, "and which one does")
Auctionator = nil

print("-- runs to keep")
for i = 1, 12 do
    table.insert(db.history, { players = {}, startedAt = NOW - i * 1000, endedAt = NOW - i * 1000 + 600,
                               name = "Run " .. i, pinned = (i == 12) or nil })
end
db.shared = { { players = {}, startedAt = NOW - 50, sharedBy = "Kett Longstride", name = "Theirs" },
              { players = {}, startedAt = NOW - 60, sharedBy = "Kett Longstride", name = "Theirs too" } }
TEXTLOG = {}
ns.SyncOptions()
check(drew("You have 12 runs (1 pinned) and 2 shared with you."), "the page says how many runs there are")
check(not drew("KB per run"), "and no longer guesses their size")
POPUPS = {}
type_in("maxHistory", "100")
check(o.maxHistory == 100 and #POPUPS == 0, "a number that deletes nothing is taken at once")
type_in("maxHistory", "10")
check(#POPUPS == 1 and POPUPS[1].which == "THATLUCKYBASTARD_KEEP_FEWER" and o.maxHistory == 100 and #db.history == 12
      and box("maxHistory"):GetText() == "100",
      "a number that would delete runs asks first, deletes nothing yet, and the box shows the number in force")
check(POPUPS[1].a == "10 runs" and POPUPS[1].b == "The oldest will be deleted now. Pinned runs stay.",
      "it says how many go (" .. tostring(POPUPS[1].b) .. ")")
StaticPopupDialogs.THATLUCKYBASTARD_KEEP_FEWER.OnAccept(nil, POPUPS[1].data)
local pinnedLeft = false
for _, s in ipairs(db.history) do
    if s.pinned then pinnedLeft = true end
end
check(o.maxHistory == 10 and #db.history == 11 and pinnedLeft and box("maxHistory"):GetText() == "10",
      "yes deletes them at once; the pinned run stays (" .. #db.history .. " runs)")
POPUPS = {}
type_in("maxHistory", "30")
check(o.maxHistory == 30 and #POPUPS == 0, "raising it again asks nothing")
type_in("maxHistory", "123456")
check(o.maxHistory == 99999 and #POPUPS == 0, "and as high as 99999")
type_in("maxHistory", "30")

print("-- defaults button")
open("Breakdown")
o.portrait, o.scale, o.minimapAngle, o.cats.junk, o.ticker = "none", 1.3, 100, false, false
db.theme = "classic"
POPUPS = {}
local defaults = button("Defaults")
defaults.tpl.__scripts.OnClick(defaults.tpl)
check(#POPUPS == 1 and POPUPS[1].which == "THATLUCKYBASTARD_DEFAULTS" and o.portrait == "none",
      "Defaults asks first")
local dialog = StaticPopupDialogs.THATLUCKYBASTARD_DEFAULTS
check(dialog.button1 == "Every page" and dialog.button3 == "This page", "every page, or this one")
dialog.OnAlt()
check(o.portrait == "2d" and o.scale == 1.3 and o.cats.junk == false and o.ticker == false and db.theme == "classic",
      "This page puts back the page on show alone: Breakdown's picture, not the size, the loot or the theme")
dialog.OnAccept()
check(o.portrait == "2d" and o.scale == 1 and o.cats.junk == true and o.ticker == true and db.theme == "modern",
      "Every page puts everything back")
check(o.maxHistory == 30 and o.minimapAngle == 100 and #db.history == 11,
      "but keeps the number of runs to keep, the minimap button's place and every run")
open("Look")
o.scale = 1.3
db.theme = "receipt"
dialog.OnAlt()
check(o.scale == 1 and db.theme == "modern", "on Look, This page puts back the theme and the size")

print("-- the meter beside its page")
local meter = ThatLuckyBastardMeterFrame
meter:Hide()
open("Meter")
check(meter:IsShown(), "on the Meter page the meter opens, to see what changes")
open("Loot")
check(not meter:IsShown(), "and shuts again as the page is left")
open("Meter")
ns.ToggleOptions()
check(not meter:IsShown(), "or as the options close")
ns.ToggleOptions()
check(meter:IsShown(), "opening them again on that page opens it again")
open("Look")
meter:Show()
open("Meter")
open("Look")
check(meter:IsShown(), "a meter that was open stays open")
meter:Hide()

print("-- replay")
open("End of run")
local replay = button("Replay")
local realShow, shown = ns.ShowWindow, nil
ns.ShowWindow = function(ceremony, s) shown = { ceremony, s } end
local viewed = ns.ViewedRun()
replay.tpl.__scripts.OnClick(replay.tpl)
ns.ShowWindow = realShow
check(viewed and shown and shown[1] == true and shown[2] == viewed, "Replay plays the reveal again for the run on show")
TIP = {}
replay.flat.__scripts.OnEnter(replay.flat)
check(TIP[1] == "The reveal again, for the run on show. Same as /tlb race.", "as its tooltip says")

print("-- size")
o.scale = 1.25
ns.Rerender()
check(ThatLuckyBastardFrame:GetScale() == 1.25 and ThatLuckyBastardBrowseFrame:GetScale() == 1.25
      and ThatLuckyBastardPaperFrame:GetScale() == 1.25
      and ThatLuckyBastardShareFrame:GetScale() == 1.25, "Size scales every window")
check(ThatLuckyBastardOptionsFrame:GetScale() == 1, "but the options, whose slider would move under the mouse")
o.scale = 1
ns.Rerender()

print("-- loot bingo is gone")
check(button("Bingo") == nil and not pcall(control, "Loot bingo") and o.bingo == nil,
      "no Bingo button, and no option for it")
check(ThatLuckyBastardBingoFrame == nil and ns.ToggleBingo == nil and ns.BingoCheck == nil, "nor its window")
local printed = {}
local realPrint = print
print = function(text) printed[#printed + 1] = tostring(text) end
SlashCmdList.THATLUCKYBASTARD("bingo")
print = realPrint
local helpShown, bingoInHelp = false, false
for _, line in ipairs(printed) do
    if line:find("/tlb meter", 1, true) then helpShown = true end
    if line:lower():find("bingo", 1, true) then bingoInHelp = true end
end
check(helpShown and not bingoInHelp, "/tlb bingo shows the help, which no longer mentions it")

ns.ToggleOptions()
check(not ThatLuckyBastardOptionsFrame:IsShown(), "a second toggle closes the options")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (options)")
