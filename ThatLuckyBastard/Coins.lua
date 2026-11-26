local _, ns = ...

-- The coins of the end-of-run race (see Race.lua). Each player's
-- loot falls into their column as coins, one at a time and all at the
-- same pace, so the smallest stack is done first and the last one still
-- growing has won. When the winner has half as much again as the next
-- player or more, their stack fills the room there is and the rest pours
-- over it, faster: coins roll off the top into a heap around it.
--
-- The coins are seen from above, at the angle that makes a coin lying
-- flat half as tall as it is wide. A coin tumbles as it falls (round
-- when it faces us, a sliver when edge on), comes down nearly flat, gives
-- a little as it hits, bounces lower and lower, skids into place and
-- rocks still. Where a coin lies has a depth too: further back is higher
-- up the column and drawn behind, so a heap has coins behind the stack
-- and in front of it, lying tilted down its slopes.
--
-- Everything is worked out ahead (Plan), from the players and the room in
-- each column, and drawn for a moment in time (Apply): a redraw in the
-- middle of the race finds every coin where it was. The same players give
-- the same coins. The coin is our own drawing (tools/make_coin.py).

local COIN = "Interface\\AddOns\\ThatLuckyBastard\\Media\\coin"
local COIN_W, COIN_H = 30, 15 -- a coin lying flat, as it is shown
local VIEW = math.asin(COIN_H / COIN_W) -- how steeply we look down on the coins
local SIN_VIEW = math.sin(VIEW)
local DEPTH = COIN_H / COIN_W -- a step back on the ground is this much of a step up the column
local EDGE = 0.1              -- a coin seen edge on: this much of its height facing us (3 pixels)
local FACING = 1.6            -- and facing us: at most this much of its flat height (24 pixels)
local STEP = 5                -- from one coin of a stack to the next
local STACK = 20              -- coins in the tallest stack
local SPILL = 36              -- coins at most poured over a winner's stack
local AHEAD = 1.5             -- how far ahead of the next the winner must be for their stack to overflow
local DROP = 0.11             -- seconds between two coins of a stack
local JITTER = 0.25           -- a coin falls up to this much of DROP early or late (a stack's last, never)
local POUR = 0.035            -- seconds between two coins poured over a winner's stack
local G = 1600                -- gravity: pixels a second, a second
local BOUNCE = 0.3            -- how much of its speed a coin keeps as it hits the stack
local RATTLE = 0.45           -- and at each bounce after
local HOP = 6                 -- the highest a coin bounces
local SQUASH, SQUASH_T = 0.1, 0.025 -- how much a coin gives as it hits, and how fast it springs back
local ROCK, ROCK_T = 45, 0.09 -- rocking still: how fast (radians a second), and how fast it dies down
local FADE_IN = 0.08          -- seconds a coin takes to come into sight (less on a short fall)
local ROLL = 0.3              -- seconds a poured coin takes to roll down the heap
local SLOT, ROW = 10, 10      -- from one place in the heap to the next: across, and front to back
local BACK, FRONT = -2, 1     -- rows of the heap behind the stack and in front of it
local LAYER = 4.5             -- from one coin of the heap to the one on it
local CLINK = 0.06            -- seconds at least between two clinks

local Coins = {}
ns.Coins = Coins

local plan             -- what the race's coins do: see Coins.Plan
local lastT, lastClink -- the last moment drawn, and the last clink

-- The same numbers from the same seed, between lo and hi.
local function Random(seed)
    local s = math.floor(seed) % 2147483646 + 1
    return function(lo, hi)
        s = (s * 48271) % 2147483647
        return lo + (hi - lo) * (s / 2147483647)
    end
end

-- How tall a coin is drawn, against its height lying flat, when it is
-- tipped `phi` radians towards us (away, below 0). Facing us it would be
-- round; it is kept a little short of that, or it reads as a bigger coin.
local function Tilt(phi)
    return math.min(FACING, math.max(EDGE, math.abs(math.sin(VIEW + phi))) / SIN_VIEW)
end

-- A coin falling from (x0, y0) onto (xi, y1), starting at `ts`: when it
-- lands (tl), its bounces (hops), when it lies still (still), how it
-- tumbles on the way down and how it lands, a little tipped (phi towards
-- us, psi sideways). Positions are in the column, from its top left
-- corner, y going down.
local function Fall(coin, rnd)
    local drop = math.max(1, coin.y1 - coin.y0)
    coin.tl = coin.ts + math.sqrt(2 * drop / G)
    local v = BOUNCE * math.sqrt(2 * G * drop)
    local peak = math.min(HOP, v * v / (2 * G))
    local hops, at = {}, coin.tl
    while peak >= 0.4 and #hops < 3 do
        local up = math.sqrt(2 * G * peak)
        hops[#hops + 1] = { at = at, len = 2 * up / G, v = up }
        at = at + 2 * up / G
        peak = peak * RATTLE * RATTLE
    end
    coin.hops, coin.still = hops, at
    coin.phi, coin.psi = rnd(-0.25, 0.25), rnd(-0.12, 0.12)
    coin.spin = rnd(11, 17) * (rnd(0, 1) < 0.5 and -1 or 1) -- tumbling, radians a second
    coin.turn = rnd(-2.5, 2.5)                              -- turning sideways as it goes
end

-- How much of its tip is left `u` seconds after a coin landed.
local function Rock(u)
    return math.exp(-u / ROCK_T) * math.cos(ROCK * u)
end

-- Where a coin is drawn `t` seconds into the race: x, y (its middle), how
-- tall against flat, how far turned, and its place in the drawing order.
local function Pose(coin, t)
    local order = coin.spill and coin.top or coin.order
    if t < coin.tl then
        local u = t - coin.ts
        return coin.x0 + (coin.xi - coin.x0) * u / (coin.tl - coin.ts), coin.y0 + 0.5 * G * u * u,
               Tilt(coin.phi + coin.spin * (t - coin.tl)), coin.psi + coin.turn * (t - coin.tl), order
    end
    if coin.spill and t >= coin.tr then
        return coin.x2, coin.y2, coin.hf2, coin.psi2, coin.order
    elseif coin.spill and t >= coin.roll then
        -- Off the top and down the heap, faster and faster, tipping up on
        -- the way, until it lies on the slope.
        local v = (t - coin.roll) / ROLL
        local e, bump = v * v, math.sin(math.pi * v)
        return coin.x1 + (coin.x2 - coin.x1) * e, coin.y1 + (coin.y2 - coin.y1) * e,
               Tilt(coin.phiR + (coin.phi2 - coin.phiR) * e + coin.tumble * bump),
               coin.psiR + (coin.psi2 - coin.psiR) * e + coin.flip * bump,
               v < 0.3 and coin.top or coin.order
    end
    local u = t - coin.tl
    local y = coin.y1
    for _, hop in ipairs(coin.hops) do
        local w = t - hop.at
        if w >= 0 and w < hop.len then y = y - (hop.v * w - 0.5 * G * w * w) end
    end
    local x = t < coin.still and coin.xi + (coin.x1 - coin.xi) * u / (coin.still - coin.tl) or coin.x1
    local rock = Rock(u)
    return x, y,
           Tilt(coin.phi * rock) * (1 - SQUASH * math.exp(-u / SQUASH_T)), coin.psi * rock, order
end

-- Works the race's coins out. `frames` are the columns, `players` their
-- players (each with market and rank), in the same order; `head` is how
-- much of a column its head takes, `room` the room under it for the
-- coins. `paper`: printed in ink, on receipts. Returns, per column, when
-- its coins are all down (doneAt), and when the last of them is (endAt).
function Coins.Plan(frames, players, head, room, paper)
    local top, second, winner = 0, 0, nil
    for i, p in ipairs(players) do
        if p.market > top then top, second, winner = p.market, top, i elseif p.market > second then second = p.market end
    end
    local overflow = top > 0 and top >= second * AHEAD and top > second
    local unit = (overflow and second > 0 and second or top) / STACK
    local spill = 0
    if overflow then spill = second > 0 and math.min(SPILL, math.floor(top / unit - STACK + 0.5)) or SPILL end

    local seed = #players
    for _, p in ipairs(players) do seed = seed + p.market * 7 + p.rank * 131 end
    local rnd = Random(seed)
    local coins, doneAt, endAt = {}, {}, 0
    local start, floor = head + 4 + COIN_H, head + room - 6
    for i, p in ipairs(players) do
        local frame = frames[i]
        local cx = frame:GetWidth() / 2
        local exact = p.market > 0 and p.market / unit or 0
        local n = 0
        if p.market > 0 then n = math.max(1, math.min(STACK, math.floor(exact + 0.5))) end
        if i == winner and overflow then n = STACK end
        local list, done = {}, 0
        for k = 0, n - 1 do
            local ts, z = k * DROP + rnd(-JITTER, JITTER) * DROP, rnd(-1.5, 1.5)
            if k == n - 1 then
                -- The last coin keeps time with the exact total, so that
                -- two close totals are never done together; it lands
                -- straight, the same way for everyone.
                local lo, hi = n == 1 and 0 or n - 0.5, n + 0.5
                if n == 1 then hi = 1.5 end
                ts = k * DROP + math.max(0, math.min(1, (exact - lo) / (hi - lo))) * DROP / 2
                z = 0
            end
            local x1 = cx + rnd(-1.5, 1.5)
            local coin = { col = i, frame = frame, ts = math.max(0, ts), row = 0, h = k * STEP,
                           x0 = cx + rnd(-6, 6), y0 = start, x1 = x1, xi = k == n - 1 and x1 or x1 + rnd(-2, 2),
                           y1 = floor - COIN_H / 2 - k * STEP + z * DEPTH }
            Fall(coin, rnd)
            list[#list + 1] = coin
            done = math.max(done, coin.still)
        end
        if i == winner and spill > 0 then
            -- The heap: places on the ground around the stack, across and
            -- front to back, each with its height in coins. A poured coin
            -- comes off the top in some direction with the speed of its
            -- fall, carrying it a way out (mostly not far), then rolls on
            -- from place to place while one is two coins lower (the
            -- nearest to its way), and lies there.
            local across = math.max(1, math.floor((frame:GetWidth() / 2 - COIN_W / 2 - 2) / SLOT))
            local height = {}
            for gz = BACK, FRONT do
                height[gz] = {}
                for gx = -across, across do height[gz][gx] = 0 end
            end
            height[0][0] = math.floor(STACK * STEP / LAYER)
            local topY = floor - COIN_H / 2 - STACK * STEP
            for j = 0, spill - 1 do
                local way = rnd(0, 2 * math.pi)
                local dx, dz = math.cos(way), math.sin(way)
                local reach = 1 + (across - 1) * rnd(0, 1) ^ 1.5
                local gx = math.max(-across, math.min(across, math.floor(reach * dx + 0.5)))
                local gz = math.max(BACK, math.min(FRONT, math.floor(reach * dz + 0.5)))
                if gx == 0 and gz == 0 then gx = dx < 0 and -1 or 1 end
                while true do
                    local nx, nz, best
                    for ox = -1, 1 do
                        for oz = -1, 1 do
                            local row = height[gz + oz]
                            local h = row and row[gx + ox]
                            if (ox ~= 0 or oz ~= 0) and h and h <= height[gz][gx] - 2 then
                                local along = (ox * dx + oz * dz) / math.sqrt(ox * ox + oz * oz)
                                if not best or along > best then nx, nz, best = gx + ox, gz + oz, along end
                            end
                        end
                    end
                    if not best then break end
                    gx, gz = nx, nz
                end
                local lie = height[gz][gx]
                height[gz][gx] = lie + 1
                -- On other coins it lies tipped down the slope, on the
                -- ground nearly flat.
                local slope = lie > 0 and rnd(0.2, 0.45) or rnd(0, 0.12)
                local len = math.sqrt(gx * gx + gz * gz)
                local sx, sz = 0, 0
                if len > 0 then sx, sz = gx / len, gz / len end
                local z2 = gz * ROW + rnd(-2, 2)
                local phi2 = slope * sz
                local x1 = cx + rnd(-2, 2)
                local coin = { col = i, frame = frame, spill = true, ts = STACK * DROP + j * POUR,
                               row = gz, h = lie * LAYER, x0 = cx + rnd(-4, 4), y0 = start, x1 = x1, xi = x1,
                               y1 = topY, phi2 = phi2, psi2 = -slope * sx, hf2 = Tilt(phi2),
                               x2 = math.max(COIN_W / 2, math.min(2 * cx - COIN_W / 2, cx + gx * SLOT + rnd(-3, 3))) }
                coin.y2 = floor - lie * LAYER + z2 * DEPTH - COIN_H * coin.hf2 / 2 - rnd(0, 1.5)
                Fall(coin, rnd)
                -- It rolls off after its first bounce, tumbling a little.
                local first = coin.hops[1]
                coin.roll = first and first.at + first.len or coin.tl
                coin.tr = coin.roll + ROLL
                coin.phiR = coin.phi * Rock(coin.roll - coin.tl)
                coin.psiR = coin.psi * Rock(coin.roll - coin.tl)
                coin.tumble = rnd(0.3, 0.8)
                coin.flip = rnd(0.4, 1) * (rnd(0, 1) < 0.5 and -1 or 1)
                list[#list + 1] = coin
                done = math.max(done, coin.tr)
            end
        end
        -- Which is drawn over which: further back first, then lower first.
        -- A poured coin is over everything while it is on the stack.
        local sorted = {}
        for k, coin in ipairs(list) do
            coin.n = k
            sorted[k] = coin
        end
        table.sort(sorted, function(a, b)
            if a.row ~= b.row then return a.row < b.row end
            if a.h ~= b.h then return a.h < b.h end
            return a.n < b.n
        end)
        for k, coin in ipairs(sorted) do coin.order, coin.top = k, #list + 1 end
        for _, coin in ipairs(list) do coins[#coins + 1] = coin end
        doneAt[i] = done
        endAt = math.max(endAt, done)
    end

    -- Their frames: each column keeps its own, from one race to the next.
    local used = {}
    for _, coin in ipairs(coins) do
        local frame = coin.frame
        frame.coins = frame.coins or {}
        used[frame] = (used[frame] or 0) + 1
        local box = frame.coins[used[frame]]
        if not box then
            box = CreateFrame("Frame", nil, frame)
            box.tex = box:CreateTexture(nil, "ARTWORK")
            box.tex:SetAllPoints()
            box.tex:SetTexture(COIN)
            frame.coins[used[frame]] = box
        end
        box.tex:SetDesaturated(paper and true or false)
        if paper then box.tex:SetVertexColor(0.62, 0.58, 0.52) else box.tex:SetVertexColor(1, 1, 1) end
        coin.box, coin.tex = box, box.tex
    end
    for _, frame in ipairs(frames) do
        for k = (used[frame] or 0) + 1, #(frame.coins or {}) do frame.coins[k]:Hide() end
    end
    if plan and plan.frames ~= frames then Coins.Hide() end
    plan = { coins = coins, frames = frames, doneAt = doneAt, endAt = endAt, overflow = overflow, spill = spill }
    lastT, lastClink = nil, nil
    return plan
end

-- Draws the coins as they are `t` seconds into the race (before it, none),
-- at `alpha`. With `sound`, a clink as coins land. Each coin keeps what it
-- was drawn as (x, y, h, rot, level), for the tests.
function Coins.Apply(t, alpha, sound)
    if not plan then return end
    local landed = false
    for _, coin in ipairs(plan.coins) do
        local box = coin.box
        if t < coin.ts then
            box:Hide()
        else
            local x, y, tall, rot, order = Pose(coin, t)
            if lastT and coin.tl > lastT and coin.tl <= t then landed = true end
            coin.x, coin.y, coin.h = x, y, COIN_H * tall
            box:SetSize(COIN_W, coin.h)
            box:ClearAllPoints()
            box:SetPoint("CENTER", coin.frame, "TOPLEFT", x, -y)
            box:SetAlpha(alpha * math.min(1, (t - coin.ts) / math.min(FADE_IN, 0.3 * (coin.tl - coin.ts))))
            if rot ~= coin.rot then
                coin.rot = rot
                coin.tex:SetRotation(rot)
            end
            if order ~= coin.level then
                coin.level = order
                box:SetFrameLevel(coin.frame:GetFrameLevel() + order)
            end
            box:Show()
        end
    end
    if landed and sound and (not lastClink or t - lastClink >= CLINK) then
        lastClink = t
        ns.PlayKit("LOOT_WINDOW_COIN_SOUND", 120)
    end
    lastT = t
end

-- Puts every coin away.
function Coins.Hide()
    if not plan then return end
    for _, coin in ipairs(plan.coins) do coin.box:Hide() end
end

-- What the race's coins are doing (for the tests): the last plan.
function Coins.Current()
    return plan
end
