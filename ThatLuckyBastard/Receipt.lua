local _, ns = ...

-- Receipt theme: the award card as a rubber stamp, and the end of each
-- receipt under its last line (a double rule, a barcode, a thank-you and
-- the torn edge).
--
-- The theme's colours and typewriter fonts are UI.lua's: every part of
-- the window uses them, and its title bar needs a font as it loads.

local Breakdown = ns.Breakdown
local PAPER, INK, STAMP_RED = Breakdown.PAPER, Breakdown.INK, Breakdown.STAMP_RED
local STAMP_BLUE, RED_STAMPS, MEDIA = Breakdown.STAMP_BLUE, Breakdown.RED_STAMPS, Breakdown.MEDIA

local TAIL_H = 62 -- from the last line to the bottom of the paper
local EDGE_H = 8  -- the torn edge, under the paper
local EDGE = MEDIA .. "receipt-edge"

local function StyleAward(af, award, paper)
    af.icon:SetShown(not paper)
    af.title:ClearAllPoints()
    af.detail:ClearAllPoints()
    if paper then
        local ink = RED_STAMPS[award.key] and STAMP_RED or STAMP_BLUE
        af.bg:SetColorTexture(0, 0, 0, 0)
        for _, e in ipairs(af.edges) do
            e:SetColorTexture(ink[1], ink[2], ink[3], 0.85)
            e:Show()
        end
        af.title:SetFontObject("ThatLuckyBastardReceiptInkBold")
        af.detail:SetFontObject("ThatLuckyBastardReceiptSmall")
        af.title:SetTextColor(ink[1], ink[2], ink[3])
        af.detail:SetTextColor(ink[1], ink[2], ink[3])
        af.title:SetPoint("TOPLEFT", 4, -3)
        af.title:SetPoint("TOPRIGHT", -4, -3)
        af.detail:SetPoint("BOTTOMLEFT", 4, 3)
        af.detail:SetPoint("BOTTOMRIGHT", -4, 3)
        af.title:SetJustifyH("CENTER")
        af.detail:SetJustifyH("CENTER")
    else
        af.bg:SetColorTexture(1, 1, 1, 0.07)
        for _, e in ipairs(af.edges) do e:Hide() end
        af.title:SetFontObject("GameFontNormalSmall")
        af.detail:SetFontObject("GameFontHighlightSmall")
        af.title:SetPoint("TOPLEFT", 30, -2)
        af.title:SetPoint("TOPRIGHT", -2, -2)
        af.detail:SetPoint("BOTTOMLEFT", 30, 2)
        af.detail:SetPoint("BOTTOMRIGHT", -2, 2)
        af.title:SetJustifyH("LEFT")
        af.detail:SetJustifyH("LEFT")
    end
end

-- Bars of one or two pixels with gaps of one to three: the same barcode
-- for the same name.
local function BarcodePattern(name)
    local out = {}
    for i = 1, 22 do
        local b = name:byte((i - 1) % #name + 1) or 7
        out[i] = { w = 1 + (b + i) % 2, gap = 1 + (b * i) % 3 }
    end
    return out
end

local function GetTail(c)
    if c.tail then return c.tail end
    local t = { bars = {} }
    t.rule1 = c:CreateTexture(nil, "ARTWORK")
    t.rule2 = c:CreateTexture(nil, "ARTWORK")
    for _, rule in ipairs({ t.rule1, t.rule2 }) do
        rule:SetHeight(1)
        rule:SetColorTexture(INK[1], INK[2], INK[3], 1)
    end
    t.thanks = c:CreateFontString(nil, "OVERLAY", "ThatLuckyBastardReceiptSmall")
    t.thanks:SetText("THANK YOU FOR LOOTING")
    t.thanks:SetJustifyH("CENTER")
    t.thanks:SetWordWrap(false)
    t.thanks:SetPoint("BOTTOMLEFT", 4, 9)
    t.thanks:SetPoint("BOTTOMRIGHT", -4, 9)
    t.edge = c:CreateTexture(nil, "BACKGROUND")
    t.edge:SetPoint("TOPLEFT", c, "BOTTOMLEFT")
    t.edge:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT")
    t.edge:SetHeight(EDGE_H)
    t.edge:SetTexture(EDGE, "REPEAT", "CLAMP") -- tiled by its texture coordinates (ShowTail)
    t.edge:SetVertexColor(PAPER[1], PAPER[2], PAPER[3])
    c.tail = t
    return t
end

local function ShowTail(c, show, name, width)
    local t = c.tail
    if not show then
        if t then
            t.rule1:Hide()
            t.rule2:Hide()
            t.thanks:Hide()
            t.edge:Hide()
            for _, b in ipairs(t.bars) do b:Hide() end
        end
        return
    end
    t = GetTail(c)
    for k, rule in ipairs({ t.rule1, t.rule2 }) do
        rule:ClearAllPoints()
        rule:SetPoint("BOTTOMLEFT", 8, TAIL_H - 8 - (k - 1) * 3)
        rule:SetPoint("BOTTOMRIGHT", -8, TAIL_H - 8 - (k - 1) * 3)
        rule:Show()
    end
    local pattern = BarcodePattern(name or "?")
    local total = 0
    for _, bar in ipairs(pattern) do total = total + bar.w + bar.gap end
    local x = math.floor((width - total) / 2)
    for i, bar in ipairs(pattern) do
        local b = t.bars[i]
        if not b then
            b = c:CreateTexture(nil, "ARTWORK")
            b:SetColorTexture(INK[1], INK[2], INK[3], 1)
            t.bars[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", x, 24)
        b:SetSize(bar.w, 20)
        b:Show()
        x = x + bar.w + bar.gap
    end
    for i = #pattern + 1, #t.bars do t.bars[i]:Hide() end
    t.thanks:Show()
    t.edge:SetTexCoord(0, width / 16, 0, 1) -- one tooth every 16 pixels
    t.edge:Show()
end

-- For the window's other files.
Breakdown.StyleAward, Breakdown.ShowTail = StyleAward, ShowTail
Breakdown.TAIL_H, Breakdown.EDGE_H = TAIL_H, EDGE_H
