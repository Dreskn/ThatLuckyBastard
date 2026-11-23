-- Finished runs in the saved file: packed as one code each when the game
-- saves, unpacked when it loads. Every check here goes through a real
-- save and reload (Reload, in the harness), and compares runs with an
-- idea of "the same run" of this file's own.
print("\n==== storage: runs packed in the saved file ====")
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = ThatLuckyBastardDB

----------------------------------------------------------------------
-- "The same run", worked out here and not by the addon.
----------------------------------------------------------------------
local function Clone(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in next, v do out[k] = Clone(x) end
    return out
end
-- An item's link as it is filed: without the looter's level and
-- specialisation (the 9th and 10th fields after the id), nor the colons
-- at the end of its item string.
local function Filed(link)
    return (link:gsub("|H(item:[^|]*)|h", function(str)
        local fields = {}
        for f in (str .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
        if #fields >= 11 then fields[10], fields[11] = "", "" end
        return "|H" .. table.concat(fields, ":"):gsub(":+$", "") .. "|h"
    end, 1))
end
-- A run without what is never saved, its items in a fixed order.
local function Essence(run)
    local out = Clone(run)
    for _, p in pairs(out.players) do
        p.joined = nil
        local list = {}
        for _, e in pairs(p.items) do
            e.lastAt, e.noAH, e.now = nil, nil, nil
            e.link = Filed(e.link)
            list[#list + 1] = e
        end
        table.sort(list, function(a, b)
            if (a.id or 0) ~= (b.id or 0) then return (a.id or 0) < (b.id or 0) end
            return a.link < b.link
        end)
        p.items = list
    end
    return out
end
-- The first difference between two values, or nil.
local function Differ(a, b, path)
    if type(a) ~= type(b) then return path .. ": " .. type(a) .. " against " .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return path .. ": " .. tostring(a):sub(1, 30) .. " against " .. tostring(b):sub(1, 30) end
        return
    end
    for k, v in pairs(a) do
        local d = Differ(v, b[k], path .. "." .. tostring(k))
        if d then return d end
    end
    for k in pairs(b) do
        if a[k] == nil then return path .. "." .. tostring(k) .. ": only after" end
    end
end
local function Packed(v)
    return type(v) == "table" and type(rawget(v, "c")) == "string" and rawget(v, "players") == nil
end
-- The strings and numbers a saved value takes in the file.
local function Constants(v)
    local seen, n = {}, 0
    local function note(x)
        local t = type(x)
        if (t == "string" or t == "number") and not seen[x] then seen[x] = true; n = n + 1 end
    end
    local function walk(t)
        local listed = #t
        for k, x in next, t do
            if not (type(k) == "number" and k >= 1 and k <= listed and k % 1 == 0) then note(k) end
            if type(x) == "table" then walk(x) else note(x) end
        end
    end
    walk(v)
    return n
end

----------------------------------------------------------------------
-- A dungeon run, played through the addon's own event handlers.
----------------------------------------------------------------------
ITEMS[100] = { 2, 1500, 4, 2 }
ITEMS[101] = { 3, 9000, 4, 2 }
ITEMS[102] = { 1, 50, 7, 0 }
ITEMS[103] = { 0, 300, 15, 0 }
ITEMS[104] = { 3, 12000, 2, 1 }
local green, blue, cloth, junk, bop = ItemLink(100, "Green Gloves", 2), ItemLink(101, "Blue Blade", 3),
    ItemLink(102, "Silk Cloth", 1), ItemLink(103, "Broken Fang", 0), ItemLink(104, "Boss Mace", 3)
local CYRILLIC = "\208\144\208\189\208\189\208\176 \208\160\208\190\209\129\209\129" -- a name with bytes 0x90 and 0x81
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { CYRILLIC, "HUNTER", "DAMAGER" }, { "Juno Ash", "ROGUE", "DAMAGER" } }
local H = "|HlootHistory:%d|h[Loot]|h: "
local function Play(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    local s = db.active
    NOW = NOW + 60
    Loot(("You receive loot: %sx%d."):format(cloth, 3))
    Loot(("%s receives loot: %s."):format("Borin Oak", junk))
    Loot((H .. "You have selected Greed for: %s"):format(7, green))
    Loot((H .. "%s has selected Greed for: %s"):format(7, "Sela Marrow", green))
    Loot((H .. "%s passed on: %s"):format(7, CYRILLIC, green))
    Loot((H .. "Greed Roll - %d for %s by %s"):format(7, 41, green, WORLD.me))
    Loot((H .. "Greed Roll - %d for %s by %s"):format(7, 88, green, "Sela Marrow"))
    Loot((H .. "%s won: %s"):format(7, "Sela Marrow", green))
    Loot(("%s receives loot: %s."):format("Sela Marrow", green))
    NOW = NOW + 240
    Fire("ENCOUNTER_END", 55, "Big Bad Boss", 1, 5, 1)
    NOW = NOW + 10
    Loot((H .. "%s has selected Need for: %s"):format(8, CYRILLIC, blue))
    Loot((H .. "Need Roll - %d for %s by %s"):format(8, 3, blue, CYRILLIC))
    Loot(("%s receives loot: %s."):format(CYRILLIC, blue))
    Loot((H .. "%s won: %s"):format(8, CYRILLIC, blue))
    Loot(("You receive loot: %s."):format(bop))
    NOW = NOW + 100
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    SlashCmdList.THATLUCKYBASTARD("stop")
    ThatLuckyBastardFrame:Hide()
    NOW = NOW + 3600
    return s
end
-- What the windows make of a run: totals, awards, fairness.
local function Shown(run)
    local sum = ns.Summarize(run)
    local out = { total = sum.market, vendor = sum.vendor, fair = ns.Fairness(sum) }
    for name, a in pairs(ns.Awards(run, sum)) do out[name] = a.title .. " / " .. tostring(a.text) end
    for _, p in ipairs(sum.players) do out["loot of " .. p.name] = p.market end
    return out
end

print("-- a save and a reload")
local first = Play(9001, "Test Keep")
local second = Play(9002, "Other Keep")
check(#db.history == 2 and db.history[1] == second, "two runs played and closed")
local was = { Essence(db.history[1]), Essence(db.history[2]) }
local shownWas = { Shown(db.history[1]), Shown(db.history[2]) }
local rawSize = Constants(db.history)

db = Reload()
check(Packed(SAVED.history[1]) and Packed(SAVED.history[2]), "in the saved file each finished run is one code and a few values")
check(#db.history == 2 and db.history[1].players ~= nil and db.history[1] ~= second,
      "after a reload they are run tables again (new ones: nothing of the old session is left)")
local d1 = Differ(was[1], Essence(db.history[1]), "run 1") or Differ(was[2], Essence(db.history[2]), "run 2")
check(d1 == nil, "and each is the same run as before, field for field (" .. tostring(d1) .. ")")
local d2 = Differ(shownWas[1], Shown(db.history[1]), "run 1") or Differ(shownWas[2], Shown(db.history[2]), "run 2")
check(d2 == nil, "the windows show the same totals, fairness and awards (" .. tostring(d2) .. ")")
check(db.history[1].players[CYRILLIC] ~= nil, "a player with a Cyrillic name is still there under that name")
local packedSize = Constants(SAVED.history)
print(("        two runs take %d strings and numbers in the file as tables, %d packed"):format(rawSize, packedSize))
check(packedSize < rawSize / 3 and packedSize < 120, "packed, they take a fraction of the room")
local image = Clone(SAVED)
db = Reload()
local d3 = Differ(image.history, SAVED.history, "saved")
check(d3 == nil, "saving again without touching anything writes the same thing (" .. tostring(d3) .. ")")

print("-- what changes after a reload is saved")
local run = db.history[2]
ns.TogglePin(run)
local e
for _, entry in pairs(db.history[1].players["Sela Marrow"].items) do e = entry end
PRICES_OFF = true
e.ah = 77000 -- an auction price, as if recorded
check(ns.ToggleAuctionPrice(db.history[1], e), "an item of an old run switched to its vendor price")
local switchedWas = Essence(db.history[1])
db = Reload()
check(db.history[2].pinned == true, "a run pinned after a reload is still pinned after the next")
local d4 = Differ(switchedWas, Essence(db.history[1]), "run 1")
check(d4 == nil and next(db.history[1].priceSwitched) ~= nil, "the price switch is saved too (" .. tostring(d4) .. ")")
ns.TogglePin(db.history[2])
ns.DeleteRun(db.history[2])
db = Reload()
check(#db.history == 1 and #SAVED.history == 1, "a deleted run is gone from the file")

print("-- the run in progress")
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 9003, "Third Keep"
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
Loot(("You receive loot: %s."):format(green))
local going = Essence(db.active)
db = Reload()
check(SAVED.active and SAVED.active.players ~= nil and not Packed(SAVED.active),
      "the run in progress is saved as it is: it is not finished")
check(db.active and Differ(going, Essence(db.active), "active") == nil, "and is the same after the reload")
Fire("PLAYER_ENTERING_WORLD", false, true)
Loot(("You receive loot: %s."):format(blue))
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
SlashCmdList.THATLUCKYBASTARD("stop")
ThatLuckyBastardFrame:Hide()
check(#db.history == 2, "it goes on, and closes like any other")

print("-- everything a run holds is kept")
-- A value a later version might add, an empty list, and no list at all:
-- a code knows none of the three.
db.history[1].future = { note = "kept", deep = { 1, 2, 3 } }
db.history[1].rollLog = db.history[1].rollLog or {}
local emptied = Clone(db.history[2])
db.history[2].rollLog, db.history[2].rollStats = {}, nil
local kept = { Essence(db.history[1]), Essence(db.history[2]) }
db = Reload()
check(Packed(SAVED.history[1]) and Packed(SAVED.history[2]), "both are packed all the same")
local d5 = Differ(kept[1], Essence(db.history[1]), "run 1") or Differ(kept[2], Essence(db.history[2]), "run 2")
check(d5 == nil, "a field no code knows, an empty list and a missing one all come back as they were (" .. tostring(d5) .. ")")
check(type(db.history[2].rollLog) == "table" and next(db.history[2].rollLog) == nil and db.history[2].rollStats == nil,
      "empty stays empty, and absent stays absent")

-- An old run: no name, no end, and its switched prices under their old
-- name. A code would give it a name, an end and the new name: it must not.
local oldRun = db.history[2]
oldRun.name, oldRun.endedAt, oldRun.priceSwitched = nil, nil, nil
oldRun.vendorOnly = { ["100"] = true }
local oldWas = Essence(oldRun)
db = Reload()
local d7 = Differ(oldWas, Essence(db.history[2]), "old run")
check(Packed(SAVED.history[2]) and d7 == nil and db.history[2].name == nil and db.history[2].endedAt == nil
      and db.history[2].priceSwitched == nil and db.history[2].vendorOnly["100"] == true,
      "an old run keeps what it lacks: no name, no end, its switched prices under their old name (" .. tostring(d7) .. ")")
db.history[2].name, db.history[2].endedAt = "Other Keep", db.history[2].startedAt + 600

print("-- a run that would not come back the same stays a table")
local function StaysTable(what, change)
    local target = db.history[1]
    local undo = change(target)
    local before = Essence(target)
    local reason = select(2, ns.PackRun(target))
    db = Reload()
    local same = Differ(before, Essence(db.history[1]), "run")
    check(not Packed(SAVED.history[1]) and same == nil,
          ("%s: saved as a table (%s), and intact (%s)"):format(what, tostring(reason), tostring(same)))
    undo(db.history[1])
    db = Reload()
    check(Packed(SAVED.history[1]), "   put right, it is packed at the next save")
end
local function AnItem(s)
    for _, p in pairs(s.players) do
        for _, entry in pairs(p.items) do return entry end
    end
end
StaysTable("an item whose value is not known yet", function(s)
    AnItem(s).resolved = false
    return function(t) for _, p in pairs(t.players) do for _, x in pairs(p.items) do x.resolved = true end end end
end)
StaysTable("a link in a form the code does not write", function(s)
    local item = AnItem(s)
    local link = item.link
    item.link = link:gsub("^|cnIQ%d:", "|cff1eff00")
    return function(t) for _, p in pairs(t.players) do for _, x in pairs(p.items) do
        x.link = x.link:gsub("^|cff1eff00", "|cnIQ" .. x.quality .. ":") end end end
end)
StaysTable("a value on an item that no code holds", function(s)
    AnItem(s).odd = "thing"
    return function(t) for _, p in pairs(t.players) do for _, x in pairs(p.items) do x.odd = nil end end end
end)
StaysTable("a name too long for a code", function(s)
    local name = s.name
    s.name = ("x"):rep(120)
    return function(t) t.name = name end
end)
StaysTable("a run of more than a week", function(s)
    local ended = s.endedAt
    s.endedAt = s.startedAt + 9 * 86400
    return function(t) t.endedAt = ended end
end)

print("-- a record that cannot be read is set aside, never thrown away")
db = Reload()
local good = Essence(db.history[2])
local broken = Clone(SAVED)
local wholeCode = broken.history[1].c
broken.history[1].c = broken.history[1].c:sub(1, 40) .. "@@@" .. broken.history[1].c:sub(44)
local keptCode = broken.history[1].c
ThatLuckyBastardDB = broken
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
db = ThatLuckyBastardDB
check(#db.history == 1 and Differ(good, Essence(db.history[1]), "run") == nil, "the other run loads as ever")
check(db.unread and #db.unread == 1 and db.unread[1].record.c == keptCode and db.unread[1].from == "history",
      "the damaged one waits aside, as it was")
local ok = pcall(function()
    ns.ShowWindow()
    ns.ShowBrowse("runs")
    ns.Rerender()
    RunTimers()
end)
check(ok, "and the windows open without it")
ThatLuckyBastardFrame:Hide()
db = Reload()
check(#SAVED.history == 1 and SAVED.unread and SAVED.unread[1].record.c == keptCode, "it is still in the file after another save")
-- Repaired (or read by a version that can): it takes its place again.
local mended = Clone(SAVED)
mended.unread[1].record.c = wholeCode
ThatLuckyBastardDB = mended
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
db = ThatLuckyBastardDB
check(#db.history == 2 and db.unread == nil and (db.history[1].startedAt or 0) > (db.history[2].startedAt or 0),
      "once it can be read it is a run again, at its place by date")

print("-- should the game go on after saving")
local held = db.history[1]
ns.PackRuns(db)
check(Packed(db.history[1]) and db.history[1].players == held.players,
      "packed for the file, a record still answers for its run")
ns.saving = true
Fire("GROUP_ROSTER_UPDATE")
check(db.history[1] == held and db.history[1].players ~= nil, "at the next event the runs are runs again")

print("-- runs shared with you")
local theirs = Clone(held)
theirs.startedAt, theirs.endedAt, theirs.owner = held.startedAt - 99999, held.endedAt - 99999, "Kind Soul"
theirs.players["Kind Soul"] = { class = "PRIEST", items = {} }
local got = ns.ImportCode(ns.EncodeRun(theirs))
check(got and got.sharedBy == "Kind Soul" and #db.shared == 1, "a run imported from a code")
local sharedWas = Essence(db.shared[1])
db = Reload()
local d6 = Differ(sharedWas, Essence(db.shared[1]), "shared")
check(Packed(SAVED.shared[1]) and d6 == nil and db.shared[1].sharedBy == "Kind Soul",
      "is packed and comes back too, with who shared it (" .. tostring(d6) .. ")")

print("-- three hundred runs made at random")
local seed = 4242
local function rnd(n)
    seed = (seed * 48271) % 2147483647
    return seed % n + 1
end
local NAMES = { "Abe Stone", "Zed", CYRILLIC, "\195\137lise No\195\171l", "O'Brien Mac", "Dot.Com, Esq", "Semi;colon", "Bang!",
                "Percent%25", "Plain Jane", "Tab Hunter", "Under_score" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "HUNTER", "ROGUE" }
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local CATS = { "epic", "rare", "uncommon", "bop", "quest", "prof", "other", "junk" }
local TAILS = { "::::::::60:258::::::::", ":2564:::::::60:258:::1:6652:::::", "::::::::::::::::::", ":::::::::70:::::2:1472:1532:::" }
local function RandomRun(k)
    local s = { name = ({ "Keep, The", "Hall; of 50%", "\208\159\208\190\208\180", "Plain" })[rnd(4)], instanceID = rnd(900),
                startedAt = NOW - 100000 - k * 5000, owner = NAMES[1], players = {}, names = {}, kills = rnd(9) - 1 }
    s.endedAt = s.startedAt + rnd(7000)
    local count = 1 + rnd(8)
    for i = 1, count do
        s.names[i] = NAMES[i]
        s.players[NAMES[i]] = { class = rnd(6) < 6 and CLASSES[rnd(5)] or nil, role = rnd(4) < 4 and ROLES[rnd(3)] or nil,
                               items = {} }
    end
    local id, t = 0, 0
    s.log, s.rollLog, s.rollStats, s.bosses = {}, {}, {}, {}
    for i = 1, count do
        for _ = 1, rnd(12) - 1 do
            id = id + 1
            local quality = rnd(6) - 1
            local link = ("|cnIQ%d:|Hitem:%d%s|h[%s]|h|r"):format(quality, 1000 + rnd(5000), TAILS[rnd(#TAILS)],
                ({ "Sword of Truth", "It's a Trap", "Heavy [Leather]", "\208\156\208\181\209\135", "50% Off, Sale!" })[rnd(5)])
            local key = ns.EntryKey(link)
            if not s.players[NAMES[i]].items[key] then
                local wins = rnd(3)
                s.players[NAMES[i]].items[key] = { link = link, id = id, count = rnd(20), vendor = rnd(99999) - 1,
                    ah = rnd(3) == 1 and rnd(9999999) or nil, cat = CATS[rnd(8)], quality = quality, resolved = true,
                    need = wins == 1 and 1 or nil, greed = wins == 2 and 1 or nil }
                t = t + rnd(90) - 1
                s.log[#s.log + 1] = ("%d:%d:%d:%d"):format(t, i, id, rnd(3))
            end
        end
        if rnd(3) > 1 then
            s.rollStats[NAMES[i]] = { sum = rnd(900), n = rnd(12), high = rnd(100), low = rnd(100), passes = rnd(5) - 1 }
        end
    end
    for _ = 1, rnd(10) - 1 do
        local parts, seen = {}, {}
        for _ = 1, rnd(count) do
            local who = rnd(count)
            if not seen[who] then
                seen[who] = true
                local choice = ({ "n", "g", "p" })[rnd(3)]
                parts[#parts + 1] = who .. choice .. (choice ~= "p" and rnd(100) or "")
            end
        end
        s.rollLog[#s.rollLog + 1] = { k = tostring(1000 + rnd(5000)), t = rnd(6000), w = rnd(count), m = rnd(2) == 1 and "n" or "g",
                                      r = table.concat(parts, ",") }
    end
    for b = 1, rnd(4) - 1 do s.bosses[b] = { t = b * 500, name = rnd(4) > 1 and ("Boss, the " .. b) or nil } end
    -- A code makes no difference between an empty list and none: both must survive.
    for _, field in ipairs({ "log", "rollLog", "rollStats", "bosses" }) do
        if next(s[field]) == nil and rnd(2) == 1 then s[field] = nil end
    end
    if s.log == nil then s.names = nil end
    if rnd(4) == 1 then s.pinned = true end
    if rnd(3) == 1 then s.stats = { group = rnd(99999), mine = rnd(9999), prior = rnd(9) - 1 } end
    if rnd(5) == 1 then s.priceSwitched = { [tostring(1000 + rnd(5000))] = true } end
    s.recorded, s.statted = true, true
    return s
end
for i = #db.history, 1, -1 do db.history[i] = nil end
local made = {}
for k = 1, 300 do
    local s = RandomRun(k)
    made[k] = Essence(s)
    db.history[k] = s
end
db.options.maxHistory = 1000
db = Reload()
local packed, tables, wrong, firstWrong = 0, 0, 0, nil
for k = 1, 300 do
    if Packed(SAVED.history[k]) then packed = packed + 1 else tables = tables + 1 end
    local d = db.history[k] and Differ(made[k], Essence(db.history[k]), "run " .. k) or ("run " .. k .. " is missing")
    if db.history[k] and Differ(made[k], Essence(db.history[k]), "run " .. k) == nil then d = nil end
    if d then
        wrong = wrong + 1
        firstWrong = firstWrong or d
    end
end
print(("        %d packed, %d left as tables; %d strings and numbers for all 300 in the file"):format(
    packed, tables, Constants(SAVED.history)))
check(wrong == 0, ("all 300 come back the same (%d did not: %s)"):format(wrong, tostring(firstWrong)))
check(packed >= 290, ("nearly all of them packed (%d)"):format(packed))
check(Constants(SAVED.history) < 30000, "three hundred runs take a small part of the 262,143 the file can hold")

print("==== loot bingo's leftovers (gone in 0.7.1) ====")
-- What an older version kept for bingo: in a finished run (saved in its
-- record's x), in the run in progress, and in the saved data itself.
db.history[1].bingo = { keys = { "blue" }, done = { blue = true }, pick = 1, won = true }
db.history[1].rollHigh, db.history[1].rollLow, db.history[1].myDeaths = true, true, 2
db.bingo, db.options.bingo = { picked = 3, won = 1 }, true
Fire("PLAYER_LOGOUT")
local record = SAVED.history[1]
check(Packed(record) and record.x and record.x.bingo ~= nil and record.x.myDeaths == 2 and SAVED.bingo ~= nil,
      "an older version's file: the card and the rest are in the run's record, the tally beside the runs")
SAVED.active = { name = "Old Keep", instanceID = 33, startedAt = NOW - 600, enteredAt = NOW - 600, lastSeen = NOW,
                 players = {}, bingo = { keys = {}, done = {} }, rollHigh = true, myDeaths = 1 }
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in next, v do out[k] = Copy(x) end
    return out
end
ThatLuckyBastardDB = Copy(SAVED) -- the file read back, as Reload does
Fire("ADDON_LOADED", "ThatLuckyBastard")
Fire("PLAYER_LOGIN")
db = ThatLuckyBastardDB
local h = db.history[1]
check(h.bingo == nil and h.rollHigh == nil and h.rollLow == nil and h.myDeaths == nil and h.players ~= nil,
      "loaded, the run keeps everything but what bingo kept")
check(db.bingo == nil and db.options.bingo == nil, "the tally of lines and the switch are gone")
-- (Ended at login or not, the run that was in progress is somewhere.)
local was = db.active and db.active.name == "Old Keep" and db.active or nil
for _, s in ipairs(db.history) do
    if s.name == "Old Keep" then was = s end
end
check(was ~= nil and was.bingo == nil and was.rollHigh == nil and was.myDeaths == nil,
      "and so is the card of the run that was in progress")
db = Reload()
record = SAVED.history[1]
check(Packed(record) and (record.x == nil or (record.x.bingo == nil and record.x.myDeaths == nil)),
      "saved again, the run's record has none of it")
check(Differ(made[2], Essence(db.history[2]), "run 2") == nil, "and the other runs are as they were")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (storage)")
