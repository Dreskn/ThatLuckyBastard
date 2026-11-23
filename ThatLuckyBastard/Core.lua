local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local issecret = issecretvalue or function() return false end

local RESUME_WINDOW = 1200 -- a run can be continued for 20 minutes after leaving or logging out
local ARRIVAL_GRACE = 10   -- seconds during which repeated arrival events count as one
local ROLL_MATCH_WINDOW = 5 -- a roll win and its loot line arrive within this many seconds, in either order
local CAPTURE_MAX = 600    -- lines kept by /tlb capture
local LOG_MAX = 3000       -- pickups kept per run for the timeline
local TICKER_RETRY = 1.5   -- seconds before a notice retries an item whose value was not known yet
local FORGET_AFTER = 90 * 24 * 3600 -- people met once are forgotten after this long
local LATE_JOIN = 120      -- seconds: who joins this close to a run's end and does nothing was not part of it
local PRICE_KEPT = 300     -- seconds for which today's price of an item is not asked for again
ns.MIN_TIMED_RUN = 60      -- runs shorter than this get no per-hour figures

local PLAYER_NAME, PLAYER_CLASS
local db

-- The addon's look, in one place: its name in two tones, its accent
-- colour and its mark. tools/make_logo.py draws the mark in the same
-- colours.
-- Its own teal is what it goes by in chat, on links and in tooltips. In
-- its windows the accent is the teal too, unless the options choose
-- another for the Modern theme: ns.ACCENT is then given other values (it
-- stays the same table, which the windows hold) by ns.ApplyAccent.
ns.TEAL_HEX = "|cff40c7b8"
ns.ACCENT = { 0.25, 0.78, 0.72 }
ns.ACCENT_HEX = ns.TEAL_HEX
ns.BRAND = "|cffffffffThat|r " .. ns.TEAL_HEX .. "Lucky|r |cffffffffBastard|r"
ns.NAME = "That Lucky Bastard" -- the same, where colour codes are not wanted
-- The version, from the .toc file, so that it is only ever written there.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or ""
ns.LOGO = "Interface\\AddOns\\ThatLuckyBastard\\Media\\logo.tga"
ns.MARK = ("|T%s:0|t"):format(ns.LOGO) -- the mark alone, for a line in a tooltip

-- The title of every window: the mark, the name (its middle word in the
-- accent colour), then what the window shows.
function ns.Title(sub)
    local text = ("|T%s:16:16:0:0|t |cffffffffThat|r %sLucky|r |cffffffffBastard|r"):format(ns.LOGO, ns.ACCENT_HEX)
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
    showAwards = true,   -- end-of-run awards (Jackpot, Hoarder, Ninja, ...)
    showInsights = true, -- run time, dungeon records and comparison with your average
    ceremonySound = true,       -- sounds while the awards are revealed
    ceremonyScreenshot = false, -- take a screenshot once they are all shown
    race = true,         -- as a run is left, its columns race for their places
    ticker = true,       -- on-screen notice when someone loots something valuable
    tickerMin = 50000,   -- copper: smallest pickup worth a notice
    alignItems = false,  -- put the same item on the same line in every column
    useColumns = true,   -- one column per player; past five, for the top five, the others on a bench
    -- The Modern theme's accent colour: "teal", "class" (the player's class
    -- colour), or "custom" (accentCustom: red, green and blue, each from 0
    -- to 1).
    accent = "teal",
    accentCustom = { 0.25, 0.78, 0.72 },
    mini = false,        -- a small window: a card per player (picture, name, award, total) and no buttons
    -- What each player on the bench shows besides their name.
    benchPicture = true, -- their picture (the Picture options say which; none with "None")
    benchAward = true,
    benchValue = true,   -- their loot value
    scale = 1,           -- window scale
    -- Categories that are switched off are hidden, and left out of every
    -- total unless countHidden is on.
    cats = { epic = true, rare = true, uncommon = true, bop = true, quest = true, prof = true, other = true,
             junk = true, coins = true },
    countHidden = false,
    valueMode = "market",   -- "market" (auction, vendor fallback) or "vendor"
    -- Auction prices as recorded when the loot dropped ("then"), or as
    -- they are today ("now"). Statistics keep what was recorded.
    priceTime = "then",
    -- Amounts as 12g 34s (copper off), 12g 34s 56c or 12g. Amounts smaller
    -- than the smallest shown unit still show, so nothing reads as zero.
    showSilver = true,
    showCopper = false,
    groupByCategory = true, -- off: every item in one list
    -- "role" (tank, healer, damage), "podium" (top looter in the middle),
    -- "value" or "name"
    sortPlayers = "podium",
    selfFirst = false,      -- always put you first (ignored in podium order)
    -- "game" (follow the game's My Secondary Name setting), "full" or "first"
    nameStyle = "game",
    sortItems = "value",    -- "value" or "name"
    popupLeave = true,      -- open the window when leaving the instance alive
    chatSummary = false,    -- print a one-line result in chat when a run ends
    trackRaids = true,
    askNewRun = true,       -- ask "new run?" when arriving back in the current run's dungeon
    maxHistory = 300,
    familiar = true,        -- notice when someone you have run with joins your group
    -- The meter (Meter.lua): what its rows show besides the bar, the name
    -- and the total; and whether it opens by itself as a run starts (or
    -- you go back in) and shuts as you leave.
    meterRank = true,
    meterShare = true,
    meterAward = true,
    meterOpen = false,
    meterClose = false,
    tipPlayers = true,      -- a line about people you have run with, in their tooltip
    tipItems = true,        -- a line about items seen in your runs, in their tooltip
    -- The kinds of item that get that line (the window's categories).
    tipCats = { epic = true, rare = true, uncommon = true, bop = true, quest = false, prof = false, other = false,
                junk = false },
    streak = true,          -- recap when you chain runs with the same group or dungeon
    showMinimap = true,     -- minimap button
    minimapAngle = 215,     -- its position around the minimap, in degrees
    -- Share window: post a "link" (for players with the addon) or a
    -- "summary" (lines anyone can read). The summary's contents:
    shareMode = "link",
    summaryLines = 5,       -- players listed: 3, 5 or 10
    summaryLink = true,     -- the first line is the run's link
    summaryTime = true,     -- run time on the first line
    summaryTotal = true,    -- the group's total on the first line
    summaryShare = true,    -- each player's share of the run
    summaryGap = false,     -- each player's gap to an equal split
    summaryAward = true,    -- each player's award
}

-- Fills in the options `o` lacks with their defaults. With `all`, puts
-- every option back to its default instead.
-- The accent colours on offer by name; the class colour and the player's
-- own are worked out in ns.ApplyAccent.
ns.ACCENTS = {
    teal = { 0.25, 0.78, 0.72 },
}

-- Whoever draws something in the accent colour once, and not at every
-- draw, asks here to be told when it changes.
local accentListeners = {}
function ns.OnAccent(fn)
    accentListeners[#accentListeners + 1] = fn
end

-- Gives ns.ACCENT the colour the options ask for. Only the Modern theme
-- has a choice: the others keep the teal for the little they draw in it.
function ns.ApplyAccent()
    local o = db and db.options
    local c
    if o and db.theme == "modern" then
        if o.accent == "class" then
            local _, class = UnitClass("player")
            local rc = class and not issecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            c = rc and { rc.r, rc.g, rc.b }
        elseif o.accent == "custom" then
            c = type(o.accentCustom) == "table" and o.accentCustom
        else
            c = ns.ACCENTS[o.accent]
        end
    end
    c = c or ns.ACCENTS.teal
    local function Part(v)
        return math.max(0, math.min(1, tonumber(v) or 0))
    end
    local r, g, b = Part(c[1]), Part(c[2]), Part(c[3])
    local a = ns.ACCENT
    if a[1] == r and a[2] == g and a[3] == b then return end
    a[1], a[2], a[3] = r, g, b
    ns.ACCENT_HEX = ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                                math.floor(b * 255 + 0.5))
    for _, fn in ipairs(accentListeners) do fn() end
end

function ns.FillDefaults(o, all)
    for key, value in pairs(ns.OPTION_DEFAULTS) do
        if type(value) == "table" then
            if all or type(o[key]) ~= "table" then o[key] = {} end
            for k, v in pairs(value) do
                if o[key][k] == nil then o[key][k] = v end
            end
        elseif all or o[key] == nil then
            o[key] = value
        end
    end
end

local function Print(msg)
    print(ns.BRAND .. ": " .. msg)
end

-- Dates are written one way everywhere.
function ns.DateText(t)
    return t and date("%Y-%m-%d %H:%M", t) or "-"
end

-- A run's dungeon by the short name players give it (Warcraft Tavern's
-- list of WoW Forever's dungeons), for the windows short on room: the
-- meter and the mini window. Found by the instance's ID, whatever the
-- language of the game, else by the English name; a dungeon not listed
-- keeps its name. Dire Maul keeps it too: DM is the Deadmines, and the
-- game does not say which wing it is.
local SHORT_BY_ID = {
    [389] = "RFC", [43] = "WC", [36] = "DM", [33] = "SFK", [48] = "BFD", [34] = "Stocks",
    [90] = "Gnomer", [47] = "RFK", [189] = "SM", [129] = "RFD", [70] = "Uld", [209] = "ZF",
    [349] = "Mara", [109] = "ST", [230] = "BRD", [229] = "BRS", [329] = "Strat", [289] = "Scholo",
    [249] = "Ony", [2970] = "DC", [2994] = "Alcaz", [3039] = "KDS",
}
local SHORT_BY_NAME = {
    ragefirechasm = "RFC", wailingcaverns = "WC", deadmines = "DM", shadowfangkeep = "SFK",
    blackfathomdeeps = "BFD", stockade = "Stocks", gnomeregan = "Gnomer", razorfenkraul = "RFK",
    scarletmonastery = "SM", razorfendowns = "RFD", uldaman = "Uld", zulfarrak = "ZF",
    maraudon = "Mara", sunkentemple = "ST", templeofatalhakkar = "ST", blackrockdepths = "BRD",
    blackrockspire = "BRS", lowerblackrockspire = "LBRS", upperblackrockspire = "UBRS",
    stratholme = "Strat", scholomance = "Scholo", onyxiaslair = "Ony",
    -- New in Forever.
    hallofthanes = "HoT", ruinsoflordaeron = "RoL", excavationsitewetlands = "ESW",
    cityofdalaran = "CoD", drownedcity = "DC", kroldokstronghold = "KDS", alcazprison = "Alcaz",
    alcazislandprison = "Alcaz", blackmawhold = "BMH", shapersterrace = "Terrace",
}
function ns.ShortName(s)
    local short = s.instanceID and SHORT_BY_ID[s.instanceID]
    if not short and s.name then
        -- Case, spaces, "The" and apostrophes (straight or curly) aside.
        local key = s.name:lower():gsub("\226\128\153", ""):gsub("^the ", ""):gsub("[%s%p]", "")
        short = SHORT_BY_NAME[key]
    end
    return short or s.name or "Run"
end

-- Who "you" are in a run: the character that recorded it. The saved data
-- is shared by every character of the account, so that is not always the
-- one logged in. (Runs from before this was stored: the one logged in.)
function ns.Me(s)
    return (s and s.owner) or PLAYER_NAME
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

-- Coins: "You loot 1 Gold, 5 Silver" when you take them alone, "Your share
-- of the loot is 25 Copper." when the game splits them among the group.
-- Guild variants first: they add a part the plain ones would swallow.
local moneySpecs = {}
for _, spec in ipairs({ { "LOOT_MONEY_SPLIT_GUILD", true }, { "LOOT_MONEY_SPLIT", true },
                        { "YOU_LOOT_MONEY_GUILD", false }, { "YOU_LOOT_MONEY", false } }) do
    local pat = BuildPattern(_G[spec[1]])
    if pat then moneySpecs[#moneySpecs + 1] = { pat = pat, split = spec[2] } end
end

-- The amounts in such a text, from the client's own words for them ("%d
-- Gold"), or from coin icons where a client draws those.
local coinUnits = {}
for _, unit in ipairs({ { GOLD_AMOUNT or "%d Gold", 10000, "Gold" }, { SILVER_AMOUNT or "%d Silver", 100, "Silver" },
                        { COPPER_AMOUNT or "%d Copper", 1, "Copper" } }) do
    local pat = unit[1]:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%[ds]", "(%%d+)")
    coinUnits[#coinUnits + 1] = { pat = pat, icon = "(%d+)%s*|T[^|]-" .. unit[3] .. "Icon", copper = unit[2] }
end

-- Copper looted, and whether it was a share of a split; nil for any other text.
local function ParseMoney(text)
    for _, spec in ipairs(moneySpecs) do
        local amount = text:match(spec.pat)
        if amount then
            local copper, found = 0, false
            for _, unit in ipairs(coinUnits) do
                local n = amount:match(unit.pat) or amount:match(unit.icon)
                if n then copper, found = copper + tonumber(n) * unit.copper, true end
            end
            if found and copper > 0 then return copper, spec.split end
            return
        end
    end
end

-- Identifies an item regardless of who looted it (its item ID).
local function LinkKey(link)
    return link:match("item:(%d+)") or link
end
local function ItemKey(e)
    return LinkKey(e.link)
end
ns.ItemKey = ItemKey

-- How an item is priced, by category.
--   never at auction    bound and quest items cannot be sold to other
--                       players, so no auction price is recorded for them
--   vendor by default   nobody buys junk, so a stray listing for a grey
--                       item means nothing; its auction price is still
--                       recorded, and the player can switch to it
-- Everything else is valued at its auction price when one is known.
local NO_AUCTION = { bop = true, quest = true }
local VENDOR_BY_DEFAULT = { junk = true }

function ns.CanAuction(e)
    return not NO_AUCTION[e.cat]
end

function ns.VendorByDefault(e)
    return VENDOR_BY_DEFAULT[e.cat] == true
end

-- Notes on an item entry whether it is valued at its vendor price in this
-- run although an auction price is known (e.noAH): because that is the
-- default for its category, or because the player switched it away from
-- the default (see ToggleAuctionPrice). EntryMarket reads the note, so it
-- has to be set before an entry is valued.
local function MarkPrice(s, e)
    local switched = s.priceSwitched or s.vendorOnly -- vendorOnly: its name before junk had its own default
    local flipped = switched ~= nil and switched[ItemKey(e)] == true
    e.noAH = (ns.VendorByDefault(e) ~= flipped) or nil
    -- With current prices chosen, the item's auction price of today stands
    -- in for the recorded one where there is one (e.now; never saved). Not
    -- in runs shared with you, which keep their owner's prices.
    e.now = (db.options.priceTime == "now" and not e.noAH and not s.sharedBy and not s.example
        and ns.CanAuction(e) and ns.TodaysPrice(e.link)) or nil
end
ns.MarkPrice = MarkPrice

-- An item's quality, also for entries saved before it was stored: the
-- colour code of a link names it ("|cnIQ3:").
local function Quality(e)
    return e.quality or tonumber(e.link:match("|cnIQ(%d+):")) or 0
end
ns.Quality = Quality

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
-- "Everyone passed on: [item]" and "X automatically passed on: [item]
-- because ..." come first: the plain "X passed on" below would read them
-- as a player called "Everyone" or "X automatically".
AddRollSpec("LOOT_ROLL_ALL_PASSED", "allpass")
AddRollSpec("LOOT_ROLL_PASSED_SELF_AUTO", "autopass")
AddRollSpec("LOOT_ROLL_PASSED_SELF_AUTO_FEMALE", "autopass")
AddRollSpec("LOOT_ROLL_PASSED_AUTO", "autopass")
AddRollSpec("LOOT_ROLL_PASSED_AUTO_FEMALE", "autopass")
-- "X passed on: [item]".
AddRollSpec("LOOT_ROLL_PASSED_SELF", "pass")
AddRollSpec("LOOT_ROLL_PASSED", "pass")
-- "X won: [item]": the method comes from what the winner selected.
AddRollSpec("LOOT_ROLL_YOU_WON", "won")
AddRollSpec("LOOT_ROLL_WON", "won")

-- Returns kind ("select", "won", "pass", "autopass" for a pass the game
-- made for a player who cannot use the item, or "allpass" when nobody
-- wanted it), method ("need", "greed" or nil), player name, item key, the
-- number rolled (when the message gives one) and the roll's id (on
-- clients that send one); or nothing if the text is not a roll message.
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

-- The two addons that can supply auction prices, when they are loaded.
local function AuctionatorAPI()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemLink and api or nil
end

local function HasTSM()
    return TSM_API ~= nil and TSM_API.ToItemString ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

local function TSMPrice(link)
    local itemString = TSM_API.ToItemString(link)
    return itemString and TSM_API.GetCustomPriceValue("dbmarket", itemString)
end

-- Auctionator's price for a link; TradeSkillMaster's when it has none.
local function AuctionPrice(link)
    local api = AuctionatorAPI()
    if api then
        local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    if HasTSM() then
        local ok, price = pcall(TSMPrice, link)
        if ok and type(price) == "number" and price > 0 then return price end
    end
end
ns.AuctionPrice = AuctionPrice

-- The auction price of today, asked of the price addon once every few
-- minutes at most: every window values every item again each time it is
-- drawn. Nil when there is none.
local todays = {} -- [link] = { price = (false for none), at = }
function ns.TodaysPrice(link)
    local known = todays[link]
    if not known or GetTime() - known.at > PRICE_KEPT then
        known = { price = AuctionPrice(link) or false, at = GetTime() }
        todays[link] = known
    end
    return known.price or nil
end

-- True when an addon that can supply auction prices is loaded.
function ns.HasPriceSource()
    return AuctionatorAPI() ~= nil or HasTSM()
end

-- The name of the addon(s) supplying auction prices, or nil.
function ns.PriceSourceName()
    local auctionator, tsm = AuctionatorAPI() ~= nil, HasTSM()
    if auctionator and tsm then return "Auctionator and TradeSkillMaster" end
    return (auctionator and "Auctionator") or (tsm and "TradeSkillMaster") or nil
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

-- The category of an item, given as a link or an id; nothing while the
-- game does not know the item.
function ns.ItemCategory(item)
    local _, _, quality, _, _, _, _, _, _, _, _, classID, _, bindType = GetItemInfo(item)
    if quality then return Categorize(quality, classID, bindType) end
end

local function FillItem(e)
    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, bindType = GetItemInfo(e.link)
    if not quality then return false end
    e.quality = quality
    e.vendor = sellPrice or 0
    e.cat = Categorize(quality, classID, bindType)
    e.ah = ns.CanAuction(e) and AuctionPrice(e.link) or nil
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
        -- joined: seconds into the run (see DropLateJoiners); not kept.
        p = { items = {}, joined = math.max(time() - (s.startedAt or time()), 0) }
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
    if not issecret(role) and role and role ~= "NONE" then p.role = role end
end

-- The other members of the group right now, as [name] = unit, and how
-- many they are.
local function GroupNow()
    local set, n = {}, 0
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = GetUnitName(unit, true)
            if not issecret(name) and name and name ~= UNKNOWNOBJECT and not set[name] then
                set[name], n = unit, n + 1
            end
        end
    end
    return set, n
end

-- Is the group of now (see GroupNow) another group than the one the run
-- was last seen with (s.group, a list of names)? It is when fewer than
-- half of the smaller of the two are the same people. Players replaced
-- one or two at a time keep it the same group, so their run goes on; a
-- group joined after the old one broke up is another, and so is the group
-- of the next queue when one friend queues along. Being alone, or a run
-- that has had no group yet, says nothing.
local function DifferentGroup(s, set, n)
    local last = s.group
    if not last or #last == 0 or n == 0 then return false end
    local shared = 0
    for _, name in ipairs(last) do
        if set[name] then shared = shared + 1 end
    end
    return shared * 2 < math.min(#last, n)
end

local SplitRun -- defined with the zone rules, below

local function UpdateRoster()
    local s = db.active
    if not Tracking(s) or not PLAYER_NAME then return end
    -- A run recorded on another character is closed at the next arrival:
    -- this character's group is not its group.
    if s.owner and s.owner ~= PLAYER_NAME then return end
    local set, n = GroupNow()
    if not s.manual and DifferentGroup(s, set, n) then return SplitRun(s) end
    local me = AddPlayer(s, PLAYER_NAME, PLAYER_CLASS)
    SetRole(me, "player")
    for name, unit in pairs(set) do
        local _, class = UnitClass(unit)
        if issecret(class) then class = nil end
        SetRole(AddPlayer(s, name, class), unit)
    end
    if n > 0 then
        s.group = {}
        for name in pairs(set) do s.group[#s.group + 1] = name end
        table.sort(s.group)
    end
    ns.Refresh()
end

local function HasLoot(s)
    for _, p in pairs(s.players) do
        if next(p.items) or (p.money or 0) > 0 then return true end
    end
    return false
end

-- Drops the oldest runs beyond the number to keep. Pinned runs are never
-- dropped and do not count towards that number. Runs shared with you are
-- kept up to the same number, counted apart (see ns.TrimShared).
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
    ns.TrimShared()
end

local PrintSummary -- defined below
local CommitRun    -- defined with the records code, further down

-- Drops what is only of use while a run is going, to keep the saved
-- file small.
local function StripRun(s)
    s.rolls, s.pendingWins, s.killed = nil, nil, nil
    s.enteredAt, s.lastSeen, s.nextId = nil, nil, nil
    s.leftDead, s.summarized, s.streakShown, s.group = nil, nil, nil, nil
    for _, p in pairs(s.players) do
        p.joined = nil
        for _, e in pairs(p.items) do
            e.lastAt, e.noAH, e.now = nil, nil, nil
        end
    end
end

-- Players who joined in a run's last moments and did nothing in it belong
-- to what came next: the group of the following run, formed while we
-- were still inside (a queue that pops there), or someone invited once it
-- was over. Nobody who joined in the run's first minutes is dropped,
-- however short it was.
local function DropLateJoiners(s)
    if s.manual then return end
    local from = math.max((s.endedAt or time()) - (s.startedAt or 0) - LATE_JOIN, LATE_JOIN)
    local logged = {}
    for _, name in ipairs(s.names or {}) do logged[name] = true end -- in the pickup or roll log
    for name, p in pairs(s.players) do
        if name ~= ns.Me(s) and p.joined and p.joined >= from and not next(p.items) and not p.money
                and not logged[name] and not (s.rollStats and s.rollStats[name]) then
            s.players[name] = nil
        end
    end
end

local function FinalizeSession()
    local s = db.active
    if not s then return end
    PrintSummary(s) -- no-op if already printed or switched off
    db.active = nil
    s.endedAt = s.leftAt or time()
    DropLateJoiners(s)
    if HasLoot(s) then
        table.insert(db.history, 1, s)
        ns.TrimHistory()
        -- Records and regulars are extras: a fault there must never cost
        -- the run itself, which is already safely in the history.
        local ok, err = pcall(CommitRun, s)
        if not ok then Print("could not update records: " .. tostring(err)) end
        StripRun(s)
    end
end

local function NewSession(name, instanceID, manual)
    FinalizeSession()
    db.active = {
        name = name or "Run",
        instanceID = instanceID,
        owner = PLAYER_NAME, -- the character recording it
        manual = manual or nil,
        startedAt = time(),
        enteredAt = time(), -- last time we arrived in the instance
        lastSeen = time(),  -- last loot, or logout
        players = {},
    }
    ns.fresh = nil -- a run that ended unseen is old news now (see ShowRunEnd)
    UpdateRoster()
    if ns.MeterAuto then ns.MeterAuto("start") end
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
        if p.name == ns.Me(s) then
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
local promptSession, promptLeftAt, promptSummarized
StaticPopupDialogs["THATLUCKYBASTARD_NEW_RUN"] = {
    text = ns.NAME .. "\n\nIs this a new run of %s?\n\n|cff909090No keeps adding to the previous run.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local s = db.active
        -- Only if that run is still the current one and we are still inside.
        if s and s == promptSession and not s.leftAt then
            -- The old run ended when it was left (or, after a requeue, when
            -- we arrived again), not when the question was answered.
            s.leftAt, s.summarized = promptLeftAt or s.enteredAt, promptSummarized
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

-- leftAt, summarized: how the run stood before we came back, if it had
-- been left.
local function AskNewRun(s, leftAt, summarized)
    promptSession, promptLeftAt, promptSummarized = s, leftAt, summarized
    StaticPopup_Show("THATLUCKYBASTARD_NEW_RUN", s.name or "this dungeon")
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
    local back = s.leftAt ~= nil
    if back then
        s.summarized = nil
        s.enteredAt = time()
    end
    s.leftAt, s.leftDead = nil, nil
    if ns.fresh == s then ns.fresh = nil end -- back inside: its end is still to come
    UpdateRoster()
    if back and ns.MeterAuto then ns.MeterAuto("start") end -- going back in is the run starting again
end

-- What the player sees when they leave a run alive: the window, with
-- its reveal, then the streak notice. With the window switched off, the
-- reveal waits for the first time that run is on show (ns.fresh: at once
-- if the window is open on it). A run left again after coming back opens
-- the window again, but the notice only the first time.
local function ShowRunEnd(s)
    ns.fresh = s
    if ns.MeterAuto then ns.MeterAuto("leave") end
    if db.options.popupLeave then ns.ShowWindow(true, s) else ns.Refresh() end
    if not s.streakShown then
        pcall(ns.StreakNotice, s)
        -- Only the run in progress can be left again: a closed one keeps no note.
        s.streakShown = s == db.active or nil
    end
end

-- The group of the run in progress has been replaced by another one
-- (see DifferentGroup): the run ends here, and what follows in the same
-- place is a new run, with the new group.
function SplitRun(s)
    s.leftAt = time()
    local ended = not UnitIsDeadOrGhost("player") and HasLoot(s) and s or nil
    NewSession(s.name, s.instanceID) -- files the old run away; the roster goes to the new one
    if ended then ShowRunEnd(ended) end
end

-- The rules, in full:
--   * A run belongs to one instance. Arriving in a different one, or with
--     no run in progress, starts a new run. Going from the run's dungeon
--     straight into another one (a queue that pops inside) leaves the run
--     first, as if through the door.
--   * Leaving alive opens the window. Leaving dead does nothing, until
--     you are alive again outside (see Revived): then it opens as well.
--   * Coming back within RESUME_WINDOW continues the run: silently after
--     a death, and with a "new run?" question otherwise. With the
--     question switched off, coming back alive starts a new run. Coming
--     back with another group (see DifferentGroup) always starts one.
--   * A run that was left is closed once RESUME_WINDOW has passed, or as
--     soon as the instance is reset.
--
-- isLogin: a fresh login. entered: arrived through a loading screen that
-- was neither a login nor a reload. Both are nil for plain zone changes.
local function CheckZone(isLogin, entered)
    local s = db.active
    -- Closes a run that ended a while ago: at the moment it was last seen,
    -- and without announcing anything.
    local function CloseStale()
        s.leftAt, s.summarized = s.leftAt or s.lastSeen, true
        FinalizeSession()
        s = nil
    end
    -- A run recorded on another character of the account is over.
    if s and s.owner and s.owner ~= PLAYER_NAME then CloseStale() end
    if s and s.manual then
        -- A manual run ends with /tlb stop. One forgotten over a logout is
        -- closed at a later login, or no dungeon run would ever start again.
        if not (isLogin and time() - (s.lastSeen or 0) > RESUME_WINDOW) then return end
        CloseStale()
    end

    local inInstance, instanceType = IsInInstance()
    local tracked = inInstance
        and (instanceType == "party" or (instanceType == "raid" and db.options.trackRaids))

    if tracked then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if not s or s.instanceID ~= instanceID then
            local ended -- the run just left without going outside, if it has something to show
            if s and not s.leftAt and not isLogin then
                s.leftAt = time()
                if not UnitIsDeadOrGhost("player") and HasLoot(s) then ended = s end
            end
            NewSession(name, instanceID) -- files the previous run away
            if ended then ShowRunEnd(ended) end
        elseif s.leftAt then
            local recent = time() - s.leftAt < RESUME_WINDOW
            if recent and DifferentGroup(s, GroupNow()) then
                NewSession(name, instanceID) -- another group: another run, without asking
            elseif recent and s.leftDead then
                Continue(s)
            elseif recent and db.options.askNewRun then
                local leftAt, summarized = s.leftAt, s.summarized
                Continue(s)
                AskNewRun(s, leftAt, summarized)
            else
                NewSession(name, instanceID)
            end
        elseif isLogin and time() - (s.lastSeen or 0) > RESUME_WINDOW then
            -- Logged back in long after the run: it ended when it was last
            -- seen, not now.
            s.leftAt, s.summarized = s.lastSeen, true
            NewSession(name, instanceID)
        else
            -- Never left: a reload, a relog, or moving around inside. A
            -- loading screen here means a requeue into the same dungeon.
            Continue(s)
            if entered then MaybeAsk(s) end
        end
    elseif s then
        if not s.leftAt and isLogin then
            -- Logged out inside and came back outside: the run was left
            -- when it was last seen. It can still be resumed for a while.
            s.leftAt, s.summarized = s.lastSeen, true
        end
        if s.leftAt then
            if time() - s.leftAt > RESUME_WINDOW then FinalizeSession() end
        else
            s.leftAt = time()
            s.leftDead = UnitIsDeadOrGhost("player") or nil
            if not s.leftDead and HasLoot(s) then -- nothing to show for a step in and out
                PrintSummary(s)
                ShowRunEnd(s)
            end
        end
    end
end

-- Moves roll wins from `wins` ({ need = n, greed = n, ... }) onto an item
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
        MarkPrice(s, e)
        local value = ns.EntryMarket(e) / e.count * count
        if value >= db.options.tickerMin then
            local p = s.players[name]
            ns.Toast(name, p and p.class, e.link, count, value)
        end
    end
    if e.resolved then show() else C_Timer.After(TICKER_RETRY, show) end
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

-- What a player's item entries are filed under: the link's item string.
-- It carries the looter's level and specialisation (its 9th and 10th
-- fields), which say nothing about the item; they are blanked, so that
-- the same item is one entry before and after a level-up.
local function EntryKey(link)
    local itemString = link:match("|H(item:[^|]+)|h") or link
    return (itemString:gsub("^(item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*):[^:]*:[^:]*", "%1::"))
end
ns.EntryKey = EntryKey

local function RecordLoot(name, rawLink, count)
    local s = db.active
    if not Tracking(s) then return end
    local link = rawLink:match("(|c.-|Hitem:.-|h.-|h|r)") or rawLink:match("(|Hitem:.-|h.-|h)")
    if not link then return end
    local entryKey = EntryKey(link)
    local p = AddPlayer(s, name)
    local e = p.items[entryKey]
    if not e then
        e = { link = link, count = 0, vendor = 0, cat = "other" }
        p.items[entryKey] = e
        ResolveItem(e)
    end
    if not e.id then
        s.nextId = (s.nextId or 0) + 1
        e.id = s.nextId
    end
    e.count = e.count + count
    e.lastAt = time()
    LogPickup(s, name, e, count)
    -- If this player just won a roll on this item, note how it was won. A
    -- win whose item never came (full bags, say) is dropped once it is too
    -- old, so that a later copy of the item is not taken for it.
    local pending = s.pendingWins and s.pendingWins[name]
    local key = ItemKey(e)
    local wins = pending and pending[key]
    if wins then
        local fresh = time() - (wins.at or 0) <= ROLL_MATCH_WINDOW
        if fresh then TagWin(e, wins) end
        if not fresh or (wins.need or 0) + (wins.greed or 0) == 0 then pending[key] = nil end
    end
    AnnounceLoot(s, name, e, count)
    s.lastSeen = time()
    ns.Refresh()
end

-- Coins, kept per player as p.money (copper). The game splits a corpse's
-- coins evenly among the group members near it and tells each of them
-- only their own share, so a share is given to everyone in the group
-- close enough to be seen. Coins looted alone are yours alone.
local function RecordMoney(copper, split)
    local s = db.active
    if not Tracking(s) or not PLAYER_NAME then return end
    local function Give(name)
        local p = AddPlayer(s, name)
        p.money = (p.money or 0) + copper
    end
    Give(PLAYER_NAME)
    if split then
        for name, unit in pairs((GroupNow())) do
            if not UnitIsVisible or UnitIsVisible(unit) then Give(name) end
        end
    end
    s.lastSeen = time()
    ns.Refresh()
end

-- A roll in progress: who chose what and who rolled what. `rk` tells
-- rolls apart: the roll's own id where the client sends one (two copies
-- of the same item are then two rolls), the item otherwise.
local function OpenRoll(s, rk, key)
    s.rolls = s.rolls or {}
    local r = s.rolls[rk]
    if not r then
        r = { key = key, t = math.max(time() - s.startedAt, 0), need = {}, greed = {}, pass = {}, num = {} }
        s.rolls[rk] = r
    end
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
        -- Its loot line has not come yet: the win waits for it (see RecordLoot).
        s.pendingWins = s.pendingWins or {}
        s.pendingWins[name] = s.pendingWins[name] or {}
        local pending = s.pendingWins[name][key] or {}
        pending[method] = (pending[method] or 0) + 1
        pending.at = time()
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
    if kind == "allpass" then -- nobody wanted it: the roll is over
        if s.rolls then s.rolls[rk] = nil end
        return
    end
    local r = OpenRoll(s, rk, key)
    -- A number can come twice: with the roll, and again with the win.
    if roll and r.num[name] == nil then
        local st = RollStats(s, name)
        st.sum, st.n = st.sum + roll, st.n + 1
        if not st.high or roll > st.high then st.high = roll end
        if not st.low or roll < st.low then st.low = roll end
        r.num[name] = roll
    end
    if kind == "select" then
        r[method][name] = true
    elseif kind == "won" then
        RecordRollWin(s, name, key, method, rk)
    elseif kind == "pass" or kind == "autopass" then
        if not r.pass[name] then
            r.pass[name] = true
            -- A pass the game made for a player who cannot use the item is
            -- no generosity: only chosen passes count.
            if kind == "pass" then
                local st = RollStats(s, name)
                st.passes = st.passes + 1
            end
        end
    end
end

----------------------------------------------------------------------
-- Capture: records raw loot-channel lines so the message formats of
-- this client can be inspected. Toggled with /tlb capture.
----------------------------------------------------------------------

local function Capture(channel, text)
    if not db.capturing or #db.capture >= CAPTURE_MAX then return end
    db.capture[#db.capture + 1] = date("%H:%M:%S") .. " " .. channel .. " " .. text
end

----------------------------------------------------------------------
-- Summary used by the window
----------------------------------------------------------------------

-- The value used for totals, shares and sorting. `e.noAH` says this item
-- is valued at its vendor price in its run: call MarkPrice first. An
-- ignored item is worth nothing; `e.part`, on the stand-ins of a split
-- item (see Summarize), is the share of it one player holds.
local function EntryMarket(e)
    if e.ignored then return 0 end
    local unit = (db.options.valueMode == "vendor" or e.noAH) and e.vendor or (e.now or e.ah or e.vendor)
    return unit * e.count * (e.part or 1)
end
ns.EntryMarket = EntryMarket

-- The same at the prices recorded when it was looted, whatever the price
-- setting says.
function ns.EntryRecorded(e)
    if e.ignored then return 0 end
    local unit = (db.options.valueMode == "vendor" or e.noAH) and e.vendor or (e.ah or e.vendor)
    return unit * e.count * (e.part or 1)
end

-- The same at vendor prices.
local function EntryVendor(e)
    if e.ignored then return 0 end
    return e.vendor * e.count * (e.part or 1)
end
ns.EntryVendor = EntryVendor

-- Switches an item between its auction and vendor price for one run. It
-- applies to every copy of the item in that run, whoever looted it.
-- s.priceSwitched holds the items switched away from their category's
-- default.
function ns.ToggleAuctionPrice(s, e)
    if not e.ah then return false end
    local key = ItemKey(e)
    s.priceSwitched, s.vendorOnly = s.priceSwitched or s.vendorOnly or {}, nil
    s.priceSwitched[key] = (not s.priceSwitched[key]) or nil
    return true
end

-- The entry a summary's stand-in stands for (see Summarize), or `e`.
function ns.RealEntry(e)
    local mt = getmetatable(e)
    return mt and type(mt.__index) == "table" and mt.__index or e
end

-- Who looted entry `e` (a real one) in run `s`.
function ns.EntryOwner(s, e)
    for name, p in pairs(s.players) do
        for _, x in pairs(p.items) do
            if x == e then return name end
        end
    end
end

-- Ignore: the item stays on show, worth nothing. It is for one player's
-- copies of an item (an entry), where a price is for every copy in the run.
function ns.ToggleIgnore(e)
    e.ignored = (not e.ignored) or nil
end

-- Split: the item's value shared equally by `names`, players of the run,
-- its looter among them or not (not: given to the others). Nil, or the
-- looter alone, undoes it. Kept in name order.
function ns.SetSplit(s, e, looter, names)
    local list, seen = {}, {}
    for _, name in ipairs(names or {}) do
        if s.players[name] and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    table.sort(list)
    if #list == 0 or (#list == 1 and list[1] == looter) then list = nil end
    e.split = list
end

-- Who a split entry's value goes to: those of its split who are players
-- of the run. Nil when it is not split.
local function SplitNames(s, e)
    if not e.split then return end
    local list = {}
    for _, name in ipairs(e.split) do
        if s.players[name] then list[#list + 1] = name end
    end
    return list[1] and list or nil
end

local function ItemName(e)
    return e.link:match("%[(.-)%]") or ""
end
ns.ItemName = ItemName

-- needOnly: count only the copies of each item that were won on a Need
-- roll. Entries are then stand-ins that carry the reduced count and read
-- everything else from the real entry.
--
-- A split item (see ns.SetSplit) is listed under each player who shares
-- it, as a stand-in with `part` (their share), `ways` (how many share it)
-- and, under anyone but its looter, `from` (the looter). Under its looter
-- it stays listed when given away (`away`: worth nothing to them). Copies
-- picked up, roll wins and the best quality stay with the looter, who
-- picked it up and won it; its value, Need and Greed value included, goes
-- with the shares.
function ns.Summarize(s, needOnly)
    local o = db.options
    local out = { players = {}, count = 0, vendor = 0, market = 0, money = 0, needOnly = needOnly }
    local byName = {}
    for name, p in pairs(s.players) do
        local ps = { name = name, class = p.class, role = p.role, count = 0, vendor = 0, market = 0, cats = {},
                     -- the coins counted in vendor and market (also in cats.coins
                     -- when that category is shown, as a group with no items)
                     money = 0,
                     -- for the awards: value won on Need / Greed rolls, and the best single item
                     needValue = 0, greedValue = 0, bestValue = 0,
                     -- also for the awards: rolls won, and the best item quality
                     needWins = 0, greedWins = 0, bestQuality = 0,
                     -- every shown item in one group, for the ungrouped layout
                     all = { items = {} },
                     -- every item counted in the totals, hidden ones too when they count
                     held = {} }
        byName[name] = ps
        out.players[#out.players + 1] = ps
    end

    -- One player's hold on an entry: `e` is what is listed (the entry or a
    -- stand-in), `part` their share of it, `own` true for its looter.
    local function Hold(ps, real, e, part, own)
        if real.count > 0 and o.cats[real.cat] ~= false then
            local unit = EntryMarket(real) / real.count * part
            ps.needValue = ps.needValue + unit * (real.need or 0)
            ps.greedValue = ps.greedValue + unit * (real.greed or 0)
            if unit > ps.bestValue then ps.bestValue, ps.bestLink = unit, real.link end
            if own then
                ps.needWins = ps.needWins + (real.need or 0)
                ps.greedWins = ps.greedWins + (real.greed or 0)
                ps.bestQuality = math.max(ps.bestQuality, Quality(real))
            end
        end
        local count = own and e.count or 0 -- copies picked up
        local v, m = EntryVendor(e), EntryMarket(e)
        local shown = e.count > 0 and o.cats[e.cat] ~= false
        if shown then
            local c = ps.cats[e.cat]
            if not c then
                c = { items = {}, count = 0, vendor = 0, market = 0 }
                ps.cats[e.cat] = c
            end
            c.items[#c.items + 1] = e
            c.count, c.vendor, c.market = c.count + count, c.vendor + v, c.market + m
            ps.all.items[#ps.all.items + 1] = e
        end
        if shown or o.countHidden then
            ps.count, ps.vendor, ps.market = ps.count + count, ps.vendor + v, ps.market + m
            if e.count > 0 then ps.held[#ps.held + 1] = e end
        end
    end

    for name, p in pairs(s.players) do
        for _, real in pairs(p.items) do
            if not real.resolved then FillItem(real) end
            MarkPrice(s, real)
            local names = SplitNames(s, real)
            local ways = names and #names or 1
            local mine = not names
            for _, other in ipairs(names or {}) do
                if other == name then mine = true end
            end
            local part = mine and 1 / ways or 0
            local count = needOnly and (real.need or 0) or nil
            local e = real
            if needOnly or names then
                e = setmetatable({ count = count, part = names and part or nil, ways = names and ways or nil,
                                   away = not mine or nil }, { __index = real })
            end
            Hold(byName[name], real, e, part, true)
            for _, other in ipairs(names or {}) do
                if other ~= name then
                    local share = setmetatable({ count = count, part = 1 / ways, ways = ways, from = name },
                                               { __index = real })
                    Hold(byName[other], real, share, 1 / ways, false)
                end
            end
        end
    end

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
    for _, ps in ipairs(out.players) do
        for _, c in pairs(ps.cats) do table.sort(c.items, ItemOrder) end
        table.sort(ps.all.items, ItemOrder)
        -- Coins are worth what they say, at auction or vendor alike. None
        -- are won on a roll, so Need only leaves them out.
        local money = not needOnly and s.players[ps.name].money or 0
        if money > 0 then
            local shown = o.cats.coins ~= false
            if shown then ps.cats.coins = { items = {}, count = 0, vendor = money, market = money } end
            if shown or o.countHidden then
                ps.money, ps.vendor, ps.market = money, ps.vendor + money, ps.market + money
            end
        end
        out.count, out.vendor, out.market = out.count + ps.count, out.vendor + ps.vendor, out.market + ps.market
        out.money = out.money + ps.money
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
            if p.name == ns.Me(s) then
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
-- goes to one player in a party and to two or three in a bigger group
-- (see Holders), so the others move on to their next best. Anyone left
-- without one is a Tourist. Every award weighs the same: the most
-- striking fit wins, whichever award it is.
--
-- fit(p, x, g) returns the fit, or nil when the player does not qualify.
--   p  the player's summary (see Summarize)
--   x  their roll figures: rolls, avgRoll, luck, high, low, passes
--   g  the group's figures: n (players), total and equal (the run's loot
--      and an equal share of it), vendor (the run's loot at vendor
--      prices), holders (how many players can have the same award),
--      best / need / greed / count / least (the single item, Need value,
--      Greed value, item count and haul it takes to be among that many
--      best; `board` lists every player's), roles and classes (the
--      players and loot of each), and the run's totals: items, junk and quest (item
--      counts), greedAll (value won on Greed rolls) and prof (value of
--      profession materials)
-- detail(p, x, g) returns the text / item / amount shown with the award.
-- An award with `each` in place of `fit` has several slots, each for one
-- player (Boss's Pet: one per boss): each(sum, extra, g) lists
-- { p, fit, slot, data }, and detail gets that `data` as a fourth argument.
-- `how` is the rule in plain words, for the tooltip and the awards guide:
-- keep it to one line of the guide (about 90 characters) and in step with
-- fit.
----------------------------------------------------------------------

-- Thresholds. Each is quoted in its award's `how` text: change both.
local NINJA_MIN = 10000   -- copper: Need wins below this never make a Ninja
local JACKPOT_MIN = 10000 -- copper: smallest item worth calling a jackpot
local FARMER_MIN = 1000   -- copper: profession materials below this do not make a Farmer
local DICE_MIN_ROLLS = 5  -- rolls needed before the dice awards apply
-- The dice awards start at an average two standard deviations from what
-- chance gives, and are remarkable at three (see RollLuck). With fair dice
-- that is one player in twenty or so: at 1.3, where the bar used to be,
-- two parties in three had someone who qualified.
local DICE_LUCK, DICE_LUCK_HIGH = 2, 3
local ONEHIT_MIN_ITEMS = 3   -- items needed for One-Hit Wonder
local PACKMULE_MIN_ITEMS = 10
local HOARDER_MIN_JUNK = 5
local VENDOR_MIN_ITEMS = 4   -- items needed for Vendor's Friend
local VENDOR_SHARE = 0.95    -- and this much of their loot's value is its vendor value
local ERRAND_MIN_QUEST = 3
local EPIC = 4               -- item quality
local UNCOMMON = 2           -- item quality: green
local HEARTBREAK_MIN = 95    -- a roll lost with this number or more
local LOWBALL_MAX = 5        -- a roll won with this number or less
local HOT_STREAK = 3         -- rolls won in a row
local DRY_SPELL = 12         -- rolls lost in a row
local NEMESIS_MIN = 4        -- rolls lost to the same player
local OVERKILL_MAX = 100     -- copper: a Need win worth less than this is Overkill

-- How well `v` fits a scale on which `lo` just qualifies and `hi` is
-- remarkable: 0.3 at `lo`, 1 at `hi`, and on up to about 2 for values far
-- beyond `hi`. Nil below `lo`.
local function Fit(v, lo, hi)
    if v < lo then return end
    return 0.3 + 0.7 * math.min((v - lo) / (hi - lo), 2.5)
end

-- A consolation prize's fit: 0.25 for the best of the group at it, down
-- towards 0.1 for the others. Below the 0.3 that every other award needs,
-- so it only goes to a player that nothing else fits. Nil without `v`.
local function Ranked(v, best)
    if not v or v <= 0 or not best or best <= 0 then return end
    return 0.1 + 0.15 * v / best
end

-- How close an average roll is to the middle, for Average Joe: 30 at
-- exactly 50.5, nothing beyond 30 points away. Five rolls at least.
local function Middling(x)
    if x.rolls < 5 then return end
    return 30 - math.abs(x.avgRoll - 50.5)
end

local function Plural(n, one, many)
    return n == 1 and ("1 " .. one) or (n .. " " .. many)
end

-- How many players can hold the same award: one in a party, two in a
-- group of up to ten, three in anything bigger. Their titles are numbered
-- from the second on ("Hoarder II").
local function Holders(n)
    return (n <= 5 and 1) or (n <= 10 and 2) or 3
end
ns.AwardHolders = Holders
local NUMERALS = { "", " II", " III" }

-- Where `v` stands in `list`, a sorted list of every player's figure: 1
-- for the best, 2 for the next. Equal figures stand together.
local function Standing(list, v)
    for i, other in ipairs(list) do
        if other == v then return i end
    end
    return #list + 1
end

-- "Most <what>" for whoever stands first, "2nd most <what>" for the next.
local function Nth(standing, what, first)
    first = first or "Most"
    if standing <= 1 then return first .. " " .. what end
    return ns.Ordinal(standing) .. " " .. first:lower() .. " " .. what
end

-- For the role and class titles: how far a player's loot is above (or
-- below) the average of a set of players (`set`: { n, total }), as a
-- fit: one and a half times the average just qualifies, three times is
-- remarkable; and half of it, or nothing at all. Nil for a set of fewer
-- than `min` players, or with no loot.
local function Above(p, set, min)
    if not set or set.n < min or set.total <= 0 then return end
    return Fit(p.market / (set.total / set.n), 1.5, 3)
end
local function Below(p, set, min)
    if not set or set.n < min or set.total <= 0 then return end
    return Fit(1 - p.market / (set.total / set.n), 0.5, 1)
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

-- "40% above the tanks' average"
local function AgainstText(p, set, whose)
    local ratio = p.market / (set.total / set.n)
    return ("%d%% %s %s"):format(Percent(math.abs(ratio - 1)), ratio >= 1 and "above" or "below", whose)
end

-- The dice awards' text. `diceLogged`: the figures come from the roll log,
-- so they only cover rolls that were a contest (see Moments).
local function DiceText(x)
    return ("Average roll of %.0f over %d %s"):format(x.diceAvg, x.diceRolls,
        x.diceLogged and "contested rolls" or "rolls")
end

local AWARDS = {
    -- Bound gear counts at vendor price, so Ninja mostly reflects needing
    -- things that can be sold.
    { key = "ninja", title = "Ninja", icon = "Ability_Stealth",
      how = "Won the most value on Need rolls: at least 1g and a tenth of the run's loot.",
      fit = function(p, _, g)
          if p.needValue < g.need or p.needValue < NINJA_MIN then return end
          return Fit(p.needValue / g.total, 0.1, 0.3)
      end,
      detail = function(p, _, g)
          return { text = Nth(Standing(g.board.need, p.needValue), "value won on Need rolls"), amount = p.needValue }
      end },
    { key = "lucky", title = "Luckiest", icon = "INV_Misc_Coin_02",
      how = "Won the most on Greed rolls, clearly more than an even split of the rolled loot.",
      fit = function(p, _, g)
          if p.greedValue <= 0 or p.greedValue < g.greed then return end
          -- What they won beyond an even split of the Greed loot, measured
          -- against an equal share of the whole run.
          return Fit((p.greedValue - g.greedAll / g.n) / g.equal, 0.1, 0.6)
      end,
      detail = function(p, _, g)
          return { text = Nth(Standing(g.board.greed, p.greedValue), "value won on Greed rolls"),
                   amount = p.greedValue }
      end },
    { key = "jackpot", title = "Jackpot", icon = "INV_Misc_Gem_Diamond_02",
      how = "Got the most valuable single item, worth 1g or more.",
      fit = function(p, _, g)
          if p.bestValue < g.best or p.bestValue < JACKPOT_MIN then return end
          return Fit(p.bestValue / g.total, 0, 0.3)
      end,
      detail = function(p, _, g)
          return { text = Nth(Standing(g.board.best, p.bestValue), "single item of the run", "Best"),
                   link = p.bestLink, amount = p.bestValue }
      end },
    { key = "lionshare", title = "Lion's Share", icon = "Ability_Druid_CatForm", minPlayers = 3,
      how = "Topped the loot, far above an equal share: 36% or more in a group of five.",
      -- Where their share sits between an equal one (0) and everything (1).
      fit = function(p, _, g)
          if p.rank > g.holders then return end
          return Fit((p.market / g.total - 1 / g.n) / (1 - 1 / g.n), 0.2, 0.5)
      end,
      detail = function(p, _, g)
          return { text = ("Took %d%% of the run's loot"):format(Percent(p.market / g.total)), amount = p.market }
      end },
    { key = "fairshare", title = "Fair Share", icon = "INV_Misc_Coin_05", minPlayers = 3,
      how = "Ended within a tenth of an equal share. Groups of 3 or more.",
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
      detail = function(p, _, g)
          return { text = Nth(Standing(g.board.market, p.market), "loot of the group", "Least"), amount = p.market }
      end },
    { key = "onehit", title = "One-Hit Wonder", icon = "INV_Misc_Gem_Ruby_01",
      how = "Got 70% or more of their loot from a single item (3 items or more).",
      fit = function(p)
          if p.count < ONEHIT_MIN_ITEMS or p.market <= 0 then return end
          return Fit(p.bestValue / p.market, 0.7, 1)
      end,
      detail = function(p)
          return { text = ("%d%% of their loot is one item"):format(Percent(p.bestValue / p.market)),
                   link = p.bestLink, amount = p.bestValue }
      end },
    { key = "purple", title = "Purple Rain", icon = "INV_Misc_Gem_Amethyst_02",
      how = "Looted an epic.",
      fit = function(p) return p.bestQuality >= EPIC and 1 or nil end,
      detail = function(p)
          local best
          for _, e in ipairs(p.all.items) do
              if Quality(e) >= EPIC and (not best or e.vendor > best.vendor) then best = e end
          end
          return { text = "Looted an epic", link = best and best.link }
      end },
    { key = "farmer", title = "The Farmer", icon = "INV_Misc_Pelt_Wolf_01",
      how = "Took a large part of the run's profession materials.",
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
      how = "Picked up the most items, well above average, yet ended below an equal share.",
      fit = function(p, _, g)
          if p.count < PACKMULE_MIN_ITEMS or p.count < g.count or p.market >= g.equal then return end
          return Fit(p.count / (g.items / g.n), 1.3, 2.5)
      end,
      detail = function(p) return { text = ("%d items, and still below an equal share"):format(p.count) } end },
    { key = "hoarder", title = "Hoarder", icon = "INV_Misc_Bag_10",
      how = "Picked up 5 or more pieces of junk, 1.5 times the group's average or more.",
      fit = function(p, _, g)
          local junk = p.cats.junk and p.cats.junk.count or 0
          if junk < HOARDER_MIN_JUNK then return end
          return Fit(junk / (g.junk / g.n), 1.5, 3)
      end,
      detail = function(p) return { text = ("Picked up %d pieces of junk"):format(p.cats.junk.count) } end },
    { key = "vendor", title = "Vendor's Friend", icon = "INV_Misc_Coin_06",
      how = "Got nothing worth auctioning, in a run where others did (4 items or more).",
      fit = function(p, _, g)
          if db.options.valueMode == "vendor" or not ns.HasPriceSource() then return end
          -- Items only: coins are worth the same either way.
          local vendor, market = p.vendor - p.money, p.market - p.money
          if p.count < VENDOR_MIN_ITEMS or market <= 0 or vendor < market * VENDOR_SHARE then return end
          -- The more of the run's value is above vendor price, the more it stands out.
          return Fit(1 - (g.vendor - g.money) / (g.total - g.money), 0.2, 0.6)
      end,
      detail = function(p)
          return { text = "Nothing worth putting up for auction", amount = p.market - p.money }
      end },
    { key = "errand", title = "Errand Runner", icon = "INV_Misc_Note_01",
      how = "Picked up 3 or more quest items, 1.5 times the group's average or more.",
      fit = function(p, _, g)
          local quest = p.cats.quest and p.cats.quest.count or 0
          if quest < ERRAND_MIN_QUEST then return end
          return Fit(quest / (g.quest / g.n), 1.5, 3)
      end,
      detail = function(p) return { text = ("Picked up %d quest items"):format(p.cats.quest.count) } end },
    { key = "nat100", title = "Natural 100", icon = "INV_Crown_01", group = "moment",
      how = "Rolled a 100.",
      fit = function(_, x) return x.high == 100 and 0.75 or nil end,
      detail = function() return { text = "Rolled a 100" } end },
    { key = "snakeeyes", title = "Snake Eyes", icon = "INV_Misc_Bone_HumanSkull_01", group = "moment",
      how = "Rolled a 1.",
      fit = function(_, x) return x.low == 1 and 0.75 or nil end,
      detail = function() return { text = "Rolled a 1" } end },
    { key = "hotdice", title = "Loaded Dice", icon = "INV_Misc_Dice_02",
      how = "Rolled far above average when it counted: about 65 over 15 rolls, or 76 over 5.",
      fit = function(_, x)
          return x.diceRolls >= DICE_MIN_ROLLS and Fit(x.diceLuck, DICE_LUCK, DICE_LUCK_HIGH) or nil
      end,
      detail = function(_, x) return { text = DiceText(x) } end },
    { key = "colddice", title = "Cursed Dice", icon = "INV_Misc_Dice_01",
      how = "Rolled far below average when it counted: about 36 over 15 rolls, or 25 over 5.",
      fit = function(_, x)
          return x.diceRolls >= DICE_MIN_ROLLS and Fit(-x.diceLuck, DICE_LUCK, DICE_LUCK_HIGH) or nil
      end,
      detail = function(_, x) return { text = DiceText(x) } end },
    { key = "window", title = "Window Shopper", icon = "INV_Misc_Spyglass_02",
      how = "Rolled on 4 or more items and won none.",
      fit = function(p, x)
          if p.needWins + p.greedWins > 0 then return end
          return Fit(x.rolls, 4, 15)
      end,
      detail = function(_, x) return { text = ("Rolled %d times, won nothing"):format(x.rolls) } end },
    { key = "saint", title = "The Saint", icon = "Spell_Holy_HolyBolt",
      how = "Passed on 2 or more rolls.",
      fit = function(_, x) return Fit(x.passes, 2, 8) end,
      detail = function(_, x) return { text = ("Passed on %d rolls"):format(x.passes) } end },

    -- Moments: odd things the dice did (figures from Moments below).
    { key = "heartbreak", title = "Heartbreak", icon = "Spell_BrokenHeart", group = "moment",
      how = "Lost a roll with 95 or more.",
      fit = function(_, x) return x.lost >= HEARTBREAK_MIN and Fit(x.lost, HEARTBREAK_MIN, 99) or nil end,
      detail = function(_, x) return { text = ("Lost a roll with a %d"):format(x.lost), link = x.lostLink } end },
    { key = "lowball", title = "Lowball", icon = "INV_Misc_Ticket_Tarot_Maelstrom_01", group = "moment",
      how = "Won a roll with 5 or less, against at least one other roll.",
      fit = function(_, x)
          if not x.won or x.won > LOWBALL_MAX then return end
          return Fit(LOWBALL_MAX + 1 - x.won, 1, LOWBALL_MAX)
      end,
      detail = function(_, x) return { text = ("Won a roll with a %d"):format(x.won), link = x.wonLink } end },
    { key = "photo", title = "Photo Finish", icon = "INV_Misc_PocketWatch_01", group = "moment",
      how = "Won a roll by a single point.",
      fit = function(_, x) return x.photo and 0.4 or nil end,
      detail = function(_, x) return { text = "Won a roll " .. x.photo, link = x.photoLink } end },
    { key = "dejavu", title = "Deja Vu", icon = "Spell_Holy_MindVision", group = "moment",
      how = "Rolled the same number twice in a row.",
      fit = function(_, x) return x.repeated and 0.5 or nil end,
      detail = function(_, x) return { text = ("Rolled %d twice in a row"):format(x.repeated) } end },
    { key = "hotstreak", title = "Hot Streak", icon = "Spell_Fire_Fireball02", group = "moment",
      how = "Won 3 rolls in a row, each against another roller.",
      fit = function(_, x) return Fit(x.winRun, HOT_STREAK, 6) end,
      detail = function(_, x) return { text = ("Won %d rolls in a row"):format(x.winRun) } end },
    { key = "dryspell", title = "Dry Spell", icon = "Spell_Frost_ChainsOfIce", group = "moment",
      how = "Lost 12 rolls in a row.",
      fit = function(_, x) return Fit(x.loseRun, DRY_SPELL, 20) end,
      detail = function(_, x) return { text = ("Lost %d rolls in a row"):format(x.loseRun) } end },
    { key = "nemesis", title = "Nemesis", icon = "Spell_Shadow_PsychicHorrors", group = "moment",
      how = "Lost 4 or more rolls to one player, who won most of the rolls you both entered.",
      fit = function(_, x) return x.nemesis > 0 and Fit(x.nemesis, NEMESIS_MIN, 8) or nil end,
      detail = function(_, x)
          return { text = ("Lost %d rolls to %s"):format(x.nemesis, ns.DisplayName(x.nemesisName)) }
      end },
    { key = "overkill", title = "Overkill", icon = "Ability_Warrior_SavageBlow", group = "moment",
      how = "Won a Need roll on something worth less than 1s.",
      fit = function(_, x) return x.overkill and 0.4 or nil end,
      detail = function(_, x)
          return { text = "Won on Need, worth next to nothing", link = x.overkillLink, amount = x.overkill }
      end },

    -- Titles from WoW lore, and for roles, classes and bosses. The role
    -- and class ones need several players of one role or class, so they
    -- mostly turn up in raids. Rolls are measured against the group's
    -- average: in a run where everyone rolls on everything, losing twenty
    -- rolls is normal.
    { key = "afk", title = "AFK", icon = "Spell_Nature_Sleep",
      how = "Picked up nothing and rolled on nothing.",
      fit = function(p, x) return p.count == 0 and x.rolls == 0 and x.entered == 0 and 1.1 or nil end,
      detail = function() return { text = "Nothing picked up, nothing rolled on" } end },
    { key = "hunterloot", title = "Hunter Loot", icon = "INV_Weapon_Bow_07",
      how = "A hunter who won on Need. Everything is hunter loot.",
      -- Any Need win will do; it grows with the wins beyond an even share.
      fit = function(p, _, g)
          if p.class ~= "HUNTER" or p.needWins < 1 then return end
          return 0.35 + math.min(0.2 * math.max(p.needWins - g.needWinsAll / g.n, 0), 1.15)
      end,
      detail = function(p)
          return { text = "A hunter, and won " .. Plural(p.needWins, "Need roll", "Need rolls"),
                   amount = p.needValue > 0 and p.needValue or nil }
      end },
    { key = "needfirst", title = "Need Before Greed", icon = "Ability_Warrior_Charge",
      how = "Chose Need on 2 rolls more than the group's average, or more.",
      fit = function(_, x, g) return Fit(x.needs - g.needsAvg, 2, 6) end,
      detail = function(_, x) return { text = ("Chose Need on %d rolls"):format(x.needs) } end },
    { key = "dkp", title = "50 DKP Minus", icon = "Ability_Warrior_WarCry",
      how = "Lost 3 rolls more than the group's average, or more.",
      fit = function(_, x, g) return Fit(x.losses - g.lossesAvg, 3, 8) end,
      detail = function(_, x) return { text = ("Lost %d rolls"):format(x.losses) } end },
    { key = "tanktax", title = "Tank Tax", icon = "INV_Shield_06",
      how = "A tank with 1.5 times the tanks' average loot, or more (2 tanks or more).",
      fit = function(p, _, g) return p.role == "TANK" and Above(p, g.roles.TANK, 2) or nil end,
      detail = function(p, _, g)
          return { text = AgainstText(p, g.roles.TANK, "the tanks' average"), amount = p.market }
      end },
    { key = "healertip", title = "Healer's Tip", icon = "Spell_Holy_FlashHeal",
      how = "A healer with 1.5 times the healers' average loot, or more (2 healers or more).",
      fit = function(p, _, g) return p.role == "HEALER" and Above(p, g.roles.HEALER, 2) or nil end,
      detail = function(p, _, g)
          return { text = AgainstText(p, g.roles.HEALER, "the healers' average"), amount = p.market }
      end },
    { key = "topdps", title = "Top DPS", icon = "Ability_DualWield",
      how = "A damage dealer with 1.5 times the damage dealers' average loot, or more.",
      fit = function(p, _, g) return p.role == "DAMAGER" and Above(p, g.roles.DAMAGER, 2) or nil end,
      detail = function(p, _, g)
          return { text = AgainstText(p, g.roles.DAMAGER, "the damage dealers' average"), amount = p.market }
      end },
    { key = "classact", title = "Class Act", icon = "INV_Misc_Book_09",
      how = "Got 1.5 times the average loot of their class, or more (3 or more of it).",
      fit = function(p, _, g) return p.class and Above(p, g.classes[p.class], 3) or nil end,
      detail = function(p, _, g)
          return { text = AgainstText(p, g.classes[p.class], "their class's average"), amount = p.market }
      end },
    { key = "classclown", title = "Class Clown", icon = "Ability_Rogue_Disguise",
      how = "Got half the average loot of their class, or less (3 or more of it).",
      fit = function(p, _, g) return p.class and Below(p, g.classes[p.class], 3) or nil end,
      detail = function(p, _, g)
          return { text = AgainstText(p, g.classes[p.class], "their class's average"), amount = p.market }
      end },
    { key = "bosspet", title = "Boss's Pet", icon = "Ability_Hunter_BeastTaming",
      how = "Got loot from a boss: the biggest share first. One player per boss, one in a party.",
      each = function(sum, _, g)
          local list = {}
          for boss, loot in pairs(g.bossLoot) do
              local total, top = 0, 0
              for _, value in pairs(loot) do total, top = total + value, math.max(top, value) end
              for _, p in ipairs(sum.players) do
                  local value = loot[p.name]
                  if value and value > 0 then
                      -- Just above the consolation prizes: one drop to one
                      -- player is what most bosses give.
                      list[#list + 1] = { p = p, fit = 0.3 + 0.1 * value / total, slot = boss,
                                          data = { boss = g.bossNames[boss], value = value, top = value == top } }
                  end
              end
          end
          return list
      end,
      detail = function(_, _, _, data)
          return { text = (data.top and "Most loot from %s" or "Loot from %s"):format(data.boss or "a boss"),
                   amount = data.value }
      end },

    -- Consolation prizes: scored below 0.3 (see Ranked), so they only go
    -- to players that nothing above fits, the best of them first. Whoever
    -- gets one need not be the best of the group at it, so `how` never
    -- says "the most".
    { key = "collector", title = "Collector", icon = "INV_Box_01", group = "consolation",
      how = "Won 2 rolls or more.",
      fit = function(p, _, g)
          local wins = p.needWins + p.greedWins
          return wins >= 2 and Ranked(wins, g.most.wins) or nil
      end,
      detail = function(p) return { text = ("Won %d rolls"):format(p.needWins + p.greedWins) } end },
    { key = "busy", title = "Busy Hands", icon = "INV_Gauntlets_04", group = "consolation",
      how = "Entered 3 rolls or more.",
      fit = function(_, x, g) return x.rolls >= 3 and Ranked(x.rolls, g.most.rolls) or nil end,
      detail = function(_, x) return { text = ("Entered %d rolls"):format(x.rolls) } end },
    { key = "second", title = "Always Second", icon = "INV_Misc_Coin_03", group = "consolation",
      how = "Second best of 3 or more rollers, twice or more.",
      fit = function(_, x, g) return x.second >= 2 and Ranked(x.second, g.most.second) or nil end,
      detail = function(_, x) return { text = ("Second best roll %d times"):format(x.second) } end },
    { key = "avgjoe", title = "Average Joe", icon = "Achievement_Character_Human_Male", group = "consolation",
      how = "Averaged close to 50 over 5 rolls or more.",
      fit = function(_, x, g) return Ranked(Middling(x), g.most.middling) end,
      detail = function(_, x) return { text = ("Average roll of %.0f over %d rolls"):format(x.avgRoll, x.rolls) } end },
    { key = "magpie", title = "Magpie", icon = "INV_Misc_Gem_Crystal_02", group = "consolation",
      how = "Picked up 2 or more green or better items.",
      fit = function(_, x, g) return x.magpie >= 2 and Ranked(x.magpie, g.most.magpie) or nil end,
      detail = function(_, x) return { text = ("%d green or better items"):format(x.magpie) } end },
    { key = "bossmagnet", title = "Boss Magnet", icon = "INV_Misc_Head_Dragon_01", group = "consolation",
      how = "Got loot from bosses.",
      fit = function(_, x, g) return Ranked(x.boss, g.most.boss) end,
      detail = function(_, x) return { text = "Loot from bosses", amount = x.boss } end },
    { key = "trashpanda", title = "Trash Panda", icon = "Ability_Druid_Cower", group = "consolation",
      how = "Got loot from trash.",
      fit = function(_, x, g) return Ranked(x.trash, g.most.trash) end,
      detail = function(_, x) return { text = "Loot from trash", amount = x.trash } end },
    { key = "leftovers", title = "Leftovers", icon = "INV_Misc_Food_15", group = "consolation",
      how = "Won an item nobody else rolled on.",
      fit = function(_, x, g) return Ranked(x.leftovers, g.most.leftovers) end,
      detail = function(_, x)
          return { text = "Won " .. Plural(x.leftovers, "item", "items") .. " nobody else rolled on" }
      end },
    { key = "booby", title = "Booby Prize", icon = "INV_Misc_Gift_01", group = "consolation",
      how = "For their cheapest item.",
      fit = function(_, x, g) return x.cheapest and Ranked(g.cheapest / x.cheapest, 1) or nil end,
      detail = function(_, x, g)
          return { text = x.cheapest == g.cheapest and "Cheapest item of the run" or "Their cheapest item",
                   link = x.cheapestLink, amount = x.cheapest }
      end },
    { key = "runnerup", title = "Runner-up", icon = "Ability_Rogue_Sprint", group = "consolation", minPlayers = 3,
      how = "Got the second most loot.",
      fit = function(p) return p.rank == 2 and p.market > 0 and 0.15 or nil end,
      detail = function(p) return { text = "Second most loot", amount = p.market } end },
    { key = "firstdibs", title = "First Dibs", icon = "Ability_Druid_Dash", group = "consolation",
      how = "Picked up the run's first item.",
      fit = function(p, _, g) return g.first and g.first.name == p.name and 0.1 or nil end,
      detail = function(_, _, g) return { text = "First item of the run", link = g.first.link } end },
    { key = "lastcall", title = "Last Call", icon = "INV_Drink_07", group = "consolation",
      how = "Picked up the run's last item.",
      fit = function(p, _, g) return g.last and g.last.name == p.name and 0.1 or nil end,
      detail = function(_, _, g) return { text = "Last item of the run", link = g.last.link } end },
}

local TOURIST = { key = "tourist", title = "Tourist", icon = "INV_Misc_Map_01", group = "consolation",
                  how = "Fitted nothing else." }

-- Every award there is, in the order of the guide: the awards, then the
-- moments, then the consolation prizes and Tourist. Each has key, title,
-- icon, how and group (nil for the awards; the rest of an entry is for
-- working the awards out).
function ns.AwardGuide()
    local list = {}
    for _, group in ipairs({ false, "moment", "consolation" }) do
        for _, def in ipairs(AWARDS) do
            if (def.group or false) == group then list[#list + 1] = def end
        end
    end
    list[#list + 1] = TOURIST
    return list
end

-- An award's title by its key ("Hoarder" for "hoarder"), nil for a key
-- no award has.
do
    local titles
    function ns.AwardTitle(key)
        if not titles then
            titles = {}
            for _, def in ipairs(ns.AwardGuide()) do titles[def.key] = def.title end
        end
        return titles[key]
    end
end

-- A player's awards in your runs, the most frequent first (on a tie, the
-- one they had last, then by title): up to `n` of { key, title, count }.
-- `who` is their entry in db.people.
function ns.TopAwards(who, n)
    local list = {}
    for key, count in pairs(who and who.awards or {}) do
        local title = ns.AwardTitle(key)
        if title and count > 0 then list[#list + 1] = { key = key, title = title, count = count } end
    end
    local last = who and who.lastAward
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.key == last) ~= (b.key == last) then return a.key == last end
        return a.title < b.title
    end)
    for i = #list, (n or #list) + 1, -1 do list[i] = nil end
    return list
end

-- The same as text: "Hoarder x4, Jackpot x2". Nil when there are none.
function ns.AwardsText(who, n)
    local parts = {}
    for i, a in ipairs(ns.TopAwards(who, n)) do parts[i] = ("%s x%d"):format(a.title, a.count) end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- The figures behind the moments and the consolation prizes, from the
-- roll log, the pickup log and the items. Adds to each player's roll
-- figures `x`:
--   lost, lostLink      their best number in a roll they lost
--   won, wonLink        their lowest winning number, beating another number
--   photo, photoLink    a roll won by one point, as "54 to 53"
--   repeated            a number they rolled twice in a row
--   winRun, loseRun     most rolls won, and lost, in a row
--   nemesis, nemesisName  rolls lost to the player who beat them most, if
--                       that player won over half the rolls they both entered
--   second              rolls where theirs was the second best number
--   leftovers           rolls won that nobody else rolled on
--   overkill, overkillLink  their cheapest Need win below OVERKILL_MAX
--   cheapest, cheapestLink  their cheapest item
--   boss, trash         loot value picked up after a boss kill, and elsewhere
--   magpie              items of uncommon quality or better
--   needs, losses, entered  rolls they chose Need on, lost, and entered
--   diceRolls, diceAvg, diceLuck  their numbers in rolls that were a
--                       contest: rolled the same way as the winner, by
--                       two players or more. A lone roll, or a Greed
--                       against a Need, decides nothing. (Runs recorded
--                       without a roll log: every number they rolled.)
-- and to the group's `g`: the best of each figure (g.most), the cheapest
-- item of the run (g.cheapest), the first and last pickups (g.first,
-- g.last: { name, link }), each boss's loot by player (g.bossLoot,
-- g.bossNames), the group's average of needs and losses (g.needsAvg,
-- g.lossesAvg) and its Need wins in all (g.needWinsAll). Runs without a
-- log simply have none of it.
local function Moments(s, sum, extra, g)
    for _, x in pairs(extra) do
        x.lost, x.second, x.leftovers, x.winRun, x.loseRun, x.nemesis = 0, 0, 0, 0, 0, 0
        x.boss, x.trash, x.magpie = 0, 0, 0
        x.needs, x.losses, x.entered = 0, 0, 0
        x.diceRolls, x.diceAvg, x.diceLuck = x.rolls, x.avgRoll, x.luck
    end

    -- Rolls, in the order they were won.
    local streak, lostTo, together, lastNumber, dice = {}, {}, {}, {}, {}
    for name in pairs(extra) do
        streak[name], lostTo[name], together[name] = { win = 0, lose = 0 }, {}, {}
        dice[name] = { sum = 0, n = 0 }
    end
    for _, r in ipairs(ns.RunRolls(s)) do
        local winner = extra[r.winner]
        local entered, numbers, passes, wnum = {}, {}, 0, nil
        local rivals = 0 -- players who rolled the same way as the winner, the winner included
        for _, roll in ipairs(r.rolls) do
            if roll.choice == "pass" then
                passes = passes + 1
            elseif extra[roll.name] then
                entered[#entered + 1] = roll.name
            end
            if roll.choice == r.method then rivals = rivals + 1 end
            if roll.choice == "need" and extra[roll.name] then
                extra[roll.name].needs = extra[roll.name].needs + 1
            end
            -- Those who rolled the same way as the winner: the numbers that
            -- decided it. RunRolls lists them highest first.
            if roll.choice == r.method and roll.roll then numbers[#numbers + 1] = roll end
            if roll.name == r.winner then wnum = roll.roll end
            local x = extra[roll.name]
            if x and roll.roll then
                if lastNumber[roll.name] == roll.roll then x.repeated = roll.roll end
                lastNumber[roll.name] = roll.roll
            end
        end
        -- A number counts for the dice awards only where it could decide
        -- something.
        if rivals >= 2 then
            for _, roll in ipairs(numbers) do
                local d = dice[roll.name]
                if d then d.sum, d.n = d.sum + roll.roll, d.n + 1 end
            end
        end
        for _, a in ipairs(entered) do
            local x, run = extra[a], streak[a]
            x.entered = x.entered + 1
            if a == r.winner then
                -- A win nobody rolled against ends a losing run, but is no
                -- part of a winning one.
                run.win, run.lose = run.win + (rivals >= 2 and 1 or 0), 0
            else
                run.win, run.lose = 0, run.lose + 1
                x.losses = x.losses + 1
                lostTo[a][r.winner] = (lostTo[a][r.winner] or 0) + 1
            end
            x.winRun, x.loseRun = math.max(x.winRun, run.win), math.max(x.loseRun, run.lose)
            for _, b in ipairs(entered) do
                if b ~= a then together[a][b] = (together[a][b] or 0) + 1 end
            end
        end
        local runnerUp
        for _, roll in ipairs(numbers) do
            local x = extra[roll.name]
            if x and roll.name ~= r.winner then
                runnerUp = runnerUp or roll
                if roll.roll > x.lost then
                    local e = ns.RollItem(s, r)
                    x.lost, x.lostLink = roll.roll, e and e.link
                end
            end
        end
        if winner and wnum and runnerUp then
            local e
            if not winner.won or wnum < winner.won then
                e = ns.RollItem(s, r)
                winner.won, winner.wonLink = wnum, e and e.link
            end
            if wnum - runnerUp.roll == 1 and not winner.photo then
                e = e or ns.RollItem(s, r)
                winner.photo, winner.photoLink = ("%d to %d"):format(wnum, runnerUp.roll), e and e.link
            end
        end
        if runnerUp and #numbers >= 3 and extra[runnerUp.name] then
            extra[runnerUp.name].second = extra[runnerUp.name].second + 1
        end
        if winner and #entered == 1 and entered[1] == r.winner and passes >= 2 then
            winner.leftovers = winner.leftovers + 1
        end
    end
    if s.rollLog then
        for name, d in pairs(dice) do
            local x = extra[name]
            x.diceLogged = true
            x.diceRolls, x.diceAvg = d.n, d.n > 0 and d.sum / d.n or 0
            x.diceLuck = d.n > 0 and RollLuck(x.diceAvg, d.n) or 0
        end
    end
    for a, beaten in pairs(lostTo) do
        local x = extra[a]
        for b, n in pairs(beaten) do
            if n >= NEMESIS_MIN and n / (together[a][b] or n) > 0.5 and n > x.nemesis then
                x.nemesis, x.nemesisName = n, b
            end
        end
    end

    -- Items: the cheapest, the cheapest won on Need, and the green ones.
    -- Their own pickups only, not a share of someone else's.
    for _, p in ipairs(sum.players) do
        local x = extra[p.name]
        for _, e in ipairs(p.all.items) do
            local unit = e.from and 0 or EntryMarket(e) / e.count
            if Quality(e) >= UNCOMMON and not e.from then x.magpie = x.magpie + e.count end
            if unit > 0 then
                if not x.cheapest or unit < x.cheapest then x.cheapest, x.cheapestLink = unit, e.link end
                if (e.need or 0) > 0 and unit < OVERKILL_MAX and (not x.overkill or unit < x.overkill) then
                    x.overkill, x.overkillLink = unit, e.link
                end
            end
        end
    end

    -- Pickups: boss loot and trash, and who picked up first and last.
    local picks = ns.Pickups(s) or {}
    g.bossLoot, g.bossNames = {}, {}
    for _, pick in ipairs(picks) do
        local x = extra[pick.name]
        local source, boss = ns.PickupSource(s, pick)
        if x and source == "boss" then
            x.boss = x.boss + pick.value
            if boss then
                local loot = g.bossLoot[boss] or {}
                g.bossLoot[boss], g.bossNames[boss] = loot, s.bosses[boss].name
                loot[pick.name] = (loot[pick.name] or 0) + pick.value
            end
        end
        if x and source == "trash" then x.trash = x.trash + pick.value end
    end
    if #picks > 0 then
        g.first = { name = picks[1].name, link = picks[1].e.link }
        g.last = { name = picks[#picks].name, link = picks[#picks].e.link }
    end

    g.most = { wins = 0, rolls = 0, second = 0, middling = 0, magpie = 0, boss = 0, trash = 0, leftovers = 0 }
    g.needsAvg, g.lossesAvg, g.needWinsAll = 0, 0, 0
    local most = g.most
    for _, p in ipairs(sum.players) do
        local x = extra[p.name]
        g.needsAvg, g.lossesAvg = g.needsAvg + x.needs / g.n, g.lossesAvg + x.losses / g.n
        g.needWinsAll = g.needWinsAll + p.needWins
        most.wins = math.max(most.wins, p.needWins + p.greedWins)
        most.rolls = math.max(most.rolls, x.rolls)
        most.second = math.max(most.second, x.second)
        most.middling = math.max(most.middling, Middling(x) or 0)
        most.magpie = math.max(most.magpie, x.magpie)
        most.boss = math.max(most.boss, x.boss)
        most.trash = math.max(most.trash, x.trash)
        most.leftovers = math.max(most.leftovers, x.leftovers)
        if x.cheapest then g.cheapest = math.min(g.cheapest or x.cheapest, x.cheapest) end
    end
end

-- Works out how well every player fits every award. Returns the fits,
-- best first, as { def, p, fit }, then the players' roll figures and the
-- group's figures; or nothing for a run with fewer than two players or
-- nothing of value.
local function AwardFits(s, sum)
    local n = #sum.players
    if n < 2 or sum.count == 0 or sum.market <= 0 then return end

    local g = { n = n, total = sum.market, equal = sum.market / n, vendor = sum.vendor, money = sum.money or 0,
                items = sum.count,
                holders = Holders(n), junk = 0, quest = 0, greedAll = 0, prof = 0, roles = {}, classes = {} }
    -- Every player's figure for the awards that go to the best of the
    -- group at something. Sorted below, best first.
    local board = { best = {}, need = {}, greed = {}, count = {}, market = {} }
    g.board = board
    local extra = {}
    for i, p in ipairs(sum.players) do
        board.best[i], board.need[i], board.greed[i] = p.bestValue, p.needValue, p.greedValue
        board.count[i], board.market[i] = p.count, p.market
        for field, sets in pairs({ role = g.roles, class = g.classes }) do
            if p[field] then
                local set = sets[p[field]] or { n = 0, total = 0 }
                sets[p[field]] = set
                set.n, set.total = set.n + 1, set.total + p.market
            end
        end
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
    for key, list in pairs(board) do
        table.sort(list, function(a, b)
            if key == "market" then return a < b end -- the smallest haul stands first
            return a > b
        end)
    end
    -- What it takes to be one of the `holders` best at each.
    local k = g.holders
    g.best, g.need, g.greed, g.count, g.least = board.best[k], board.need[k], board.greed[k], board.count[k],
        board.market[k]
    Moments(s, sum, extra, g)

    -- Every award a player qualifies for, best fit first. Equal fits are
    -- settled by the order of the list above, then by who looted more, so
    -- the result does not depend on how the window is sorted.
    local fits = {}
    for i, def in ipairs(AWARDS) do
        if n >= (def.minPlayers or 2) and def.each then
            for _, f in ipairs(def.each(sum, extra, g)) do
                f.def, f.order = def, i * 1000 + f.p.rank + f.slot / 1000
                fits[#fits + 1] = f
            end
        elseif n >= (def.minPlayers or 2) then
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
    local out, seen = {}, {}
    for _, f in ipairs(AwardFits(s, sum) or {}) do
        local list = out[f.p.name] or {}
        out[f.p.name] = list
        local once = f.p.name .. "\0" .. f.def.key -- an award with slots is listed once, at its best
        if not seen[once] then
            seen[once] = true
            list[#list + 1] = { title = f.def.title, fit = f.fit }
        end
    end
    return out
end

-- A run that is still going: nothing about it is final.
function ns.InProgress(s)
    return s == db.active and not s.leftAt
end

-- The awards to show for a run: none while it is still going, and none
-- when awards are switched off.
function ns.RunAwards(s, sum)
    if not db.options.showAwards or ns.InProgress(s) then return {} end
    return ns.Awards(s, sum)
end

-- Returns [playerName] = award, one for every player of the run. An award
-- is { key, title, icon, how, text, link, amount, place }. `sum` must be
-- a full summary (not the Need-only view). Empty for a run with fewer
-- than two players or nothing of value.
--
-- An award goes to as many players as the size of the group allows (see
-- Holders), best fit first, and each slot of a slotted award to one.
-- Players who cannot be told apart, with the same fit and the same loot,
-- share it whatever the limit: nothing but their names would choose
-- between them. `place` numbers an award's holders by fit, and the title
-- of the second and third says so ("Hoarder II"); holders with equal fits
-- (three players who each rolled a 100) have the same place. In a party,
-- where an award has one holder, a slotted award has one in all.
function ns.Awards(s, sum)
    local out = {}
    local fits, extra, g = AwardFits(s, sum)
    if not fits then return out end

    local given = {} -- [award or slot] = { n = holders, and the last one's fit, market and place }
    local slotted = {} -- [award with slots] = true once a party's only one is given
    for _, f in ipairs(fits) do
        local def, p = f.def, f.p
        if not out[p.name] and not (f.slot and slotted[def.key]) then
            local slot = f.slot and (def.key .. ":" .. f.slot) or def.key
            local got = given[slot]
            if not got then
                got = { n = 0 }
                given[slot] = got
            end
            local same = got.n > 0 and f.fit == got.fit
            if got.n < (f.slot and 1 or g.holders) or (same and p.market == got.market) then
                local place = same and got.place or got.n + 1
                got.n, got.fit, got.market, got.place = got.n + 1, f.fit, p.market, place
                local award = def.detail(p, extra[p.name], g, f.data)
                award.key, award.icon, award.how, award.place = def.key, def.icon, def.how, place
                award.fit = f.fit -- how far from normal it was: the Front page leads with the most
                award.title = def.title .. (NUMERALS[place] or "")
                out[p.name] = award
                if f.slot and g.holders == 1 then slotted[def.key] = true end
            end
        end
    end
    for _, p in ipairs(sum.players) do
        if not out[p.name] then
            out[p.name] = { key = TOURIST.key, title = TOURIST.title, icon = TOURIST.icon,
                            how = TOURIST.how, text = "Along for the ride", place = 1 }
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
-- their total loot value (`value`) and yours in the same runs (`mine`),
-- and how often they had each award (`awards`, by key: every award
-- alike, numbered or not, Tourist too), the latest in `lastAward`.
-- `mine` is nil for a player whose runs with you were all deleted before
-- it was kept.
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
        if p.name == ns.Me(s) then st.mine = p.market end
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

    -- Regulars: each player's loot, and yours beside it.
    local awards = ns.Awards(s, sum)
    for _, p in ipairs(sum.players) do
        if p.name ~= ns.Me(s) then
            local who = db.people[p.name]
            if not who then
                who = { runs = 0, value = 0, mine = 0, awards = {} }
                db.people[p.name] = who
            elseif who.mine == nil then
                -- Your side of their earlier runs is unknown: both totals
                -- start again, so that they always cover the same runs.
                who.runs, who.value, who.mine = 0, 0, 0
            end
            who.runs = who.runs + 1
            who.value = who.value + p.market
            who.mine = who.mine + st.mine
            who.class = p.class or who.class
            who.last = s.startedAt
            local a = awards[p.name]
            if a then
                who.awards = who.awards or {}
                who.awards[a.key] = (who.awards[a.key] or 0) + 1
                who.lastAward = a.key
            end
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
    -- How the dungeon's averages stood before this run: it is compared with
    -- the runs that came before it, however many follow.
    s.stats.prior = rec.runs
    if hadRuns then
        s.stats.avgGroup = math.floor(rec.sumGroup / rec.runs + 0.5)
        s.stats.avgMine = math.floor(rec.sumMine / rec.runs + 0.5)
    end
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
--     groupPct, minePct, priorRuns, earlier }  (every field optional)
-- priorRuns: the runs it is compared with. `earlier`: they are the ones
-- that came before it. (A run counted before that was kept is compared
-- with every other run of the dungeon.)
function ns.RunInsights(s, sum)
    local out = { duration = ns.RunDuration(s) }
    if out.duration and out.duration >= ns.MIN_TIMED_RUN then
        out.perHour = sum.market * 3600 / out.duration
    end
    local rec = s.instanceID and db.records[s.instanceID]
    -- Compared with the records: a run that is counted in them, or the one
    -- that is over and about to be. Not one still going, and not an old run
    -- the records never saw.
    if not rec or ns.InProgress(s) or s.example or (not s.recorded and s ~= db.active) then return out end

    local st = RunStats(s, sum)
    if s.recorded and s.stats then
        -- As it was counted: today's options and prices must not move an
        -- old run against its own average.
        st.group, st.mine = s.stats.group, s.stats.mine
    end
    local priorRuns, avgGroup, avgMine
    if s.recorded and s.stats and s.stats.prior then
        -- Against the runs before it, as they stood when it was counted.
        out.records, out.earlier = s.records, true
        priorRuns, avgGroup, avgMine = s.stats.prior, s.stats.avgGroup, s.stats.avgMine
    elseif s.recorded then
        -- Already counted in the records: leave it out of its own average.
        out.records = s.records
        priorRuns = rec.runs - 1
        if priorRuns > 0 and s.stats then
            avgGroup = (rec.sumGroup - s.stats.group) / priorRuns
            avgMine = (rec.sumMine - s.stats.mine) / priorRuns
        end
    else
        out.earlier = true
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
    ThatLuckyBastardDB = ThatLuckyBastardDB or {}
    db = ThatLuckyBastardDB
    db.history = db.history or {}
    db.shared = db.shared or {}   -- runs other players shared with you (Code.lua)
    -- Finished runs are saved packed, one code each (Code.lua): from here
    -- on they are the tables the rest of the addon works with.
    ns.unread = ns.UnpackRuns(db)
    db.capture = db.capture or {}
    db.records = db.records or {} -- [instanceID] = dungeon records
    db.people = db.people or {}   -- [player name] = figures for people you have run with
    db.me = db.me or {}           -- your own roll figures, over all runs
    db.drops = db.drops or {}     -- [instanceID][item id] = how often an item was seen
    db.dropRuns = db.dropRuns or {} -- [instanceID] = the number of runs those drops were counted over
    db.roles = db.roles or {}     -- [role] and
    db.classes = db.classes or {} -- [class] = how loot shares turn out
    db.options = db.options or {}
    -- Left behind by features that no longer exist.
    db.options.compact, db.options.popupBoss = nil, nil
    -- The podium window is gone. Its switch becomes the race's, and
    -- whoever had only the podium open at the end of a run gets the
    -- breakdown, where the race is run.
    local podium = db.options.podiumOnLeave
    if podium ~= nil then
        if db.options.race == nil then db.options.race = podium end
        if podium and db.options.popupLeave == false then db.options.popupLeave = true end
        db.options.podiumOnLeave = nil
    end
    db.finalBoss, db.bossCount = nil, nil
    -- Players' saved looks (race, sex and gear), from stand-in pictures
    -- that were never a likeness.
    local function DropLooks(s)
        s.lookedAt = nil
        for _, p in pairs(s.players or {}) do p.race, p.raceID, p.sex, p.gear = nil, nil, nil, nil end
    end
    if db.active then DropLooks(db.active) end
    for _, s in ipairs(db.history) do DropLooks(s) end
    -- Loot bingo is gone (0.7.1): its switch, its tally of lines, and what
    -- each run kept for it (the card, high and low rolls, your deaths).
    db.options.bingo, db.bingo = nil, nil
    local function DropBingo(s)
        s.bingo, s.rollHigh, s.rollLow, s.myDeaths = nil, nil, nil, nil
    end
    if db.active then DropBingo(db.active) end
    for _, list in ipairs({ db.history, db.shared }) do
        for _, s in ipairs(list) do DropBingo(s) end
    end
    -- Modern unless another theme was chosen (themes that no longer exist
    -- fall back to it too).
    if db.theme ~= "classic" and db.theme ~= "receipt" then db.theme = "modern" end
    ns.FillDefaults(db.options)
    -- Silver off with copper on was a fourth way to write amounts, which
    -- the options no longer offer: it reads as 12g.
    if not db.options.showSilver then db.options.showCopper = false end
    -- Amber, Light and Dark are gone (0.7.1): the teal again.
    local accent = db.options.accent
    if accent ~= "class" and accent ~= "custom" then db.options.accent = "teal" end
    ns.db = db
    ns.ApplyAccent()
end

-- Once, when the version that keeps your side arrives: each player's total
-- and yours are worked out again from the runs still kept, so that both
-- cover the same runs. Runs deleted earlier cannot be counted; a player
-- whose runs with you are all gone keeps their figures, with yours
-- unknown. Award counts stay as they were.
local function RebuildRegulars()
    if db.regularsBoth then return end
    db.regularsBoth = true
    local tally = {}
    for _, s in ipairs(db.history) do
        if not s.example and s.players then
            local sum = ns.Summarize(s)
            local me, mine = ns.Me(s), 0
            for _, p in ipairs(sum.players) do
                if p.name == me then mine = p.market end
            end
            for _, p in ipairs(sum.players) do
                if p.name ~= me then
                    local t = tally[p.name] or { runs = 0, value = 0, mine = 0, last = 0 }
                    tally[p.name] = t
                    t.runs, t.value, t.mine = t.runs + 1, t.value + p.market, t.mine + mine
                    t.class = p.class or t.class
                    t.last = math.max(t.last, s.startedAt or 0)
                end
            end
        end
    end
    for name, who in pairs(db.people) do
        if not tally[name] then who.mine = nil end
    end
    for name, t in pairs(tally) do
        local who = db.people[name]
        if not who then
            who = { awards = {} }
            db.people[name] = who
        end
        who.runs, who.value, who.mine, who.last = t.runs, t.value, t.mine, t.last
        who.class = t.class or who.class
    end
end

-- Once, when the version that counts every award alike arrives: each
-- player's awards are counted again from the runs still kept. Until then
-- only Ninja and Luckiest were counted, and those counts also cover runs
-- deleted since: each is kept where it is the higher.
local function RebuildAwards()
    if db.awardsCounted then return end
    db.awardsCounted = true
    local tally = {}
    for _, s in ipairs(db.history) do
        if not s.example and s.players then
            local ok, awards = pcall(function() return ns.Awards(s, ns.Summarize(s)) end)
            if ok then
                local me = ns.Me(s)
                for name, a in pairs(awards) do
                    if name ~= me then
                        local t = tally[name] or { counts = {}, at = -1 }
                        tally[name] = t
                        t.counts[a.key] = (t.counts[a.key] or 0) + 1
                        if (s.startedAt or 0) > t.at then t.at, t.last = s.startedAt or 0, a.key end
                    end
                end
            end
        end
    end
    for name, who in pairs(db.people) do
        local t = tally[name] or { counts = {} }
        local counts = t.counts
        for _, key in ipairs({ "ninja", "lucky" }) do
            local kept = math.max(counts[key] or 0, tonumber(who[key]) or 0)
            counts[key] = kept > 0 and kept or nil
            who[key] = nil
        end
        who.awards, who.lastAward = counts, t.last or who.lastAward
    end
end

function handlers.PLAYER_LOGIN()
    -- On Forever a character has a first and a second name. UnitName
    -- returns them separately; GetUnitName gives the full name, which is
    -- the form used for other group members and in loot messages.
    PLAYER_NAME = GetUnitName("player", true) or UnitName("player")
    ns.playerName = PLAYER_NAME
    PLAYER_CLASS = select(2, UnitClass("player"))
    ns.ApplyAccent() -- the class is known by now, should the accent be its colour
    if ns.ApplyScale then ns.ApplyScale() end -- the windows' size, from the options
    if (ns.unread or 0) > 0 then
        Print(("%d saved %s could not be read. Nothing was deleted: they are kept aside in the saved file.")
            :format(ns.unread, ns.unread == 1 and "run" or "runs"))
    end
    RebuildRegulars()
    RebuildAwards()
    -- People met in a single run, long ago, are forgotten: with random
    -- groups the list would otherwise grow for ever.
    local cutoff = time() - FORGET_AFTER
    for name, who in pairs(db.people) do
        if (who.runs or 0) <= 1 and (who.last or 0) < cutoff then db.people[name] = nil end
    end
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

function handlers.CHAT_MSG_MONEY(text)
    if type(text) ~= "string" then return end
    if issecret(text) then
        Capture("MONEY", "<hidden from addons>")
        return
    end
    Capture("MONEY", text)
    local copper, split = ParseMoney(text)
    if copper then RecordMoney(copper, split) end
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
function handlers.ENCOUNTER_END(encounterID, encounterName, _, _, success)
    local s = db.active
    if not Tracking(s) or issecret(success) or not (success == 1 or success == true) then return end
    -- Each boss counts once, so that two passes through a dungeon recorded
    -- as one run do not read as a fuller clear.
    local id = not issecret(encounterID) and encounterID or nil
    s.killed = s.killed or {}
    if id == nil or not s.killed[id] then
        if id ~= nil then s.killed[id] = true end
        s.kills = (s.kills or 0) + 1
        s.bosses = s.bosses or {}
        s.bosses[#s.bosses + 1] = {
            t = math.max(time() - s.startedAt, 0),
            name = type(encounterName) == "string" and not issecret(encounterName) and encounterName or nil,
        }
    end
end

-- Left the dungeon dead, and now alive outside it: you were resurrected
-- out there, so you are not running back in as a ghost. The run is shown
-- as when leaving alive, and coming back in will ask whether it is a new
-- run. (Both events can report the same return to life; the first clears
-- the note, so the second finds nothing to do.)
local function Revived()
    local s = db.active
    if not s or s.manual or not s.leftAt or not s.leftDead then return end
    if IsInInstance() or UnitIsDeadOrGhost("player") then return end
    s.leftDead = nil
    if HasLoot(s) then
        PrintSummary(s)
        ShowRunEnd(s)
    end
end
function handlers.PLAYER_ALIVE() Revived() end
function handlers.PLAYER_UNGHOST() Revived() end

-- Stamp the run so that, at the next login, we know how long we were away.
function handlers.PLAYER_LOGOUT()
    if db.active then db.active.lastSeen = time() end
    -- Today's prices are for today: none goes into the saved file.
    for _, s in ipairs(ns.AllRuns()) do
        for _, p in pairs(s.players or {}) do
            for _, e in pairs(p.items or {}) do e.now = nil end
        end
    end
    -- Last of all: the finished runs go into the saved file packed.
    ns.PackRuns(db)
    ns.saving = true
end

frame:SetScript("OnEvent", function(_, event, ...)
    -- Nothing can be handled before the saved data has loaded.
    if not db and event ~= "ADDON_LOADED" then return end
    -- The game went on after saving (it should not): the runs packed for
    -- the saved file are runs again.
    if ns.saving then
        ns.saving = nil
        if event ~= "ADDON_LOADED" then ns.WakeRuns(db) end
    end
    handlers[event](...)
end)
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event) -- some events may not exist on this client
end

----------------------------------------------------------------------
-- Pinning and deleting runs
--
-- A pinned run is never deleted: not by the limit on runs to keep, not
-- by /tlb clear, and not one at a time until it is unpinned. Deleting a
-- run removes it from the history only: the long-term statistics have
-- already counted it and are left as they are. Runs shared with you can
-- be deleted, not pinned.
----------------------------------------------------------------------

-- The saved list a run is in (db.history or db.shared), and where.
local function ListOf(s)
    for _, list in ipairs({ db.history, db.shared }) do
        for i, run in ipairs(list) do
            if run == s then return list, i end
        end
    end
end

local function IsStored(s)
    if not s or s.example then return false end
    return s == db.active or ListOf(s) ~= nil
end

-- Pins or unpins a run. Returns true when it did.
function ns.TogglePin(s)
    if not IsStored(s) or s.sharedBy then return false end
    s.pinned = (not s.pinned) or nil -- an unpinned run counts towards the limit again when the next run ends
    ns.Rerender()
    return true
end

-- Deletes one run. Returns true when it did.
function ns.DeleteRun(s)
    if not IsStored(s) or s.pinned then return false end
    if s == db.active then
        db.active = nil
        CheckZone() -- keep tracking if we are inside a dungeon
    else
        local list, i = ListOf(s)
        table.remove(list, i)
    end
    ns.Rerender()
    return true
end

local deleteTarget
StaticPopupDialogs["THATLUCKYBASTARD_DELETE_RUN"] = {
    text = ns.NAME .. "\n\nDelete this run?\n%s\n\n"
        .. "|cff909090This cannot be undone. Statistics keep what the run added.|r",
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
        Print(s and s.example and "Example runs are not saved." or "No run to delete.")
    elseif s.pinned then
        Print("This run is pinned. Unpin it first.")
    else
        deleteTarget = s
        StaticPopup_Show("THATLUCKYBASTARD_DELETE_RUN", (s.name or "Run") .. ", " .. ns.DateText(s.startedAt))
    end
end

-- Deletes every run that is not pinned, shared ones included. Returns
-- how many were left.
local function ClearRuns()
    wipe(db.shared)
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

StaticPopupDialogs["THATLUCKYBASTARD_CLEAR_RUNS"] = {
    text = ns.NAME .. "\n\nDelete all runs?\n%s\n\n"
        .. "|cff909090This cannot be undone. Pinned runs are kept. Statistics keep what the runs added.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local left = ClearRuns()
        CheckZone() -- keep tracking if this was asked for inside a dungeon
        ns.Rerender()
        if left > 0 then
            Print(("Runs deleted, except %d pinned."):format(left))
        else
            Print("All runs deleted.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Asks before deleting every run that is not pinned, saying how many
-- that is: yours (the one in progress among them) and those shared with
-- you.
function ns.AskClearRuns()
    local own, going = 0, db.active ~= nil and not db.active.pinned
    if going then own = 1 end
    for _, s in ipairs(db.history) do
        if not s.pinned then own = own + 1 end
    end
    local shared = #db.shared
    if own + shared == 0 then
        Print("No runs to delete: only pinned runs are kept.")
        return
    end
    local parts = {}
    if own > 0 then
        parts[1] = Plural(own, "run of yours", "runs of yours") .. (going and " (the one in progress too)" or "")
    end
    if shared > 0 then parts[#parts + 1] = shared .. " shared with you" end
    StaticPopup_Show("THATLUCKYBASTARD_CLEAR_RUNS", table.concat(parts, " and "))
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_THATLUCKYBASTARD1 = "/tlb"
SLASH_THATLUCKYBASTARD2 = "/lucky"
SlashCmdList.THATLUCKYBASTARD = function(msg)
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
    elseif cmd == "paper" then
        ns.OpenRunWindow("paper", ns.ViewedRun())
    elseif cmd == "race" then
        ns.ShowWindow(true, ns.ViewedRun()) -- the reveal again, for the run on show
        if not ns.Racing() then
            Print("No race: it takes the Race option, columns in podium order, and two players with loot.")
        end
    elseif cmd == "analysis" or cmd == "timeline" or cmd == "rolls" or cmd == "numbers" then
        ns.ShowAnalysis(cmd ~= "analysis" and cmd or nil, ns.ViewedRun())
    elseif cmd == "export" then
        ns.ShowExport(arg == "all" and "all" or "run", ns.ViewedRun())
    elseif cmd == "share" then
        ns.ToggleShare(ns.ViewedRun())
    elseif cmd == "import" then
        ns.ToggleImport()
    elseif cmd == "meter" then
        ns.ToggleMeter()
    elseif cmd == "capture" then
        if db.capturing then
            db.capturing = nil
            Print(("Capture stopped: %d lines. Type /reload to write them to the saved file."):format(#db.capture))
        else
            db.capturing = true
            db.capture = {}
            Print("Capture started: loot and roll messages are being recorded. Type /tlb capture again to stop.")
        end
    elseif cmd == "theme" then
        if not ns.SetTheme(arg) then
            Print("Themes: modern, classic, receipt. Example: /tlb theme receipt")
        end
    elseif cmd == "start" then
        NewSession(GetRealZoneText() or "Manual run", nil, true)
        Print("Manual run started. Use /tlb stop to end it.")
    elseif cmd == "stop" then
        if db.active then
            FinalizeSession()
            CheckZone() -- a run ended by hand inside a dungeon: tracking goes on with a new one
            Print("Run ended.")
            ns.ShowWindow()
        else
            Print("No run in progress.")
        end
    elseif cmd == "pin" then
        local s = ns.ViewedRun()
        if ns.TogglePin(s) then
            Print(s.pinned and "Run pinned." or "Run unpinned.")
        else
            Print("No saved run on show.")
        end
    elseif cmd == "delete" then
        ns.AskDeleteRun(ns.ViewedRun())
    elseif cmd == "clear" then
        ns.AskClearRuns()
    else
        Print("/tlb - the breakdown window")
        Print("/tlb options")
        Print("/tlb paper - the front page of the run on show")
        Print("/tlb race - the race again, for the run on show")
        Print("/tlb analysis - its timeline, rolls and numbers (also /tlb timeline, rolls, numbers)")
        Print("/tlb stats - dungeons, records, runs, luck, regulars, drops, roles")
        Print("/tlb search <item> - find an item in past runs")
        Print("/tlb awards - what each award means")
        Print("/tlb meter - the loot meter")
        Print("/tlb export - the run on show as text (/tlb export all: every run)")
        Print("/tlb share - share the run on show: a link in chat, or a code")
        Print("/tlb import - open a run from a code, and the runs shared with you")
        Print("/tlb pin - pin or unpin the run on show; pinned runs are never deleted")
        Print("/tlb delete - delete the run on show")
        Print("/tlb clear - delete all runs except pinned ones (asks first)")
        Print("/tlb start, /tlb stop - track a run by hand, outside a dungeon")
        Print("/tlb theme modern|classic|receipt")
        Print("/tlb capture - record raw loot messages, for troubleshooting")
    end
end

----------------------------------------------------------------------
-- Public hook used by ThatLuckyBastard_Example: runs added here are shown in
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

ThatLuckyBastard = {
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

function ThatLuckyBastard_OnAddonCompartmentClick()
    ns.ToggleWindow()
end
