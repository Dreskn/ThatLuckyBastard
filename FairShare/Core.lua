local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local issecret = issecretvalue or function() return false end

local POPUP_DELAY = 45          -- seconds after the last boss before the window opens
local RESUME_AFTER_DEATH = 1200 -- left the instance as a ghost: same run if back within 20 min
local RESUME_AFTER_EXIT = 180   -- walked out alive: same run only if back within 3 min
local RESUME_IDLE = 3600        -- reload / relog inside the instance

local PLAYER_NAME, PLAYER_CLASS
local db

ns.OPTION_DEFAULTS = {
    portrait = "2d",     -- "3d", "2d", "class" or "none"
    showVendor = true,   -- vendor value under each player
    showShare = true,    -- share of the run and over/under an equal split
    showIcons = true,    -- item icons
    showBar = true,      -- share bar (Modern theme)
    showTotals = true,   -- total / equal split line
    alignItems = false,  -- put the same item on the same line in every column
    useColumns = true,   -- one column per player for groups of 5 or fewer
    compact = false,     -- tighter rows
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
    sortItems = "value",    -- "value" or "name"
    popupBoss = true,       -- open the window after the last boss
    popupLeave = true,      -- open the window when leaving the instance
    chatSummary = false,    -- print a one-line result in chat when a run ends
    trackRaids = true,
    askNewRun = true,       -- ask "new run?" when re-entering a dungeon you walked out of
    maxHistory = 30,
    showMinimap = true,     -- minimap button
    minimapAngle = 215,     -- its position around the minimap, in degrees
}

local function Print(msg)
    print("|cff33ff99FairShare|r: " .. msg)
end

----------------------------------------------------------------------
-- Loot chat parsing (built from the client's own format strings, so it
-- works in every locale)
----------------------------------------------------------------------

local function BuildPattern(fmt)
    if type(fmt) ~= "string" then return end
    local order, n = {}, 0
    local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    pat = pat:gsub("%%(%d*)%%?%$?([sd])", function(i, t)
        n = n + 1
        order[n] = tonumber(i) or n
        return t == "s" and "(.+)" or "(%d+)"
    end)
    return "^" .. pat .. "$", order
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

local function UpdateRoster()
    local s = db.active
    if not Tracking(s) or not PLAYER_NAME then return end
    SetRole(AddPlayer(s, PLAYER_NAME, PLAYER_CLASS), "player")
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = GetUnitName(unit, true)
            if name and not issecret(name) and name ~= UNKNOWNOBJECT then
                local _, class = UnitClass(unit)
                if issecret(class) then class = nil end
                SetRole(AddPlayer(s, name, class), unit)
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

function ns.TrimHistory()
    while #db.history > db.options.maxHistory do table.remove(db.history) end
end

local PrintSummary -- defined below

local function FinalizeSession()
    local s = db.active
    if not s then return end
    PrintSummary(s) -- no-op if already printed or switched off
    db.active = nil
    -- Remember the last boss killed so the window can pop after it next
    -- time. A run with fewer kills than the best one seen (an abandoned
    -- run) does not overwrite it.
    local kills = #s.bosses
    if s.instanceID and kills > 0 and kills >= (db.bossCount[s.instanceID] or 0) then
        db.finalBoss[s.instanceID] = s.bosses[kills].id
        db.bossCount[s.instanceID] = kills
    end
    if HasLoot(s) then
        table.insert(db.history, 1, s)
        ns.TrimHistory()
    end
end

local function NewSession(name, instanceID, manual)
    FinalizeSession()
    db.active = {
        name = name or "Run",
        instanceID = instanceID,
        manual = manual or nil,
        startedAt = time(),
        lastSeen = time(),
        players = {},
        bosses = {},
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

local function Popup()
    local s = db.active
    if not s or s.popped then return end
    s.popped = true
    ns.ShowWindow()
end

-- Opens the window a little after the run is complete, leaving time for
-- rolls and last loot. Does nothing if another run has started by then.
local function SchedulePopup(s)
    if not db.options.popupBoss then return end
    C_Timer.After(POPUP_DELAY, function()
        if db.active == s then Popup() end
    end)
end

-- Asked when you walk back into a dungeon you left alive: it may be the
-- same run, or a new one after a reset. Until answered (or if the answer
-- is No, or the prompt times out) the previous run simply continues.
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

-- isLogin: a fresh login. entered: arrived through a loading screen that
-- was neither a login nor a reload. Both are nil for plain zone changes.
local function CheckZone(isLogin, entered)
    local inInstance, instanceType = IsInInstance()
    local s = db.active
    if inInstance and (instanceType == "party" or (instanceType == "raid" and db.options.trackRaids)) then
        if s and s.manual then return end
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        local resume, ask = false, false
        if s and s.instanceID == instanceID then
            if s.leftAt then
                -- Came back after leaving.
                local away = time() - s.leftAt
                if s.completed then
                    resume = false -- the run was finished: this is a new one
                elseif s.leftDead then
                    resume = away < RESUME_AFTER_DEATH -- corpse run: same run
                elseif db.options.askNewRun then
                    -- Walked out alive and back in: possibly a reset. Keep
                    -- the run for now and let the player decide.
                    resume = away < RESUME_AFTER_DEATH
                    ask = resume
                else
                    resume = away < RESUME_AFTER_EXIT
                end
            elseif isLogin then
                resume = (time() - (s.lastSeen or 0)) < RESUME_IDLE
            else
                -- Never left. A loading screen after the run was completed
                -- means a new run of the same dungeon (requeue).
                resume = not (s.completed and entered)
            end
        end
        if resume then
            if s.leftAt then s.popped, s.summarized = nil, nil end
            s.leftAt, s.leftDead = nil, nil
            s.lastSeen = time()
            UpdateRoster()
            if ask then AskNewRun(s) end
        else
            NewSession(name, instanceID)
        end
    elseif s and not s.manual then
        if not s.leftAt and isLogin then
            -- Logged out inside the instance and came back outside it: the
            -- run ended some time ago, so close it without any popup.
            s.leftAt = s.lastSeen
            s.summarized = true
            FinalizeSession()
        elseif not s.leftAt then
            s.leftAt = time()
            s.leftDead = UnitIsDeadOrGhost("player") or nil
            if not s.leftDead then
                PrintSummary(s)
                if db.options.popupLeave then Popup() end
            end
        elseif time() - s.leftAt > RESUME_AFTER_DEATH then
            FinalizeSession()
        end
    end
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
    e.count = e.count + count
    s.lastSeen = time()
    ns.Refresh()
end

----------------------------------------------------------------------
-- Summary used by the window
----------------------------------------------------------------------

-- The value used for totals, shares and sorting.
local function EntryMarket(e)
    if db.options.valueMode == "vendor" then return e.vendor * e.count end
    return (e.ah or e.vendor) * e.count
end

ns.EntryMarket = EntryMarket

local function ItemName(e)
    return e.link:match("%[(.-)%]") or ""
end
ns.ItemName = ItemName

function ns.Summarize(s)
    local o = db.options
    local out = { players = {}, count = 0, vendor = 0, market = 0 }
    for name, p in pairs(s.players) do
        local ps = { name = name, class = p.class, role = p.role, count = 0, vendor = 0, market = 0, cats = {},
                     -- every shown item in one group, for the ungrouped layout
                     all = { items = {} } }
        for _, e in pairs(p.items) do
            if not e.resolved then FillItem(e) end
            local v, m = e.vendor * e.count, EntryMarket(e)
            local shown = o.cats[e.cat] ~= false
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
-- Events
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    FairShareDB = FairShareDB or {}
    db = FairShareDB
    db.history = db.history or {}
    db.finalBoss = db.finalBoss or {} -- [instanceID] = encounterID of the last boss
    db.bossCount = db.bossCount or {} -- [instanceID] = most bosses killed in one run
    db.options = db.options or {}
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
    PLAYER_NAME = UnitName("player")
    PLAYER_CLASS = select(2, UnitClass("player"))
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
    CheckZone(isLogin, not isLogin and not isReload)
end
function handlers.ZONE_CHANGED_NEW_AREA() CheckZone() end
function handlers.GROUP_ROSTER_UPDATE() UpdateRoster() end

function handlers.CHAT_MSG_LOOT(text)
    if type(text) ~= "string" or issecret(text) then return end
    local name, link, count = ParseLoot(text)
    if name and link then RecordLoot(name, link, count) end
end

-- The instance was reset while we were outside it: the run is over, so
-- the next entry starts a new one without asking.
function handlers.CHAT_MSG_SYSTEM(text)
    if not resetPattern or type(text) ~= "string" or issecret(text) then return end
    local name = text:match(resetPattern)
    local s = db.active
    if name and s and not s.manual and s.leftAt and s.name == name then
        FinalizeSession()
        ns.Refresh()
    end
end

function handlers.ENCOUNTER_END(encounterID, encounterName, _, _, success)
    local s = db.active
    if not Tracking(s) or (success ~= 1 and success ~= true) then return end
    s.bosses[#s.bosses + 1] = { id = encounterID, name = encounterName }
    s.lastSeen = time()
    if s.instanceID and db.finalBoss[s.instanceID] == encounterID then
        s.completed = true
        SchedulePopup(s)
    end
end

function handlers.LFG_COMPLETION_REWARD()
    local s = db.active
    if not Tracking(s) then return end
    s.completed = true
    SchedulePopup(s)
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
    elseif cmd == "theme" then
        if not ns.SetTheme(arg) then
            Print("Themes: classic, retail, modern. Example: /fs theme modern")
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
    elseif cmd == "clear" then
        db.active = nil
        wipe(db.history)
        CheckZone() -- keep tracking if this was typed inside a dungeon
        ns.Refresh()
        Print("All recorded runs deleted.")
    else
        Print("/fs - open the breakdown window")
        Print("/fs options - open the options panel")
        Print("/fs theme classic|retail|modern - change the look")
        Print("/fs start - track a run manually (outside a dungeon)")
        Print("/fs stop - end the current run")
        Print("/fs clear - delete all recorded runs")
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
        run.bosses = run.bosses or {}
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
