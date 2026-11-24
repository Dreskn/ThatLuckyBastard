-- Ignore and Split per copies (0.8.1). Ignore covers the copies there
-- when it was set: all of them with the box, or how many of a stack with
-- - and + in the item menu. A split covers the copies there when it was
-- made. Copies looted later follow the general rule. Ignored copies count
-- for nothing: no value, no item count, no award, no drop.
print("\n==== ignore and split per copies ====")
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

local PRICES = {}
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
    return PRICES[tonumber(link:match("item:(%d+)"))]
end } } }

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB
local o = db.options
o.ticker, o.streak, o.popupLeave, o.race = false, false, false, false
local ME, BRYN, COLE = WORLD.me, "Bryn Ash", "Cole Dart"

ITEMS[501] = { 2, 0, 7, 0 }     -- a green trade good, sold at auction only
ITEMS[502] = { 3, 20000, 4, 2 } -- a blue BoE
ITEMS[503] = { 4, 0, 7, 0 }     -- an epic trade good
PRICES[501], PRICES[502], PRICES[503] = 10000, 30000, 500000
local essence = ItemLink(501, "Glowing Essence", 2)
local cloak = ItemLink(502, "Blue Cloak", 3)
local crystal = ItemLink(503, "Big Crystal", 4)

WORLD.party = { { BRYN, "WARRIOR", "TANK" }, { COLE, "MAGE", "DAMAGER" } }
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9101, "Copy Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
local run = db.active
Loot(("You receive loot: %sx%d."):format(essence, 7))
Loot(("%s receives loot: %s."):format(BRYN, cloak))
Loot(("%s receives loot: %s."):format(COLE, crystal))
RunTimers()

local function Plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|r", "")) end
local function P(name, sum)
    for _, p in ipairs((sum or ns.Summarize(run)).players) do
        if p.name == name then return p end
    end
end
local function Entries(name, link)
    local list = {}
    for key, e in pairs(run.players[name].items) do
        if e.link == link then list[#list + 1] = { key = key, e = e } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end
local ess = Entries(ME, essence)[1].e
local menu = ThatLuckyBastardItemMenu
-- A control of the menu, by the words on it.
local function Button(words)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if rawget(w, "onClick") ~= nil and type(t) == "table" and w:IsShown() and Plain(t.__text) == words then
            return w
        end
    end
end
local function Shown(words)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and w:IsShown() and w:GetParent() and Plain(t.__text) == words then return true end
    end
    return false
end
local function Click(words)
    local b = Button(words)
    if b then b.__scripts.OnClick(b, "LeftButton") return true end
    return false
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if Plain(t):find(text, 1, true) then return true end
    end
    return false
end

print("==== a stack: how many are ignored ====")
check(ess.count == 7 and P(ME).market == 70000 and P(ME).count == 7, "seven essences, worth 1g each")
ns.ShowRun(run)
ns.ShowItemMenu(run, ess)
check(menu:IsShown() and Shown("0/7") and Button("+") ~= nil and Button("-") == nil,
      "the menu counts the ignored ones: none yet, so - does nothing")
for _ = 1, 4 do Click("+") end
check(ess.ignored == 4 and Shown("4/7"), "+ four times: four ignored")
check(P(ME).market == 30000 and P(ME).count == 3, "only the three others count, in value and in the item count")
Click("-")
check(ess.ignored == 3 and Shown("3/7"), "- takes one back")
Click("+")
TEXTLOG = {}
ns.Rerender()
RunTimers()
local note
for _, w in ipairs(FRAMES) do
    local line = rawget(w, "line")
    if type(line) == "table" and line.e and ns.RealEntry(line.e) == ess and w:IsShown() then note = line.note end
end
check(note and note:find("4 of 7 ignored.", 1, true), "its line says how many are ignored")

print("==== later copies follow the general rule ====")
Loot(("You receive loot: %sx%d."):format(essence, 2))
check(ess.count == 9 and ess.ignored == 4 and P(ME).market == 50000, "two more essences: counted, the four stay ignored")
Click("Ignore")
check(ess.ignored == true and P(ME).market == 0 and P(ME).count == 0 and #P(ME).all.items == 1,
      "the box ignores every copy: listed, worth nothing, out of the item count")
Loot(("You receive loot: %s."):format(essence))
check(ess.count == 10 and ess.ignored == 9 and P(ME).market == 10000, "one more: it counts, the nine stay ignored")
ns.ShowItemMenu(run, ess)
check(Shown("9/10") and not (Button("Ignore") and Button("Ignore").tick.__shown), "not every copy: the box is clear")
Click("Ignore")
check(ess.ignored == true, "the box again: every copy")
Click("Ignore")
check(ess.ignored == nil and P(ME).market == 100000, "and once more: none")
menu:Hide()

print("==== ignored copies count for nothing ====")
local cry = Entries(COLE, crystal)[1].e
check(P(COLE).bestQuality == 4 and P(COLE).count == 1, "Cole's crystal is an epic")
ns.SetIgnored(cry, 1)
check(cry.ignored == true and P(COLE).bestQuality == 0 and P(COLE).count == 0 and P(COLE).market == 0,
      "ignored, it is no best quality and no item")
TEXTLOG = {}
ns.Rerender()
RunTimers()
check(not drew("No loot seen") and drew("ignored"), "Cole's column lists it as ignored, not as no loot")
local awards = ns.Awards(run, ns.Summarize(run))
check(awards[COLE] == nil or awards[COLE].key ~= "purple", "no Purple Rain for an ignored epic")
ns.SetIgnored(cry, 0)

print("==== a split covers the copies already there ====")
local cl = Entries(BRYN, cloak)[1].e
ns.SetSplit(run, cl, BRYN, { BRYN, COLE })
check(P(BRYN).market == 15000 and P(COLE).market == 515000, "the cloak split in two")
Loot(("%s receives loot: %s."):format(BRYN, cloak))
local cloaks = Entries(BRYN, cloak)
check(#cloaks == 2 and cloaks[1].e == cl and cl.count == 1 and cloaks[2].e.split == nil and cloaks[2].e.count == 1,
      "a second cloak is filed apart, not split")
check(P(BRYN).market == 45000 and P(COLE).market == 515000, "and counts whole for Bryn")
Loot(("%s receives loot: %s."):format(BRYN, cloak))
cloaks = Entries(BRYN, cloak)
check(#cloaks == 2 and cloaks[2].e.count == 2, "a third joins the second")

print("==== saved and shared ====")
ns.SetIgnored(ess, 4)
check(ess.ignored == 4, "four essences ignored again")
local code = ns.EncodeRun(run)
local back = ns.DecodeRun(code)
local bess
for _, e in pairs(back and back.players[ME].items or {}) do
    if e.count == 10 then bess = e end
end
check(bess and bess.ignored == 4, "a share code carries how many are ignored")
-- In a field of its own after the split, the 0.7.0 field left empty, so 0.8.0 reads past it.
local fields
for chunk in code:gmatch("[^,!]+") do
    local f = {}
    for part in (chunk .. "."):gmatch("(.-)%.") do f[#f + 1] = part end
    if #f == 12 and f[10] == "" and f[12] ~= "" then fields = f end
end
check(fields ~= nil, "in a twelfth field, the old one left empty")

-- A code saying every copy, or none, is ignored that way is refused.
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
local function WithCopies(n)
    local chunk = table.concat(fields, ".")
    local f = { unpack(fields) }
    f[12] = N(n)
    local i, j = body:find(chunk, 1, true)
    return Signed(body:sub(1, i - 1) .. table.concat(f, ".") .. body:sub(j + 1))
end
check(ns.DecodeRun(WithCopies(9)) ~= nil, "nine of ten reads")
check(ns.DecodeRun(WithCopies(10)) == nil and ns.DecodeRun(WithCopies(0)) == nil, "ten of ten, or none, is refused")

WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
RunTimers()
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false)
check(db.history[1] == run and run.recorded, "the run is closed")
local drops = db.drops[9101]
check(drops and drops["501"] and drops["501"].c == 6, "its drops count the six essences not ignored")
Reload()
local record
for _, v in ipairs(SAVED.history) do
    if v.c and v.c:find("Copy Keep", 1, true) then record = v end
end
check(record ~= nil and record.players == nil, "the run is saved packed, as one code")
local loaded = ThatLuckyBastardDB.history[1]
local lcount
for _, e in pairs(loaded.players[ME].items) do
    if e.count == 10 then lcount = e.ignored end
end
check(lcount == 4, "and comes back with four of ten essences ignored")

print("==== enchanting materials are ignored as they are looted ====")
local db2 = ThatLuckyBastardDB
ITEMS[504] = { 2, 0, 7, 0, 12 } -- a green essence: Trade Goods, Enchanting
ITEMS[505] = { 3, 0, 7, 0, 12 } -- a blue shard
PRICES[504], PRICES[505] = 40000, 90000
local odd, shard = ItemLink(504, "Odd Essence", 2), ItemLink(505, "Odd Shard", 3)
NOW = NOW + 4000
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9102, "Dust Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
run = db2.active
check(run and run.bet and run.bet.offered and not run.bet.closed, "a new run: calls are open")
ThatLuckyBastardFrame:Hide()
TEXTLOG = {}
db2.options.ticker, db2.options.tickerMin = true, 10000
Loot(("You receive loot: %sx%d."):format(odd, 3))
Loot(("%s receives loot: %s."):format(BRYN, shard))
RunTimers()
local mine, bryns = Entries(ME, odd)[1].e, Entries(BRYN, shard)[1].e
check(mine.ignored == true and bryns.ignored == true, "three essences of mine and a shard of Bryn's: ignored as they come")
check(P(ME).market == 0 and P(ME).count == 0 and P(BRYN).market == 0 and P(BRYN).bestQuality == 0,
      "worth nothing, no item, no best quality")
check(not run.bet.closed, "they close no calls")
check(not drew("Odd Shard"), "and get no loot notice")
ns.ShowRun(run)
TEXTLOG = {}
ns.Rerender()
RunTimers()
local why
for _, w in ipairs(FRAMES) do
    local line = rawget(w, "line")
    if type(line) == "table" and line.e and ns.RealEntry(line.e) == bryns and w:IsShown() then why = line.note end
end
check(why == "Ignored: most come from disenchanting.", "its line says why")
ns.ShowItemMenu(run, mine)
check(Shown("3/3") and Button("Ignore").tick.__shown, "the menu: every copy ignored")
Click("-")
check(mine.ignored == 2 and P(ME).market == 40000, "one counted again, from a chest say")
Loot(("You receive loot: %s."):format(odd))
check(mine.count == 4 and mine.ignored == 3 and P(ME).market == 40000, "the next essence is ignored as it comes")
menu:Hide()
ThatLuckyBastardFrame:Hide()
TEXTLOG = {}
Loot(("You receive loot: %s."):format(essence))
RunTimers()
check(run.bet.closed, "a green that counts closes the calls")
check(drew("Glowing Essence"), "and gets its loot notice")
menu:Hide()

print("==== Reprice: today's prices put on a run ====")
local copy = db2.history[1]
check(copy and copy.name == "Copy Keep" and copy.recorded, "the run from before, closed")
local function Of(s, name, id)
    local list = {}
    for _, e in pairs(s.players[name].items) do
        if tonumber(e.link:match("item:(%d+)")) == id then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end
local function SumOf(s, name)
    for _, p in ipairs(ns.Summarize(s).players) do
        if p.name == name then return p end
    end
end
local function FootButton(words)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == words then return w, tpl end
    end
end
local cess, ccry = Of(copy, ME, 501)[1], Of(copy, COLE, 503)[1]
local ccloaks = Of(copy, BRYN, 502)
check(cess.ah == 10000 and cess.ignored == 4 and ccry.ah == 500000 and #ccloaks == 2 and ccloaks[1].split,
      "it has its prices of then, four essences ignored, a split cloak and one apart")
local statsBefore = db2.records[9101].sumGroup
PRICES[501], PRICES[502], PRICES[503] = 20000, nil, 600000
ns.ShowRun(copy)
local btn, tpl = FootButton("Reprice")
check(btn and btn:IsShown() and tpl:IsEnabled(), "Reprice is beside Delete, ready")
POPUPS = {}
tpl.__scripts.OnClick(tpl)
check(#POPUPS == 1 and POPUPS[1].which == "THATLUCKYBASTARD_REPRICE_RUN" and POPUPS[1].a:find("Copy Keep", 1, true),
      "it asks first, naming the run")
check(cess.ah == 10000, "nothing changes before the answer")
StaticPopupDialogs.THATLUCKYBASTARD_REPRICE_RUN.OnAccept()
check(cess.ah == 20000 and ccry.ah == 600000 and ccloaks[1].ah == 30000 and ccloaks[2].ah == 30000,
      "every item with a price today gets it; the cloak, with none, keeps its own")
check(cess.ignored == 4 and ccloaks[1].split and #ccloaks[1].split == 2, "Ignore and Split stay")
check(SumOf(copy, ME).market == 120000 and copy.pricedAt ~= nil, "the six counted essences are worth 2g each now")
check(db2.records[9101].sumGroup == statsBefore, "statistics keep what the run added")
ns.ShowAnalysis("numbers", copy)
RunTimers()
check(drew("Repriced on " .. ns.DateText(copy.pricedAt) .. "."), "Analysis › Numbers says when it was repriced")

local gift = { name = "Gift Keep", startedAt = NOW - 5000, endedAt = NOW - 4000, sharedBy = "Kind Soul",
               players = { ["Kind Soul"] = { items = { g = { link = essence, count = 1, vendor = 0, ah = 10000,
                                                             cat = "prof", quality = 2, resolved = true } } } } }
table.insert(db2.shared, 1, gift)
check(not ns.CanReprice(gift), "a run shared with you keeps its owner's prices")
table.remove(db2.shared, 1)
Auctionator = nil
ns.ShowRun(copy)
check(not tpl:IsEnabled() and not ns.CanReprice(copy), "with no price addon, Reprice is greyed out")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
    return PRICES[tonumber(link:match("item:(%d+)"))]
end } } }
Reload()
local again = ThatLuckyBastardDB.history[1]
local aess = again and Of(again, ME, 501)[1]
check(again and again.name == "Copy Keep" and aess.ah == 20000 and aess.ignored == 4 and again.pricedAt == copy.pricedAt,
      "saved: the new prices, and when")
