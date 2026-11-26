local _, ns = ...

-- The race: how a run is revealed when it is left (each time it is),
-- with one column per player in podium order. The columns start side by
-- side in name order, showing who is in them and nothing else, each as
-- tall as its head and the room for its pile. Each player's loot falls
-- into their column, item by item, each as big as its worth, with their
-- gold as coins (Coins.lua): first all but the run's three most valuable
-- items, then those three one by one, a beat apart. Each total counts up
-- as its pieces land, with no place shown, so nobody knows who has won
-- until the last of the three is down; then the places are shown, all
-- together, with the fanfare.
-- A moment on the piles, then the race fades out and the run fades in
-- as it is: the columns in their places on the podium, with the rest
-- (awards, shares, loot, the footer, the bench). A click on the columns
-- skips to the end. About seven seconds.

local Breakdown = ns.Breakdown
local race, footLines, cols, f = Breakdown.race, Breakdown.footLines, Breakdown.cols, Breakdown.f
local scroll, content, Render = Breakdown.scroll, Breakdown.content, Breakdown.Render
local DisplayName, Money = Breakdown.DisplayName, Breakdown.Money
local SCREENSHOT_DELAY = Breakdown.SCREENSHOT_DELAY

-- Seconds: a beat before the first piece, a while on the piles once the
-- places are shown (Coins.lua says when), the race fading out, the run
-- fading in.
local HOLD, PAUSE, OUT, IN = 0.3, 1.5, 0.4, 0.5
-- A racing column is this much taller than its head, for its pile: as
-- much as the window has room for under the heads, within these.
local ROOM_MIN, ROOM_MAX = 150, 260
local token = 0
-- When the race began: with its first frame on screen, nil until then.
-- The window is often opened under a loading screen, where time
-- passes unseen.
local startedAt
local lay            -- what the last draw laid out (see race.Lay)
local detail         -- the alpha the details were last given
local fanfare = false
local tension        -- the sound under the finale, while it plays (its handle, or true)
local tensed = false -- and whether it has played

local driver = CreateFrame("Frame", nil, f)
driver:Hide()
-- Lies over the columns while they race: nothing under it answers the
-- mouse (a tooltip would give the result away), and a click on it ends
-- the race there and then.
local curtain = CreateFrame("Button", nil, content)
curtain.curtain = true
curtain:SetAllPoints()
curtain:SetFrameLevel(content:GetFrameLevel() + 20)
curtain:Hide()

-- Everything a column holds besides who is in it, and the footer.
local function Details(alpha)
    if alpha == detail then return end
    detail = alpha
    for _, c in ipairs(cols) do
        for _, r in ipairs(c.rows) do r:SetAlpha(alpha) end
        c.vendor:SetAlpha(alpha)
        c.share:SetAlpha(alpha)
        c.pill:SetAlpha(alpha)
        c.track:SetAlpha(alpha)
        for _, seg in ipairs(c.segs) do seg:SetAlpha(alpha) end
        if c.awardFrame then c.awardFrame:SetAlpha(alpha) end
        local t = c.tail
        if t then
            t.rule1:SetAlpha(alpha)
            t.rule2:SetAlpha(alpha)
            t.thanks:SetAlpha(alpha)
            for _, b in ipairs(t.bars) do b:SetAlpha(alpha) end
        end
    end
    for _, fs in ipairs(footLines) do fs:SetAlpha(alpha) end
    race.Bench(alpha)
end

local function StopTension()
    if type(tension) == "number" and StopSound then pcall(StopSound, tension, 300) end
    tension = nil
end

-- A total as the column's head writes it (in ink on receipts).
local function Counted(value)
    local was = Breakdown.ink
    Breakdown.ink = lay.paper
    local text = Money(value)
    Breakdown.ink = was
    return text
end

-- Puts the columns where the race has got to.
local function Apply()
    local t = startedAt and (GetTime() - startedAt) or 0
    local plan = lay.plan
    local loot = t - HOLD -- how far into the loot
    local down = HOLD + plan.endAt -- when the places are shown
    local swap = down + PAUSE + OUT -- when the race is gone and the run comes in
    local over = t >= swap
    -- Everything fades: the race out, then the run in.
    content:SetAlpha(over and math.min(1, (t - swap) / IN) or 1 - math.max(0, math.min(1, (t - down - PAUSE) / OUT)))
    -- The loot, the totals so far and the bars, put away with the race.
    if not over then
        ns.Coins.Apply(loot, 1, lay.sound)
    elseif not lay.cleared then
        lay.cleared = true
        ns.Coins.Hide()
    end
    local placed = loot >= plan.endAt
    for i, p in ipairs(lay.players) do
        local c = cols[i]
        -- Its total as it counts up, and its place once the last of the
        -- three is down.
        local value = placed and p.market or plan.live[i]
        if value ~= c.counted then
            c.counted = value
            c.market:SetText(Counted(value))
        end
        c.market:SetAlpha((placed or value > 0) and 1 or 0)
        c.rank:SetAlpha(placed and 1 or 0)
        c.medal:SetAlpha(placed and 1 or 0)
        -- Side by side in name order and as tall as the race needs, then,
        -- once the race is gone, in its place on the podium at its own
        -- height (a receipt torn off at its own length).
        local drop = over and c.offset or 0
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", (over and i - 1 or lay.from[i]) * lay.pitch, -drop)
        if not over then
            c:SetHeight(lay.high)
        elseif lay.paper then
            c:SetHeight(c.ownH)
        else
            c:SetHeight(lay.tall - drop)
        end
        if not lay.paper then c.bg:SetColorTexture(1, 1, 1, lay.tint + (over and p.rank == 1 and 0.04 or 0)) end
    end
    -- Under the finale, a tension sound; with the places, the fanfare.
    if lay.sound and not tensed and #plan.finale > 0 and loot >= plan.mainAt and loot < plan.endAt then
        tensed = true
        tension = ns.Coins.Play("tension") or true
    end
    if tension and loot >= plan.endAt then StopTension() end
    if t >= down and not fanfare then
        fanfare = true
        if lay.sound then ns.Coins.Play("fanfare") end
    end
    Details(over and 1 or 0)
end

-- Called by RenderColumns once it has drawn the columns as they will
-- end up, while a race is on: `players` in column order, `pitch` from
-- one column to the next, `tall` the height the columns share (the
-- longest receipt, on paper), `tint` how bright a column's panel is
-- and `head` how much of a column its head takes.
function race.Lay(players, pitch, tall, paper, tint, head)
    local order = {}
    for i in ipairs(players) do order[i] = i end
    table.sort(order, function(a, b)
        local x, y = DisplayName(players[a].name), DisplayName(players[b].name)
        if x ~= y then return x < y end
        return players[a].name < players[b].name
    end)
    local from, frames = {}, {}
    for slot, i in ipairs(order) do from[i] = slot - 1 end
    for i in ipairs(players) do frames[i] = cols[i] end
    local room = math.max(ROOM_MIN, math.min(ROOM_MAX, math.floor(scroll:GetHeight() - head - 8)))
    lay = { players = players, pitch = pitch, tall = tall, paper = paper, tint = tint, from = from,
            head = head, high = head + room, sound = ns.db.options.ceremonySound,
            plan = ns.Coins.Plan(frames, players, head, room, paper) }
    detail = nil -- the draw may have made new rows
    for _, c in ipairs(cols) do c.counted = nil end -- and written the totals as they end
    Apply()
end

function race.Start()
    token = token + 1
    startedAt, fanfare, tensed = nil, false, false
    StopTension()
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end -- the heads of the columns in sight
    race.on = true
    curtain:Show()
    driver:Show()
end

local function Stop()
    race.on = false
    token = token + 1
    driver:Hide()
    curtain:Hide()
    StopTension()
    content:SetAlpha(1)
    detail = nil
    Details(1)
    for _, c in ipairs(cols) do
        c.market:SetAlpha(1)
        c.rank:SetAlpha(1)
        c.medal:SetAlpha(1)
    end
    ns.Coins.Hide()
end

-- Calls the race off: another run comes on show, or the list, or the
-- window closes. The next draw shows the run as it is.
function race.Cancel()
    if race.on then Stop() end
end

-- The race is over, or was skipped with a click: the run as it is,
-- and the souvenir photo.
local function Finish()
    Stop()
    local mine = token
    Render()
    if ns.db.options.ceremonyScreenshot and Screenshot then
        C_Timer.After(SCREENSHOT_DELAY, function()
            if mine == token and f:IsShown() then Screenshot() end
        end)
    end
end

driver:SetScript("OnUpdate", function()
    if not race.on then return end
    if not lay then return end
    startedAt = startedAt or GetTime()
    if GetTime() - startedAt >= HOLD + lay.plan.endAt + PAUSE + OUT + IN then Finish() else Apply() end
end)
driver:SetScript("OnHide", function() race.Cancel() end)
curtain:SetScript("OnClick", Finish)

function ns.Racing() return race.on end
