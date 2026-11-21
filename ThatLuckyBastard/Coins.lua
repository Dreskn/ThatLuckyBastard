local _, ns = ...

-- The coins of the end-of-run race (see the race in UI.lua). Each player's
-- loot falls into their column as coins, one at a time and all at the
-- same pace, so the smallest stack is done first and the last one still
-- growing has won. A coin falls under gravity, spinning, bounces where it
-- lands and settles on the stack. When the winner has half as much again
-- as the next player or more, their stack fills the room there is and the
-- rest pours over it, faster: coins roll off the top and down its sides
-- into a heap.
--
-- Everything is worked out ahead (Plan), from the players and the room in
-- each column, and drawn for a moment in time (Apply): a redraw in the
-- middle of the race finds every coin where it was. The same players give
-- the same coins. The coin is our own drawing (tools/make_coin.py).

local COIN = "Interface\\AddOns\\ThatLuckyBastard\\Media\\coin"
local COIN_W, COIN_H = 30, 15 -- as it is shown
local STEP = 5                -- from one coin of a stack to the next
local STACK = 20              -- coins in the tallest stack
local SPILL = 36              -- coins at most poured over a winner's stack
local AHEAD = 1.5             -- how far ahead of the next the winner must be for their stack to overflow
local DROP = 0.11             -- seconds between two coins of a stack
local POUR = 0.035            -- seconds between two coins poured over a winner's stack
local G = 1600                -- gravity: pixels a second, a second
local HOP = 6                 -- the highest a coin bounces where it lands
local ROLL = 0.25             -- seconds a poured coin takes to roll down the heap
local SLOT = 10               -- from one place in the heap to the next
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

-- A coin falling from (x0, y0) onto (x1, y1), starting at `ts`: when it
-- lands (tl), and how high and how long it bounces (hop, th). Positions
-- are in the column, from its top left corner, y going down.
local function Fall(coin, rnd)
    local drop = math.max(1, coin.y1 - coin.y0)
    coin.tl = coin.ts + math.sqrt(2 * drop / G)
    local hop = math.min(HOP, drop * 0.08)
    coin.vh = math.sqrt(2 * G * hop)
    coin.th = coin.tl + 2 * coin.vh / G
    coin.spin0, coin.spin = rnd(0, math.pi), rnd(14, 20)
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
    local start, floor = head + 4 + COIN_H / 2, head + room - 6
    for i, p in ipairs(players) do
        local frame = frames[i]
        local cx = frame:GetWidth() / 2
        local n = 0
        if p.market > 0 then n = math.max(1, math.min(STACK, math.floor(p.market / unit + 0.5))) end
        if i == winner and overflow then n = STACK end
        local done = 0
        for k = 0, n - 1 do
            local coin = { col = i, frame = frame, ts = k * DROP, x0 = cx + rnd(-6, 6), y0 = start,
                           x1 = cx + rnd(-1.5, 1.5), y1 = floor - COIN_H / 2 - k * STEP }
            Fall(coin, rnd)
            coins[#coins + 1] = coin
            done = math.max(done, coin.th)
        end
        if i == winner and spill > 0 then
            -- The heap: places either side of the stack, each with its
            -- height in coins. A poured coin rolls on while the next place
            -- is two coins lower, to either side, then lies there.
            local side = math.max(1, math.floor((frame:GetWidth() / 2 - COIN_W / 2 - 2) / SLOT))
            local height = {}
            for s = -side, side do height[s] = 0 end
            height[0] = math.floor(STACK * STEP / LAYER)
            for j = 0, spill - 1 do
                local s, dir = 0, (j % 2 == 0) and 1 or -1
                while true do
                    local moved = false
                    for _, nxt in ipairs({ s + dir, s - dir }) do
                        if height[nxt] and height[nxt] <= height[s] - 2 then
                            s, moved = nxt, true
                            break
                        end
                    end
                    if not moved then break end
                end
                local squash = rnd(0.65, 1) -- lying anyhow: flatter or rounder, as if tilted
                -- Within the column, and never below its foot.
                local x2 = math.max(COIN_W / 2, math.min(2 * cx - COIN_W / 2, cx + s * SLOT + rnd(-3.5, 3.5)))
                local coin = { col = i, frame = frame, spill = true, ts = STACK * DROP + j * POUR, x0 = cx + rnd(-4, 4),
                               y0 = start, x1 = cx, y1 = floor - COIN_H / 2 - STACK * STEP, squash = squash, x2 = x2,
                               y2 = floor - COIN_H * squash / 2 - height[s] * LAYER - rnd(0, 1.5) }
                height[s] = height[s] + 1
                Fall(coin, rnd)
                coin.tr = coin.th + ROLL
                coins[#coins + 1] = coin
                done = math.max(done, coin.tr)
            end
        end
        doneAt[i] = done
        endAt = math.max(endAt, done)
    end

    -- Their textures: each column keeps its own, from one race to the next.
    local used = {}
    for _, coin in ipairs(coins) do
        local frame = coin.frame
        frame.coins = frame.coins or {}
        used[frame] = (used[frame] or 0) + 1
        local tex = frame.coins[used[frame]]
        if not tex then
            tex = frame:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(COIN)
            frame.coins[used[frame]] = tex
        end
        tex:SetDesaturated(paper and true or false)
        if paper then tex:SetVertexColor(0.62, 0.58, 0.52) else tex:SetVertexColor(1, 1, 1) end
        coin.tex = tex
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
-- at `alpha`. With `sound`, a clink as coins land.
function Coins.Apply(t, alpha, sound)
    if not plan then return end
    local landed = false
    for _, coin in ipairs(plan.coins) do
        local tex = coin.tex
        if t < coin.ts then
            tex:Hide()
        else
            local x, y, h
            if t < coin.tl then
                -- Falling, and spinning: seen edge on now and then.
                local u = t - coin.ts
                x = coin.x0 + (coin.x1 - coin.x0) * u / (coin.tl - coin.ts)
                y = coin.y0 + 0.5 * G * u * u
                h = 0.3 + 0.7 * math.abs(math.cos(coin.spin0 + coin.spin * u))
            elseif t < coin.th then
                local u = t - coin.tl
                x, y, h = coin.x1, coin.y1 - (coin.vh * u - 0.5 * G * u * u), 1
            elseif coin.spill and t < coin.tr then
                -- Rolling off the top of the stack and down the heap.
                local u = (t - coin.th) / ROLL
                x = coin.x1 + (coin.x2 - coin.x1) * u
                y = coin.y1 + (coin.y2 - coin.y1) * u * u
                h = 1 + (coin.squash - 1) * u
            else
                x, y, h = coin.x2 or coin.x1, coin.y2 or coin.y1, coin.squash or 1
            end
            if lastT and coin.tl > lastT and coin.tl <= t then landed = true end
            tex:SetSize(COIN_W, COIN_H * h)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", coin.frame, "TOPLEFT", x, -y)
            tex:SetAlpha(alpha)
            tex:Show()
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
    for _, coin in ipairs(plan.coins) do coin.tex:Hide() end
end

-- What the race's coins are doing (for the tests): the last plan.
function Coins.Current()
    return plan
end
