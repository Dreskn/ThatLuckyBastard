local _, ns = ...

-- The race: how a run is revealed when it is left (each time it is),
-- with one column per player in podium order. The columns start side by
-- side in name order, showing who is in them and nothing else, each as
-- tall as its head and the room for its coins. Each player's loot falls
-- into their column as coins, all at the same pace (Coins.lua), and when
-- a player's last coin is down, their total is shown with their place.
-- So the smallest stack is done first and takes the last place, and the
-- one still growing at the end has won; a winner far ahead overflows.
-- Then the columns walk to their places on the podium, taking their own
-- height, and the rest (awards, shares, loot, the footer, the bench)
-- fades in. A click on the columns skips to the end. About five seconds.

local Breakdown = ns.Breakdown
local race, footLines, cols, f = Breakdown.race, Breakdown.footLines, Breakdown.cols, Breakdown.f
local scroll, content, Render = Breakdown.scroll, Breakdown.content, Breakdown.Render
local DisplayName, PlayKit = Breakdown.DisplayName, Breakdown.PlayKit
local SCREENSHOT_DELAY = Breakdown.SCREENSHOT_DELAY

-- Seconds: a beat before the coins, a beat on the result once they are
-- down (Coins.lua says when), the walk to the podium, the rest fading in.
local HOLD, PAUSE, WALK, FADE = 0.3, 0.3, 0.6, 0.4
local ROOM = 150 -- a racing column is this much taller than its head, for its coins
local token = 0
-- When the race began: with its first frame on screen, nil until then.
-- The window is often opened under a loading screen, where time
-- passes unseen.
local startedAt
local lay            -- what the last draw laid out (see race.Lay)
local detail         -- the alpha the details were last given
local fanfare = false

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

-- Puts the columns where the race has got to.
local function Apply()
    local t = startedAt and (GetTime() - startedAt) or 0
    local coins = t - HOLD -- how far into the coins
    local down = HOLD + lay.plan.endAt -- when the last coin is
    local walk = math.max(0, math.min(1, (t - down - PAUSE) / WALK))
    walk = walk * walk * (3 - 2 * walk) -- sets off and arrives gently
    local fade = math.max(0, math.min(1, (t - down - PAUSE - WALK) / FADE))
    for i, p in ipairs(lay.players) do
        local c = cols[i]
        local done = coins >= lay.plan.doneAt[i]
        -- Its total and its place, once its last coin is down.
        c.market:SetAlpha(done and 1 or 0)
        c.rank:SetAlpha(done and 1 or 0)
        c.medal:SetAlpha(done and 1 or 0)
        local slot = lay.from[i] + (i - 1 - lay.from[i]) * walk
        local drop = c.offset * walk
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", slot * lay.pitch, -drop)
        -- As tall as the race needs while the coins fall, taking its
        -- own height on the way to its place.
        local height
        if lay.paper then
            -- Receipts are torn off once they are in place.
            height = walk < 1 and lay.high or c.ownH
        else
            height = lay.high + (lay.tall - lay.high) * walk - drop
            c.bg:SetColorTexture(1, 1, 1, lay.tint + (p.rank == 1 and 0.04 * fade or 0))
        end
        c:SetHeight(height)
    end
    -- The coins go as the columns walk.
    ns.Coins.Apply(coins, 1 - walk, lay.sound)
    if t >= down and not fanfare then
        fanfare = true
        if lay.sound then PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
    end
    Details(fade)
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
    lay = { players = players, pitch = pitch, tall = tall, paper = paper, tint = tint, from = from,
            head = head, high = head + ROOM, sound = ns.db.options.ceremonySound,
            plan = ns.Coins.Plan(frames, players, head, ROOM, paper) }
    detail = nil -- the draw may have made new rows
    Apply()
end

function race.Start()
    token = token + 1
    startedAt, fanfare = nil, false
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
    if GetTime() - startedAt >= HOLD + lay.plan.endAt + PAUSE + WALK + FADE then Finish() else Apply() end
end)
driver:SetScript("OnHide", function() race.Cancel() end)
curtain:SetScript("OnClick", Finish)

function ns.Racing() return race.on end
