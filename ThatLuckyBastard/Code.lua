local _, ns = ...

-- Runs as text, for sharing: a code of plain characters that survives
-- being pasted anywhere (Discord, a forum post) and that the addon turns
-- back into the run. The same code travels between two players' addons
-- when someone clicks a run's link in chat (see Share.lua).
--
-- A code carries what the windows need to show a run as its owner saw
-- it: the players, every item at the prices it was valued at, the rolls
-- and the timeline. Layout:
--
--   TLB1!head!names!tails!players!pickups!rolls!bosses!switched!check
--
-- Sections are separated by "!", records by ";", fields by "," and the
-- parts of a field by ".". Numbers are written in base 64, text is
-- escaped (%XX) wherever it holds a separator. Every character used is
-- safe in game chat and in Discord, which would turn *, _, ~, | and
-- :word: into formatting. `check` is a checksum of the rest: a code cut
-- short is refused rather than read wrong. A five-player dungeon run
-- takes about 3,000 to 6,000 characters; a raid of forty with ten bosses
-- or more, 30,000 to 65,000.
--
-- A code comes from someone else, so reading one never trusts it: it is
-- text taken apart, never run. Its length is checked before anything
-- else is done with it, every list it holds has a limit well above what
-- a raid needs (see the MAX_ constants), and no step takes longer than
-- the code is long. What a code can cost is thereby bounded, whoever
-- wrote it.
--
-- Runs received from other players are kept in db.shared, apart from
-- your own: they count in none of your statistics.

local PREFIX = "TLB1!"
local MAX_CODE = 200000 -- longest code accepted, in characters
-- Longest text looked at: a code, with room for the line breaks and
-- spaces a chat program may have put around and into it.
local MAX_TEXT = MAX_CODE + 20000
-- The most a run may hold. A busy raid of forty has some 2,200 items,
-- 2,800 pickups, 170 rolls with 4,200 entries, and 13 bosses.
local MAX_ITEMS = 6000         -- item entries, all players together
local MAX_PICKUPS = 5000
local MAX_ROLLS = 2000
local MAX_ROLL_ENTRIES = 10000 -- players' entries, all rolls together
local MAX_BOSSES = 60
local DAMAGED = "This code is incomplete or damaged. Copy all of it, and try again."
local TOO_LONG = "This is too long to be a run's code."

local CATS = { "epic", "rare", "uncommon", "bop", "quest", "prof", "other", "junk" }
local CAT_INDEX = {}
for i, cat in ipairs(CATS) do CAT_INDEX[cat] = i end
local ROLES = { T = "TANK", H = "HEALER", D = "DAMAGER" }
-- A player's choice in a roll, written between their number and what they
-- rolled: characters that are neither digits nor separators.
local CHOICE_MARK = { n = "(", g = ")", p = "=" }
local MARK_CHOICE = { ["("] = "n", [")"] = "g", ["="] = "p" }

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

----------------------------------------------------------------------
-- The pieces of a code
----------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local VALUE = {}
for i = 1, #DIGITS do VALUE[DIGITS:sub(i, i)] = i - 1 end

-- A whole number in base 64; nothing for nil.
local function N(n)
    if n == nil then return "" end
    n = math.floor(n + 0.5)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    local out = ""
    repeat
        local d = n % 64
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = (n - d) / 64
    until n == 0
    return sign .. out
end

-- Reads a number written by N, which must lie between low and high. Nil
-- for an empty field; an error for anything else.
local function Num(text, low, high)
    if text == nil or text == "" then return nil end
    local sign, digits = text:match("^(%-?)([%w+/]+)$")
    assert(digits and #digits <= 8, "number")
    local n = 0
    for i = 1, #digits do n = n * 64 + VALUE[digits:sub(i, i)] end
    if sign == "-" then n = -n end
    assert(n >= low and n <= high, "range")
    return n
end

-- The control characters of ASCII, spelled out. (`%c` asks the C library,
-- which on some systems also names bytes above 127: there they are half
-- of a letter, in a name written in Cyrillic or with accents.)
local CONTROL = "%z\1-\31\127"

-- Text with the separators escaped.
local function S(text)
    return (tostring(text or ""):gsub("[%%!;,%.'|" .. CONTROL .. "]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

-- Reads text written by S. Escape sequences and control characters are
-- dropped: text from outside never gets to draw anything in a window.
local function ReadS(text, max)
    text = (text or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    text = text:gsub("[|" .. CONTROL .. "]", "")
    assert(#text <= max, "text")
    return text
end

local function Split(text, sep)
    local out = {}
    if text == nil or text == "" then return out end
    for part in (text .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return out
end

-- Joins fields, leaving out the empty ones at the end.
local function Join(fields, sep)
    local last = #fields
    while last > 0 and fields[last] == "" do last = last - 1 end
    return table.concat(fields, sep, 1, last)
end

local function Checksum(text)
    local h = 0
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 16777213 end
    return h
end

-- A run's id in chat links: when it started, in base 36, so that it is
-- letters and digits only.
function ns.ShareId(s)
    local n, out = s.startedAt or 0, ""
    repeat
        local d = n % 36
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    until n == 0
    return out
end

----------------------------------------------------------------------
-- Writing a code
----------------------------------------------------------------------

-- `written`, when given, receives the item entries in the order they are
-- written (an entry without an item ID is not written at all).
function ns.EncodeRun(s, written)
    -- Names: the run's own list first, since the pickups and rolls point
    -- into it, then everyone missing from it.
    local names, index = {}, {}
    local function Name(name)
        if not index[name] then
            names[#names + 1] = name
            index[name] = #names
        end
        return index[name]
    end
    for _, name in ipairs(s.names or {}) do Name(name) end
    local owner = Name(ns.Me(s))
    local playerNames = {}
    for name in pairs(s.players) do playerNames[#playerNames + 1] = name end
    table.sort(playerNames)

    -- An item string past its ID (bonus IDs and the like) is shared by
    -- many items: each one is written once and referred to by number.
    local tails, tailIndex = {}, {}
    local function Tail(itemString)
        local tail = (itemString:match("^item:%d+:(.*)$") or ""):gsub(":+$", ""):gsub(":", "'")
        if tail == "" then return nil end
        if not tailIndex[tail] then
            tails[#tails + 1] = tail
            tailIndex[tail] = #tails
        end
        return tailIndex[tail]
    end

    -- Players, each with their items. An item's category and quality share
    -- one digit.
    local players, entryIds = {}, {}
    for _, name in ipairs(playerNames) do
        local p = s.players[name]
        local st = s.rollStats and s.rollStats[name] or {}
        local fields = { Join({ N(Name(name)), S(p.class), p.role and p.role:sub(1, 1) or "",
                                N(st.sum), N(st.n), N(st.high), N(st.low), N(st.passes) }, ".") }
        local entries = {}
        for _, e in pairs(p.items) do entries[#entries + 1] = e end
        table.sort(entries, function(a, b)
            if (a.id or 0) ~= (b.id or 0) then return (a.id or 0) < (b.id or 0) end
            return a.link < b.link
        end)
        for _, e in ipairs(entries) do
            local itemString = ns.EntryKey(e.link)
            local id = tonumber(itemString:match("^item:(%d+)"))
            if id then
                if written then written[#written + 1] = e end
                if e.id then entryIds[e.id] = true end
                local kind = ((CAT_INDEX[e.cat] or CAT_INDEX.other) - 1) * 8 + math.min(e.quality or 1, 7)
                fields[#fields + 1] = Join({ N(e.id), N(id), N(e.count), N(e.vendor), N(kind), N(e.ah),
                                             N(Tail(itemString)), N(e.need), N(e.greed) }, ".")
            end
        end
        players[#players + 1] = table.concat(fields, ",")
    end

    -- Pickups: the time as the gap since the one before, the item entry
    -- (which says whose it is), and the count only when it is not 1.
    local pickups, last = {}, 0
    for _, text in ipairs(s.log or {}) do
        local t, _, id, count = text:match("^(%d+):(%d+):(%d+):(%d+)$")
        if t and entryIds[tonumber(id)] then
            t = tonumber(t)
            pickups[#pickups + 1] = Join({ N(t - last), N(tonumber(id)), count == "1" and "" or N(tonumber(count)) }, ".")
            last = t
        end
    end

    -- Rolls: the item, when, the winner and how, then each player's choice
    -- and number.
    local rolls = {}
    for _, r in ipairs(s.rollLog or {}) do
        local fields = { Join({ N(tonumber(r.k)), N(r.t), N(r.w), r.m == "n" and "n" or "g" }, ".") }
        for who, choice, num in (r.r or ""):gmatch("(%d+)(%a)(%d*)") do
            if CHOICE_MARK[choice] then fields[#fields + 1] = N(tonumber(who)) .. CHOICE_MARK[choice] .. N(tonumber(num)) end
        end
        rolls[#rolls + 1] = table.concat(fields, ",")
    end

    local bosses = {}
    for _, b in ipairs(s.bosses or {}) do bosses[#bosses + 1] = Join({ N(b.t), S(b.name) }, ".") end

    local switched = {}
    for key in pairs(s.priceSwitched or s.vendorOnly or {}) do
        if tonumber(key) then switched[#switched + 1] = N(tonumber(key)) end
    end
    table.sort(switched)

    local finish = s.endedAt or s.leftAt or time()
    local nameList = {}
    for i, name in ipairs(names) do nameList[i] = S(name) end
    local body = PREFIX .. table.concat({
        Join({ S(s.name or "Run"), N(s.instanceID), N(s.startedAt), N(math.max(finish - (s.startedAt or finish), 0)),
               N(owner), N(s.kills) }, ","),
        table.concat(nameList, ","),
        table.concat(tails, ","),
        table.concat(players, ";"),
        table.concat(pickups, ","),
        table.concat(rolls, ";"),
        table.concat(bosses, ","),
        table.concat(switched, "."),
    }, "!")
    return body .. "!" .. N(Checksum(body))
end

----------------------------------------------------------------------
-- Reading a code
----------------------------------------------------------------------

-- The item's link. An item this client has not loaded yet gets a
-- stand-in until it has (see LoadNames).
local function ItemLink(itemString, quality, id)
    local _, link = GetItemInfo(itemString)
    if link then return link end
    return ("|cnIQ%d:|H%s|h[Item %d]|h|r"):format(quality, itemString, id)
end

-- A link with the name it was saved with: nothing is asked of the game.
local function NamedLink(itemString, quality, name)
    return ("|cnIQ%d:|H%s|h[%s]|h|r"):format(quality, itemString, name)
end

-- Builds the run from the sections of a code. Errors on anything that
-- is not what a code holds. `itemNames`, when given, are the names of the
-- items in the order the code holds them, for their links; `read`, when
-- given, receives the item entries in that order.
local function Build(sec, itemNames, read)
    local nth = 0
    local function Link(itemString, quality, id)
        nth = nth + 1
        if not itemNames then return ItemLink(itemString, quality, id) end
        return NamedLink(itemString, quality, assert(itemNames[nth], "item name"))
    end
    local head = Split(sec[1], ",")
    local names = {}
    for i, text in ipairs(Split(sec[2], ",")) do names[i] = ReadS(text, 64) end
    assert(#names >= 1 and #names <= 80, "names")
    local function NameAt(text)
        local i = Num(text, 1, #names)
        return i and names[i]
    end

    local s = {
        name = ReadS(head[1], 80),
        instanceID = Num(head[2], 0, 1e9),
        startedAt = Num(head[3], 1, 4e9),
        kills = Num(head[6], 0, 100),
        names = names,
        players = {},
    }
    assert(s.startedAt, "start")
    if s.name == "" then s.name = "Run" end
    s.endedAt = s.startedAt + (Num(head[4], 0, 7 * 86400) or 0)
    s.recordedBy = NameAt(head[5])

    local tails = Split(sec[3], ",")
    assert(#tails <= MAX_ITEMS, "tails")
    for _, tail in ipairs(tails) do assert(#tail <= 200 and tail:match("^[%d%-']+$"), "tail") end

    local whose = {} -- item entry id -> the number of the player it belongs to
    local items = 0
    for _, record in ipairs(Split(sec[4], ";")) do
        local fields = Split(record, ",")
        local h = Split(fields[1], ".")
        local nameIndex = Num(h[1], 1, #names)
        local name = names[nameIndex]
        local class = ReadS(h[2], 20)
        assert(name and not s.players[name] and class:match("^%u*$"), "player")
        local p = { class = class ~= "" and class or nil, role = ROLES[h[3] or ""], items = {} }
        if (h[5] or "") ~= "" then
            s.rollStats = s.rollStats or {}
            s.rollStats[name] = { sum = Num(h[4], 0, 1e7) or 0, n = Num(h[5], 0, 1e5), high = Num(h[6], 0, 100),
                                  low = Num(h[7], 0, 100), passes = Num(h[8], 0, 1e5) or 0 }
        end
        items = items + #fields - 1
        assert(items <= MAX_ITEMS, "items")
        local copies = {} -- [item string] = entries of it so far, for this player
        for i = 2, #fields do
            local f = Split(fields[i], ".")
            local entryId, id = Num(f[1], 1, 1e5), Num(f[2], 1, 1e8)
            local kind = Num(f[5], 0, 63) or ((CAT_INDEX.other - 1) * 8 + 1)
            local tail = Num(f[7], 1, #tails)
            assert(id and not (entryId and whose[entryId]), "item")
            local itemString = "item:" .. id .. (tail and (":" .. tails[tail]:gsub("'", ":")) or "")
            local quality = kind % 8
            -- Two entries of one item, from an older version's keys: the
            -- second is filed as "<item>#2".
            local nth = (copies[itemString] or 0) + 1
            copies[itemString] = nth
            local key = nth == 1 and itemString or (itemString .. "#" .. nth)
            p.items[key] = {
                id = entryId, count = Num(f[3], 0, 1e6) or 1, vendor = Num(f[4], 0, 1e10) or 0,
                cat = CATS[math.floor(kind / 8) + 1], quality = quality, ah = Num(f[6], 0, 1e11),
                need = Num(f[8], 0, 1e6), greed = Num(f[9], 0, 1e6),
                -- Valued as the owner saw it: never priced again here.
                resolved = true,
                link = Link(itemString, quality, id),
            }
            if read then read[#read + 1] = p.items[key] end
            if entryId then whose[entryId] = nameIndex end
        end
        s.players[name] = p
    end
    assert(next(s.players), "no players")
    assert(not itemNames or nth == #itemNames, "item names")

    local log, t = {}, 0
    for _, text in ipairs(Split(sec[5], ",")) do
        local f = Split(text, ".")
        t = t + (Num(f[1], -1e6, 1e6) or 0)
        local id = Num(f[2], 1, 1e5)
        assert(id and whose[id] and t >= 0 and #log < MAX_PICKUPS, "pickup")
        log[#log + 1] = ("%d:%d:%d:%d"):format(t, whose[id], id, Num(f[3], 1, 1e6) or 1)
    end

    local rollLog, entries = {}, 0
    for _, record in ipairs(Split(sec[6], ";")) do
        local fields = Split(record, ",")
        local h = Split(fields[1], ".")
        local parts, inRoll = {}, {}
        entries = entries + #fields - 1
        assert(#fields - 1 <= #names and entries <= MAX_ROLL_ENTRIES, "roll")
        for i = 2, #fields do
            local who, mark, num = fields[i]:match("^([%w+/]+)([%(%)=])([%w+/]*)$")
            who = Num(who, 1, #names)
            assert(who and not inRoll[who], "roll") -- a player is in a roll once
            inRoll[who] = true
            parts[#parts + 1] = who .. MARK_CHOICE[mark] .. (Num(num, 1, 100) or "")
        end
        local k, w = Num(h[1], 1, 1e8), Num(h[3], 1, #names)
        assert(k and w and #rollLog < MAX_ROLLS, "roll")
        rollLog[#rollLog + 1] = { k = tostring(k), t = Num(h[2], 0, 1e6) or 0, w = w, m = h[4] == "n" and "n" or "g",
                                  r = table.concat(parts, ",") }
    end

    local bosses = {}
    for _, text in ipairs(Split(sec[7], ",")) do
        assert(#bosses < MAX_BOSSES, "boss")
        local f = Split(text, ".")
        local name = ReadS(f[2], 80)
        bosses[#bosses + 1] = { t = Num(f[1], 0, 1e6) or 0, name = name ~= "" and name or nil }
    end

    local switched = Split(sec[8], ".")
    assert(#switched <= MAX_ITEMS, "switched")
    for _, text in ipairs(switched) do
        s.priceSwitched = s.priceSwitched or {}
        s.priceSwitched[tostring(Num(text, 1, 1e8))] = true
    end

    -- A run recorded before the timeline existed has none: nil, as for
    -- the owner, rather than an empty one.
    s.log = log[1] and log or nil
    s.rollLog = rollLog[1] and rollLog or nil
    s.bosses = bosses[1] and bosses or nil
    return s
end

-- The run in a code, or nil and why not. `itemNames` and `read`: see Build.
function ns.DecodeRun(code, itemNames, read)
    code = tostring(code or "")
    -- Its length, before anything else looks at it.
    if #code > MAX_TEXT then return nil, TOO_LONG end
    code = code:gsub("[\r\n]", "")
    -- The spaces around it, found from each end. (A pattern doing both in
    -- one go takes the square of the length on a long run of spaces.)
    local first, last = code:find("%S"), #code
    while last > 0 and code:find("^%s", last) do last = last - 1 end
    code = first and code:sub(first, last) or ""
    if code:sub(1, 3) ~= "TLB" then return nil, "This is not a That Lucky Bastard code." end
    if code:sub(1, #PREFIX) ~= PREFIX then
        return nil, "This code was made by a newer version of That Lucky Bastard. Update the addon."
    end
    if #code > MAX_CODE then return nil, TOO_LONG end
    local body, check = code:match("^(.*)!([%w+/]+)$")
    if not body or not pcall(function() assert(Num(check, 0, 16777213) == Checksum(body)) end) then
        return nil, DAMAGED
    end
    local sections = Split(body:sub(#PREFIX + 1), "!")
    if #sections ~= 8 then return nil, DAMAGED end
    local ok, s = pcall(Build, sections, itemNames, read)
    if not ok then return nil, DAMAGED end
    return s
end

----------------------------------------------------------------------
-- Runs received from other players
----------------------------------------------------------------------

-- Items this client had not loaded yet show a stand-in name; the real
-- link replaces it as each one arrives.
local function LoadNames(s)
    if not (Item and Item.CreateFromItemID) then return end
    -- One request per item, however many players have it.
    local waiting = {} -- [item id] = { { e, itemString }, ... }
    for _, p in pairs(s.players) do
        for _, e in pairs(p.items) do
            local itemString = e.link:match("|H(item:[^|]+)|h%[Item %d+%]|h")
            local id = itemString and tonumber(itemString:match("^item:(%d+)"))
            if id then
                waiting[id] = waiting[id] or {}
                waiting[id][#waiting[id] + 1] = { e, itemString }
            end
        end
    end
    for id, list in pairs(waiting) do
        local item = Item:CreateFromItemID(id)
        if not item:IsItemEmpty() then
            item:ContinueOnItemLoad(function()
                for _, entry in ipairs(list) do
                    local _, link = GetItemInfo(entry[2])
                    if link then entry[1].link = link end
                end
                ns.Refresh()
            end)
        end
    end
end

-- Runs shared with you are kept up to the number of runs to keep, counted
-- apart from your own, so that importing never costs you a run of yours.
-- They are stored in the order they arrived: the first to arrive go first.
function ns.TrimShared()
    local list = ns.db.shared
    for i = #list, ns.db.options.maxHistory + 1, -1 do table.remove(list, i) end
end

-- The runs shared with you, newest first by when they started.
function ns.SharedByDate()
    local out = {}
    for i, s in ipairs(ns.db.shared) do out[i] = s end
    table.sort(out, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
    return out
end

-- One of your own runs: a code of it opens the run itself, not a copy.
local function OwnRun(s)
    for _, run in ipairs(ns.AllRuns()) do
        if run.startedAt == s.startedAt and ns.Me(run) == s.recordedBy then return run end
    end
end

-- Keeps a run read from a code, in place of an earlier copy of it.
-- `from`: who shared it, when known. Returns the run to show, or nil and
-- why not.
function ns.ImportCode(code, from)
    local s, err = ns.DecodeRun(code)
    if not s then return nil, err end
    local own = OwnRun(s)
    if own then return own end
    s.sharedBy, s.receivedAt = from or s.recordedBy, time()
    local list = ns.db.shared
    for i = #list, 1, -1 do
        if list[i].startedAt == s.startedAt and list[i].recordedBy == s.recordedBy then table.remove(list, i) end
    end
    table.insert(list, 1, s)
    ns.TrimShared()
    LoadNames(s)
    return s
end

----------------------------------------------------------------------
-- Runs in the saved file
--
-- The game's saved file is one Lua chunk, and Lua cannot load a chunk
-- with more than 262,143 different strings and numbers. A run kept as a
-- table takes 550 to 1,000 of them (every pickup, every item), so the
-- file was full at some 300 runs. A finished run is therefore saved as a
-- record of a few values:
--
--   c  the run's code, the same one sharing uses
--   n  its items' names, each followed by "|", in the order of the code
--   m  how many names the run's own list had (absent: it had none)
--   e  fields that were empty tables, d  fields the run did not have:
--      a code makes no difference between "none" and "nothing"
--   x  every other field of the run, as it is: whatever a code does not
--      carry (owner, pinned, the figures it was counted with...), and
--      whatever a later version adds
--
-- That is 13 values for a dungeon run, and a tenth of the text.
--
-- Runs are packed when the game saves (PLAYER_LOGOUT) and unpacked when
-- it loads (ADDON_LOADED): in between they are the tables they always
-- were. A run is only packed once unpacking its record has been checked
-- to give the run back: every field and every item, the same. One thing
-- is let go, as sharing already does: an item's link is filed without the
-- looter's level and specialisation (see ns.EntryKey), and without the
-- colons that end it. A run that does not come back the same (an item
-- still unresolved, a field a code cannot hold) stays a table, and is
-- tried again at the next save. A record that cannot be read is never
-- thrown away: it is set aside in db.unread, and tried again at each load.
----------------------------------------------------------------------

-- What a code carries of a run. Everything else goes into `x`.
local CODED = { name = true, instanceID = true, startedAt = true, endedAt = true, kills = true, names = true,
                players = true, rollStats = true, log = true, rollLog = true, bosses = true, priceSwitched = true }
-- Of the moment only: never saved, so not compared.
local ITEM_PASSING = { lastAt = true, noAH = true, now = true }
local PLAYER_PASSING = { joined = true }
local NAME_END = "|" -- cannot be part of a name inside a link

-- [run] = the record it was read from, or was last packed as: a run whose
-- code and names have not changed since needs no second check.
local packedAs = setmetatable({}, { __mode = "k" })

local function IsPacked(v)
    return type(v) == "table" and type(rawget(v, "c")) == "string" and rawget(v, "players") == nil
end

-- Plain values, and tables of them, compared all the way down.
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- The run in a record, or nil and why not. Also returns its item entries
-- in the order of the code.
function ns.UnpackRun(record)
    local names = {}
    for name in (record.n or ""):gmatch("([^" .. NAME_END .. "]*)" .. NAME_END) do names[#names + 1] = name end
    local read = {}
    local s, why = ns.DecodeRun(record.c, names, read)
    if not s then return nil, why end
    s.recordedBy = nil -- a code names its recorder; a run has `owner`, in x
    if record.m then
        for i = #s.names, record.m + 1, -1 do s.names[i] = nil end -- the code adds the players its lists lack
    else
        s.names = nil
    end
    for _, field in ipairs(record.d or {}) do s[field] = nil end
    for _, field in ipairs(record.e or {}) do
        if s[field] == nil then s[field] = {} end
    end
    for k, v in pairs(record.x or {}) do s[k] = v end
    return s, read
end

-- Is `back`, unpacked from a record of `s`, the same run? `written` and
-- `read`: their item entries, in the order of the code. Returns false and
-- the first thing that differs.
local function Lossless(s, back, written, read)
    for key in pairs(CODED) do
        if key ~= "players" and not Same(s[key], back[key]) then return false, key end
    end
    for k, v in pairs(s) do
        if not CODED[k] and back[k] ~= v then return false, k end
    end
    for k in pairs(back) do
        if s[k] == nil then return false, k end
    end

    local players = 0
    for name, p in pairs(s.players) do
        players = players + 1
        local q = back.players[name]
        if not q or p.class ~= q.class or p.role ~= q.role then return false, "player" end
        for k in pairs(p) do
            if k ~= "class" and k ~= "role" and k ~= "items" and not PLAYER_PASSING[k] then return false, "player." .. k end
        end
        local have, got = 0, 0
        for _ in pairs(p.items) do have = have + 1 end
        for _ in pairs(q.items) do got = got + 1 end
        if have ~= got then return false, "items" end
    end
    for _ in pairs(back.players) do players = players - 1 end
    if players ~= 0 then return false, "players" end

    if #written ~= #read then return false, "items" end
    for i, e in ipairs(written) do
        local d = read[i]
        for k, v in pairs(e) do
            if k == "link" then
                -- The same link, but for its item string, which must be
                -- the one the item is filed under, less the colons at its end.
                local filed = ns.EntryKey(v):gsub(":+$", "")
                local expected = v:gsub("|Hitem:[^|]*|h", function() return "|H" .. filed .. "|h" end, 1)
                if d.link ~= expected then return false, "link" end
            elseif not ITEM_PASSING[k] and d[k] ~= v then
                return false, "item." .. k
            end
        end
        for k in pairs(d) do
            if e[k] == nil then return false, "item." .. k end
        end
    end
    return true
end

-- What a code holds of an item, and as what.
local ITEM_CODED = { id = "number", count = "number", vendor = "number", ah = "number", need = "number",
                     greed = "number", quality = "number", cat = "text", link = "text", resolved = "flag" }
local function Whole(v) return type(v) == "number" and v >= 0 and v % 1 == 0 end

-- Are the players and items of `s` exactly what a code holds: no value it
-- has no place for, none it would round or default, no item it leaves
-- out, every link in the form it is rebuilt in? Two runs for which this
-- holds and whose codes and item names are equal are the same run. (That
-- is what lets a run checked once be saved again without a second check;
-- the check itself asks for no such thing.) `written`: see ns.EncodeRun.
local function Plain(s, written)
    local items = 0
    for _, p in pairs(s.players) do
        for k in pairs(p) do
            if k ~= "class" and k ~= "role" and k ~= "items" and not PLAYER_PASSING[k] then return false end
        end
        for _ in pairs(p.items) do items = items + 1 end
    end
    if items ~= #written then return false end
    for _, e in ipairs(written) do
        if e.resolved ~= true or not CAT_INDEX[e.cat] or not Whole(e.quality) or e.quality > 7 then return false end
        for k, v in pairs(e) do
            if not ITEM_PASSING[k] then
                local kind = ITEM_CODED[k]
                if not kind or (kind == "number" and not Whole(v)) then return false end
            end
        end
        if tonumber(e.link:match("^|cnIQ(%d):|Hitem:[^|]*|h%[.*%]|h|r$")) ~= e.quality then return false end
    end
    return true
end

-- The record to save run `s` as, or nil and why not: then it is saved
-- as the table it is.
function ns.PackRun(s)
    local written = {}
    local code = ns.EncodeRun(s, written)
    local names = {}
    for i, e in ipairs(written) do
        local name = e.link:match("|h%[(.*)%]|h")
        if not name or name:find(NAME_END, 1, true) then return nil, "item name" end
        names[i] = name .. NAME_END
    end
    local record = { c = code, n = table.concat(names), m = s.names and #s.names or nil }
    local empty, x = {}, {}
    for k, v in pairs(s) do
        if not CODED[k] then
            x[k] = v
        elseif type(v) == "table" and next(v) == nil then
            empty[#empty + 1] = k
        end
    end
    table.sort(empty)
    record.e, record.x = empty[1] and empty or nil, next(x) and x or nil

    -- Checked before, and nothing has changed since: the code and the names
    -- are the same, and nothing a code cannot show has crept in.
    local known = packedAs[s]
    if known and known.c == record.c and known.n == record.n and known.m == record.m and Same(known.e, record.e)
            and Plain(s, written) then
        record.d = known.d
        packedAs[s] = record
        return record
    end

    local back, read = ns.UnpackRun(record)
    if not back then return nil, read end
    local absent = {}
    for key in pairs(CODED) do
        if s[key] == nil and back[key] ~= nil then
            absent[#absent + 1] = key
            back[key] = nil
        end
    end
    table.sort(absent)
    record.d = absent[1] and absent or nil
    local same, what = Lossless(s, back, written, read)
    if not same then return nil, what end
    packedAs[s] = record
    return record
end

local LISTS = { "history", "shared" }

-- When the saved data has loaded: every record becomes the run it holds.
-- Returns how many could not be read (they wait in db.unread).
function ns.UnpackRuns(db)
    -- Those set aside before get another try: this version may read them.
    local waiting = db.unread or {}
    db.unread = nil
    for _, item in ipairs(waiting) do
        if type(item) == "table" and db[item.from] and item.record then
            table.insert(db[item.from], item.record)
        end
    end
    local unread = 0
    for _, key in ipairs(LISTS) do
        local list, runs = db[key], {}
        for _, v in ipairs(list) do
            if IsPacked(v) then
                local ok, s = pcall(ns.UnpackRun, v)
                if ok and s then
                    packedAs[s] = v
                    runs[#runs + 1] = s
                else
                    db.unread = db.unread or {}
                    db.unread[#db.unread + 1] = { from = key, record = v }
                    unread = unread + 1
                end
            else
                runs[#runs + 1] = v
            end
        end
        for i = 1, math.max(#list, #runs) do list[i] = runs[i] end
        if #waiting > 0 then -- a run that came back goes where its date puts it
            table.sort(list, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
        end
    end
    return unread
end

-- When the game is about to save: every finished run that packs becomes
-- its record. A record stands in for its run until the game is gone
-- (anything still reading the run finds it behind the record); only the
-- record's own values are saved.
function ns.PackRuns(db)
    for _, key in ipairs(LISTS) do
        local list = db[key]
        for i, s in ipairs(list) do
            if type(s) == "table" and not IsPacked(s) and type(s.players) == "table" then
                local ok, record = pcall(ns.PackRun, s)
                if ok and record then list[i] = setmetatable(record, { __index = s }) end
            end
        end
    end
end

-- The game is torn down right after it saves, so nothing should follow
-- PackRuns. Should something follow all the same, the records become the
-- runs again, with whatever was written to them meanwhile.
local RECORD = { c = true, n = true, m = true, e = true, d = true, x = true }
function ns.WakeRuns(db)
    for _, key in ipairs(LISTS) do
        local list = db[key]
        for i, v in ipairs(list) do
            local behind = getmetatable(v)
            local s = behind and behind.__index
            if type(s) == "table" then
                for k, x in next, v do
                    if not RECORD[k] then s[k] = x end
                end
                list[i] = s
            end
        end
    end
end
