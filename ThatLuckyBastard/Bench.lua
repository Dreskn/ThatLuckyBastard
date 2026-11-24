local _, ns = ...

-- The bench: in a group too big for one column each, the columns go to
-- the top five and everyone else follows under them, side by side, on
-- small cards: picture, name, award and loot value, one under the other
-- (the options say which). As many cards are shown as fit on one row. The
-- row ends with an arrow that shows this run as a list instead, where
-- everyone has a line (a Columns button there leads back); it says how
-- many players the row had no room for.
--
-- Each theme draws the cards its own way: Modern, a faint panel under a
-- line in the player's class colour, and the arrow in the accent colour;
-- Classic, the same panel bare, and the game's own page arrow; Receipt, a
-- paper ticket printed in ink, and the arrow on a till key.

local Breakdown = ns.Breakdown
local race, MAX_COLUMNS, ACCENT = Breakdown.race, Breakdown.MAX_COLUMNS, Breakdown.ACCENT
local PAPER, INK, INK_GREY, KEY = Breakdown.PAPER, Breakdown.INK, Breakdown.INK_GREY, Breakdown.KEY
local KEY_EDGE, INK_GREY_CODE = Breakdown.KEY_EDGE, Breakdown.INK_GREY_CODE
local listRuns, Render, Money = Breakdown.listRuns, Breakdown.Render, Breakdown.Money
local ClassRGB, DisplayName = Breakdown.ClassRGB, Breakdown.DisplayName
local ClassColored, content = Breakdown.ClassColored, Breakdown.content
local AwardTitle, PersonTooltip = Breakdown.AwardTitle, Breakdown.PersonTooltip
local DISC, NewRoundPicture = Breakdown.DISC, Breakdown.NewRoundPicture
local UnitForName, InSight = Breakdown.UnitForName, Breakdown.InSight
local FillPortrait = Breakdown.FillPortrait

local RenderBench, HideBench, ShowBackButton, BenchRoom

local CARD_W, CARD_GAP = 104, 6
local CARD_PAD = 6      -- above and below what a card holds
local CARD_PICTURE = 30
local MORE_W = 64       -- the arrow at the end of the row
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ARROW_CLASSIC = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local ARROW_CLASSIC_BACK = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local BACK_W, BACK_BUTTON_H = 104, 26 -- the arrow back to the columns, at the top of the list
local BACK_H = 34       -- room for it there
local benchMore, backButton
local benchSeats = {}

function HideBench()
    if benchMore then benchMore:Hide() end
    for _, seat in ipairs(benchSeats) do seat:Hide() end
end

-- How wide a row of `n` cards is; `more`: with the arrow after them.
function BenchRoom(n, more)
    return n * (CARD_W + CARD_GAP) - CARD_GAP + (more and CARD_GAP + MORE_W or 0)
end

-- The race stands its columns taller than they will be: the bench
-- under them is out of sight until it is over.
function race.Bench(alpha)
    if benchMore then benchMore:SetAlpha(alpha) end
    for _, seat in ipairs(benchSeats) do seat:SetAlpha(alpha) end
end

local function BenchSeat(i)
    local seat = benchSeats[i]
    if seat then return seat end
    seat = CreateFrame("Frame", nil, content)
    seat.bench = true
    seat.bg = seat:CreateTexture(nil, "BACKGROUND")
    seat.bg:SetAllPoints()
    seat.strip = seat:CreateTexture(nil, "BORDER")
    seat.strip:SetPoint("TOPLEFT")
    seat.strip:SetPoint("TOPRIGHT")
    seat.strip:SetHeight(2)
    seat.portrait, seat.ring, seat.ringInner = NewRoundPicture(seat)
    seat.portrait:SetSize(CARD_PICTURE, CARD_PICTURE)
    seat.ring:SetSize(CARD_PICTURE + 4, CARD_PICTURE + 4)
    seat.ringInner:SetSize(CARD_PICTURE + 2, CARD_PICTURE + 2)
    local function Line()
        local fs = seat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        fs:SetWidth(CARD_W - 8) -- a longer name is cut short, not spilled
        return fs
    end
    seat.name, seat.title, seat.gold = Line(), Line(), Line()
    seat:EnableMouse(true)
    seat:SetScript("OnEnter", function(self)
        if self.p then PersonTooltip(self, self.p, self.won) end
    end)
    seat:SetScript("OnLeave", function() GameTooltip:Hide() end)
    benchSeats[i] = seat
    return seat
end

-- An arrow with a word under or beside it. There are two, mirrors of
-- one another: the one that ends the bench and leads to the list, and
-- the one at the top of that list that leads back to the columns.
-- `list`: whether a click makes this run a list, or gives it back its
-- columns. `tip(self)` adds the lines of its tooltip.
local function NewArrow(list, tip)
    local b = CreateFrame("Button", nil, content)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = b:CreateTexture(nil, "BORDER") -- a till key's darker lower edge
    b.edge:SetPoint("BOTTOMLEFT")
    b.edge:SetPoint("BOTTOMRIGHT")
    b.edge:SetHeight(3)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetScript("OnClick", function()
        local run = Breakdown.CurrentRun()
        if run then listRuns[run] = list or nil end
        GameTooltip:Hide()
        Render()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        tip(self)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Paints an arrow the way the theme in force has it, and writes `label`
-- on it (in capitals on a till key), with `under` in grey on a line of
-- its own beneath when given. `back`: pointing left.
local function PaintArrow(b, label, paper, back, under)
    local theme = Breakdown.theme
    b.edge:SetShown(paper and true or false)
    b.arrow:SetDesaturated(false)
    b.arrow:SetTexCoord(0, 1, 0, 1)
    if paper then
        b.bg:SetColorTexture(KEY[1], KEY[2], KEY[3], 1)
        b.edge:SetColorTexture(KEY_EDGE[1], KEY_EDGE[2], KEY_EDGE[3], 1)
        b.hl:SetColorTexture(1, 1, 1, 0.22)
        b.arrow:SetTexture(ARROW)
        b.arrow:SetDesaturated(true)
        b.arrow:SetVertexColor(INK[1], INK[2], INK[3])
        b.text:SetFontObject("ThatLuckyBastardReceiptKey")
        label, under = label:upper(), under and under:upper()
    elseif theme.flat then
        b.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.14)
        b.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
        b.arrow:SetTexture(ARROW)
        b.arrow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
        b.text:SetFontObject("GameFontHighlightSmall")
    else
        b.bg:SetColorTexture(1, 1, 1, 0.05)
        b.hl:SetColorTexture(1, 1, 1, 0.10)
        b.arrow:SetTexture(back and ARROW_CLASSIC_BACK or ARROW_CLASSIC) -- the game has one for each way
        b.arrow:SetVertexColor(1, 1, 1)
        b.text:SetFontObject("GameFontNormalSmall")
    end
    -- The plain arrow points right: turned over, it points back.
    if back and (paper or theme.flat) then b.arrow:SetTexCoord(1, 0, 0, 1) end
    if under then label = label .. "\n" .. (paper and INK_GREY_CODE or "|cffa0a0a8") .. under .. "|r" end
    b.text:SetText(label)
end

local function BenchMore()
    if benchMore then return benchMore end
    benchMore = NewArrow(true, function(self)
        GameTooltip:AddLine("Show this run as a list")
        if (self.hidden or 0) > 0 then
            GameTooltip:AddLine(("%d more %s there."):format(self.hidden, self.hidden == 1 and "player is" or "players are"),
                0.7, 0.7, 0.7)
        end
    end)
    benchMore.more = true
    benchMore.text:SetJustifyH("CENTER")
    benchMore.text:SetWidth(MORE_W - 6)
    return benchMore
end

-- Draws the bench for the players in `bench` (in rank order), `top` down
-- from the top of the content, and returns where what follows starts.
-- `all`: the cards are the whole window (mini mode). They show their
-- picture, award and total whatever the bench's own options say; there
-- are up to five of them, and the arrow only when there are more
-- players than that.
function RenderBench(bench, awards, top, paper, all)
    local theme = Breakdown.theme
    HideBench()
    if #bench == 0 then return top end
    local o = ns.db.options
    local flat = theme.flat
    local picture = (all or o.benchPicture) and o.portrait ~= "none"
    local title = (all or o.benchAward) and next(awards) ~= nil -- no awards yet while a run is going
    local gold = all or o.benchValue
    local height = CARD_PAD * 2 + (picture and CARD_PICTURE + 6 or 0) + 14 + (title and 13 or 0) + (gold and 13 or 0)

    -- As many cards as the row holds beside the arrow, the whole of it
    -- centred. (The mini window is made to measure: its cards are
    -- counted, not fitted, since a width that fits exactly may be a
    -- hair short once the game has rounded it.)
    local width = content:GetWidth()
    local shown, arrow
    if all then
        shown = math.min(#bench, MAX_COLUMNS)
        arrow = #bench > shown
    else
        shown = math.min(#bench, math.max(0, math.floor((width - MORE_W) / (CARD_W + CARD_GAP))))
        arrow = true
    end
    local x = math.max(0, (width - BenchRoom(shown, arrow)) / 2)

    Breakdown.ink = paper -- a ticket is paper: its text is printed in ink
    for i = 1, shown do
        local p = bench[i]
        local seat = BenchSeat(i)
        seat.p, seat.won = p, awards[p.name]
        local cr, cg, cb = ClassRGB(p.class)
        if paper then
            seat.bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
        else
            seat.bg:SetColorTexture(1, 1, 1, flat and 0.045 or 0.03)
        end
        seat.strip:SetShown(flat and not paper)
        seat.strip:SetColorTexture(cr, cg, cb, 0.9)

        local y = -CARD_PAD
        seat.portrait:SetShown(picture and true or false)
        seat.ring:SetShown(picture and true or false)
        seat.ringInner:SetShown(picture and true or false)
        if picture then
            seat.portrait:ClearAllPoints()
            seat.portrait:SetPoint("TOP", 0, y - 2)
            -- As in the list: the portrait of a player in sight, else the class icon.
            local unit = o.portrait ~= "class" and UnitForName(p.name) or nil
            if unit and not InSight(unit) then unit = nil end
            FillPortrait(seat.portrait, p, unit)
            seat.portrait:SetDesaturated(paper and true or false)
            if paper then
                seat.ring:SetVertexColor(INK_GREY[1], INK_GREY[2], INK_GREY[3])
                seat.ringInner:SetVertexColor(0.851, 0.824, 0.761)
            else
                seat.ring:SetVertexColor(cr, cg, cb)
                seat.ringInner:SetVertexColor(DISC[1], DISC[2], DISC[3])
            end
            y = y - CARD_PICTURE - 6
        end
        local function Put(line, on, font, text, room)
            line:SetShown(on and true or false)
            if not on then return end
            line:SetFontObject(font)
            line:ClearAllPoints()
            line:SetPoint("TOP", 0, y)
            line:SetText(text)
            y = y - room
        end
        Put(seat.name, true, paper and "ThatLuckyBastardReceiptInkBold" or "GameFontHighlightSmall",
            ns.BetMark(ns.ViewedRun(), p.name) .. ClassColored(DisplayName(p.name), p.class), 14)
        Put(seat.title, title, paper and "ThatLuckyBastardReceiptSmall" or "GameFontHighlightSmall",
            seat.won and AwardTitle(seat.won) or "", 13)
        Put(seat.gold, gold, paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall",
            Money(p.market), 13)

        seat:ClearAllPoints()
        seat:SetPoint("TOPLEFT", x, -top)
        seat:SetSize(CARD_W, height)
        seat:Show()
        x = x + CARD_W + CARD_GAP
    end
    Breakdown.ink = false

    if not arrow then return top + height + 10 end
    -- The arrow at the end of the row: this run as a list.
    local more = BenchMore()
    more.hidden = #bench - shown
    PaintArrow(more, "List", paper, false, more.hidden > 0 and (more.hidden .. " more") or nil)
    local big = math.min(30, height - (more.hidden > 0 and 38 or 26))
    more.arrow:SetSize(big, big)
    more.arrow:ClearAllPoints()
    more.arrow:SetPoint("CENTER", 0, more.hidden > 0 and 12 or 7)
    more.text:ClearAllPoints()
    more.text:SetPoint("BOTTOM", 0, paper and 9 or 7)
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", x, -top)
    more:SetSize(MORE_W, height)
    more:Show()
    return top + height + 10
end

-- The way back for a run its bench switched to the list: at the top of
-- the list, the mirror of the bench's arrow, pointing left, with
-- "Columns" beside it. Returns the room it takes there.
function ShowBackButton(show)
    local theme = Breakdown.theme
    if not show then
        if backButton then backButton:Hide() end
        return 0
    end
    if not backButton then
        backButton = NewArrow(false, function() GameTooltip:AddLine("Back to the columns") end)
        backButton.back = true
        backButton.text:SetJustifyH("LEFT")
    end
    local paper = theme.paper and true or false
    PaintArrow(backButton, "Columns", paper, true)
    backButton.arrow:SetSize(16, 16)
    backButton.arrow:ClearAllPoints()
    backButton.arrow:SetPoint("LEFT", 8, paper and 1 or 0)
    backButton.text:ClearAllPoints()
    backButton.text:SetPoint("LEFT", 30, paper and 1 or 0)
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPLEFT", 4, -4)
    backButton:SetSize(BACK_W, BACK_BUTTON_H)
    backButton:Show()
    return BACK_H
end

-- For the window's other files.
Breakdown.RenderBench, Breakdown.HideBench = RenderBench, HideBench
Breakdown.ShowBackButton, Breakdown.BenchRoom = ShowBackButton, BenchRoom
