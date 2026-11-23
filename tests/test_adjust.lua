-- The item menu: a right-click on an item opens it. Its price, Ignore (the
-- item stays listed, worth nothing) and Split with (its value shared
-- equally by the players ticked, its looter among them or not). Copies
-- picked up and roll wins stay with the looter; value, Need value
-- included, goes with the shares. The marks are saved and shared.
print("\n==== ignore and split ====")
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
o.ticker, o.streak, o.popupLeave, o.race = false, false, false, false
local H = "|HlootHistory:%d|h[Loot]|h: "
local ME, BRYN, COLE = WORLD.me, "Bryn Ash", "Cole Dart"

ITEMS[401] = { 3, 50000, 4, 1 } -- a blue, bound on pickup: 5g at the vendor, no auction price
ITEMS[402] = { 2, 10000, 4, 1 } -- a green, bound on pickup: 1g
local swordLink, gemLink = ItemLink(401, "Sword", 3), ItemLink(402, "Gem", 2)

WORLD.party = { { BRYN, "WARRIOR", "TANK" }, { COLE, "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9001, "Test Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
local run = db.active
Loot((H .. "%s has selected Need for: %s"):format(7, BRYN, swordLink))
Loot((H .. "%s won: %s"):format(7, BRYN, swordLink))
Loot(("%s receives loot: %s."):format(BRYN, swordLink))
Loot(("You receive loot: %s."):format(gemLink))
RunTimers()
local sword = select(2, next(run.players[BRYN].items))
local gem = select(2, next(run.players[ME].items))
check(sword and sword.need == 1 and gem, "a run: Bryn won the sword on Need, I picked up a gem")

local function Plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Sum() return ns.Summarize(run) end
local function P(name, sum)
    for _, p in ipairs((sum or Sum()).players) do
        if p.name == name then return p end
    end
end
local menu = ThatLuckyBastardItemMenu
-- A control of the menu, by the words on it.
local function Button(words)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "onClick") and type(t) == "table" and w:IsShown() and Plain(t.__text):find(words, 1, true) then
            return w
        end
    end
end
local function Click(words)
    local b = Button(words)
    if b and b:IsEnabled() then b.__scripts.OnClick(b, "LeftButton") return true end
    return false
end
local function Ticked(words)
    local b = Button(words)
    return b ~= nil and b.tick.__shown == true
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end

print("==== a right-click opens the menu ====")
ns.ShowRun(run)
RunTimers()
local swordRow
for _, w in ipairs(FRAMES) do
    local line = rawget(w, "line")
    if type(line) == "table" and line.e == sword and w.__scripts.OnClick and w:IsShown() then swordRow = w end
end
check(swordRow ~= nil, "the sword has a row in the window")
TIP = {}
if swordRow then swordRow.__scripts.OnEnter(swordRow) end
local hinted = false
for _, line in ipairs(TIP) do
    if line:find("Right-click: price, ignore, split", 1, true) then hinted = true end
end
check(hinted, "its tooltip says what a right-click does")
if swordRow then swordRow.__scripts.OnClick(swordRow, "RightButton") end
check(menu:IsShown() and Plain(menu.__text or "") == "" and Button("Ignore") ~= nil, "a right-click opens its menu")
check(Button("Auction price") and not Button("Auction price"):IsEnabled() and Ticked("Vendor price"),
      "no auction price for a bound item: Vendor price, and Auction price greyed out")
check(Button("Everyone") == nil and Button("Split with...") ~= nil, "the players to split with wait behind Split with")

print("==== ignore ====")
local before = Sum()
Click("Ignore")
local sum = Sum()
check(sword.ignored == true and Ticked("Ignore"), "Ignore ticks, and marks the item")
check(P(BRYN, sum).market == 0 and sum.market == before.market - 50000, "an ignored item is worth nothing")
check(P(BRYN, sum).count == 1 and #P(BRYN, sum).cats.bop.items == 1, "but stays listed, and picked up")
check(P(BRYN, sum).needWins == 1 and P(BRYN, sum).needValue == 0, "its roll stays won, at no value")
TEXTLOG = {}
ns.Refresh()
RunTimers()
check(drew("ignored"), "the window says it is ignored")
Click("Ignore")
check(sword.ignored == nil and P(BRYN).market == 50000, "a second click counts it again")

print("==== split ====")
Click("Split with...")
check(Button("Everyone") and Button("Not split") and Ticked("Bryn") and not Ticked("Cole"),
      "the players are listed, the looter alone ticked")
Click("Cole")
sum = Sum()
local bryn, cole, me = P(BRYN, sum), P(COLE, sum), P(ME, sum)
check(sword.split and #sword.split == 2, "ticking Cole splits it two ways")
check(bryn.market == 25000 and cole.market == 25000 and sum.market == before.market,
      "each holds half its value; the run's total stays the same")
check(bryn.count == 1 and cole.count == 0, "the copy picked up stays Bryn's")
check(bryn.needWins == 1 and cole.needWins == 0 and bryn.needValue == 25000 and cole.needValue == 25000,
      "the Need win stays Bryn's, its value goes with the shares")
check(#cole.cats.bop.items == 1 and cole.cats.bop.items[1].from == BRYN, "the sword is listed under Cole too")
TEXTLOG = {}
ns.Refresh()
RunTimers()
check(drew("1/2"), "each share says it is a half")

o.alignItems = true
ns.Refresh()
RunTimers()
local rowsOf = {}
for _, w in ipairs(FRAMES) do
    local line = rawget(w, "line")
    if type(line) == "table" and line.e and ns.RealEntry(line.e) == sword and w:IsShown() then
        rowsOf[#rowsOf + 1] = w.__points[1] and w.__points[1][3]
    end
end
check(#rowsOf == 2 and rowsOf[1] == rowsOf[2], "with items lined up, both shares sit on one row")
o.alignItems = false

Click("Everyone")
sum = Sum()
check(#sword.split == 3 and math.abs(P(ME, sum).market - (10000 + 50000 / 3)) < 0.01, "Everyone: three ways")
Click("Bryn")
sum = Sum()
bryn = P(BRYN, sum)
check(#sword.split == 2 and bryn.market == 0 and bryn.count == 1 and P(COLE, sum).market == 25000,
      "unticking its looter gives it to the others")
local away
for _, e in ipairs(bryn.all.items) do
    if ns.RealEntry(e) == sword then away = e end
end
check(away and away.away, "and it stays listed under its looter, as given")
Click("Me") -- no such player: nothing happens
Click("Not split")
check(sword.split == nil and P(BRYN).market == 50000, "Not split: back to its looter")
Click("Cole")
Click("Cole")
check(sword.split == nil, "ticking and unticking a player again: not split")

print("==== Need only ====")
Click("Cole")
local needOnly = ns.Summarize(run, true)
check(P(BRYN, needOnly).market == 25000 and P(COLE, needOnly).market == 25000 and P(ME, needOnly).market == 0,
      "Need only splits the Need wins the same way")

print("==== the CSV adds up ====")
local csv = ns.ExportRun(run)
local totals = {}
for line in csv:gmatch("[^\n]+") do
    local f = {}
    for field in (line .. ","):gmatch("([^,]*),") do f[#f + 1] = field end
    local value = tonumber(f[10])
    if value then totals[f[3]] = (totals[f[3]] or 0) + value end
end
sum = Sum()
local adds = true
for _, p in ipairs(sum.players) do
    if math.abs((totals[p.name] or 0) - p.market / 10000) > 0.001 then adds = false end
end
check(adds, "each player's lines add up to their total, shares included")
check(csv:find("Split 2 ways", 1, true) ~= nil, "a share says it is one")

print("==== saved and shared ====")
gem.ignored = true
local code = ns.EncodeRun(run)
local back = ns.DecodeRun(code)
local bsword = back and select(2, next(back.players[BRYN].items))
local bgem = back and select(2, next(back.players[ME].items))
check(bsword and bsword.split and #bsword.split == 2 and bgem and bgem.ignored == true and bsword.ignored == nil,
      "a share code carries ignored items and splits")

-- A code whose split names one player twice is refused.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local function N(n)
    local out = ""
    repeat
        local d = n % 64
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = (n - d) / 64
    until n == 0
    return out
end
local function Signed(body)
    local h = 0
    for i = 1, #body do h = (h * 31 + body:byte(i)) % 16777213 end
    return body .. "!" .. N(h)
end
local body = code:match("^(.*)!")
local sections = {}
for part in (body .. "!"):gmatch("(.-)!") do sections[#sections + 1] = part end
local players = sections[5] -- after "TLB1"
local twice = players:gsub("%.([%w+/]+)'([%w+/]+)", ".%1'%1", 1)
sections[5] = twice
local bad = ns.DecodeRun(Signed(table.concat(sections, "!")))
check(twice ~= players and bad == nil, "a split naming a player twice is refused")

WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
RunTimers()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false)
check(db.history[1] == run and run.recorded, "the run is closed")
local recorded = db.records[9001].sumGroup
sword.ignored = true
check(db.records[9001].sumGroup == recorded, "statistics keep what they counted at closing")
sword.ignored = nil
Reload()
local record
for _, v in ipairs(SAVED.history) do
    if v.c and v.c:find("Test Keep", 1, true) then record = v end
end
check(record ~= nil and record.players == nil, "the run is saved packed, as one code")
local loaded = db.history[1]
local lsword = select(2, next(loaded.players[BRYN].items))
local lgem = select(2, next(loaded.players[ME].items))
check(lsword.split and #lsword.split == 2 and lgem.ignored == true, "and comes back with its marks")
run = loaded
check(P(COLE).market == 25000 and P(ME).market == 0, "worth the same after a reload")

print("==== the menu goes with the window ====")
ns.ShowRun(loaded)
ns.ShowItemMenu(loaded, lsword)
check(menu:IsShown() and Ticked("Cole") and Ticked("Bryn"), "opened on a split item, its players are listed")
ThatLuckyBastardFrame:Hide()
ns.Rerender()
check(not menu:IsShown(), "it closes when the run window does")
