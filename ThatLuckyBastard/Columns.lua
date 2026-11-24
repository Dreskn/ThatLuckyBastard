local _, ns = ...

-- The column view: one column per player, for up to five (a bigger
-- group puts the rest on the bench, Bench.lua). Each column has the
-- player's place, picture, name, totals and share, their award card,
-- then their items, by category or lined up with the other columns. On
-- the Receipt theme each column is a receipt (Receipt.lua). A run shown
-- as it is left is revealed here: by the race (Race.lua) when the
-- columns stand in podium order, else by the award cards coming up one
-- after another.

local Breakdown = ns.Breakdown
local MAX_COLUMNS, COL_GAP, PAPER = Breakdown.MAX_COLUMNS, Breakdown.COL_GAP, Breakdown.PAPER
local INK, INK_GREY, reveal = Breakdown.INK, Breakdown.INK_GREY, Breakdown.reveal
local race, footLines, CATS = Breakdown.race, Breakdown.footLines, Breakdown.CATS
local cols, MEDALS, Money, Grey = Breakdown.cols, Breakdown.MEDALS, Breakdown.Money, Breakdown.Grey
local MoneyGrey, CatColored = Breakdown.MoneyGrey, Breakdown.CatColored
local ClassRGB, ItemIcon, CIRCLE = Breakdown.ClassRGB, Breakdown.ItemIcon, Breakdown.CIRCLE
local SetRowBg, SetMark, DiffText = Breakdown.SetRowBg, Breakdown.SetMark, Breakdown.DiffText
local DisplayName, ClassColored, f = Breakdown.DisplayName, Breakdown.ClassColored, Breakdown.f
local SetFade, content, RowOnClick = Breakdown.SetFade, Breakdown.content, Breakdown.RowOnClick
local AWARDS_HINT, AwardTitle = Breakdown.AWARDS_HINT, Breakdown.AwardTitle
local AddAwardLines, PersonTooltip = Breakdown.AddAwardLines, Breakdown.PersonTooltip
local RowOnEnter, StyleHighlight = Breakdown.RowOnEnter, Breakdown.StyleHighlight
local DISC, NewRoundPicture, Pct = Breakdown.DISC, Breakdown.NewRoundPicture, Breakdown.Pct
local UnitForName, InSight = Breakdown.UnitForName, Breakdown.InSight
local FillPortrait, PlayKit, TAIL_H = Breakdown.FillPortrait, Breakdown.PlayKit, Breakdown.TAIL_H
local EDGE_H, StyleAward, ShowTail = Breakdown.EDGE_H, Breakdown.StyleAward, Breakdown.ShowTail
local FooterTexts, ItemLine = Breakdown.FooterTexts, Breakdown.ItemLine
local NoLootLabel, GroupOf = Breakdown.NoLootLabel, Breakdown.GroupOf
local RenderBench = Breakdown.RenderBench

-- mode: "3d" model, "2d" portrait, "class" icon or "none". A model or a
-- portrait needs the player in the group and in sight right now; anyone
-- else gets their class icon.
--
-- Pictures are framed in the player's class colour: a ring around the
-- round 2D portrait / class icon, a square frame around the 3D model
-- (model frames cannot be masked to a circle).
local function SetPortrait(c, p, mode)
    local tex, model = c.portrait, c.model
    local unit = (mode == "2d" or mode == "3d") and UnitForName(p.name) or nil
    if unit and not InSight(unit) then unit = nil end -- still inside the dungeon, say
    local useModel = mode == "3d" and unit ~= nil
    local useTexture = mode ~= "none" and not useModel

    local r, g, b = ClassRGB(p.class)
    c.ring:SetVertexColor(r, g, b)
    c.box:SetColorTexture(r, g, b, 1)
    c.ring:SetShown(useTexture)
    c.ringInner:SetShown(useTexture)
    c.box:SetShown(useModel)
    c.boxInner:SetShown(useModel)
    tex:SetShown(useTexture)
    model:SetShown(useModel)

    if not useModel then
        c.modelFor = nil
        if useTexture then FillPortrait(tex, p, unit) end
        return
    end
    -- c.modelFor: whose model the frame holds, so that it is only loaded
    -- again when that changes (reloading makes it flicker).
    if c.modelFor ~= p.name then
        model:SetUnit(unit)
        if model.SetPortraitZoom then model:SetPortraitZoom(1) end
        c.modelFor = p.name
    end
end

local function GetCol(i)
    local c = cols[i]
    if c then return c end
    c = CreateFrame("Frame", nil, content)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    -- The header's parts are placed by RenderColumns, which knows what the
    -- options show; here they are only made.
    c.portrait, c.ring, c.ringInner = NewRoundPicture(c)
    c.portrait:SetSize(48, 48)
    c.ring:SetSize(54, 54)
    c.ringInner:SetSize(50, 50)
    c.model = CreateFrame("PlayerModel", nil, c)
    c.model:SetSize(52, 52)
    c.model:Hide()

    -- 3D model: class-coloured square frame with a dark backdrop.
    c.box = c:CreateTexture(nil, "BORDER", nil, 1)
    c.box:SetSize(56, 56)
    c.box:SetPoint("CENTER", c.model)
    c.boxInner = c:CreateTexture(nil, "BORDER", nil, 2)
    c.boxInner:SetColorTexture(DISC[1], DISC[2], DISC[3], 1)
    c.boxInner:SetSize(52, 52)
    c.boxInner:SetPoint("CENTER", c.model)
    local function Text(font)
        local fs = c:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        return fs
    end
    c.name = Text("GameFontNormal")
    c.market = Text("GameFontHighlight")
    c.vendor = Text("GameFontHighlightSmall")
    c.share = Text("GameFontHighlightSmall")
    -- Modern-theme decoration: class-coloured glow and strip at the top,
    -- a pill behind the over/under figure, and a bar whose length is the
    -- player's share of the run, split into category colours.
    c.top = c:CreateTexture(nil, "BORDER")
    c.top:SetPoint("TOPLEFT")
    c.top:SetPoint("TOPRIGHT")
    c.strip = c:CreateTexture(nil, "ARTWORK")
    c.strip:SetPoint("TOPLEFT")
    c.strip:SetPoint("TOPRIGHT")
    c.strip:SetHeight(2)
    c.pill = c:CreateTexture(nil, "BORDER")
    c.pill:SetHeight(14)
    c.track = c:CreateTexture(nil, "BORDER")
    c.track:SetHeight(5)
    c.track:SetColorTexture(1, 1, 1, 0.08)
    c.segs = {}
    for k = 1, #CATS do
        local seg = c:CreateTexture(nil, "ARTWORK")
        seg:SetHeight(5)
        c.segs[k] = seg
    end
    -- Podium mode: medal-coloured line across the top and a rank label.
    c.medal = c:CreateTexture(nil, "OVERLAY")
    c.medal:SetPoint("TOPLEFT")
    c.medal:SetPoint("TOPRIGHT")
    c.medal:SetHeight(3)
    c.rank = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.rank:SetPoint("TOPLEFT", 6, -8)
    -- Invisible hover area over the picture and name, for the tooltip
    -- with what is known about this player from earlier runs.
    c.hover = CreateFrame("Button", nil, c)
    c.hover:SetPoint("TOPLEFT")
    c.hover:SetPoint("TOPRIGHT")
    c.hover:SetScript("OnEnter", function(self)
        if self.p then PersonTooltip(self, self.p) end -- the award card below explains itself
    end)
    c.hover:SetScript("OnLeave", GameTooltip_Hide)
    c.rows = {}
    cols[i] = c
    return c
end

----------------------------------------------------------------------
-- Awards: small cards under each player's totals (column view), or
-- titles after the name (list view). A run shown as it is left is
-- revealed: by the race (further down) when the columns stand in podium
-- order, else by the cards coming up one after another.
----------------------------------------------------------------------

local AWARD_H = 30
local REVEAL_STEP = 0.5       -- seconds between two cards
local REVEAL_FADE = 0.4       -- seconds a card takes to appear
local FANFARE_DELAY = 0.3     -- after the last card
local SCREENSHOT_DELAY = 1.2  -- after the last card, or the race

-- Calls off a reveal in progress: its timers do nothing from now on.
local function CancelReveal()
    reveal.token = reveal.token + 1
    reveal.run, reveal.ends = nil, 0
    race.Cancel()
end

-- The one line that fits under the title; the tooltip has the rest.
local function AwardShort(award)
    if award.link then return award.link end
    if award.amount then return Money(award.amount) end
    return award.text or ""
end

local function AwardOnEnter(self)
    local award = self.award
    if not award then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    AddAwardLines(award)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(AWARDS_HINT, 0.6, 0.8, 1)
    GameTooltip:Show()
end

-- A column's award card.
local function GetAwardFrame(c)
    local af = c.awardFrame
    if af then return af end
    af = CreateFrame("Button", nil, c)
    af:SetHeight(AWARD_H - 3)
    local bg = af:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.07)
    af.icon = af:CreateTexture(nil, "ARTWORK")
    af.icon:SetSize(22, 22)
    af.icon:SetPoint("LEFT", 3, 0)
    af.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    af.title = af:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    af.title:SetPoint("TOPLEFT", 30, -2)
    af.title:SetPoint("TOPRIGHT", -2, -2)
    af.title:SetJustifyH("LEFT")
    af.title:SetWordWrap(false)
    af.detail = af:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    af.detail:SetPoint("BOTTOMLEFT", 30, 2)
    af.detail:SetPoint("BOTTOMRIGHT", -2, 2)
    af.detail:SetJustifyH("LEFT")
    af.detail:SetWordWrap(false)
    af.bg = bg
    -- Receipt theme: the card is a rubber stamp, a border in ink.
    af.edges = {}
    for k, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = af:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1])
        t:SetPoint(pts[2])
        if k <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        t:Hide()
        af.edges[k] = t
    end
    af:SetScript("OnEnter", AwardOnEnter)
    af:SetScript("OnLeave", GameTooltip_Hide)
    af:SetScript("OnClick", function() ns.ShowBrowse("awards") end)
    c.awardFrame = af
    return af
end

local function GetColRow(c, j)
    local r = c.rows[j]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -13, 0) -- leaves room for the price marker
    r.value:SetJustifyH("RIGHT")
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(CIRCLE)
    r.mark:SetSize(7, 7)
    r.mark:SetPoint("RIGHT", -3, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetPoint("TOPLEFT")
    r.chip:SetPoint("BOTTOMLEFT")
    r.chip:SetWidth(3)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleHighlight(r)
    c.rows[j] = r
    return r
end

local function PlaceText(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 2, y)
    fs:SetPoint("TOPRIGHT", -2, y)
end

-- Returns one list of lines per player. With `alignItems` every column
-- gets the same rows in the same order (a dash where the player has none
-- of that item), so a line can be compared straight across.
local function BuildColumnLines(sum, o)
    local out = {}
    for i = 1, #sum.players do out[i] = {} end
    local function add(i, line) out[i][#out[i] + 1] = line end

    local function Header(cat, cs)
        -- On paper, a heading and its sum in the same bold ink.
        local value = cs and (Breakdown.ink and Money(cs.market) or MoneyGrey(cs.market)) or Grey("-")
        return { label = CatColored(cat.short, cat), cat = cat, bg = 0.08, value = value }
    end

    -- Each player's own items, in their own order.
    local function Plain(cat)
        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            if cs then
                if cat then add(i, Header(cat, cs)) end
                for _, e in ipairs(cs.items) do
                    add(i, ItemLine(e, e.count, ns.EntryMarket(e), sum.market))
                end
            end
        end
    end

    -- The same rows for everyone: every item anyone has in this group,
    -- ordered by name or by combined value.
    local function Aligned(cat)
        local union, order = {}, {}
        for _, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ns.ItemKey(e)
                local u = union[k]
                if not u then
                    u = { key = k, name = ns.ItemName(e), total = 0, quest = e.cat == "quest" }
                    union[k] = u
                    order[#order + 1] = u
                end
                u.total = u.total + ns.EntryMarket(e)
            end
        end
        if #order == 0 then return end
        table.sort(order, function(a, b)
            if a.quest ~= b.quest then return b.quest end -- quest items last
            if o.sortItems == "name" and a.name ~= b.name then return a.name < b.name end
            if a.total ~= b.total then return a.total > b.total end
            return a.key < b.key
        end)

        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            local mine = {} -- this player's items by key (same item merged)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ns.ItemKey(e)
                local m = mine[k]
                if m then
                    m.count, m.market = m.count + e.count, m.market + ns.EntryMarket(e)
                else
                    mine[k] = { e = e, count = e.count, market = ns.EntryMarket(e) }
                end
            end
            if cat then add(i, Header(cat, cs)) end
            for _, u in ipairs(order) do
                local m = mine[u.key]
                if m then
                    add(i, ItemLine(m.e, m.count, m.market, sum.market))
                else
                    add(i, { label = "|cff505050-|r" })
                end
            end
        end
    end

    -- Coins are one sum with no items under it: a heading of their own
    -- when the loot is grouped, else a line before the items.
    local anyCoins = false
    for _, p in ipairs(sum.players) do
        if p.cats.coins then anyCoins = true end
    end
    local function Coins(grouped)
        if not anyCoins then return end
        local cat = CATS.coins
        for i, p in ipairs(sum.players) do
            local cs = p.cats.coins
            if grouped then
                if cs or o.alignItems then add(i, Header(cat, cs)) end
            elseif cs then
                add(i, { label = CatColored(cat.short, cat), value = Money(cs.market) })
            elseif o.alignItems then
                add(i, { label = "|cff505050-|r" })
            end
        end
    end

    -- `false` stands for "no categories": one group holding everything.
    for _, cat in ipairs(o.groupByCategory and CATS or { false }) do
        if cat and cat.coins then
            Coins(true)
        else
            if not cat then Coins(false) end
            if o.alignItems then Aligned(cat) else Plain(cat) end
        end
    end

    -- With aligned items an empty-handed player has a column of dashes,
    -- which says it already; unless nobody has anything.
    for i, p in ipairs(sum.players) do
        -- (Nothing counted, and nothing listed either: an ignored item is.)
        if p.count == 0 and p.money == 0 and #p.all.items == 0
                and (not o.alignItems or (sum.count == 0 and sum.money == 0)) then
            add(i, { label = NoLootLabel(sum) })
        end
    end
    return out
end

-- The order players stand in on a podium: most loot in the middle, 2nd on
-- its left, 3rd on its right, then outwards. `ranked` is in rank order.
local function PodiumOrder(ranked)
    local arranged = {}
    for rank, p in ipairs(ranked) do
        if rank % 2 == 0 then
            table.insert(arranged, 1, p)
        else
            arranged[#arranged + 1] = p
        end
    end
    return arranged
end

local HEADER_GLOW_H = 72 -- Modern theme: the class-coloured glow at the top of a column

local function RenderColumns(sum, awards, insights)
    local theme = Breakdown.theme
    -- A bigger group: columns for its top five, the bench for the others.
    -- `view` is the summary with the columns' players only; every total
    -- and the equal split stay the whole run's.
    local view, bench = sum, {}
    if #sum.players > MAX_COLUMNS then
        local top = {}
        for _, p in ipairs(sum.players) do
            if p.rank <= MAX_COLUMNS then top[#top + 1] = p else bench[#bench + 1] = p end
        end
        table.sort(bench, function(a, b) return a.rank < b.rank end)
        view = setmetatable({ players = top }, { __index = sum })
    end
    local n = #view.players
    -- Receipt theme: each column is a receipt, printed in ink and lying a
    -- little apart from the next on the counter.
    local paper = theme.paper and true or false
    local gap = paper and 12 or COL_GAP
    local colW = (content:GetWidth() - gap * (n - 1)) / n
    local rowH = theme.rowH
    local equal = sum.market / #sum.players
    local maxH = 0
    Breakdown.ink = paper -- the footer under the receipts is on the counter: see below

    -- Header layout depends on what the options show.
    local o = ns.db.options
    local showBar = theme.flat and o.showBar
    local y = -8
    local yRank, yPortrait, yName, yMarket, yVendor, yShare, yBar
    if paper then yRank = y; y = y - 18 end -- "*** 1ST ***"
    if o.portrait ~= "none" then yPortrait = y; y = y - 58 end
    yName = y; y = y - 18
    yMarket = y; y = y - (paper and 24 or theme.flat and 20 or 18)
    if o.showVendor and o.valueMode ~= "vendor" then yVendor = y; y = y - 14 end
    if o.showShare then yShare = y; y = y - 16 end
    if showBar then yBar = y; y = y - 9 end

    -- The award card goes under the totals. Every column keeps room for
    -- one when anyone has one, so the item rows stay level.
    local yAward = y - 4
    if next(awards) then y = yAward - AWARD_H end
    local headerH = 4 - y

    -- Podium: columns in podium order, stepping down by rank unless items
    -- are aligned. (Summarize leaves the players in rank order for it.)
    local podium = o.sortPlayers == "podium"
    if podium then view.players = PodiumOrder(view.players) end

    -- The reveal: in podium order the columns race for their places (if
    -- there is anything to race for), else the award cards come up one
    -- after another.
    local revealIndex = 0
    local racing = false
    if reveal.pending then
        CancelReveal() -- an earlier one, if any
        reveal.run = Breakdown.CurrentRun()
        racing = (o.race and podium and n > 1 and sum.market > 0) and true or false
        if racing then race.Start() end
    end
    local token = reveal.token
    -- Receipts all come out of the printer at the same height.
    local step = (podium and not o.alignItems and not paper) and 14 or 0
    local colLines = BuildColumnLines(view, o)
    local tint = theme.flat and 0.045 or 0.03 -- how bright a column's panel is

    for i, p in ipairs(view.players) do
        local c = GetCol(i)
        c:ClearAllPoints()
        c.offset = step * math.min(p.rank - 1, 3)
        c:SetPoint("TOPLEFT", (i - 1) * (colW + gap), -c.offset)
        c:SetWidth(colW)
        if paper then
            c.bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
        else
            c.bg:SetColorTexture(1, 1, 1, tint + ((podium and p.rank == 1) and 0.04 or 0))
        end
        c.rank:ClearAllPoints()
        if paper then
            -- Every receipt says its place, podium order or not.
            c.rank:SetFontObject("ThatLuckyBastardReceiptInkBold")
            c.rank:SetTextColor(INK[1], INK[2], INK[3])
            c.rank:SetPoint("TOP", 0, yRank)
            c.rank:SetText("*** " .. ns.Ordinal(p.rank):upper() .. " ***")
        else
            c.rank:SetFontObject("GameFontNormalSmall")
            c.rank:SetPoint("TOPLEFT", 6, -8)
            if podium then
                local medal = MEDALS[p.rank] or MEDALS[4]
                c.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
                c.rank:SetText(ns.Ordinal(p.rank))
                c.rank:SetTextColor(medal[1], medal[2], medal[3])
            end
        end
        c.medal:SetShown(podium and not paper)
        c.rank:SetShown(podium or paper)

        SetPortrait(c, p, o.portrait)
        -- On paper the picture is printed: in grey, ringed in grey ink.
        c.portrait:SetDesaturated(paper)
        if paper then
            c.ring:SetVertexColor(INK_GREY[1], INK_GREY[2], INK_GREY[3])
            c.ringInner:SetVertexColor(0.851, 0.824, 0.761)
        else
            c.ringInner:SetVertexColor(DISC[1], DISC[2], DISC[3])
        end
        if yPortrait then
            c.portrait:ClearAllPoints()
            c.portrait:SetPoint("TOP", 0, yPortrait)
            c.model:ClearAllPoints()
            c.model:SetPoint("TOP", 0, yPortrait + 2)
        end
        PlaceText(c.name, yName)
        c.name:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontNormal")
        c.name:SetText(ns.BetMark(ns.ViewedRun(), p.name) .. ClassColored(DisplayName(p.name), p.class))
        c.hover.p = p
        c.hover:SetHeight(-yMarket) -- from the top down to just under the name
        PlaceText(c.market, yMarket)
        c.market:SetText(Money(p.market))
        c.vendor:SetShown(yVendor ~= nil)
        if yVendor then
            PlaceText(c.vendor, yVendor)
            if paper then
                c.vendor:SetFontObject("ThatLuckyBastardReceiptGrey")
                c.vendor:SetText("VENDOR " .. Money(p.vendor))
            else
                c.vendor:SetFontObject("GameFontHighlightSmall")
                c.vendor:SetText("|cff909090Vendor|r " .. Money(p.vendor))
            end
        end
        c.share:SetShown(yShare ~= nil)
        c.share:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
        if yShare then PlaceText(c.share, yShare) end

        -- Modern's decoration: the glow, the strip and the pill. None on paper.
        local flat = theme.flat and not paper
        local cr, cg, cb = ClassRGB(p.class)
        c.top:SetShown(flat)
        c.top:SetHeight(math.min(HEADER_GLOW_H, headerH))
        c.strip:SetShown(flat and not podium)
        c.track:SetShown(showBar)
        if showBar then
            c.track:ClearAllPoints()
            c.track:SetPoint("TOPLEFT", 8, yBar)
            c.track:SetPoint("TOPRIGHT", -8, yBar)
            if paper then
                c.track:SetColorTexture(0.839, 0.812, 0.749, 1)
            else
                c.track:SetColorTexture(1, 1, 1, 0.08)
            end
        end
        if flat and c.glowClass ~= (p.class or "") then -- only when the column changes hands
            c.glowClass = p.class or ""
            c.strip:SetColorTexture(cr, cg, cb, 0.9)
            if not SetFade(c.top, "VERTICAL", cr, cg, cb, 0, 0.30) then
                c.top:SetColorTexture(cr, cg, cb, 0.12)
            end
        end
        c.market:SetFontObject(paper and "ThatLuckyBastardReceiptTotal"
            or flat and "GameFontHighlightLarge" or "GameFontHighlight")

        local diff = p.market - equal
        local diffText = sum.market > 0 and DiffText(diff) or ""
        local showDiff = diffText ~= ""
        if sum.market > 0 then
            c.share:SetText((paper and "SHARE " or "") .. Pct(p.market, sum.market)
                .. (showDiff and ("  " .. diffText) or ""))
        else
            c.share:SetText("")
        end
        if flat and showDiff and yShare then
            c.pill:ClearAllPoints()
            c.pill:SetPoint("TOP", 0, yShare + 2)
            c.pill:SetWidth(math.min(colW - 4, c.share:GetStringWidth() + 14))
            if diff > 0 then
                c.pill:SetColorTexture(0.25, 0.82, 0.25, 0.16)
            else
                c.pill:SetColorTexture(0.88, 0.31, 0.31, 0.16)
            end
            c.pill:Show()
        else
            c.pill:Hide()
        end

        local award = awards[p.name]
        if award or c.awardFrame then
            local af = GetAwardFrame(c)
            af.award = award
            af:SetShown(award ~= nil)
            if award then
                af:ClearAllPoints()
                af:SetPoint("TOPLEFT", 4, yAward)
                af:SetPoint("TOPRIGHT", -4, yAward)
                af.icon:SetTexture("Interface\\Icons\\" .. award.icon)
                StyleAward(af, award, paper)
                af.title:SetText(AwardTitle(award))
                af.detail:SetText(AwardShort(award))
                if reveal.pending and not racing then
                    -- Hidden now, faded in a little later than the one before.
                    revealIndex = revealIndex + 1
                    af:SetAlpha(0)
                    C_Timer.After(REVEAL_STEP * revealIndex, function()
                        if token ~= reveal.token or not af.award then return end
                        if UIFrameFadeIn then UIFrameFadeIn(af, REVEAL_FADE, 0, 1) else af:SetAlpha(1) end
                        if o.ceremonySound and f:IsShown() then PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) end
                    end)
                elseif GetTime() >= reveal.ends then
                    af:SetAlpha(1)
                end
            end
        end

        -- Share bar: total length = share of the run, segments = categories.
        local x = 8
        local full = (colW - 16) * (sum.market > 0 and p.market / sum.market or 0)
        for k, cat in ipairs(CATS) do
            local seg, cs = c.segs[k], p.cats[cat.key]
            if showBar and cs and cs.market > 0 and p.market > 0 then
                local w = full * cs.market / p.market
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", x, yBar)
                seg:SetWidth(math.max(w, 1))
                if paper then -- one bar in ink: a till prints in one colour
                    seg:SetColorTexture(INK[1], INK[2], INK[3], 1)
                else
                    seg:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 0.95)
                end
                seg:Show()
                x = x + w
            else
                seg:Hide()
            end
        end

        local lines = colLines[i]

        for j, line in ipairs(lines) do
            local r = GetColRow(c, j)
            r.line = line
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(headerH + (j - 1) * rowH))
            r:SetPoint("TOPRIGHT", 0, -(headerH + (j - 1) * rowH))
            r:SetHeight(rowH)
            local left = 4
            -- A receipt prints no icons and no colour chips.
            if line.link and o.showIcons and not paper then
                r.icon:SetSize(rowH - 4, rowH - 4)
                r.icon:SetTexture(ItemIcon(line.link))
                r.icon:Show()
                left = rowH + 4
            else
                r.icon:Hide()
            end
            if line.cat and not paper then
                r.chip:SetColorTexture(line.cat.color[1], line.cat.color[2], line.cat.color[3], 0.9)
                r.chip:Show()
                left = 8
            else
                r.chip:Hide()
            end
            local font = paper and (line.cat and "ThatLuckyBastardReceiptInkBold" or "ThatLuckyBastardReceiptInk")
                or "GameFontHighlightSmall"
            r.label:SetFontObject(font)
            r.value:SetFontObject(font)
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", left, 0)
            r.label:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
            r.label:SetText(line.label or "")
            r.value:SetText(line.value or "")
            -- An item worth nothing here (ignored, given away) is faded.
            r.label:SetAlpha(line.dim and 0.5 or 1)
            r.icon:SetAlpha(line.dim and 0.5 or 1)
            SetMark(r.mark, line.mark)
            SetRowBg(r.bg, line)
            r:EnableMouse(line.link ~= nil)
            r:Show()
        end
        for j = #lines + 1, #c.rows do c.rows[j]:Hide() end

        -- A receipt ends where its print does, with its tail; the other
        -- looks keep the columns level.
        c.ownH = headerH + #lines * rowH + (paper and TAIL_H or 6)
        ShowTail(c, paper, p.name, colW)
        maxH = math.max(maxH, c.offset + c.ownH + (paper and EDGE_H or 0))
        c:Show()
    end
    for i = 1, n do
        local c = cols[i]
        c:SetHeight(paper and c.ownH or (maxH - c.offset))
    end
    for i = n + 1, #cols do cols[i]:Hide() end
    Breakdown.ink = false -- the footer is written on the counter, not on paper
    if reveal.pending then
        reveal.pending = false
        local length = REVEAL_STEP * revealIndex
        reveal.ends = GetTime() + length + REVEAL_FADE
        if revealIndex > 0 then
            -- A fanfare once the last card is up, then the souvenir photo.
            if o.ceremonySound then
                C_Timer.After(length + FANFARE_DELAY, function()
                    if token == reveal.token and f:IsShown() then PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
                end)
            end
            if o.ceremonyScreenshot and Screenshot then
                C_Timer.After(length + SCREENSHOT_DELAY, function()
                    if token == reveal.token and f:IsShown() then Screenshot() end
                end)
            end
        end
    end

    local bottom = RenderBench(bench, awards, maxH + 10, paper)
    local texts = FooterTexts(sum, insights, true)
    for i, text in ipairs(texts) do
        local fs = footLines[i]
        if not fs then
            fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            footLines[i] = fs
        end
        fs:SetFontObject(paper and "ThatLuckyBastardReceiptCounter" or "GameFontHighlightSmall")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -bottom)
        fs:SetText(text)
        fs:Show()
        bottom = bottom + 16
    end
    for i = #texts + 1, #footLines do footLines[i]:Hide() end
    content:SetHeight(bottom + 4)

    -- A race in progress takes the columns from here.
    if race.on then
        local tall = maxH
        if paper then
            tall = 0
            for i = 1, n do tall = math.max(tall, cols[i].ownH) end
        end
        race.Lay(view.players, colW + gap, tall, paper, tint, headerH)
    end
end

-- For the window's other files.
Breakdown.RenderColumns, Breakdown.CancelReveal = RenderColumns, CancelReveal
Breakdown.SCREENSHOT_DELAY = SCREENSHOT_DELAY
