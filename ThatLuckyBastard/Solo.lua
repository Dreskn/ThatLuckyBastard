local _, ns = ...

-- The solo page: the breakdown of a run with one player (a farm alone, a
-- dungeon soloed), in place of a lone column. On the left, its figures:
-- the time it took (a farm's pauses left out), the total, gold per hour
-- and how that compares with your other farms in the zone (or runs of the
-- dungeon), the best item, and the run's note. On the right, the loot by
-- category, each item with how many came per hour. No reveal: there is
-- nobody to race.

local Breakdown = ns.Breakdown
local content = Breakdown.content
local Money, Grey, HeadCode = Breakdown.Money, Breakdown.Grey, Breakdown.HeadCode
local INK, INK_GREY = Breakdown.INK, Breakdown.INK_GREY

local PANEL_W = 250 -- the figures on the left
local GAP = 12      -- between them and the loot
local PAD = 12      -- inside the figures' panel
local LINE = 20     -- a figure's line

local panel = CreateFrame("Frame", nil, content)
panel.soloPanel = true
panel:SetPoint("TOPLEFT", 0, 0)
panel:SetWidth(PANEL_W)
panel:Hide()
panel.bg = panel:CreateTexture(nil, "BACKGROUND")
panel.bg:SetAllPoints()

-- Its words: a pool of left and right texts, and rules between groups.
local texts, rules = {}, {}
local function TextAt(i)
    local t = texts[i]
    if t then return t end
    t = {
        label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
    }
    t.label:SetJustifyH("LEFT")
    t.label:SetWordWrap(false)
    t.value:SetJustifyH("RIGHT")
    t.value:SetWordWrap(false)
    texts[i] = t
    return t
end
local function RuleAt(i)
    rules[i] = rules[i] or panel:CreateTexture(nil, "BORDER")
    return rules[i]
end

-- The best item: its icon and its link.
panel.icon = panel:CreateTexture(nil, "ARTWORK")
panel.icon:SetSize(20, 20)
panel.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
panel.item = CreateFrame("Button", nil, panel)
panel.item:SetHeight(20)
panel.item.text = panel.item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.item.text:SetAllPoints()
panel.item.text:SetJustifyH("LEFT")
panel.item.text:SetWordWrap(false)
panel.item:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
end)
panel.item:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The note: a box to click and write in (Notes.lua).
panel.note = CreateFrame("Button", nil, panel)
panel.note.soloNote = true
panel.note:SetHeight(26)
panel.note.edge = panel.note:CreateTexture(nil, "BORDER")
panel.note.edge:SetAllPoints()
panel.note.face = panel.note:CreateTexture(nil, "BACKGROUND")
panel.note.face:SetPoint("TOPLEFT", 1, -1)
panel.note.face:SetPoint("BOTTOMRIGHT", -1, 1)
panel.note.text = panel.note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.note.text:SetPoint("LEFT", 8, 0)
panel.note.text:SetPoint("RIGHT", -8, 0)
panel.note.text:SetJustifyH("LEFT")
panel.note.text:SetWordWrap(false)
panel.note:SetScript("OnClick", function(self)
    if self.run and ns.EditNote then ns.EditNote(self.run, self) end
end)

-- "76/h" (or "2.5/h" under ten): how many came per hour.
local function PerHour(count, seconds)
    if not seconds or seconds < 60 or not count or count <= 0 then return "" end
    local n = count * 3600 / seconds
    return (n >= 10 and ("%d/h"):format(n + 0.5) or ("%.1f/h"):format(n))
end

-- Gold per hour, short: "58g/h".
local function GoldHour(copper)
    local g = math.floor((copper or 0) / 10000 + 0.5)
    return (Breakdown.ink and tostring(g) or ("|cffffd700" .. g .. "|r")) .. "g/h"
end

-- The figures, as lines: { label, value } or { big = text } or { rule }.
local function Figures(s, p, insights)
    local lines = {}
    local function add(t) lines[#lines + 1] = t end
    local seconds = ns.RunDuration(s)
    add({ label = s.manual and "Farmed" or "Run time", value = seconds and ns.Duration(seconds) or "-" })
    if s.manual and (s.pausedFor or 0) + (s.pausedAt and 1 or 0) > 0 then
        local paused = (s.pausedFor or 0) + (s.pausedAt and math.max(time() - s.pausedAt, 0) or 0)
        add({ label = "Paused", value = Grey(ns.Duration(paused) .. ", not counted"), small = true })
    end
    if s.dungeons then -- taken into the farm (ns.AnswerAside): its time is in it
        local spent = 0
        for _, d in ipairs(s.dungeons) do spent = spent + (d.t or 0) end
        add({ label = "In dungeons", value = Grey(ns.Duration(spent)), small = true })
    end
    add({ rule = true })
    add({ label = "Total" })
    add({ big = Money(p.market) })
    local perHour = seconds and seconds >= (ns.MIN_TIMED_RUN or 60) and p.market * 3600 / seconds or nil
    add({ label = "Per hour", value = perHour and Money(perHour) or "-" })
    if s.manual then
        local zone = ns.FarmZone(s)
        if zone then
            local pct = perHour and zone.perHour > 0 and (perHour - zone.perHour) / zone.perHour * 100 or nil
            local mark = ""
            if pct and math.abs(pct) >= 1 then
                mark = ("  %s%+d%%|r"):format(pct > 0 and Breakdown.GoodCode() or Breakdown.BadCode(), pct + (pct > 0 and 0.5 or -0.5))
            end
            add({ label = "Your average", value = GoldHour(zone.perHour) .. mark })
            if zone.best then add({ label = "Your best", value = GoldHour(zone.best) }) end
        end
    elseif insights and insights.minePct then
        add({ label = "Your average", value = ("%s%+d%%|r"):format(
            insights.minePct >= 0 and Breakdown.GoodCode() or Breakdown.BadCode(), insights.minePct + 0.5) })
    end
    add({ rule = true })
    add({ label = "Best item" })
    add({ item = p.bestLink or false })
    add({ rule = true })
    add({ label = "Note" })
    add({ note = true })
    return lines
end

local function Paint(theme)
    local paper, flat = theme.paper and true or false, theme.flat and true or false
    if paper then
        panel.bg:SetColorTexture(0, 0, 0, 0)
    elseif flat then
        panel.bg:SetColorTexture(1, 1, 1, 0.045)
    else
        panel.bg:SetColorTexture(0, 0, 0, 0.25)
    end
    return paper, flat
end

function Breakdown.RenderSolo(s, sum, insights)
    local theme = Breakdown.theme
    local o = ns.db.options
    local p = sum.players[1]
    local paper, flat = Paint(theme)
    Breakdown.ink = paper

    -- The figures.
    local y = -PAD
    local n, r = 0, 0
    local labelColor = paper and INK_GREY or flat and { 0.62, 0.66, 0.71 } or { 1, 0.82, 0 }
    local strong = paper and INK or { 1, 1, 1 }
    panel.icon:Hide()
    panel.item:Hide()
    panel.note:Hide()
    for _, line in ipairs(Figures(s, p, insights)) do
        if line.rule then
            r = r + 1
            local t = RuleAt(r)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", PAD, y - 4)
            t:SetPoint("TOPRIGHT", -PAD, y - 4)
            t:SetHeight(1)
            if paper then t:SetColorTexture(INK_GREY[1], INK_GREY[2], INK_GREY[3], 0.6) else t:SetColorTexture(1, 1, 1, 0.1) end
            t:Show()
            y = y - 10
        elseif line.item ~= nil or line.note then
            local box = line.note and panel.note or panel.item
            box:ClearAllPoints()
            if line.note then
                box:SetPoint("TOPLEFT", PAD, y)
                box:SetPoint("TOPRIGHT", -PAD, y)
                if paper then
                    box.edge:SetColorTexture(INK_GREY[1], INK_GREY[2], INK_GREY[3], 0.8)
                    box.face:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
                else
                    box.edge:SetColorTexture(1, 1, 1, 0.18)
                    box.face:SetColorTexture(0.05, 0.06, 0.08, 1)
                end
                box.text:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
                box.text:SetText(s.note or Grey("Click to write a note"))
                box.run = (not s.example) and s or nil
                box:EnableMouse(box.run ~= nil)
                y = y - 30
            else
                local link = line.item ~= false and line.item or nil
                panel.icon:SetShown(link ~= nil and not paper)
                panel.icon:ClearAllPoints()
                panel.icon:SetPoint("TOPLEFT", PAD, y)
                if link then panel.icon:SetTexture(Breakdown.ItemIcon(link)) end
                box:SetPoint("TOPLEFT", PAD + (paper and 0 or 26), y)
                box:SetPoint("TOPRIGHT", -PAD, y)
                box.text:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
                box.text:SetText(link and (paper and link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|r", "") or link)
                                 or Grey("-"))
                box.link = link
                y = y - 24
            end
            box:Show()
        else
            n = n + 1
            local t = TextAt(n)
            t.label:ClearAllPoints()
            t.value:ClearAllPoints()
            t.label:SetPoint("TOPLEFT", PAD, y)
            t.value:SetPoint("TOPRIGHT", -PAD, y)
            t.label:SetFontObject(paper and "ThatLuckyBastardReceiptGrey" or "GameFontNormalSmall")
            t.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
            if line.big then
                t.label:SetText("")
                t.value:ClearAllPoints()
                t.value:SetPoint("TOPLEFT", PAD, y)
                t.value:SetJustifyH("LEFT")
                t.value:SetFontObject(paper and "ThatLuckyBastardReceiptTotal" or flat and "GameFontHighlightLarge"
                                      or "GameFontHighlight")
                t.value:SetText(line.big)
                y = y - 28
            else
                t.value:SetJustifyH("RIGHT")
                t.value:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
                t.label:SetText(paper and (line.label or ""):upper() or line.label or "")
                t.value:SetText(line.value or "")
                y = y - (line.small and 16 or LINE)
            end
            t.value:SetTextColor(strong[1], strong[2], strong[3])
            t.label:Show()
            t.value:Show()
        end
    end
    for i = n + 1, #texts do
        texts[i].label:Hide()
        texts[i].value:Hide()
    end
    for i = r + 1, #rules do rules[i]:Hide() end
    local panelH = PAD - y
    panel:SetHeight(panelH)
    panel:Show()

    -- The loot, as the column view lists it, with how many per hour.
    local seconds = ns.RunDuration(s)
    local lines = { {
        indent = 4, bg = 0.12, label = HeadCode() .. "Loot|r", share = Grey("per hour"),
    } }
    for _, line in ipairs(Breakdown.BuildColumnLines(sum, o)[1] or {}) do
        if line.cat then
            line.indent, line.market = 4, line.value
        else
            line.indent, line.icon, line.market = 16, line.link ~= nil, line.value
            line.share = line.e and not line.dim and Grey(PerHour(ns.CountedCopies(ns.RealEntry(line.e)), seconds)) or ""
        end
        lines[#lines + 1] = line
    end
    if #lines == 1 then lines[2] = { indent = 16, wide = true, label = Grey("Nothing looted.") } end
    Breakdown.RenderList(lines, false, true, 0, PANEL_W + GAP)
    content:SetHeight(math.max(content:GetHeight(), panelH))
    Breakdown.ink = false
end

function Breakdown.HideSolo()
    panel:Hide()
end
