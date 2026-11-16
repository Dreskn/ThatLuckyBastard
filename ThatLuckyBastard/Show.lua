local _, ns = ...

-- The run details window. Two pages live here:
--   podium  the group's characters standing on blocks by rank, each
--           playing an emote that fits how they did
--   paper   a mock newspaper front page written from the run's awards
-- and other files add more with ns.AddShowPage (see RunPages.lua).
-- Opened from the main window, by /tlb details and the page names, and
-- (if the option is on) by itself when a run ends, revealing the podium
-- last place first.

local WIDTH, HEIGHT = 720, 540
local STAGE_W = WIDTH - 24
local MAX_SLOTS = 5
local SLOT_W, BLOCK_W = 132, 112
local BLOCK_H = { 150, 112, 86, 60, 60 } -- by rank
local MODEL_H = 180
local TEXT_H = 64       -- room under the blocks for name, value and awards
local REVEAL_STEP = 0.8 -- seconds between two players during the reveal
local TICK = 4          -- seconds between refreshes of the pictures

local MEDALS = ns.MEDALS -- gold, silver, bronze, then grey

-- The game's emote animations, by id. Dancing loops; the others play
-- once and are replayed on every tick.
local ANIM = { dance = 69, applaud = 80, wave = 67, cry = 77, kneel = 75 }

local show, ui, title, skins = ns.MakeWindow("ThatLuckyBastardShowFrame", WIDTH, HEIGHT, "HIGH", true)
show:SetPoint("CENTER", 0, 20)

local page = "podium"
local run           -- the run on show
local drawToken = 0 -- raised on every draw, so a stale reveal can tell it is stale
local Draw

local podiumTab = ns.MakeButton("Podium", 100, function() page = "podium"; Draw() end, ui)
local paperTab = ns.MakeButton("Front page", 100, function() page = "paper"; Draw() end, ui)
paperTab:SetPoint("LEFT", podiumTab, "RIGHT", 4, 0)
podiumTab.isTab, paperTab.isTab = true, true

-- Pages added by other files: [key] = { frame, draw, tab }. A page is a
-- frame (a child of ns.ShowParent, placed by this window) and a function
-- that draws a run into it.
local extra, extraList = {}, {}
local lastTab = paperTab
ns.ShowParent = ui

function ns.AddShowPage(key, label, frame, draw)
    local tab = ns.MakeButton(label, 100, function() page = key; Draw() end, ui)
    tab:SetPoint("LEFT", lastTab, "RIGHT", 4, 0)
    tab.isTab = true
    lastTab = tab
    extra[key] = { frame = frame, draw = draw, tab = tab }
    extraList[#extraList + 1] = extra[key]
    frame:Hide()
end

----------------------------------------------------------------------
-- Podium
----------------------------------------------------------------------

local stage = CreateFrame("Frame", nil, ui)

local emptyText = stage:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER")

local slots = {}

-- Tooltip for a player on the podium: their award (slot.won), with the
-- rule behind it.
local function SlotOnEnter(self)
    if not self.won then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ns.AddAwardLines(self.won)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.AWARDS_HINT, 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function GetSlot(i)
    local slot = slots[i]
    if slot then return slot end
    slot = CreateFrame("Frame", nil, stage)
    slot:SetSize(SLOT_W, TEXT_H + BLOCK_H[1] + MODEL_H)

    slot.block = slot:CreateTexture(nil, "ARTWORK")
    slot.rank = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    slot.rank:SetPoint("TOP", slot.block, "TOP", 0, -8)
    slot.rank:SetTextColor(0.13, 0.10, 0.07)
    slot.rank:SetShadowColor(0, 0, 0, 0)

    -- The character, standing on the block.
    slot.model = CreateFrame("PlayerModel", nil, slot)
    slot.model:SetSize(SLOT_W, MODEL_H)
    slot.model:SetPoint("BOTTOM", slot.block, "TOP", 0, -6)
    slot.model:SetScript("OnModelLoaded", function(self)
        if slot.anim then self:SetAnimation(slot.anim) end
    end)

    -- Shown in the model's place when there is no model to show.
    slot.portrait, slot.ring, slot.ringInner = ns.NewRoundPicture(slot)
    slot.portrait:SetSize(64, 64)
    slot.portrait:SetPoint("BOTTOM", slot.block, "TOP", 0, 14)
    slot.ring:SetSize(72, 72)
    slot.ringInner:SetSize(66, 66)

    slot.name = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slot.name:SetPoint("TOP", slot.block, "BOTTOM", 0, -6)
    slot.name:SetWidth(SLOT_W)
    slot.name:SetWordWrap(false)
    slot.value = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.value:SetPoint("TOP", slot.name, "BOTTOM", 0, -2)
    slot.awards = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.awards:SetPoint("TOP", slot.value, "BOTTOM", 0, -2)
    slot.awards:SetWidth(SLOT_W)

    -- Hovering a player explains their award; a click opens the guide.
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", SlotOnEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    slot:SetScript("OnMouseUp", function(self)
        if self.won then ns.ShowBrowse("awards") end
    end)

    slots[i] = slot
    return slot
end

-- The player's award title, coloured.
local function AwardText(a)
    if not a then return "" end
    return "|cffffd100" .. a.title .. "|r"
end

-- First place dances, the Ninja kneels, last place cries, second place
-- applauds and everyone else waves. `players`: how many took part in the
-- run (in a big group, nobody on the podium is last).
local function AnimFor(p, players, a)
    if p.rank == 1 then return ANIM.dance end
    if a and a.key == "ninja" then return ANIM.kneel end
    if players >= 3 and p.rank == players then return ANIM.cry end
    if p.rank == 2 then return ANIM.applaud end
    return ANIM.wave
end

-- Shows the slot's player as a 3D model when they are close enough to be
-- seen, and as their class icon otherwise: the game cannot save a model.
-- Called again on every tick, so a teammate who walks out of the dungeon
-- a little later still gets their model.
local function SetupPicture(slot)
    local p = slot.p
    local unit = ns.UnitForName(p.name)
    if unit and ns.InSight(unit) then
        slot.portrait:Hide()
        slot.ring:Hide()
        slot.ringInner:Hide()
        slot.model:Show()
        -- slot.modelFor: whose model the frame holds.
        if slot.modelFor ~= p.name then
            slot.modelFor = p.name
            slot.model:SetUnit(unit)
            slot.model:SetAnimation(slot.anim)
        elseif slot.anim ~= ANIM.dance then
            slot.model:SetAnimation(slot.anim) -- replay the one-shot emotes
        end
    else
        slot.modelFor = nil
        slot.model:Hide()
        local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
        if c then slot.ring:SetVertexColor(c.r, c.g, c.b) else slot.ring:SetVertexColor(1, 0.82, 0) end
        ns.FillPortrait(slot.portrait, p)
        slot.portrait:Show()
        slot.ring:Show()
        slot.ringInner:Show()
    end
end

local function DrawPodium(ceremony)
    local token = drawToken
    local sum = ns.Summarize(run)
    local awards = ns.RunAwards(run, sum)

    -- The top five, in podium order.
    local ranked, top = {}, {}
    for _, p in ipairs(sum.players) do ranked[p.rank] = p end
    local count = math.min(#ranked, MAX_SLOTS)
    for rank = 1, count do top[rank] = ranked[rank] end
    local order = ns.PodiumOrder(top)

    emptyText:SetText("Nobody to put on the podium for this run.")
    emptyText:SetShown(count == 0)

    local sound = ns.db.options.ceremonySound
    local spacing = STAGE_W / math.max(count, 1)
    for i, p in ipairs(order) do
        local slot = GetSlot(i)
        slot.p = p
        slot.won = awards[p.name]
        slot.anim = AnimFor(p, #ranked, awards[p.name])
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOM", stage, "BOTTOMLEFT", spacing * (i - 0.5), 0)

        local medal = MEDALS[math.min(p.rank, #MEDALS)]
        slot.block:ClearAllPoints()
        slot.block:SetPoint("BOTTOM", slot, "BOTTOM", 0, TEXT_H)
        slot.block:SetSize(BLOCK_W, BLOCK_H[p.rank])
        slot.block:SetColorTexture(medal[1], medal[2], medal[3], 0.92)
        slot.rank:SetText(ns.Ordinal(p.rank))
        slot.name:SetText(ns.ClassColored(ns.DisplayName(p.name), p.class))
        slot.value:SetText(ns.Money(p.market))
        slot.awards:SetText(AwardText(awards[p.name]))

        if ceremony then
            -- Last place first, the winner last.
            slot:Hide()
            C_Timer.After(REVEAL_STEP * (count - p.rank + 1), function()
                if token ~= drawToken or not show:IsShown() then return end
                slot:Show()
                SetupPicture(slot)
                if sound then ns.PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) end
            end)
        else
            slot:Show()
            SetupPicture(slot)
        end
    end
    for i = count + 1, #slots do
        slots[i].p = nil
        slots[i]:Hide()
    end

    if ceremony and count > 0 then
        local length = REVEAL_STEP * count
        if sound then
            C_Timer.After(length + 0.3, function()
                if token == drawToken and show:IsShown() then ns.PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
            end)
        end
        if ns.db.options.ceremonyScreenshot and Screenshot then
            C_Timer.After(length + 1.5, function()
                if token == drawToken and show:IsShown() then Screenshot() end
            end)
        end
    end
end

----------------------------------------------------------------------
-- Front page
----------------------------------------------------------------------

local PAPER_W = WIDTH - 44
local MARGIN = 22
local INK = { 0.13, 0.10, 0.07 }

local paperScroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local paper = CreateFrame("Frame", nil, paperScroll)
paper:SetSize(PAPER_W, 1)
paperScroll:SetScrollChild(paper)

local paperBg = paper:CreateTexture(nil, "BACKGROUND")
paperBg:SetAllPoints()
paperBg:SetColorTexture(0.93, 0.89, 0.77, 1)

-- Dark, shadowless text for the paper. Falls back to the standard font
-- if the requested one is missing.
local function Ink(size, fontPath)
    local fs = paper:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont(fontPath or STANDARD_TEXT_FONT, size, "")
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetTextColor(INK[1], INK[2], INK[3])
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetWordWrap(true)
    return fs
end

local function Rule()
    local t = paper:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(INK[1], INK[2], INK[3], 0.8)
    t:SetHeight(2)
    return t
end

local masthead = Ink(34, "Fonts\\MORPHEUS.TTF")
local tagline = Ink(10)
local headline = Ink(20)
local lead = Ink(12)
local rule1, rule2 = Rule(), Rule()
local storyText = {} -- [i] = { head = font string, body = font string }

-- Puts a font string at (x, y from the top) with the given width and
-- returns the y just under it. The text must be set first.
local function Place(fs, x, y, width, justify)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    return y + fs:GetStringHeight()
end

local function PlaceRule(t, y)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", MARGIN, -y)
    t:SetPoint("TOPRIGHT", -MARGIN, -y)
end

local function ItemName(link)
    return link and link:match("%[(.-)%]") or "something shiny"
end

local function LowerFirst(text)
    return text:sub(1, 1):lower() .. text:sub(2)
end

-- One short story per award: possible headlines, and the text.
-- body(who, award) where `who` is the player's display name.
local STORIES = {
    ninja = {
        heads = { "NEED BUTTON WORN OUT", "AUTHORITIES BAFFLED", "\"I NEEDED IT\"" },
        body = function(who, a)
            return ("%s won %s on Need rolls. Sources close to the party describe the mood as \"tense\".")
                :format(who, ns.MoneyPlain(a.amount))
        end,
    },
    lucky = {
        heads = { "DICE UNDER INVESTIGATION", "LUCK OR SKILL?", "FORTUNE PICKS A FAVOURITE" },
        body = function(who, a)
            return ("%s won %s on Greed rolls alone. \"Pure skill,\" they insist."):format(who, ns.MoneyPlain(a.amount))
        end,
    },
    jackpot = {
        heads = { "A STAR IS LOOTED", "JACKPOT", "ONE DROP TO RULE THEM ALL" },
        body = function(who, a)
            return ("%s picked up %s, worth %s. Friends say it has already changed them.")
                :format(who, ItemName(a.link), ns.MoneyPlain(a.amount))
        end,
    },
    lionshare = {
        heads = { "ONE FOR YOU, FOUR FOR ME", "SHARING \"NOT A PRIORITY\"", "THE REST IS CRUMBS" },
        body = function(who, a)
            return ("%s %s. The others are said to be \"doing the maths\"."):format(who, LowerFirst(a.text))
        end,
    },
    fairshare = {
        heads = { "PERFECTLY, SUSPICIOUSLY FAIR", "EXACTLY WHAT THEY DESERVED" },
        body = function(who, a)
            return ("%s left with %s, almost to the copper an equal share. Accountants are thrilled.")
                :format(who, ns.MoneyPlain(a.amount))
        end,
    },
    onehit = {
        heads = { "ALL EGGS, ONE BASKET", "ONE ITEM, ONE DREAM" },
        body = function(who, a)
            return ("Take away %s and %s has very little to show for the trip. Nobody is taking it away.")
                :format(ItemName(a.link), who)
        end,
    },
    purple = {
        heads = { "PURPLE SPOTTED IN THE WILD", "IT'S PURPLE. IT'S ACTUALLY PURPLE." },
        body = function(who, a)
            return ("%s looted %s and has linked it four times already."):format(who, ItemName(a.link))
        end,
    },
    packmule = {
        heads = { "BAGS FULL, PURSE EMPTY", "QUANTITY OVER QUALITY" },
        body = function(who, a)
            return ("%s: %s. Every single one was picked up with hope."):format(who, LowerFirst(a.text))
        end,
    },
    vendor = {
        heads = { "VENDOR EXPECTING A VISIT", "AUCTION HOUSE NOT INTERESTED" },
        body = function(who, a)
            return ("%s carries %s of loot, all of it headed straight for the nearest vendor.")
                :format(who, ns.MoneyPlain(a.amount))
        end,
    },
    errand = {
        heads = { "SOMEONE READ THE QUEST TEXT", "ERRANDS RUN, THANKS PENDING" },
        body = function(who, a)
            return ("%s %s while everyone else was busy with the loot."):format(who, LowerFirst(a.text))
        end,
    },
    nat100 = {
        heads = { "ONE HUNDRED", "A PERFECT ROLL" },
        body = function(who)
            return ("%s rolled a 100. Witnesses confirm they will be hearing about it for weeks."):format(who)
        end,
    },
    snakeeyes = {
        heads = { "ROLLED A ONE", "THE DICE SAY NO" },
        body = function(who)
            return ("%s rolled a 1. The dice declined to comment."):format(who)
        end,
    },
    window = {
        heads = { "ALWAYS ROLLING, NEVER WINNING", "JUST LOOKING, THANKS" },
        body = function(who, a)
            return ("%s %s. \"Next time,\" they said, as they said last time."):format(who, LowerFirst(a.text))
        end,
    },
    hotdice = {
        heads = { "DICE BLESSED BY UNKNOWN POWER", "ROLLS LIKE A LEGEND" },
        body = function(who, a)
            return ("%s: %s. Rivals demand to inspect the dice."):format(who, LowerFirst(a.text))
        end,
    },
    colddice = {
        heads = { "CURSED DICE STRIKE AGAIN", "ROLLS LIKE A BRICK" },
        body = function(who, a)
            return ("%s: %s. A priest has been called."):format(who, LowerFirst(a.text))
        end,
    },
    farmer = {
        heads = { "LOCAL WILDLIFE FILES COMPLAINT", "NOTHING WAS SPARED" },
        body = function(who, a)
            return ("%s left with %s in skins, herbs and ore. The dungeon will need time to recover.")
                :format(who, ns.MoneyPlain(a.amount))
        end,
    },
    saint = {
        heads = { "SAINT SPOTTED IN DUNGEON", "GENEROSITY SHOCKS PARTY" },
        body = function(who, a)
            return ("%s %s. Canonisation is expected shortly."):format(who, LowerFirst(a.text))
        end,
    },
    hoarder = {
        heads = { "\"IT MIGHT BE WORTH SOMETHING\"", "BAGS AT BREAKING POINT" },
        body = function(who, a)
            return ("%s %s. The bags could not be reached for comment."):format(who, LowerFirst(a.text))
        end,
    },
    empty = {
        heads = { "THOUGHTS AND PRAYERS", "BETTER LUCK NEXT TIME" },
        body = function(who, a)
            local got = ns.MoneyPlain(a.amount)
            return ("%s leaves with %s. A collection has not been started.")
                :format(who, got == "-" and "nothing" or got)
        end,
    },
    tourist = {
        heads = { "ALSO PRESENT", "IN OTHER NEWS" },
        body = function(who)
            return ("%s was there too, and reports having a lovely time."):format(who)
        end,
    },
}

-- Writes the paper for a run. The same run always gives the same paper:
-- the "random" choices are derived from the run's start time.
local function Paper(s)
    local sum = ns.Summarize(s)
    local awards = ns.RunAwards(s, sum)

    local seed = (s.startedAt or 1) % 2147483646 + 1
    local function pick(list)
        seed = (seed * 48271) % 2147483647
        return list[seed % #list + 1]
    end

    local place = s.name or "the dungeon"
    local n = #sum.players
    local ranked = {}
    local top, ninja, jackpot
    for _, p in ipairs(sum.players) do
        ranked[p.rank] = p
        local a = awards[p.name]
        if p.rank == 1 then top = p end
        if a and a.key == "ninja" then ninja = p end
        if a and a.key == "jackpot" then jackpot = p end
    end

    local doc = { stories = {} }
    doc.masthead = "The " .. place .. " Gazette"
    doc.tagline = date("%A %d %B %Y", s.startedAt)
        .. "    -    All the loot that's fit to print    -    Price: your dignity"

    if ninja then
        doc.headline = pick({
            "%s NEEDS EVERYTHING, DENIES WRONGDOING",
            "NINJA SUSPECTED: %s QUESTIONED OVER NEED ROLLS",
            "\"I NEEDED IT,\" INSISTS %s",
        }):format(ns.DisplayName(ninja.name):upper())
    elseif jackpot then
        doc.headline = pick({
            "%s STRIKES IT RICH IN %s",
            "FORTUNE SMILES ON %s IN %s",
            "%s HITS THE JACKPOT IN %s",
        }):format(ns.DisplayName(jackpot.name):upper(), place:upper())
    elseif top and top.market > 0 then
        doc.headline = pick({
            "%s WALKS OUT OF %s THE RICHEST",
            "%s TOPS THE LOOT TABLE IN %s",
        }):format(ns.DisplayName(top.name):upper(), place:upper())
    else
        doc.headline = ("QUIET DAY IN %s: NOBODY GETS ANYTHING"):format(place:upper())
    end

    local duration = ns.RunDuration(s)
    local after = duration and (" after " .. ns.Duration(duration)) or ""
    if top and sum.market > 0 then
        doc.lead = ("A party of %d emerged from %s%s carrying loot worth %s. %s took home %d%% of it%s")
            :format(n, place, after, ns.MoneyPlain(sum.market), ns.DisplayName(top.name),
                    top.market / sum.market * 100 + 0.5,
                    pick({
                        ", and is said to be \"very humble about it\".",
                        ". Nobody else wishes to comment.",
                        ", to nobody's surprise but their own.",
                    }))
    else
        doc.lead = ("A party of %d emerged from %s%s with nothing to show for it. Morale is described as \"fine\".")
            :format(n, place, after)
    end

    local function story(p, award)
        local def = award and STORIES[award.key]
        if def then
            doc.stories[#doc.stories + 1] = {
                head = pick(def.heads),
                body = def.body(ns.DisplayName(p.name), award),
            }
        end
    end
    -- The scandals first, then everyone else, best-placed first.
    local scandal = { ninja = 1, lucky = 2 }
    for pass = 1, 3 do
        for _, p in ipairs(ranked) do
            local a = awards[p.name]
            if a and (scandal[a.key] or 3) == pass then story(p, a) end
        end
    end
    return doc
end

local function DrawPaper()
    local doc = Paper(run)
    local width = PAPER_W - 2 * MARGIN

    masthead:SetText(doc.masthead)
    local y = Place(masthead, MARGIN, 14, width, "CENTER")
    tagline:SetText(doc.tagline)
    y = Place(tagline, MARGIN, y + 4, width, "CENTER")
    PlaceRule(rule1, y + 6)

    headline:SetText(doc.headline)
    y = Place(headline, MARGIN, y + 18, width, "CENTER")
    lead:SetText(doc.lead)
    y = Place(lead, MARGIN, y + 10, width, "LEFT")
    PlaceRule(rule2, y + 10)
    y = y + 22

    -- Stories fill two columns, each new one going to the shorter column.
    local colW = (width - MARGIN) / 2
    local colY = { y, y }
    for i, item in ipairs(doc.stories) do
        local text = storyText[i]
        if not text then
            text = { head = Ink(12), body = Ink(11) }
            storyText[i] = text
        end
        local col = colY[2] < colY[1] and 2 or 1
        local x = MARGIN + (col - 1) * (colW + MARGIN)
        text.head:SetText(item.head)
        text.body:SetText(item.body)
        colY[col] = Place(text.head, x, colY[col], colW) + 3
        colY[col] = Place(text.body, x, colY[col], colW) + 14
        text.head:Show()
        text.body:Show()
    end
    for i = #doc.stories + 1, #storyText do
        storyText[i].head:Hide()
        storyText[i].body:Hide()
    end
    paper:SetHeight(math.max(colY[1], colY[2]) + 10)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

local function ApplyTheme()
    local flat, top = ns.ApplyWindowTheme(skins, title)
    podiumTab:ClearAllPoints()
    podiumTab:SetPoint("TOPLEFT", 12, top)
    podiumTab:SetFlat(flat)
    paperTab:SetFlat(flat)

    stage:ClearAllPoints()
    stage:SetPoint("TOPLEFT", 12, top - 30)
    stage:SetPoint("BOTTOMRIGHT", -12, 12)
    paperScroll:ClearAllPoints()
    paperScroll:SetPoint("TOPLEFT", 12, top - 30)
    paperScroll:SetPoint("BOTTOMRIGHT", -32, 12)
    for _, x in ipairs(extraList) do
        x.tab:SetFlat(flat)
        x.frame:ClearAllPoints()
        x.frame:SetPoint("TOPLEFT", 12, top - 30)
        x.frame:SetPoint("BOTTOMRIGHT", -12, 12)
    end
end

function Draw(ceremony)
    drawToken = drawToken + 1 -- cancels any reveal still in progress
    ApplyTheme()
    podiumTab:SetSelected(page == "podium")
    paperTab:SetSelected(page == "paper")
    for _, x in ipairs(extraList) do
        x.tab:SetSelected(extra[page] == x)
        x.frame:Hide()
    end

    if not run then
        title:SetText(ns.Title("Run details"))
        paperScroll:Hide()
        stage:Show()
        for _, slot in ipairs(slots) do
            slot.p = nil
            slot:Hide()
        end
        emptyText:SetText("No run to show yet.")
        emptyText:Show()
        return
    end

    title:SetText(ns.Title(run.name or "Run"))
    if extra[page] then
        stage:Hide()
        paperScroll:Hide()
        extra[page].frame:Show()
        extra[page].draw(run)
    elseif page == "paper" then
        stage:Hide()
        paperScroll:Show()
        DrawPaper()
    else
        paperScroll:Hide()
        stage:Show()
        DrawPodium(ceremony)
    end
end

-- Keep the podium alive: bring in the models of players who have come
-- into view, and replay the one-shot emotes.
local sinceTick = 0
show:SetScript("OnUpdate", function(_, dt)
    sinceTick = sinceTick + dt
    if sinceTick < TICK then return end
    sinceTick = 0
    if page ~= "podium" then return end
    for _, slot in ipairs(slots) do
        if slot.p and slot:IsShown() then SetupPicture(slot) end
    end
end)

show:SetScript("OnHide", function()
    drawToken = drawToken + 1
    -- Models are set up again from scratch the next time the show opens.
    for _, slot in ipairs(slots) do slot.modelFor = nil end
end)

-- s: the run. ceremony: reveal the podium one player at a time.
-- which: "podium" (default), "paper", or a page added by another file.
function ns.OpenShow(s, ceremony, which)
    if s ~= run then
        -- Another run: nothing the slots hold belongs to it.
        for _, slot in ipairs(slots) do slot.modelFor = nil end
    end
    run = s
    page = (which == "paper" or extra[which]) and which or "podium"
    show:Show()
    show:Raise()
    Draw(ceremony)
end

-- The Run details button: closes the window if it already shows run `s`,
-- and opens it on `s` otherwise.
function ns.ToggleShow(s)
    if show:IsShown() and run == s then show:Hide() else ns.OpenShow(s) end
end

ns.OnRerender(function()
    if show:IsShown() then Draw() end
end)
