local _, ns = ...

-- Windows about one run each, opened by the main window's buttons and by
-- /tlb podium, paper and timeline. Two live here:
--   podium  the group's characters standing on blocks by rank, each
--           playing an emote that fits how they did. Also opens by itself
--           when a run ends (if the option is on), revealing the podium
--           last place first.
--   paper   a mock newspaper front page written from the run's awards
-- and RunPages.lua adds the Analysis window (timeline, rolls, numbers).

local WIDTH, HEIGHT = 720, 510
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

----------------------------------------------------------------------
-- A window about one run
----------------------------------------------------------------------

local windows = {} -- [key] = run window

-- Makes a window that shows one run and nothing else. draw(run, ceremony,
-- top) fills it; `top` is where the content starts under the title. Its
-- title names the run. Returns { frame, ui, run, Open }.
function ns.MakeRunWindow(key, name, label, width, height, draw)
    local w, ui, title, skins = ns.MakeWindow(name, width, height, "HIGH", true)
    local rw = { frame = w, ui = ui }
    function rw.Draw(ceremony)
        local _, top = ns.ApplyWindowTheme(skins, title)
        title:SetText(ns.Title(label .. (rw.run and ("  -  " .. (rw.run.name or "Run")) or "")))
        draw(rw.run, ceremony, top)
    end
    function rw.Open(s, ceremony)
        rw.run = s
        w:Show()
        w:Raise()
        rw.Draw(ceremony)
    end
    windows[key] = rw
    ns.OnRerender(function()
        if w:IsShown() then rw.Draw() end
    end)
    return rw
end

-- Opens run window `key` ("podium", "paper" or "analysis") on run `s`.
-- ceremony: reveal the podium one player at a time.
function ns.OpenRunWindow(key, s, ceremony)
    windows[key].Open(s, ceremony)
end

-- The main window's buttons: open the window on run `s`, or close it if
-- it shows that run already.
function ns.ToggleRunWindow(key, s)
    local rw = windows[key]
    if rw.frame:IsShown() and rw.run == s then rw.frame:Hide() else rw.Open(s) end
end

local drawToken = 0 -- raised on every podium draw, so a stale reveal can tell it is stale
local DrawPodium, DrawPaper
local podium = ns.MakeRunWindow("podium", "ThatLuckyBastardPodiumFrame", "Podium", WIDTH, HEIGHT,
    function(s, ceremony, top) DrawPodium(s, ceremony, top) end)
podium.frame:SetPoint("CENTER", 0, 20)

----------------------------------------------------------------------
-- Podium
----------------------------------------------------------------------

local stage = CreateFrame("Frame", nil, podium.ui)

local emptyText = stage:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER")

-- The bench: whoever comes after the podium's five, in a line or two
-- under the stage. A raid's bench names the first few and counts the rest.
local BENCH_H = 34      -- room the bench takes under the stage
local BENCH_NAMED = 8
local benchText = podium.ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
benchText:SetPoint("BOTTOMLEFT", 16, 12)
benchText:SetPoint("BOTTOMRIGHT", -16, 12)
benchText:SetJustifyH("CENTER")

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

local drawnRun -- the run the slots were last set up for

function DrawPodium(s, ceremony, top)
    drawToken = drawToken + 1 -- calls off any reveal still in progress
    local token = drawToken
    stage:ClearAllPoints()
    stage:SetPoint("TOPLEFT", 12, top)
    stage:SetPoint("BOTTOMRIGHT", -12, 12)
    benchText:SetText("")
    if s ~= drawnRun then
        -- Another run: nothing the slots hold belongs to it.
        for _, slot in ipairs(slots) do slot.modelFor = nil end
        drawnRun = s
    end
    if not s then
        for _, slot in ipairs(slots) do
            slot.p = nil
            slot:Hide()
        end
        emptyText:SetText("No run to show yet.")
        emptyText:Show()
        return
    end
    local sum = ns.Summarize(s)
    local awards = ns.RunAwards(s, sum)

    -- The top five, in podium order.
    local ranked, top = {}, {}
    for _, p in ipairs(sum.players) do ranked[p.rank] = p end
    local count = math.min(#ranked, MAX_SLOTS)
    for rank = 1, count do top[rank] = ranked[rank] end
    local order = ns.PodiumOrder(top)

    local seated = {}
    for rank = MAX_SLOTS + 1, math.min(#ranked, MAX_SLOTS + BENCH_NAMED) do
        local p = ranked[rank]
        seated[#seated + 1] = ("|cff909090%d.|r %s %s"):format(rank,
            ns.ClassColored(ns.DisplayName(p.name), p.class), ns.Money(p.market))
    end
    if #seated > 0 then
        local more = #ranked - MAX_SLOTS - #seated
        benchText:SetText(table.concat(seated, "    ")
            .. (more > 0 and ("    |cff909090and %d more|r"):format(more) or ""))
        stage:SetPoint("BOTTOMRIGHT", -12, 12 + BENCH_H) -- the stage makes room
    end

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
                if token ~= drawToken or not podium.frame:IsShown() then return end
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
                if token == drawToken and podium.frame:IsShown() then ns.PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
            end)
        end
        if ns.db.options.ceremonyScreenshot and Screenshot then
            C_Timer.After(length + 1.5, function()
                if token == drawToken and podium.frame:IsShown() then Screenshot() end
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

local paperWin = ns.MakeRunWindow("paper", "ThatLuckyBastardPaperFrame", "Front page", WIDTH, HEIGHT,
    function(s, _, top) DrawPaper(s, top) end)
paperWin.frame:SetPoint("CENTER", 30, 0)

local paperScroll = CreateFrame("ScrollFrame", nil, paperWin.ui, "UIPanelScrollFrameTemplate")
local paperNote = paperWin.ui:CreateFontString(nil, "OVERLAY", "GameFontDisable")
paperNote:SetPoint("CENTER")
paperNote:SetText("No run to show yet.")
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
    heartbreak = {
        heads = { "SO CLOSE, YET SO FAR", "HEARTBREAK AT THE LOOT TABLE" },
        body = function(who, a)
            return ("%s %s. Friends say they are \"fine, honestly, totally fine\"."):format(who, LowerFirst(a.text))
        end,
    },
    lowball = {
        heads = { "WINS WITH A WHAT?", "THE LOWEST WINNING ROLL" },
        body = function(who, a)
            return ("%s %s. Mathematicians are looking into it."):format(who, LowerFirst(a.text))
        end,
    },
    photo = {
        heads = { "PHOTO FINISH", "BY A SINGLE POINT" },
        body = function(who, a)
            return ("%s %s. The other side has asked for a recount."):format(who, LowerFirst(a.text))
        end,
    },
    dejavu = {
        heads = { "HAVEN'T WE BEEN HERE BEFORE?", "GLITCH IN THE DICE" },
        body = function(who, a)
            return ("%s %s. Scholars suspect a glitch in reality."):format(who, LowerFirst(a.text))
        end,
    },
    hotstreak = {
        heads = { "ON FIRE", "CAN'T STOP WINNING" },
        body = function(who, a)
            return ("%s %s. The others are thinking of not rolling against them."):format(who, LowerFirst(a.text))
        end,
    },
    dryspell = {
        heads = { "STILL WAITING", "THE LONG DROUGHT" },
        body = function(who, a)
            return ("%s %s. Their dice have been seen weeping."):format(who, LowerFirst(a.text))
        end,
    },
    nemesis = {
        heads = { "A RIVALRY IS BORN", "\"IT'S PERSONAL NOW\"" },
        body = function(who, a)
            return ("%s %s. A rematch has been demanded."):format(who, LowerFirst(a.text))
        end,
    },
    overkill = {
        heads = { "NEEDED IT. REALLY NEEDED IT.", "A NEED ROLL FOR THE AGES" },
        body = function(who, a)
            return ("%s rolled Need on %s, worth %s. No regrets."):format(who, ItemName(a.link), ns.MoneyPlain(a.amount))
        end,
    },
    afk = {
        heads = { "PRESENT, TECHNICALLY", "BE RIGHT BACK" },
        body = function(who)
            return ("%s picked up nothing and rolled on nothing. Reports of a pulse are unconfirmed."):format(who)
        end,
    },
    hunterloot = {
        heads = { "THAT'S A HUNTER WEAPON", "HUNTER LOOT, OBVIOUSLY" },
        body = function(who, a)
            return ("%s: %s. Experts agree that everything is hunter loot."):format(who, LowerFirst(a.text))
        end,
    },
    needfirst = {
        heads = { "NEED FIRST, ASK LATER", "THE NEED BUTTON, WORN OUT" },
        body = function(who, a)
            return ("%s %s. The Greed button is said to be in mint condition."):format(who, LowerFirst(a.text))
        end,
    },
    dkp = {
        heads = { "THAT'S A 50 DKP MINUS", "MINUS FIFTY, AGAIN" },
        body = function(who, a)
            return ("%s %s. The raid leader was heard from three zones away."):format(who, LowerFirst(a.text))
        end,
    },
    tanktax = {
        heads = { "THE TANK TAX IS DUE", "REPAIR BILLS, PAID IN FULL" },
        body = function(who, a)
            return ("%s ended %s. Taking the hits has its perks."):format(who, a.text)
        end,
    },
    healertip = {
        heads = { "TIP YOUR HEALER", "GRATITUDE, IN GOLD" },
        body = function(who, a)
            return ("%s ended %s. Somebody remembered who kept them alive."):format(who, a.text)
        end,
    },
    topdps = {
        heads = { "TOP OF THE OTHER METER", "BIG NUMBERS, BIG BAGS" },
        body = function(who, a)
            return ("%s ended %s. The damage meter was not consulted."):format(who, a.text)
        end,
    },
    classact = {
        heads = { "A CLASS ACT", "TOP OF THE CLASS" },
        body = function(who, a)
            return ("%s ended %s. The others are taking notes."):format(who, a.text)
        end,
    },
    classclown = {
        heads = { "CLASS CLOWN", "BOTTOM OF THE CLASS" },
        body = function(who, a)
            return ("%s ended %s. The class trainer has been informed."):format(who, a.text)
        end,
    },
    bosspet = {
        heads = { "TEACHER'S PET", "THE BOSS PLAYS FAVOURITES" },
        body = function(who, a)
            return ("%s: %s, worth %s. A thank-you note is in the mail.")
                :format(who, LowerFirst(a.text), ns.MoneyPlain(a.amount))
        end,
    },
    collector = {
        heads = { "THE WINS ADD UP", "A LITTLE OF EVERYTHING" },
        body = function(who, a)
            return ("%s %s. None of it was much, but all of it was theirs."):format(who, LowerFirst(a.text))
        end,
    },
    busy = {
        heads = { "ROLLS ON EVERYTHING", "NO ROLL LEFT BEHIND" },
        body = function(who, a)
            return ("%s %s. Their keyboard is said to be tired."):format(who, LowerFirst(a.text))
        end,
    },
    second = {
        heads = { "ALWAYS THE BRIDESMAID", "SILVER, AGAIN" },
        body = function(who, a)
            return ("%s: %s. Close is not a prize, but here is one anyway."):format(who, LowerFirst(a.text))
        end,
    },
    avgjoe = {
        heads = { "PERFECTLY AVERAGE", "MIDDLE OF THE ROAD" },
        body = function(who, a)
            return ("%s: %s. Statisticians call it beautiful."):format(who, LowerFirst(a.text))
        end,
    },
    magpie = {
        heads = { "OOH, SHINY", "AN EYE FOR COLOUR" },
        body = function(who, a)
            return ("%s collected %s. Not a single grey among them."):format(who, LowerFirst(a.text))
        end,
    },
    bossmagnet = {
        heads = { "THE BOSSES PAID", "BIG GAME HUNTER" },
        body = function(who, a)
            return ("%s took %s from the bosses alone. The trash was beneath them."):format(who, ns.MoneyPlain(a.amount))
        end,
    },
    trashpanda = {
        heads = { "ONE MOB'S TRASH...", "KING OF THE TRASH" },
        body = function(who, a)
            return ("%s made %s from trash, and checked every corpse twice."):format(who, ns.MoneyPlain(a.amount))
        end,
    },
    leftovers = {
        heads = { "NOBODY WANTED IT", "WASTE NOT, WANT NOT" },
        body = function(who, a)
            return ("%s %s. Someone had to."):format(who, LowerFirst(a.text))
        end,
    },
    booby = {
        heads = { "THE BOOBY PRIZE", "IT'S THE THOUGHT THAT COUNTS" },
        body = function(who, a)
            return ("%s got %s, worth %s. It will have pride of place at home.")
                :format(who, ItemName(a.link), ns.MoneyPlain(a.amount))
        end,
    },
    runnerup = {
        heads = { "SO NEAR THE TOP", "SECOND IS THE NEW FIRST" },
        body = function(who, a)
            return ("%s finished with %s, the second most. Nobody remembers second place, except this paper.")
                :format(who, ns.MoneyPlain(a.amount))
        end,
    },
    firstdibs = {
        heads = { "FIRST IN LINE", "THE EARLY BIRD GETS THE LOOT" },
        body = function(who, a)
            return ("%s picked up the first item of the run, %s. Off to a flying start."):format(who, ItemName(a.link))
        end,
    },
    lastcall = {
        heads = { "LAST ONE OUT", "THE FINAL WORD" },
        body = function(who, a)
            return ("%s picked up the last item of the run, %s, and turned off the lights."):format(who, ItemName(a.link))
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
        -- The headline is about the first of them, not a "Ninja II".
        if a and a.key == "ninja" and a.place == 1 then ninja = ninja or p end
        if a and a.key == "jackpot" and a.place == 1 then jackpot = jackpot or p end
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

function DrawPaper(s, top)
    paperScroll:ClearAllPoints()
    paperScroll:SetPoint("TOPLEFT", 12, top)
    paperScroll:SetPoint("BOTTOMRIGHT", -32, 12)
    paperScroll:SetShown(s ~= nil)
    paperNote:SetShown(s == nil)
    if not s then return end
    local doc = Paper(s)
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
-- Keeping the podium alive
----------------------------------------------------------------------

-- Brings in the models of players who have come into view, and replays
-- the one-shot emotes.
local sinceTick = 0
podium.frame:SetScript("OnUpdate", function(_, dt)
    sinceTick = sinceTick + dt
    if sinceTick < TICK then return end
    sinceTick = 0
    for _, slot in ipairs(slots) do
        if slot.p and slot:IsShown() then SetupPicture(slot) end
    end
end)

podium.frame:SetScript("OnHide", function()
    drawToken = drawToken + 1
    -- Models are set up again from scratch the next time the podium opens.
    for _, slot in ipairs(slots) do slot.modelFor = nil end
end)
