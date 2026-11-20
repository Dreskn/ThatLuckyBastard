-- The options panel: its pages, the choices that stand for two saved
-- switches, what is greyed out when it does nothing, the runs to keep,
-- the Defaults button, the size of the windows and the Bingo button.
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

-- An option of the panel, by its label; the `nth` one with that label
-- (the first unless said: the loot categories are also the kinds of item
-- a tooltip line is for).
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
-- A frame whose text is `label`: a page of the panel, for one.
local function has(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == label then return true end
    end
    return false
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
local pagesFound = true
for _, name in ipairs({ "Window", "Players", "Loot", "End of run", "While you play", "Share", "General" }) do
    pagesFound = pagesFound and has(name)
end
check(pagesFound, "seven pages: Window, Players, Loot, End of run, While you play, Share, General")
check(not has("Appearance") and not has("Behaviour") and not has("Extras") and not has("Items and values"),
      "the old pages are gone")
for _, label in ipairs({
    "Modern", "Classic", "One column per player, up to 5", "Always a list", "Group items by category",
    "Line up the same item across columns", "Picture", "Award", "Gold", "Item icons", "Each share, and its gap to an equal split", "Share bar",
    "Run total and equal split", "Run time, records and averages", "12g 34s 56c", "12g 34s", "12g",
    "2D portrait", "3D model", "Class icon", "None", "As the game shows them", "Full name", "First name only",
    "Podium (top looter in the middle)", "Loot value", "Role (tank, healer, damage)", "Put me first",
    "Auction price, vendor when there is none", "Vendor price only", "Historical auction prices",
    "Current auction prices", "Vendor totals too", "Epic BoE", "Quest items",
    "Hidden ones still count in totals", "The breakdown", "Race",
    "Hand out awards (Ninja, Jackpot and more)", "Sounds", "Screenshot at the end",
    "Streak recap after back-to-back runs", "A line in my chat window (only I see it)",
    "1g", "5g", "25g", "100g", "Off", "Someone I've run with joins my group", "Players: our runs together",
    "Items: seen in my runs", "Loot bingo", "Track raids too", "Ask if it's a new run", "Always a new run",
    "10", "30", "100", "300", "Unlimited", "Minimap button",
}) do
    control(label) -- errors if missing
end
check(true, "every option is there under its new name")
check(ticked("The breakdown") and ticked("Race") and ticked("5g") and ticked("12g 34s") and ticked("Ask if it's a new run")
      and ticked("2D portrait") and ticked("Podium (top looter in the middle)") and ticked("300"),
      "the defaults are ticked")

print("-- the end of a run")
check(not has("The breakdown and the podium") and not has("The podium") and o.podiumOnLeave == nil,
      "the podium window's choices are gone")
click("The breakdown")
check(o.popupLeave == false and not greyed("Race") and not greyed("Sounds"),
      "the breakdown can stay shut: the reveal waits for the first time it is opened")
click("The breakdown")
click("Race")
check(o.race == false and o.popupLeave and not greyed("Sounds"), "without the race, the awards are revealed one by one")
click("Hand out awards (Ninja, Jackpot and more)")
check(not o.showAwards and greyed("Sounds") and greyed("Screenshot at the end"),
      "and without awards either, nothing is: the sound and the screenshot are greyed out")
click("Race")
check(o.race and not greyed("Sounds"), "the race alone is a reveal")
click("Hand out awards (Ninja, Jackpot and more)")

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

click("12g")
check(not o.showSilver and not o.showCopper and ns.MoneyPlain(123456) == "12g", "12g: gold only")
click("12g 34s 56c")
check(o.showSilver and o.showCopper and ns.MoneyPlain(123456) == "12g 34s 56c" and not ticked("12g"),
      "12g 34s 56c: all three (" .. ns.MoneyPlain(123456) .. ")")
click("12g 34s")

click("Off")
check(o.ticker == false and ticked("Off") and not ticked("5g"), "the loot notice can be switched off")
click("25g")
check(o.ticker and o.tickerMin == 250000 and not ticked("Off"), "picking an amount switches it on at that amount")
click("5g")

print("-- greyed out when it does nothing")
check(not greyed("Line up the same item across columns"), "lining items up works in the column view")
click("Always a list")
check(o.useColumns == false and greyed("Line up the same item across columns"), "but not in the list")
check(greyed("Race"), "nor does the race, which the columns run")
click("One column per player, up to 5")
check(not greyed("Race"), "which is back with them")
check(not greyed("Share bar"), "the share bar works in Modern")
click("Classic")
check(db.theme == "classic" and greyed("Share bar"), "but not in Classic")
click("Modern")
check(greyed("Put me first"), "putting me first does nothing in podium order")
click("Loot value")
check(o.sortPlayers == "value" and not greyed("Put me first"), "it works in any other")
check(greyed("Race"), "where there is no podium to race for")
click("Podium (top looter in the middle)")
click("Vendor price only")
check(o.valueMode == "vendor" and greyed("Vendor totals too"), "vendor totals mean nothing with vendor prices only")
check(greyed("Historical auction prices") and greyed("Current auction prices"), "nor does the day of an auction price")
click("Auction price, vendor when there is none")
check(o.priceTime == "then" and not greyed("Current auction prices"), "auction prices are the recorded ones unless chosen otherwise")
click("Current auction prices")
check(o.priceTime == "now", "current prices can be chosen")
click("Historical auction prices")
check(o.priceTime == "then", "and historical ones again")
check(greyed("Hidden ones still count in totals"), "with every category shown, nothing is hidden to count")
click("Junk")
check(o.cats.junk == false and not greyed("Hidden ones still count in totals"), "unticking one makes it count")
click("Junk")

print("-- the kinds of item with a tooltip line")
local kinds = { "Epic BoE", "Blue BoE", "Green BoE", "Bind on Pickup", "Profession materials", "Other", "Junk",
                "Quest items" }
local on, off = {}, {}
for _, label in ipairs(kinds) do
    local list = ticked(label, 2) and on or off
    list[#list + 1] = label
end
check(table.concat(on, ", ") == "Epic BoE, Blue BoE, Green BoE, Bind on Pickup"
      and table.concat(off, ", ") == "Profession materials, Other, Junk, Quest items",
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
check(#TIP <= 1 and Tip(100) ~= nil and Tip(100):find("Seen in 2 runs", 1, true) ~= nil and Tip(103) == nil,
      "a green has its line; junk has none (" .. tostring(Tip(100)) .. ")")
click("Junk", 2)
check(Tip(103) ~= nil and Tip(103):find("Seen in 5 runs", 1, true) ~= nil, "junk has it once its box is ticked")
click("Junk", 2)
click("Green BoE", 2)
check(Tip(100) == nil, "and a green loses it when its box is unticked")
click("Green BoE", 2)
check(Tip(999) == nil, "an item the game cannot tell the kind of gets none")
click("Items: seen in my runs")
check(o.tipItems == false and greyed("Epic BoE", 2) and greyed("Quest items", 2) and not greyed("Epic BoE"),
      "with the line switched off altogether they are greyed out")
check(Tip(100) == nil, "and no item has it")
click("Items: seen in my runs")
check(Tip(100) ~= nil, "until it is switched on again")
db.drops[9001] = nil

print("-- where prices come from")
TEXTLOG = {}
ns.SyncOptions()
check(drew("No Auctionator or TradeSkillMaster: vendor prices are used."), "says when no addon gives auction prices")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return nil end } } }
TEXTLOG = {}
ns.SyncOptions()
check(drew("Auction prices from Auctionator. Right-click an item"), "and which one does")
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
POPUPS = {}
click("100")
check(o.maxHistory == 100 and #POPUPS == 0, "a number that deletes nothing is taken at once")
click("10")
check(#POPUPS == 1 and POPUPS[1].which == "THATLUCKYBASTARD_KEEP_FEWER" and o.maxHistory == 100 and #db.history == 12,
      "a number that would delete runs asks first, and deletes nothing yet")
check(POPUPS[1].a == "10" and POPUPS[1].b == "The 1 oldest will be deleted now. Pinned runs stay.",
      "it says how many go (" .. tostring(POPUPS[1].b) .. ")")
StaticPopupDialogs.THATLUCKYBASTARD_KEEP_FEWER.OnAccept(nil, POPUPS[1].data)
local pinnedLeft = false
for _, s in ipairs(db.history) do
    if s.pinned then pinnedLeft = true end
end
check(o.maxHistory == 10 and #db.history == 11 and pinnedLeft and ticked("10"),
      "yes deletes them at once; the pinned run stays (" .. #db.history .. " runs)")
POPUPS = {}
click("30")
check(o.maxHistory == 30 and #POPUPS == 0, "raising it again asks nothing")

print("-- defaults button")
o.portrait, o.scale, o.minimapAngle, o.cats.junk, o.ticker = "none", 1.3, 100, false, false
db.theme = "classic"
POPUPS = {}
local defaults = button("Defaults")
defaults.tpl.__scripts.OnClick(defaults.tpl)
check(#POPUPS == 1 and POPUPS[1].which == "THATLUCKYBASTARD_DEFAULTS" and o.portrait == "none",
      "Defaults asks first")
StaticPopupDialogs.THATLUCKYBASTARD_DEFAULTS.OnAccept()
check(o.portrait == "2d" and o.scale == 1 and o.cats.junk == true and o.ticker == true and db.theme == "modern",
      "then puts the options back")
check(o.maxHistory == 30 and o.minimapAngle == 100 and #db.history == 11,
      "but keeps the number of runs to keep, the minimap button's place and every run")

print("-- size")
o.scale = 1.25
ns.Rerender()
check(ThatLuckyBastardFrame:GetScale() == 1.25 and ThatLuckyBastardBrowseFrame:GetScale() == 1.25
      and ThatLuckyBastardBingoFrame:GetScale() == 1.25 and ThatLuckyBastardPaperFrame:GetScale() == 1.25
      and ThatLuckyBastardShareFrame:GetScale() == 1.25, "Size scales every window")
check(ThatLuckyBastardOptionsFrame:GetScale() == 1, "but the options, whose slider would move under the mouse")
o.scale = 1
ns.Rerender()

print("-- bingo button")
local bingo = button("Bingo")
check(bingo and bingo:IsShown(), "the main window has a Bingo button")
click("Loot bingo")
check(o.bingo == false and not bingo:IsShown(), "it goes while bingo is off")
click("Loot bingo")
check(o.bingo and bingo:IsShown(), "and comes back")

ns.ToggleOptions()
check(not ThatLuckyBastardOptionsFrame:IsShown(), "a second toggle closes the options")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (options)")
