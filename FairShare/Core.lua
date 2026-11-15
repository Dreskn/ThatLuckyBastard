local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local issecret = issecretvalue or function() return false end

local RESUME_WINDOW = 1200 -- a run can be continued for 20 minutes after leaving or logging out
local ARRIVAL_GRACE = 10   -- seconds during which repeated arrival events count as one
local ROLL_MATCH_WINDOW = 5 -- a roll win and its loot line arrive within this many seconds
local CAPTURE_MAX = 600    -- lines kept by /fs capture
local LOG_MAX = 3000       -- pickups kept per run for the timeline

local PLAYER_NAME, PLAYER_CLASS
local db

-- The addon's look, in one place: its name in two tones, its accent
-- colour and its mark. tools/make_logo.py draws the mark in the same
-- colours.
ns.ACCENT = { 0.25, 0.78, 0.72 }
ns.ACCENT_HEX = "|cff40c7b8"
ns.BRAND = "|cffffffffFair|r" .. ns.ACCENT_HEX .. "Share|r"
ns.LOGO = "Interface\\AddOns\\FairShare\\Media\\logo.tga"

-- The title of every window: the mark, the name, then what the window
-- shows.
function ns.Title(sub)
    local text = ("|T%s:16:16:0:0|t %s"):format(ns.LOGO, ns.BRAND)
    if sub and sub ~= "" then text = text .. "  |cff707070/|r  " .. sub end
    return text
end

ns.OPTION_DEFAULTS = {
    portrait = "2d",     -- "3d", "2d", "class" or "none"
    showVendor = true,   -- vendor value under each player
    showShare = true,    -- share of the run and over/under an equal split
    showIcons = true,    -- item icons
    showBar = true,      -- share bar (Modern theme)
    showTotals = true,   -- total / equal split line
    showAwards = true,   -- end-of-run awards (Ninja, Luckiest, Jackpot, ...)
    showInsights = true, -- run time, dungeon records and comparison with your average
    ceremonySound = true,       -- sounds while the awards are revealed
    ceremonyScreenshot = false, -- take a screenshot once they are all shown
    podiumOnLeave = true, -- open the podium scene when a run ends
    bingo = true,        -- deal a loot bingo card each run and announce completed lines
    ticker = true,       -- on-screen notice when someone loots something valuable
    tickerMin = 50000,   -- copper: smallest pickup worth a notice
    alignItems = false,  -- put the same item on the same line in every column
    useColumns = true,   -- one column per player for groups of 5 or fewer
    scale = 1,           -- window scale
    -- Categories that are switched off are hidden, and left out of every
    -- total unless countHidden is on.
    cats = { epic = true, rare = true, uncommon = true, bop = true, quest = true, prof = true, other = true,
             junk = true },
    countHidden = false,
    valueMode = "market",   -- "market" (auction, vendor fallback) or "vendor"
    showSilver = true,      -- amounts smaller than the smallest shown unit
    showCopper = true,      -- are still displayed, so nothing reads as zero
    groupByCategory = true, -- off: every item in one list
    -- "role" (tank, healer, damage), "podium" (top looter in the middle),
    -- "value" or "name"
    sortPlayers = "role",
    selfFirst = false,      -- always put you first (ignored in podium order)
    -- "game" (follow the game's My Secondary Name setting), "full" or "first"
    nameStyle = "game",
    sortItems = "value",    -- "value" or "name"
    popupLeave = true,      -- open the window when leaving the instance alive
    chatSummary = false,    -- print a one-line result in chat when a run ends
    trackRaids = true,
    askNewRun = true,       -- ask "new run?" when arriving back in the current run's dungeon
    maxHistory = 30,
    familiar = true,        -- notice when someone you have run with joins your group
    tipPlayers = true,      -- a line about people you have run with, in their tooltip
    tipItems = true,        -- a line about items seen in your runs, in their tooltip
    streak = true,          -- recap when you chain runs with the same group or dungeon
    showMinimap = true,     -- minimap button
    minimapAngle = 215,     -- its position around the minimap, in degrees
}

local function Print(msg)
    print(ns.BRAND .. ": " .. msg)
end

----------------------------------------------------------------------
-- Loot chat parsing (built from the client's own format strings, so it
-- works in every locale)
----------------------------------------------------------------------

-- Turns one of the game's format strings into a Lua pattern. Also returns,
-- for each capture in turn, which format argument it is (`order`) and
-- whether it is text or a number (`types`: "s" or "d").
local function BuildPattern(fmt)
    if type(fmt) ~= "string" then return end
    local order, types, n = {}, {}, 0
    local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    pat = pat:gsub("%%(%d*)%%?%$?([sd])", function(i, t)
        n = n + 1
        order[n] = tonumber(i) or n
        types[n] = t
        return t == "s" and "(.+)" or "(%d+)"
    end)
    return "^" .. pat .. "$", order, types
end

-- Order matters: self before others, "multiple" before single.
local specs = {}
local function AddSpec(globalName, isSelf)
    local pat, order = BuildPattern(_G[globalName])
    if pat then
        specs[#specs + 1] = { pat = pat, order = order, self = isSelf }
    end
end
AddSpec("LOOT_ITEM_SELF_MULTIPLE", true)
AddSpec("LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", true)
AddSpec("LOOT_ITEM_SELF", true)
AddSpec("LOOT_ITEM_BONUS_ROLL_SELF", true)
AddSpec("LOOT_ITEM_MULTIPLE", false)
AddSpec("LOOT_ITEM_BONUS_ROLL_MULTIPLE", false)
AddSpec("LOOT_ITEM", false)
AddSpec("LOOT_ITEM_BONUS_ROLL", false)

-- "<instance> has been reset." (seen by the player who resets)
local resetPattern = BuildPattern(INSTANCE_RESET_SUCCESS)

-- Identifies an item regardless of who looted it (its item ID).
local function LinkKey(link)
    return link:match("item:(%d+)") or link
end
local function ItemKey(e)
    return LinkKey(e.link)
end
ns.ItemKey = ItemKey

----------------------------------------------------------------------
-- Roll messages. They arrive on the same channel as loot and tell us who
-- chose Need or Greed on an item and who won it.
--
-- The wording and the order of the arguments differ between game clients,
-- and the modern client starts every roll message with a "[Loot]" link
-- carrying the roll's id. So nothing here relies on argument positions:
-- the parts of a message are told apart by what they are (see ParseRoll).
-- `method` is set when the message itself says how the item was won.
-- Disenchant and transmog rolls count as Greed: rolled for, but not Need.
----------------------------------------------------------------------

local rollSpecs = {}
local function AddRollSpec(globalName, kind, method)
    local fmt = _G[globalName]
    local pat, order, types = BuildPattern(fmt)
    if pat then
        rollSpecs[#rollSpecs + 1] = {
            pat = pat, order = order, types = types, kind = kind, method = method,
            hasID = fmt:find("lootHistory:", 1, true) ~= nil, -- first number is the roll's id
        }
    end
end
-- Order matters: messages about you before the same message about others.
-- "X won: [item] (Need - 54)": the short form, which states the method.
AddRollSpec("LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", "need")
AddRollSpec("LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", "greed")
AddRollSpec("LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", "greed")
AddRollSpec("LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG", "won", "greed")
AddRollSpec("LOOT_ROLL_WON_NO_SPAM_NEED", "won", "need")
AddRollSpec("LOOT_ROLL_WON_NO_SPAM_GREED", "won", "greed")
AddRollSpec("LOOT_ROLL_WON_NO_SPAM_DE", "won", "greed")
AddRollSpec("LOOT_ROLL_WON_NO_SPAM_TRANSMOG", "won", "greed")
-- "X has selected Need for: [item]" and "Need Roll - 54 for [item] by X".
AddRollSpec("LOOT_ROLL_NEED_SELF", "select", "need")
AddRollSpec("LOOT_ROLL_GREED_SELF", "select", "greed")
AddRollSpec("LOOT_ROLL_DISENCHANT_SELF", "select", "greed")
AddRollSpec("LOOT_ROLL_TRANSMOG_SELF", "select", "greed")
AddRollSpec("LOOT_ROLL_NEED", "select", "need")
AddRollSpec("LOOT_ROLL_GREED", "select", "greed")
AddRollSpec("LOOT_ROLL_DISENCHANT", "select", "greed")
AddRollSpec("LOOT_ROLL_TRANSMOG", "select", "greed")
AddRollSpec("LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "select", "need")
AddRollSpec("LOOT_ROLL_ROLLED_NEED", "select", "need")
AddRollSpec("LOOT_ROLL_ROLLED_GREED", "select", "greed")
AddRollSpec("LOOT_ROLL_ROLLED_DE", "select", "greed")
AddRollSpec("LOOT_ROLL_ROLLED_TRANSMOG", "select", "greed")
-- "X passed on: [item]".
AddRollSpec("LOOT_ROLL_PASSED_SELF", "pass")
AddRollSpec("LOOT_ROLL_PASSED", "pass")
-- "X won: [item]": the method comes from what the winner selected.
AddRollSpec("LOOT_ROLL_YOU_WON", "won")
AddRollSpec("LOOT_ROLL_WON", "won")

-- Returns kind ("select", "won" or "pass"), method ("need", "greed" or
-- nil), player name, item key, the number rolled (when the message gives
-- one) and the roll's id (on clients that send one); or nothing if the
-- text is not a roll message.
--
-- Of a message's parts, the item is the text holding an item link, the
-- player is the other text (none: the message is about you), and the
-- number rolled is the only number, or the second one when the message
-- starts with the roll's id.
local function ParseRoll(text)
    for _, spec in ipairs(rollSpecs) do
        local c = { text:match(spec.pat) }
        if #c > 0 then
            local link, name
            local numbers = {}
            for k, value in ipairs(c) do
                if spec.types[k] == "d" then
                    numbers[#numbers + 1] = { arg = spec.order[k], value = tonumber(value) }
                elseif value:find("|Hitem:", 1, true) then
                    link = value
                else
                    name = value
                end
            end
            if not link then return end
            table.sort(numbers, function(x, y) return x.arg < y.arg end)
            local roll = numbers[spec.hasID and 2 or 1]
            local id = spec.hasID and numbers[1] or nil
            return spec.kind, spec.method, name or PLAYER_NAME, LinkKey(link), roll and roll.value,
                id and id.value
        end
    end
end

local function ParseLoot(text)
    for _, spec in ipairs(specs) do
        local c = { text:match(spec.pat) }
        if #c > 0 then
            local a = {}
            for k, idx in ipairs(spec.order) do a[idx] = c[k] end
            if spec.self then
                return PLAYER_NAME, a[1], tonumber(a[2]) or 1
            end
            return a[1], a[2], tonumber(a[3]) or 1
        end
    end
end

----------------------------------------------------------------------
-- Item valuation
----------------------------------------------------------------------

local function AuctionPrice(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemLink then
        local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    if TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue then
        local ok, price = pcall(function()
            local itemString = TSM_API.ToItemString(link)
            return itemString and TSM_API.GetCustomPriceValue("dbmarket", itemString)
        end)
        if ok and type(price) == "number" and price > 0 then return price end
    end
end
ns.AuctionPrice = AuctionPrice

-- True when an addon that can supply auction prices is loaded.
function ns.HasPriceSource()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemLink then return true end
    return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

local function Categorize(quality, classID, bindType)
    if bindType == 4 or classID == 12 then return "quest" end -- quest items
    if bindType == 1 then return "bop" end                     -- bind on pickup
    if classID == 7 then return "prof" end                  -- trade goods
    if quality == 0 then return "junk" end
    if bindType == 2 then
        if quality >= 4 then return "epic" end
        if quality == 3 then return "rare" end
        if quality == 2 then return "uncommon" end
    end
    return "other"
end

local function FillItem(e)
    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, bindType = GetItemInfo(e.link)
    if not quality then return false end
    e.quality = quality
    e.vendor = sellPrice or 0
    e.cat = Categorize(quality, classID, bindType)
    -- Bound and quest items cannot be sold on the auction house.
    e.ah = (e.cat ~= "bop" and e.cat ~= "quest") and AuctionPrice(e.link) or nil
    e.resolved = true
    return true
end

local function ResolveItem(e)
    if FillItem(e) then return end
    if not Item or not Item.CreateFromItemLink then return end
    local item = Item:CreateFromItemLink(e.link)
    if item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
        FillItem(e)
        ns.Refresh()
    end)
end

----------------------------------------------------------------------
-- Sessions
----------------------------------------------------------------------

local function AddPlayer(s, name, class)
    local p = s.players[name]
    if not p then
        p = { items = {} }
        s.players[name] = p
    end
    if class and not p.class then p.class = class end
    return p
end

local function Tracking(s)
    return s and (s.manual or not s.leftAt)
end

local function SetRole(p, unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" and not issecret(role) then p.role = role end
end

-- What a player looks like, saved while they are around so that their
-- picture can be rebuilt once the group is gone: race, sex and the gear
-- that shows. The game does not tell us faces or hair. Other players'
-- gear is only readable when they are close by, so a slot keeps the last
-- thing seen in it.
local LOOK_SLOTS = { 1, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 16, 17 } -- head to feet, then weapons

local function SaveLook(p, unit)
    local _, raceFile, raceID = UnitRace(unit)
    if type(raceFile) == "string" and not issecret(raceFile) and not issecret(raceID) then
        p.race, p.raceID = raceFile, raceID
    end
    local sex = UnitSex(unit)
    if type(sex) == "number" and not issecret(sex) and sex > 1 then p.sex = sex end -- 2 male, 3 female
    if not GetInventoryItemID then return end
    for _, slot in ipairs(LOOK_SLOTS) do
        local id = GetInventoryItemID(unit, slot)
        if type(id) == "number" and not issecret(id) then
            p.gear = p.gear or {}
            p.gear[slot] = id
        end
    end
end

local function UpdateRoster()
    local s = db.active
    if not Tracking(s) or not PLAYER_NAME then return end
    local me = AddPlayer(s, PLAYER_NAME, PLAYER_CLASS)
    SetRole(me, "player")
    SaveLook(me, "player")
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = GetUnitName(unit, true)
            if name and not issecret(name) and name ~= UNKNOWNOBJECT then
                local _, class = UnitClass(unit)
                if issecret(class) then class = nil end
                local p = AddPlayer(s, name, class)
                SetRole(p, unit)
                SaveLook(p, unit)
            end
        end
    end
    ns.Refresh()
end

local function HasLoot(s)
    for _, p in pairs(s.players) do
        if next(p.items) then return true end
    end
    return false
end

-- Drops the oldest runs beyond the number to keep. Pinned runs are never
-- dropped and do not count towards that number.
function ns.TrimHistory()
    local unpinned = 0
    for _, s in ipairs(db.history) do
        if not s.pinned then unpinned = unpinned + 1 end
    end
    for i = #db.history, 1, -1 do
        if unpinned <= db.options.maxHistory then break end
        if not db.history[i].pinned then
            table.remove(db.history, i)
            unpinned = unpinned - 1
        end
    end
end

local PrintSummary -- defined below
local CommitRun    -- defined with the records code, further down

local function FinalizeSession()
    local s = db.active
    if not s then return end
    PrintSummary(s) -- no-op if already printed or switched off
    db.active = nil
    s.endedAt = s.leftAt or time()
    s.rolls, s.pendingWins = nil, nil -- only of use while the run is going
    if HasLoot(s) then
        table.insert(db.history, 1, s)
        ns.TrimHistory()
        -- Records and regulars are extras: a fault there must never cost
        -- the run itself, which is already safely in the history.
        local ok, err = pcall(CommitRun, s)
        if not ok then Print("could not update records: " .. tostring(err)) end
    end
end

local function NewSession(name, instanceID, manual)
    FinalizeSession()
    db.active = {
        name = name or "Run",
        instanceID = instanceID,
        manual = manual or nil,
        startedAt = time(),
        enteredAt = time(), -- last time we arrived in the instance
        lastSeen = time(),  -- last loot, or logout
        players = {},
    }
    UpdateRoster()
end

local function CoinText(copper)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    copper = math.floor(copper + 0.5)
    return fn and fn(copper) or (math.floor(copper / 10000) .. "g")
end

-- Optional one-line result in the chat window when a run ends.
function PrintSummary(s)
    if not s or s.summarized or not db.options.chatSummary then return end
    local sum = ns.Summarize(s)
    local n = #sum.players
    if n == 0 or sum.market <= 0 then return end
    for _, p in ipairs(sum.players) do
        if p.name == PLAYER_NAME then
            s.summarized = true
            Print(("%s: you looted %s (%.0f%%). An equal split would be %s."):format(
                s.name or "Run", CoinText(p.market), p.market / sum.market * 100, CoinText(sum.market / n)))
            return
        end
    end
end

-- Asked when you arrive in the dungeon of the current run without having
-- died out of it: it may be the same run, or a new one after a reset or
-- a requeue. Until answered (or if the answer is No, or the prompt times
-- out) the current run simply continues.
local promptSession
StaticPopupDialogs["FAIRSHARE_NEW_RUN"] = {
    text = "FairShare\n\nIs this a new run of %s?\n\n|cff909090No keeps adding to the previous run.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local s = db.active
        -- Only if that run is still the current one and we are still inside.
        if s and s == promptSession and not s.leftAt then
            local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
            NewSession(name, instanceID)
            ns.Refresh()
        end
    end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AskNewRun(s)
    promptSession = s
    StaticPopup_Show("FAIRSHARE_NEW_RUN", s.name or "this dungeon")
end

-- Several events can report the same arrival, so only ask once per arrival.
local function MaybeAsk(s)
    if not db.options.askNewRun then return end
    if time() - (s.enteredAt or 0) < ARRIVAL_GRACE then return end
    s.enteredAt = time()
    AskNewRun(s)
end

-- Back inside the dungeon of the current run.
local function Continue(s)
    if s.leftAt then
        s.summarized = nil
        s.enteredAt = time()
    end
    s.leftAt, s.leftDead = nil, nil
    UpdateRoster()
end

-- The rules, in full:
--   * A run belongs to one instance. Arriving in a different one, or with
--     no run in progress, starts a new run.
--   * Leaving alive opens the window. Leaving dead does nothing.
--   * Coming back within RESUME_WINDOW continues the run: silently after
--     a death, and with a "new run?" question otherwise. With the
--     question switched off, coming back alive starts a new run.
--   * A run that was left is closed once RESUME_WINDOW has passed, or as
--     soon as the instance is reset.
--
-- isLogin: a fresh login. entered: arrived through a loading screen that
-- was neither a login nor a reload. Both are nil for plain zone changes.
local function CheckZone(isLogin, entered)
    local s = db.active
    if s and s.manual then return end

    local inInstance, instanceType = IsInInstance()
    local tracked = inInstance
        and (instanceType == "party" or (instanceType == "raid" and db.options.trackRaids))

    if tracked then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if not s or s.instanceID ~= instanceID then
            NewSession(name, instanceID)
        elseif s.leftAt then
            local recent = time() - s.leftAt < RESUME_WINDOW
            if recent and s.leftDead then
                Continue(s)
            elseif recent and db.options.askNewRun then
                Continue(s)
                AskNewRun(s)
            else
                NewSession(name, instanceID)
            end
        elseif isLogin and time() - (s.lastSeen or 0) > RESUME_WINDOW then
            NewSession(name, instanceID) -- logged back in long after the run
        else
            -- Never left: a reload, a relog, or moving around inside. A
            -- loading screen here means a requeue into the same dungeon.
            Continue(s)
            if entered then MaybeAsk(s) end
        end
    elseif s then
        if s.leftAt then
            if time() - s.leftAt > RESUME_WINDOW then FinalizeSession() end
        elseif isLogin then
            -- Logged out inside and came back outside: the run ended some
            -- time ago, so close it quietly.
            s.leftAt = s.lastSeen
            s.summarized = true
            FinalizeSession()
        else
            s.leftAt = time()
            s.leftDead = UnitIsDeadOrGhost("player") or nil
            if not s.leftDead then
                PrintSummary(s)
                -- The breakdown window, and on top of it the podium. Only one
                -- of the two plays the reveal.
                local podium = db.options.podiumOnLeave
                if db.options.popupLeave then ns.ShowWindow(not podium) end
                if podium then ns.OpenShow(s, true) end
                if ns.StreakNotice then pcall(ns.StreakNotice, s) end
            end
        end
    end
end

-- Moves roll wins from `wins` ({ need = n, greed = n }) onto an item
-- entry, as far as the entry has copies not yet accounted for. An entry's
-- `need` / `greed` fields count how many of its copies were won that way.
local function TagWin(e, wins)
    for _, method in ipairs({ "need", "greed" }) do
        local free = e.count - (e.need or 0) - (e.greed or 0)
        local n = math.min(wins[method] or 0, free)
        if n > 0 then
            e[method] = (e[method] or 0) + n
            wins[method] = wins[method] - n
        end
    end
end

-- Live ticker: a short on-screen notice (never a chat message) when a
-- pickup is worth at least the chosen amount. The item's value may not be
-- known the instant it is looted, so an unresolved item is retried once.
local function AnnounceLoot(s, name, e, count)
    if not db.options.ticker or not ns.Toast then return end
    local function show()
        if not e.resolved or e.count <= 0 then return end
        local value = ns.EntryMarket(e) / e.count * count
        if value >= db.options.tickerMin then
            local p = s.players[name]
            ns.Toast(name, p and p.class, e.link, count, value)
        end
    end
    if e.resolved then show() else C_Timer.After(1.5, show) end
end

-- Players are named by a small number in the run's two logs (pickups
-- and rolls), to keep the saved file small: s.names[index] = name.
local function NameIndex(s, name)
    s.names = s.names or {}
    for i, n in ipairs(s.names) do
        if n == name then return i end
    end
    s.names[#s.names + 1] = name
    return #s.names
end

-- The pickup log, for the timeline: one short text per pickup,
-- "seconds since the start:player:entry:count". An entry is the item
-- record in the player's `items`, found again by its `id`.
local function LogPickup(s, name, e, count)
    s.log = s.log or {}
    if #s.log >= LOG_MAX then return end
    s.log[#s.log + 1] = ("%d:%d:%d:%d"):format(math.max(time() - s.startedAt, 0), NameIndex(s, name), e.id, count)
end

local function RecordLoot(name, rawLink, count)
    local s = db.active
    if not Tracking(s) then return end
    local link = rawLink:match("(|c.-|Hitem:.-|h.-|h|r)") or rawLink:match("(|Hitem:.-|h.-|h)")
    if not link then return end
    local key = link:match("|H(item:[^|]+)|h") or link
    local p = AddPlayer(s, name)
    local e = p.items[key]
    if not e then
        e = { link = link, count = 0, vendor = 0, cat = "other" }
        p.items[key] = e
        ResolveItem(e)
    end
    if not e.id then
        s.nextId = (s.nextId or 0) + 1
        e.id = s.nextId
    end
    e.count = e.count + count
    e.lastAt = time()
    LogPickup(s, name, e, count)
    -- If this player just won a roll on this item, note how it was won.
    local wins = s.pendingWins and s.pendingWins[name] and s.pendingWins[name][ItemKey(e)]
    if wins then
        TagWin(e, wins)
    end
    AnnounceLoot(s, name, e, count)
    s.lastSeen = time()
    -- Looting happens next to the others: a good moment to note their gear.
    if time() - (s.lookedAt or 0) >= 60 then
        s.lookedAt = time()
        UpdateRoster()
    end
    ns.Refresh()
    if ns.BingoCheck then ns.BingoCheck() end
end

-- A roll in progress: who chose what and who rolled what. `rk` tells
-- rolls apart: the roll's own id where the client sends one (two copies
-- of the same item are then two rolls), the item otherwise.
local function OpenRoll(s, rk, key)
    s.rolls = s.rolls or {}
    local r = s.rolls[rk]
    if not r then
        r = { key = key, t = math.max(time() - s.startedAt, 0), need = {}, greed = {} }
        s.rolls[rk] = r
    end
    r.key, r.pass, r.num = r.key or key, r.pass or {}, r.num or {}
    return r
end

-- The roll log, for the roll sheet and the luck figures: one record per
-- roll that someone won.
--   { k = item key, t = seconds since the start, w = winner, m = "n" or
--     "g" (won on Need or Greed), r = "1n54,3g12,4p" }
-- `w` and the numbers leading each part of `r` are indexes into s.names;
-- each part is a player, what they chose (n, g, or p for pass) and the
-- number they rolled, when the game told us.
local function LogRoll(s, r, winner, method)
    local parts, seen = {}, {}
    local function add(name, code)
        if seen[name] then return end
        seen[name] = true
        parts[#parts + 1] = NameIndex(s, name) .. code .. (r.num[name] or "")
    end
    add(winner, method == "need" and "n" or "g")
    for name in pairs(r.need) do add(name, "n") end
    for name in pairs(r.greed) do add(name, "g") end
    for name in pairs(r.pass) do add(name, "p") end
    s.rollLog = s.rollLog or {}
    s.rollLog[#s.rollLog + 1] = {
        k = r.key, t = r.t, w = NameIndex(s, winner), m = method == "need" and "n" or "g",
        r = table.concat(parts, ","),
    }
end

-- `name` won `key`. The "receives loot" line for it usually follows, but
-- may also have arrived just before, so both orders are handled.
local function RecordRollWin(s, name, key, method, rk)
    local r = s.rolls and s.rolls[rk]
    if not method and r then
        method = (r.need[name] and "need") or (r.greed[name] and "greed") or nil
    end
    if s.rolls then s.rolls[rk] = nil end
    if not method then return end
    if r then LogRoll(s, r, name, method) end

    local wins = { [method] = 1 }
    local p = s.players[name]
    if p then
        for _, e in pairs(p.items) do
            if ItemKey(e) == key and e.lastAt and time() - e.lastAt <= ROLL_MATCH_WINDOW then
                TagWin(e, wins)
                break
            end
        end
    end
    if wins[method] > 0 then
        s.pendingWins = s.pendingWins or {}
        s.pendingWins[name] = s.pendingWins[name] or {}
        local pending = s.pendingWins[name][key] or {}
        pending[method] = (pending[method] or 0) + 1
        s.pendingWins[name][key] = pending
    end
    ns.Refresh()
end

-- Per-player roll figures for the awards: numbers rolled and passes.
local function RollStats(s, name)
    s.rollStats = s.rollStats or {}
    local st = s.rollStats[name]
    if not st then
        st = { sum = 0, n = 0, passes = 0 }
        s.rollStats[name] = st
    end
    return st
end

local function HandleRoll(text)
    local s = db.active
    if not Tracking(s) then return end
    local kind, method, name, key, roll, rollID = ParseRoll(text)
    if not kind then return end
    local rk = rollID and ("#" .. rollID) or key
    local r = OpenRoll(s, rk, key)
    if roll then
        local st = RollStats(s, name)
        st.sum, st.n = st.sum + roll, st.n + 1
        if not st.high or roll > st.high then st.high = roll end
        if not st.low or roll < st.low then st.low = roll end
        r.num[name] = roll
        -- Remembered for the bingo card.
        if roll >= 95 then s.rollHigh = true end
        if roll <= 5 then s.rollLow = true end
    end
    if kind == "select" then
        r[method][name] = true
    elseif kind == "won" then
        RecordRollWin(s, name, key, method, rk)
    elseif kind == "pass" then
        if not r.pass[name] then
            r.pass[name] = true
            local st = RollStats(s, name)
            st.passes = st.passes + 1
        end
    end
    if ns.BingoCheck then ns.BingoCheck() end
end

----------------------------------------------------------------------
-- Capture: records raw loot-channel lines so the message formats of
-- this client can be inspected. Toggled with /fs capture.
----------------------------------------------------------------------

local function Capture(channel, text)
    if not db.capturing or #db.capture >= CAPTURE_MAX then return end
    db.capture[#db.capture + 1] = date("%H:%M:%S") .. " " .. channel .. " " .. text
end

----------------------------------------------------------------------
-- Summary used by the window
----------------------------------------------------------------------

-- The value used for totals, shares and sorting. `e.noAH` is set by
-- Summarize when the player has switched this item to its vendor price.
local function EntryMarket(e)
    if db.options.valueMode == "vendor" or e.noAH then return e.vendor * e.count end
    return (e.ah or e.vendor) * e.count
end
ns.EntryMarket = EntryMarket

-- Switches an item between its auction and vendor price for one run. It
-- applies to every copy of the item in that run, whoever looted it.
function ns.ToggleAuctionPrice(s, e)
    if not e.ah then return false end
    local key = ItemKey(e)
    s.vendorOnly = s.vendorOnly or {}
    s.vendorOnly[key] = (not s.vendorOnly[key]) or nil
    return true
end

local function ItemName(e)
    return e.link:match("%[(.-)%]") or ""
end
ns.ItemName = ItemName

-- needOnly: count only the copies of each item that were won on a Need
-- roll. Entries are then stand-ins that carry the reduced count and read
-- everything else from the real entry.
function ns.Summarize(s, needOnly)
    local o = db.options
    local out = { players = {}, count = 0, vendor = 0, market = 0, needOnly = needOnly }
    for name, p in pairs(s.players) do
        local ps = { name = name, class = p.class, role = p.role, count = 0, vendor = 0, market = 0, cats = {},
                     -- the saved look, for pictures once the group is gone
                     race = p.race, raceID = p.raceID, sex = p.sex, gear = p.gear,
                     -- for the awards: value won on Need / Greed rolls, and the best single item
                     needValue = 0, greedValue = 0, bestValue = 0,
                     -- also used by the bingo card: rolls won, and the best item quality
                     needWins = 0, greedWins = 0, bestQuality = 0,
                     -- every shown item in one group, for the ungrouped layout
                     all = { items = {} } }
        for _, real in pairs(p.items) do
            if not real.resolved then FillItem(real) end
            real.noAH = (s.vendorOnly and s.vendorOnly[ItemKey(real)]) or nil
            if real.count > 0 and o.cats[real.cat] ~= false then
                local unit = EntryMarket(real) / real.count
                ps.needValue = ps.needValue + unit * (real.need or 0)
                ps.greedValue = ps.greedValue + unit * (real.greed or 0)
                if unit > ps.bestValue then ps.bestValue, ps.bestLink = unit, real.link end
                ps.needWins = ps.needWins + (real.need or 0)
                ps.greedWins = ps.greedWins + (real.greed or 0)
                if (real.quality or 0) > ps.bestQuality then ps.bestQuality = real.quality end
            end
            local e = real
            if needOnly then
                e = setmetatable({ count = real.need or 0 }, { __index = real })
            end
            local v, m = e.vendor * e.count, EntryMarket(e)
            local shown = e.count > 0 and o.cats[e.cat] ~= false
            if shown then
                local c = ps.cats[e.cat]
                if not c then
                    c = { items = {}, count = 0, vendor = 0, market = 0 }
                    ps.cats[e.cat] = c
                end
                c.items[#c.items + 1] = e
                c.count, c.vendor, c.market = c.count + e.count, c.vendor + v, c.market + m
                ps.all.items[#ps.all.items + 1] = e
            end
            if shown or o.countHidden then
                ps.count, ps.vendor, ps.market = ps.count + e.count, ps.vendor + v, ps.market + m
            end
        end
        do
            local function ItemOrder(a, b)
                -- Quest items go last however the rest is ordered.
                local qa, qb = a.cat == "quest", b.cat == "quest"
                if qa ~= qb then return qb end
                if o.sortItems == "name" then
                    local na, nb = ItemName(a), ItemName(b)
                    if na ~= nb then return na < nb end
                end
                local ma, mb = EntryMarket(a), EntryMarket(b)
                if ma ~= mb then return ma > mb end
                return a.link < b.link
            end
            for _, c in pairs(ps.cats) do table.sort(c.items, ItemOrder) end
            table.sort(ps.all.items, ItemOrder)
        end
        out.players[#out.players + 1] = ps
        out.count, out.vendor, out.market = out.count + ps.count, out.vendor + ps.vendor, out.market + ps.market
    end
    -- Rank by value first (1 = most loot); "value" and "podium" keep this order.
    table.sort(out.players, function(a, b)
        if a.market ~= b.market then return a.market > b.market end
        return a.name < b.name
    end)
    for i, p in ipairs(out.players) do p.rank = i end

    local mode = o.sortPlayers
    if mode == "name" then
        table.sort(out.players, function(a, b) return a.name < b.name end)
    elseif mode == "role" then
        local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
        table.sort(out.players, function(a, b)
            local ra, rb = order[a.role] or 4, order[b.role] or 4
            if ra ~= rb then return ra < rb end
            return a.name < b.name
        end)
    end
    if o.selfFirst and mode ~= "podium" then
        for i, p in ipairs(out.players) do
            if p.name == PLAYER_NAME then
                table.insert(out.players, 1, table.remove(out.players, i))
                break
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Awards, shown at the end of a run.
--
-- Every player gets exactly one award: the one that fits them best. Each
-- award says how well a player fits it, as how far they are from what is
-- normal: 0.3 just qualifies, 1 is remarkable, and it keeps rising to
-- about 2 for the extraordinary. So an average roll of 51 earns nothing,
-- and an average of 99 beats nearly everything. That figure is multiplied
-- by the award's weight, and the best fits are served first: an award
-- goes to one player only, so the others move on to their next best.
-- Anyone left without one is a Tourist.
--
-- Ninja and Luckiest weigh more than the rest, so they usually win when
-- someone earns them, but a more striking award can still take their
-- place.
--
-- fit(p, x, g) returns the fit, or nil when the player does not qualify.
--   p  the player's summary (see Summarize)
--   x  their roll figures: rolls, avgRoll, luck, high, low, passes
--   g  the group's figures: n (players), total and equal (the run's loot
--      and an equal share of it), vendor (the run's loot at vendor
--      prices), best / need / greed / count (the highest single item, Need
--      value, Greed value and item count of any player), least (the
--      smallest haul), and the run's totals: items, junk and quest (item
--      counts), greedAll (value won on Greed rolls) and prof (value of
--      profession materials)
-- detail(p, x, g) returns the text / item / amount shown with the award.
-- `how` is the rule in plain words, for the tooltip and the awards guide:
-- keep it to one line of the guide (about 90 characters) and in step with
-- fit.
----------------------------------------------------------------------

local NINJA_MIN = 10000   -- copper: Need wins below this never make a Ninja
local JACKPOT_MIN = 10000 -- copper: smallest item worth calling a jackpot
local FARMER_MIN = 1000   -- copper: profession materials below this do not make a Farmer
local DICE_MIN_ROLLS = 3  -- rolls needed before the dice awards apply

-- How well `v` fits a scale on which `lo` just qualifies and `hi` is
-- remarkable: 0.3 at `lo`, 1 at `hi`, and on up to about 2 for values far
-- beyond `hi`. Nil below `lo`.
local function Fit(v, lo, hi)
    if v < lo then return end
    return 0.3 + 0.7 * math.min((v - lo) / (hi - lo), 2.5)
end

-- How far an average of `n` rolls is from what chance gives, in standard
-- deviations: 0 is average, 2 happens about once in 40 tries, 3 once in
-- 700. Rolls run from 1 to 100: mean 50.5, standard deviation 28.87.
-- Counting the number of rolls is what makes an average of 70 over 15
-- rolls worth more than the same average over 3.
local function RollLuck(avg, n)
    return (avg - 50.5) * math.sqrt(n) / 28.87
end

local function Percent(x)
    return math.floor(x * 100 + 0.5)
end

local AWARDS = {
    -- Bound gear counts at vendor price, so Ninja mostly reflects needing
    -- things that can be sold.
    { key = "ninja", title = "Ninja", icon = "Ability_Stealth", weight = 1.5,
      how = "Won the most value on Need rolls: at least 1g, and a tenth of the run's loot.",
      fit = function(p, _, g)
          if p.needValue < g.need or p.needValue < NINJA_MIN then return end
          return Fit(p.needValue / g.total, 0.1, 0.3)
      end,
      detail = function(p) return { text = "Most value won on Need rolls", amount = p.needValue } end },
    { key = "lucky", title = "Luckiest", icon = "INV_Misc_Coin_02", weight = 1.5,
      how = "Won the most on Greed rolls, clearly more than an even split of what was rolled for.",
      fit = function(p, _, g)
          if p.greedValue <= 0 or p.greedValue < g.greed then return end
          -- What they won beyond an even split of the Greed loot, measured
          -- against an equal share of the whole run.
          return Fit((p.greedValue - g.greedAll / g.n) / g.equal, 0.1, 0.6)
      end,
      detail = function(p) return { text = "Most value won on Greed rolls", amount = p.greedValue } end },
    { key = "jackpot", title = "Jackpot", icon = "INV_Misc_Gem_Diamond_02",
      how = "Got the most valuable single item of the run, worth 1g or more.",
      fit = function(p, _, g)
          if p.bestValue < g.best or p.bestValue < JACKPOT_MIN then return end
          return Fit(p.bestValue / g.total, 0, 0.3)
      end,
      detail = function(p) return { text = "Best single item of the run", link = p.bestLink, amount = p.bestValue } end },
    { key = "lionshare", title = "Lion's Share", icon = "Ability_Druid_CatForm", minPlayers = 3,
      how = "Top looter with far more than an equal share: 36% of the loot or more in a group of five.",
      -- Where their share sits between an equal one (0) and everything (1).
      fit = function(p, _, g)
          if p.rank ~= 1 then return end
          return Fit((p.market / g.total - 1 / g.n) / (1 - 1 / g.n), 0.2, 0.5)
      end,
      detail = function(p, _, g)
          return { text = ("Took %d%% of the run's loot"):format(Percent(p.market / g.total)), amount = p.market }
      end },
    { key = "fairshare", title = "Fair Share", icon = "INV_Misc_Coin_05", minPlayers = 3,
      how = "Ended within a tenth of a perfectly equal share. Groups of 3 or more.",
      fit = function(p, _, g) return Fit(1 - math.abs(p.market - g.equal) / g.equal, 0.9, 1) end,
      detail = function(p, _, g)
          return { text = ("%d%% of the loot, in a group of %d"):format(Percent(p.market / g.total), g.n),
                   amount = p.market }
      end },
    { key = "empty", title = "Empty Pockets", icon = "INV_Misc_Bag_08", minPlayers = 3,
      how = "Got the least loot, well below an equal share. Groups of 3 or more.",
      fit = function(p, _, g)
          if p.market > g.least then return end
          return Fit(1 - p.market / g.equal, 0.2, 1)
      end,
      detail = function(p) return { text = "Least loot of the group", amount = p.market } end },
    { key = "onehit", title = "One-Hit Wonder", icon = "INV_Misc_Gem_Ruby_01",
      how = "One item makes up 70% or more of everything they got (3 items or more).",
      fit = function(p)
          if p.count < 3 or p.market <= 0 then return end
          return Fit(p.bestValue / p.market, 0.7, 1)
      end,
      detail = function(p)
          return { text = ("%d%% of their loot is one item"):format(Percent(p.bestValue / p.market)),
                   link = p.bestLink, amount = p.bestValue }
      end },
    { key = "purple", title = "Purple Rain", icon = "INV_Misc_Gem_Amethyst_02",
      how = "Looted an epic item.",
      fit = function(p) return p.bestQuality >= 4 and 1 or nil end,
      detail = function(p)
          local best
          for _, e in ipairs(p.all.items) do
              if (e.quality or 0) >= 4 and (not best or e.vendor > best.vendor) then best = e end
          end
          return { text = "Looted an epic item", link = best and best.link }
      end },
    { key = "farmer", title = "The Farmer", icon = "INV_Misc_Pelt_Wolf_01",
      how = "Took a large part of the run's profession materials: skins, herbs, ore, cloth.",
      fit = function(p, _, g)
          local prof = p.cats.prof and p.cats.prof.market or 0
          if prof < FARMER_MIN then return end
          local lo = math.max(0.4, 1.5 / g.n)
          return Fit(prof / g.prof, lo, lo + 0.4)
      end,
      detail = function(p, _, g)
          local prof = p.cats.prof.market
          return { text = ("%d%% of the run's profession materials"):format(Percent(prof / g.prof)), amount = prof }
      end },
    { key = "packmule", title = "Pack Mule", icon = "INV_Misc_Bag_07",
      how = "Picked up the most items, well above the group's average, yet ended below an equal share.",
      fit = function(p, _, g)
          if p.count < 10 or p.count < g.count or p.market >= g.equal then return end
          return Fit(p.count / (g.items / g.n), 1.3, 2.5)
      end,
      detail = function(p) return { text = ("%d items, and still below an equal share"):format(p.count) } end },
    { key = "hoarder", title = "Hoarder", icon = "INV_Misc_Bag_10",
      how = "Picked up 5 or more pieces of junk, at least half again as many as the group's average.",
      fit = function(p, _, g)
          local junk = p.cats.junk and p.cats.junk.count or 0
          if junk < 5 then return end
          return Fit(junk / (g.junk / g.n), 1.5, 3)
      end,
      detail = function(p) return { text = ("Picked up %d pieces of junk"):format(p.cats.junk.count) } end },
    { key = "vendor", title = "Vendor's Friend", icon = "INV_Misc_Coin_06",
      how = "Got nothing worth auctioning (4 items or more), in a run where the others did.",
      fit = function(p, _, g)
          if db.options.valueMode == "vendor" or not ns.HasPriceSource() then return end
          if p.count < 4 or p.market <= 0 or p.vendor < p.market * 0.95 then return end
          -- The more of the run's value is above vendor price, the more it stands out.
          return Fit(1 - g.vendor / g.total, 0.2, 0.6)
      end,
      detail = function(p) return { text = "Nothing worth putting up for auction", amount = p.market } end },
    { key = "errand", title = "Errand Runner", icon = "INV_Misc_Note_01",
      how = "Picked up 3 or more quest items, at least half again as many as the group's average.",
      fit = function(p, _, g)
          local quest = p.cats.quest and p.cats.quest.count or 0
          if quest < 3 then return end
          return Fit(quest / (g.quest / g.n), 1.5, 3)
      end,
      detail = function(p) return { text = ("Picked up %d quest items"):format(p.cats.quest.count) } end },
    { key = "nat100", title = "Natural 100", icon = "INV_Crown_01",
      how = "Rolled a 100.",
      fit = function(_, x) return x.high == 100 and 0.75 or nil end,
      detail = function() return { text = "Rolled a 100" } end },
    { key = "snakeeyes", title = "Snake Eyes", icon = "INV_Misc_Bone_HumanSkull_01",
      how = "Rolled a 1.",
      fit = function(_, x) return x.low == 1 and 0.75 or nil end,
      detail = function() return { text = "Rolled a 1" } end },
    { key = "hotdice", title = "Loaded Dice", icon = "INV_Misc_Dice_02",
      how = "Average roll well above 50: about 60 over 15 rolls, or 68 over 5.",
      fit = function(_, x) return x.rolls >= DICE_MIN_ROLLS and Fit(x.luck, 1.3, 2.6) or nil end,
      detail = function(_, x) return { text = ("Average roll of %d over %d rolls"):format(x.avgRoll, x.rolls) } end },
    { key = "colddice", title = "Cursed Dice", icon = "INV_Misc_Dice_01",
      how = "Average roll well below 50: about 41 over 15 rolls, or 33 over 5.",
      fit = function(_, x) return x.rolls >= DICE_MIN_ROLLS and Fit(-x.luck, 1.3, 2.6) or nil end,
      detail = function(_, x) return { text = ("Average roll of %d over %d rolls"):format(x.avgRoll, x.rolls) } end },
    { key = "window", title = "Window Shopper", icon = "INV_Misc_Spyglass_02",
      how = "Rolled on 4 or more items and won none of them.",
      fit = function(p, x)
          if p.needWins + p.greedWins > 0 then return end
          return Fit(x.rolls, 4, 15)
      end,
      detail = function(_, x) return { text = ("Rolled %d times, won nothing"):format(x.rolls) } end },
    { key = "saint", title = "The Saint", icon = "Spell_Holy_HolyBolt",
      how = "Passed on 2 or more rolls.",
      fit = function(_, x) return Fit(x.passes, 2, 8) end,
      detail = function(_, x) return { text = ("Passed on %d rolls"):format(x.passes) } end },
}

local TOURIST = { key = "tourist", title = "Tourist", icon = "INV_Misc_Map_01",
                  how = "No other award fitted. Nobody leaves empty-handed." }

-- Every award there is: a list of { key, title, icon, how }.
function ns.AwardGuide()
    local list = {}
    for _, def in ipairs(AWARDS) do list[#list + 1] = def end
    list[#list + 1] = TOURIST
    return list
end

-- Works out how well every player fits every award. Returns the fits,
-- best first, as { def, p, fit }, then the players' roll figures and the
-- group's figures; or nothing for a run with fewer than two players or
-- nothing of value.
local function AwardFits(s, sum)
    local n = #sum.players
    if n < 2 or sum.count == 0 or sum.market <= 0 then return end

    local g = { n = n, total = sum.market, equal = sum.market / n, vendor = sum.vendor, items = sum.count,
                best = 0, need = 0, greed = 0, count = 0, least = math.huge,
                junk = 0, quest = 0, greedAll = 0, prof = 0 }
    local extra = {}
    for _, p in ipairs(sum.players) do
        g.best = math.max(g.best, p.bestValue)
        g.need = math.max(g.need, p.needValue)
        g.greed = math.max(g.greed, p.greedValue)
        g.count = math.max(g.count, p.count)
        g.least = math.min(g.least, p.market)
        g.junk = g.junk + (p.cats.junk and p.cats.junk.count or 0)
        g.quest = g.quest + (p.cats.quest and p.cats.quest.count or 0)
        g.greedAll = g.greedAll + p.greedValue
        g.prof = g.prof + (p.cats.prof and p.cats.prof.market or 0)

        local st = s.rollStats and s.rollStats[p.name]
        local rolls = st and st.n or 0
        local avgRoll = rolls > 0 and st.sum / rolls or 0
        extra[p.name] = {
            rolls = rolls,
            avgRoll = avgRoll,
            luck = rolls > 0 and RollLuck(avgRoll, rolls) or 0,
            high = st and st.high,
            low = st and st.low,
            passes = st and st.passes or 0,
        }
    end

    -- Every award a player qualifies for, best fit first. Equal fits are
    -- settled by the order of the list above, then by who looted more, so
    -- the result does not depend on how the window is sorted.
    local fits = {}
    for i, def in ipairs(AWARDS) do
        if n >= (def.minPlayers or 2) then
            for _, p in ipairs(sum.players) do
                local fit = def.fit(p, extra[p.name], g)
                if fit then
                    fits[#fits + 1] = { def = def, p = p, fit = fit * (def.weight or 1), order = i * 1000 + p.rank }
                end
            end
        end
    end
    table.sort(fits, function(a, b)
        if a.fit ~= b.fit then return a.fit > b.fit end
        return a.order < b.order
    end)
    return fits, extra, g
end

-- Every award each player qualified for, with its weighted fit, best
-- first: [playerName] = { { title = , fit = }, ... }. For the curious.
function ns.AwardScores(s, sum)
    local out = {}
    for _, f in ipairs(AwardFits(s, sum) or {}) do
        local list = out[f.p.name] or {}
        out[f.p.name] = list
        list[#list + 1] = { title = f.def.title, fit = f.fit }
    end
    return out
end

-- Returns [playerName] = award, one for every player of the run. An award
-- is { key, title, icon, how, text, link, amount }. `sum` must be a full
-- summary (not the Need-only view). Empty for a run with fewer than two
-- players or nothing of value.
function ns.Awards(s, sum)
    local out = {}
    local fits, extra, g = AwardFits(s, sum)
    if not fits then return out end

    local given = {}
    for _, f in ipairs(fits) do
        local def, p = f.def, f.p
        if not out[p.name] and not given[def.key] then
            given[def.key] = true
            local award = def.detail(p, extra[p.name], g)
            award.key, award.title, award.icon, award.how = def.key, def.title, def.icon, def.how
            out[p.name] = award
        end
    end
    for _, p in ipairs(sum.players) do
        if not out[p.name] then
            out[p.name] = { key = TOURIST.key, title = TOURIST.title, icon = TOURIST.icon,
                            how = TOURIST.how, text = "Along for the ride" }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Run time, dungeon records, averages and regulars.
--
-- db.records[instanceID] keeps, per dungeon: how many runs, the sums
-- needed for averages, the richest run, your best haul, the biggest
-- single item, and the fastest run. "Fastest" only compares runs with
-- the most boss kills seen for that dungeon, so an abandoned run cannot
-- take the record; with no boss kills counted there is no fastest run.
--
-- db.people[name] keeps, per player you have run with: runs together,
-- total loot value, and how often they were Luckiest or Ninja.
--
-- Both are updated once per run, when it is closed (CommitRun). A run
-- that is over but not closed yet is compared against them on the fly.
----------------------------------------------------------------------

-- Seconds from the start of a run to its end (or to now while it is in
-- progress). Nil for example runs.
function ns.RunDuration(s)
    if s.example or not s.startedAt then return end
    local finish = s.endedAt or s.leftAt or (s == db.active and time()) or nil
    if finish then return math.max(finish - s.startedAt, 0) end
end

-- The figures records are made of. `sum` is a full summary of the run.
local function RunStats(s, sum)
    local st = { group = sum.market, mine = 0, jackpot = 0, kills = s.kills or 0 }
    for _, p in ipairs(sum.players) do
        if p.name == PLAYER_NAME then st.mine = p.market end
        if p.bestValue > st.jackpot then
            st.jackpot, st.jackpotLink, st.jackpotBy = p.bestValue, p.bestLink, p.name
        end
    end
    st.duration = ns.RunDuration(s)
    return st
end

function CommitRun(s)
    if s.recorded or s.example then return end
    local sum = ns.Summarize(s)
    if #sum.players == 0 then return end
    s.recorded = true
    local st = RunStats(s, sum)
    s.stats = { group = st.group, mine = st.mine }

    -- Regulars
    local awards = ns.Awards(s, sum)
    for _, p in ipairs(sum.players) do
        if p.name ~= PLAYER_NAME then
            local who = db.people[p.name]
            if not who then
                who = { runs = 0, value = 0, lucky = 0, ninja = 0 }
                db.people[p.name] = who
            end
            who.runs = who.runs + 1
            who.value = who.value + p.market
            who.class = p.class or who.class
            who.last = s.startedAt
            local a = awards[p.name]
            if a and a.key == "lucky" then who.lucky = who.lucky + 1 end
            if a and a.key == "ninja" then who.ninja = who.ninja + 1 end
        end
    end

    -- Dungeon records (manual runs have no dungeon)
    if not s.instanceID then
        ns.CommitStats(s, sum)
        return
    end
    local rec = db.records[s.instanceID]
    if not rec then
        rec = { runs = 0, sumGroup = 0, sumMine = 0, bestGroup = 0, bestMine = 0, jackpot = 0, maxKills = 0 }
        db.records[s.instanceID] = rec
    end
    local hadRuns = rec.runs > 0 -- a first run sets every record; that is not news
    local set = {}
    rec.name = s.name or rec.name
    rec.runs = rec.runs + 1
    rec.sumGroup = rec.sumGroup + st.group
    rec.sumMine = rec.sumMine + st.mine
    if st.group > rec.bestGroup then
        rec.bestGroup = st.group
        if hadRuns then set.group = true end
    end
    if st.mine > rec.bestMine then
        rec.bestMine = st.mine
        if hadRuns then set.mine = true end
    end
    if st.jackpot > rec.jackpot then
        rec.jackpot, rec.jackpotLink, rec.jackpotBy = st.jackpot, st.jackpotLink, st.jackpotBy
        if hadRuns then set.jackpot = true end
    end
    if st.duration and st.kills > 0 then
        if st.kills > rec.maxKills then
            rec.maxKills, rec.fastest = st.kills, st.duration -- a fuller clear starts a new baseline
        elseif st.kills == rec.maxKills and (not rec.fastest or st.duration < rec.fastest) then
            rec.fastest = st.duration
            set.fastest = true
        end
    end
    s.records = next(set) and set or nil
    ns.CommitStats(s, sum) -- the long-term figures of Data.lua; last, so a fault there costs nothing above
end

-- What the window says about a run beyond its loot: how long it took,
-- which dungeon records it set, and how it compares with your average.
-- `sum` must be a full summary. Returns
--   { duration, perHour, records = { group, mine, jackpot, fastest },
--     groupPct, minePct, priorRuns }  (every field optional)
function ns.RunInsights(s, sum)
    local out = { duration = ns.RunDuration(s) }
    if out.duration and out.duration >= 60 then
        out.perHour = sum.market * 3600 / out.duration
    end
    local inProgress = s == db.active and not s.leftAt
    local rec = s.instanceID and db.records[s.instanceID]
    if not rec or inProgress or s.example then return out end

    local st = RunStats(s, sum)
    local priorRuns, avgGroup, avgMine
    if s.recorded then
        -- Already counted in the records: leave it out of its own average.
        out.records = s.records
        priorRuns = rec.runs - 1
        if priorRuns > 0 and s.stats then
            avgGroup = (rec.sumGroup - s.stats.group) / priorRuns
            avgMine = (rec.sumMine - s.stats.mine) / priorRuns
        end
    else
        priorRuns = rec.runs
        if priorRuns > 0 then
            local set = {}
            if st.group > rec.bestGroup then set.group = true end
            if st.mine > rec.bestMine then set.mine = true end
            if st.jackpot > rec.jackpot then set.jackpot = true end
            if st.duration and st.kills > 0 and st.kills == rec.maxKills
                    and rec.fastest and st.duration < rec.fastest then
                set.fastest = true
            end
            out.records = next(set) and set or nil
            avgGroup, avgMine = rec.sumGroup / priorRuns, rec.sumMine / priorRuns
        end
    end
    out.priorRuns = priorRuns
    if avgGroup and avgGroup > 0 then out.groupPct = (st.group - avgGroup) / avgGroup * 100 end
    if avgMine and avgMine > 0 then out.minePct = (st.mine - avgMine) / avgMine * 100 end
    return out
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    FairShareDB = FairShareDB or {}
    db = FairShareDB
    db.history = db.history or {}
    db.capture = db.capture or {}
    db.records = db.records or {} -- [instanceID] = dungeon records
    db.people = db.people or {}   -- [player name] = figures for people you have run with
    db.me = db.me or {}           -- your own roll figures, over all runs
    db.drops = db.drops or {}     -- [instanceID][item id] = how often an item was seen
    db.dropRuns = db.dropRuns or {} -- [instanceID] = the number of runs those drops were counted over
    db.roles = db.roles or {}     -- [role] and
    db.classes = db.classes or {} -- [class] = how loot shares turn out
    db.options = db.options or {}
    db.options.compact = nil -- an option that no longer exists: rows are always compact
    for key, value in pairs(ns.OPTION_DEFAULTS) do
        if type(value) == "table" then
            if type(db.options[key]) ~= "table" then db.options[key] = {} end
            for k, v in pairs(value) do
                if db.options[key][k] == nil then db.options[key][k] = v end
            end
        elseif db.options[key] == nil then
            db.options[key] = value
        end
    end
    ns.db = db
end

function handlers.PLAYER_LOGIN()
    -- On Forever a character has a first and a second name. UnitName
    -- returns them separately; GetUnitName gives the full name, which is
    -- the form used for other group members and in loot messages.
    PLAYER_NAME = GetUnitName("player", true) or UnitName("player")
    ns.playerName = PLAYER_NAME
    PLAYER_CLASS = select(2, UnitClass("player"))
    -- Earlier versions knew you by your first name only, and so listed
    -- you among the people you have run with.
    local first = UnitName("player")
    local ghost = first and first ~= PLAYER_NAME and db.people[first]
    if ghost and ghost.class == PLAYER_CLASS then db.people[first] = nil end
    -- Runs recorded before the long-term figures existed are counted now.
    local ok, err = pcall(ns.Backfill)
    if not ok then Print("could not update the statistics: " .. tostring(err)) end
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
    CheckZone(isLogin, not isLogin and not isReload)
end
function handlers.ZONE_CHANGED_NEW_AREA() CheckZone() end
function handlers.GROUP_ROSTER_UPDATE() UpdateRoster() end

function handlers.CHAT_MSG_LOOT(text)
    if type(text) ~= "string" then return end
    if issecret(text) then
        Capture("LOOT", "<hidden from addons>")
        return
    end
    Capture("LOOT", text)
    local name, link, count = ParseLoot(text)
    if name and link then
        RecordLoot(name, link, count)
    else
        HandleRoll(text)
    end
end

-- The instance was reset while we were outside it: the run is over, so
-- the next entry starts a new one without asking.
function handlers.CHAT_MSG_SYSTEM(text)
    if type(text) ~= "string" or issecret(text) then return end
    -- Some clients report rolls here; keep anything that mentions an item.
    if text:find("|Hitem:", 1, true) then Capture("SYSTEM", text) end
    if not resetPattern then return end
    local name = text:match(resetPattern)
    local s = db.active
    if name and s and not s.manual and s.leftAt and s.name == name then
        FinalizeSession()
        ns.Refresh()
    end
end

-- Boss kills are counted, to tell a full clear from an abandoned run when
-- comparing run times, and timed, for the timeline and to tell boss loot
-- from the rest.
function handlers.ENCOUNTER_END(_, encounterName, _, _, success)
    local s = db.active
    if Tracking(s) and (success == 1 or success == true) then
        s.kills = (s.kills or 0) + 1
        s.bosses = s.bosses or {}
        s.bosses[#s.bosses + 1] = {
            t = math.max(time() - s.startedAt, 0),
            name = type(encounterName) == "string" and not issecret(encounterName) and encounterName or nil,
        }
        if ns.BingoCheck then ns.BingoCheck() end
    end
end

-- Your own deaths, for the bingo card.
function handlers.PLAYER_DEAD()
    local s = db.active
    if Tracking(s) then
        s.myDeaths = (s.myDeaths or 0) + 1
        if ns.BingoCheck then ns.BingoCheck() end
    end
end

-- Stamp the run so that, at the next login, we know how long we were away.
function handlers.PLAYER_LOGOUT()
    if db.active then db.active.lastSeen = time() end
end

frame:SetScript("OnEvent", function(_, event, ...)
    -- Nothing can be handled before the saved data has loaded.
    if not db and event ~= "ADDON_LOADED" then return end
    handlers[event](...)
end)
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event) -- some events may not exist on this client
end

----------------------------------------------------------------------
-- Pinning and deleting runs
--
-- A pinned run is never deleted: not by the limit on runs to keep, not
-- by /fs clear, and not one at a time until it is unpinned. Deleting a
-- run removes it from the history only: the long-term statistics have
-- already counted it and are left as they are.
----------------------------------------------------------------------

local function IsStored(s)
    if not s or s.example then return false end
    if s == db.active then return true end
    for _, run in ipairs(db.history) do
        if run == s then return true end
    end
    return false
end

-- Pins or unpins a run. Returns true when it did.
function ns.TogglePin(s)
    if not IsStored(s) then return false end
    s.pinned = (not s.pinned) or nil
    ns.TrimHistory() -- an unpinned run counts towards the limit again
    ns.Refresh()
    return true
end

-- Deletes one run. Returns true when it did.
function ns.DeleteRun(s)
    if not IsStored(s) or s.pinned then return false end
    if s == db.active then
        db.active = nil
        CheckZone() -- keep tracking if we are inside a dungeon
    else
        for i, run in ipairs(db.history) do
            if run == s then
                table.remove(db.history, i)
                break
            end
        end
    end
    ns.Refresh()
    return true
end

local deleteTarget
StaticPopupDialogs["FAIRSHARE_DELETE_RUN"] = {
    text = "FairShare\n\nDelete this run of %s?\n\n"
        .. "|cff909090It cannot be brought back. Statistics already counted stay as they are.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if deleteTarget then ns.DeleteRun(deleteTarget) end
        deleteTarget = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Asks before deleting a run, and says why when it cannot be deleted.
function ns.AskDeleteRun(s)
    if not IsStored(s) then
        Print(s and s.example and "Example runs are not saved, so there is nothing to delete." or "No run to delete.")
    elseif s.pinned then
        Print("This run is pinned. Unpin it first if you really want to delete it.")
    else
        deleteTarget = s
        StaticPopup_Show("FAIRSHARE_DELETE_RUN", (s.name or "Run") .. ", " .. date("%Y-%m-%d %H:%M", s.startedAt))
    end
end

-- Deletes every run that is not pinned. Returns how many were left.
local function ClearRuns()
    local left = 0
    if db.active then
        if db.active.pinned then left = left + 1 else db.active = nil end
    end
    for i = #db.history, 1, -1 do
        if db.history[i].pinned then
            left = left + 1
        else
            table.remove(db.history, i)
        end
    end
    return left
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_FAIRSHARE1 = "/fs"
SLASH_FAIRSHARE2 = "/fairshare"
SlashCmdList.FAIRSHARE = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "" or cmd == "show" then
        ns.ToggleWindow()
    elseif cmd == "options" or cmd == "config" then
        ns.ToggleOptions()
    elseif cmd == "search" then
        -- Everything after the command word, as typed.
        ns.ShowBrowse("search", (msg or ""):match("^%s*%S+%s+(.-)%s*$") or "")
    elseif cmd == "stats" then
        ns.ShowBrowse("dungeons")
    elseif cmd == "dungeons" or cmd == "runs" or cmd == "luck" or cmd == "drops" or cmd == "roles"
            or cmd == "regulars" or cmd == "records" or cmd == "awards" then
        ns.ShowBrowse(cmd)
    elseif cmd == "details" then
        ns.OpenShow(ns.ViewedRun(), false, "timeline")
    elseif cmd == "podium" or cmd == "paper" or cmd == "timeline" or cmd == "rolls" or cmd == "numbers" then
        ns.OpenShow(ns.ViewedRun(), false, cmd)
    elseif cmd == "export" then
        ns.ShowExport(arg == "all" and "all" or "run", ns.ViewedRun())
    elseif cmd == "bingo" then
        ns.ToggleBingo()
    elseif cmd == "capture" then
        if db.capturing then
            db.capturing = nil
            Print(("Capture stopped: %d lines. Type /reload to write them to the saved file."):format(#db.capture))
        else
            db.capturing = true
            db.capture = {}
            Print("Capture started: loot and roll messages are being recorded. Type /fs capture again to stop.")
        end
    elseif cmd == "theme" then
        if not ns.SetTheme(arg) then
            Print("Themes: classic, modern. Example: /fs theme modern")
        end
    elseif cmd == "start" then
        NewSession(GetRealZoneText() or "Manual run", nil, true)
        Print("Manual run started. Use /fs stop to end it.")
    elseif cmd == "stop" then
        if db.active then
            PrintSummary(db.active)
            FinalizeSession()
            Print("Run ended.")
            ns.ShowWindow()
        else
            Print("No run in progress.")
        end
    elseif cmd == "pin" then
        local s = ns.ViewedRun()
        if ns.TogglePin(s) then
            Print(s.pinned and "Run pinned: it will never be deleted." or "Run unpinned.")
        else
            Print("No saved run on show to pin.")
        end
    elseif cmd == "delete" then
        ns.AskDeleteRun(ns.ViewedRun())
    elseif cmd == "clear" then
        local left = ClearRuns()
        CheckZone() -- keep tracking if this was typed inside a dungeon
        ns.Refresh()
        if left > 0 then
            Print(("Recorded runs deleted, except the %d you pinned."):format(left))
        else
            Print("All recorded runs deleted.")
        end
    else
        Print("/fs - open the breakdown window")
        Print("/fs options - open the options panel")
        Print("/fs theme classic|modern - change the look")
        Print("/fs start - track a run manually (outside a dungeon)")
        Print("/fs stop - end the current run")
        Print("/fs search <item name> - find an item in past runs")
        Print("/fs stats - statistics: dungeons, runs, luck, regulars, drops, roles, records")
        Print("/fs details - the run on show: podium, front page, timeline, rolls, numbers")
        Print("/fs export - the run on show as text for a spreadsheet (/fs export all: every run)")
        Print("/fs awards - what every award means")
        Print("/fs bingo - your loot bingo card")
        Print("/fs pin - pin the run on show, so that it is never deleted (again to unpin)")
        Print("/fs delete - delete the run on show")
        Print("/fs clear - delete all recorded runs, except pinned ones")
        Print("/fs capture - record raw loot and roll messages (for troubleshooting)")
    end
end

----------------------------------------------------------------------
-- Public hook used by FairShare_Example: runs added here are shown in
-- the window but never saved.
----------------------------------------------------------------------

ns.exampleRuns = {}

-- Example loot is given as item IDs only. Each item goes through the same
-- valuation as real loot: vendor price and category from the client,
-- auction price from Auctionator / TSM.
local function AddItemByID(p, id, count)
    if C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then return end
    if not Item or not Item.CreateFromItemID then return end
    local item = Item:CreateFromItemID(id)
    if item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
        local link = item:GetItemLink()
        if not link then return end
        local e = { link = link, count = count or 1, vendor = 0, cat = "other" }
        p.items[#p.items + 1] = e
        FillItem(e)
        ns.Refresh()
    end)
end

FairShare = {
    -- run.players[name] = { class = "MAGE", loot = { { itemID, count }, ... } }
    AddExampleRun = function(run)
        run.example = true
        for _, p in pairs(run.players) do p.items = {} end
        ns.exampleRuns[#ns.exampleRuns + 1] = run
        -- Wait a moment so price addons have finished loading their data.
        C_Timer.After(3, function()
            for _, p in pairs(run.players) do
                for _, l in ipairs(p.loot or {}) do AddItemByID(p, l[1], l[2]) end
            end
            ns.Refresh()
        end)
    end,
}

function FairShare_OnAddonCompartmentClick()
    ns.ToggleWindow()
end
