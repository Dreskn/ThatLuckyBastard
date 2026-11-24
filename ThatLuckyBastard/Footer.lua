local _, ns = ...

-- Footer: the text lines under the breakdown. Totals, run time, dungeon
-- records, comparison with your average, and the legend for the dots.

local Breakdown = ns.Breakdown
local Money, LEGEND, LEGEND_INK = Breakdown.Money, Breakdown.LEGEND, Breakdown.LEGEND_INK
local GoodCode, BadCode, HeadCode = Breakdown.GoodCode, Breakdown.BadCode, Breakdown.HeadCode
local LowCode = Breakdown.LowCode

local function Duration(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes >= 60 then
        return ("%dh %02dm"):format(math.floor(minutes / 60), minutes % 60)
    end
    return ("%dm %02ds"):format(minutes, seconds % 60)
end

-- Is any item of the run valued at an auction price? (The legend for the
-- dots is pointless otherwise.)
local function AnyAuctionPrice(sum)
    for _, p in ipairs(sum.players) do
        for _, e in ipairs(p.all.items) do
            if e.ah then return true end
        end
    end
    return false
end

local RECORD_LABELS = {
    { "group", "richest run" }, { "mine", "your best haul" },
    { "jackpot", "biggest single item" }, { "fastest", "fastest run" },
}

-- "40% higher" / "12% lower" / "about the same"
local function Versus(pct)
    if math.abs(pct) < 5 then return "about the same" end
    return ("%d%% %s"):format(math.abs(pct) + 0.5, pct > 0 and (GoodCode() .. "higher|r") or (BadCode() .. "lower|r"))
end

-- insights: nil when they are switched off. includeTotals: the list view
-- shows its totals as rows of its own.
local function FooterTexts(sum, insights, includeTotals)
    local o = ns.db.options
    local texts = {}
    local n = #sum.players
    -- Headings and secondary words: gold and grey, or two inks on paper.
    local hi, lo = HeadCode(), LowCode()

    if includeTotals and o.showTotals and n > 0 then
        local equal = sum.market / n
        if o.valueMode == "vendor" then
            texts[#texts + 1] = ("%sTotal|r  %s      %sEqual split|r  %s"):format(
                hi, Money(sum.market), lo, Money(equal))
        else
            texts[#texts + 1] = ("%sTotal|r  %s      %sVendor|r  %s      %sEqual split|r  %s")
                :format(hi, Money(sum.market), lo, Money(sum.vendor), lo, Money(equal))
        end
    end

    if insights then
        local parts = {}
        if insights.duration then
            parts[#parts + 1] = lo .. "Run time|r  " .. Duration(insights.duration)
            if insights.perHour then
                parts[#parts + 1] = lo .. "Group per hour|r  " .. Money(insights.perHour)
            end
        end
        if insights.fair then
            parts[#parts + 1] = ("%sFairness|r  %d / 100"):format(lo, insights.fair)
        end
        if #parts > 0 then texts[#texts + 1] = table.concat(parts, "      ") end
        if insights.streak then
            local streak = insights.streak
            texts[#texts + 1] = ("%s%s|r      %stogether so far|r  %s      %syours|r  %s")
                :format(hi, ns.StreakLabel(streak), lo, Money(streak.total), lo, Money(streak.mine))
        end
        if insights.records then
            local names = {}
            for _, label in ipairs(RECORD_LABELS) do
                if insights.records[label[1]] then names[#names + 1] = label[2] end
            end
            if #names > 0 then
                texts[#texts + 1] = hi .. "New record here:|r  " .. table.concat(names, ", ")
            end
        end
        if insights.groupPct then
            local text = ("%sAgainst your average here|r  group loot %s"):format(lo, Versus(insights.groupPct))
            if insights.minePct then
                text = text .. (",  your own %s"):format(Versus(insights.minePct))
            end
            texts[#texts + 1] = text .. ("  %s(%d %s %s)|r"):format(
                lo, insights.priorRuns, insights.earlier and "earlier" or "other",
                insights.priorRuns == 1 and "run" or "runs")
        end
    end

    if n > 0 and o.valueMode ~= "vendor" and (ns.HasPriceSource() or AnyAuctionPrice(sum)) then
        texts[#texts + 1] = Breakdown.ink and LEGEND_INK or LEGEND
    end
    return texts
end

-- For the window's other files.
Breakdown.FooterTexts = FooterTexts
ns.Duration = Duration
