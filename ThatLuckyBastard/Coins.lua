local _, ns = ...

-- What falls in the end-of-run race (see Race.lua): each player's actual
-- loot, item by item and copy by copy (20 cloth fall as 20 icons), each as
-- big as its worth (its area follows its value), and their gold as coins.
--
-- The order of the race: first everything but the run's three most
-- valuable items, into every column over the same time, cheapest first.
-- The coins tell nobody apart (everyone near a corpse gets the same share),
-- so they are the filler: about as many for everyone, falling steadily all
-- through, so no column looks empty. Then the finale: the three fall one by
-- one into their owners' columns, the third most valuable first, a beat
-- apart, each named as it lands. All along, a column's total counts up as
-- its pieces land, and a faint bar behind its pile rises with it, as a
-- share of the richest final total; nobody knows who has won until the
-- last of the three is down. Then the totals are final, and Race.lua shows
-- the places.
--
-- The view is from above, at the angle that makes a coin lying flat half
-- as tall as it is wide. A coin tumbles as it falls, comes down nearly
-- flat, gives a little, bounces lower and lower, skids into place and
-- rocks still. An item turns as it falls; a heavy one turns slower, bounces
-- less and lies straighter. Each piece lands on whatever is highest under
-- it, and is drawn over what landed before it.
--
-- Everything is worked out ahead (Plan), from the players and the room in
-- each column, and drawn for a moment in time (Apply): a redraw in the
-- middle of the race finds every piece where it was. The same players give
-- the same race. The coin is our own drawing (tools/make_coin.py).

local COIN = "Interface\\AddOns\\ThatLuckyBastard\\Media\\coin"
local COIN_W, COIN_H = 30, 15 -- a coin lying flat, as it is shown
local VIEW = math.asin(COIN_H / COIN_W) -- how steeply we look down
local SIN_VIEW = math.sin(VIEW)
local EDGE = 0.1              -- a coin seen edge on: this much of its height facing us (3 pixels)
local FACING = 1.6            -- and facing us: at most this much of its flat height (24 pixels)
local COIN_STEP = 5           -- a coin's thickness on the pile
local COIN_FILL = 8           -- coins for a player with the group's usual gold
local MAX_COINS = 14
local FILL = 0.42             -- the richest pile covers this much of a column 150 pixels deep
local SIZED = 150             -- (sizes do not change with the room the window gives)
local ROLL = 0.5              -- pixels of height a piece gives up for each pixel it rolls aside
local SPOTS = 9               -- places across a column a piece may roll to
local ICON_MIN, ICON_MAX = 10, 96 -- an item's side, in pixels (cheap copies down to 10)
local COPIES = 30             -- copies of one item shown at most
local SHOW = 80               -- pieces of loot shown per column at most, the most valuable
local LEAD = 0.45             -- seconds before the first landing: room for a whole fall
local SPAN = 1.6              -- seconds from then to the end of the first drop
local STAGGER = 0.1           -- a column's first drop ends up to this long before that
local ITEM_POW = 0.5          -- a column's items follow their share of its item value to this power
local COIN_END = 0.12         -- its last coin lands this long before its last item
local JITTER = 0.03           -- seconds a coin may land early or late
local GAP = 0.012             -- seconds at least between two landings in a column
local FINALE = 3              -- the run's most valuable items, held back for the finale
local FINALE_IN = 0.55        -- seconds from the end of the first drop to the first of them landing
local FINALE_GAP = 0.75       -- and from one of them to the next
local FINALE_OUT = 0.35       -- and from the last of them to the places
local NOTE = 1.1              -- seconds the name of one of them stays up
local RISE = 0.25             -- seconds a total and its bar take to take a piece in
local BAR, BAR_INK = 0.1, 0.07 -- how faint the bars are (in colour, and in ink on receipts)
local G = 1600                -- gravity: pixels a second, a second
local BOUNCE = 0.3            -- how much of its speed a piece keeps as it lands
local RATTLE = 0.45           -- and at each bounce after
local HOP = 6                 -- the highest a piece bounces
local SQUASH, SQUASH_T = 0.1, 0.025 -- how much a coin gives as it hits, and how fast it springs back
local ROCK, ROCK_T = 45, 0.09 -- rocking still: how fast (radians a second), and how fast it dies down
local FADE_IN = 0.08          -- seconds a piece takes to come into sight (less on a short fall)
local THUD_GAP = 0.06          -- seconds at least from one thud to the next
local CLINK_GAP = 0.1          -- and from any sound to a clink (coins never drown the items)
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 0.9, 0.9, 0.9 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 },
                  { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }
local INK = { 0.36, 0.33, 0.3 } -- the Receipt theme's border

local Coins = {}
ns.Coins = Coins

-- The race's sounds, by what they are for: one of the game's own, by name,
-- with an id that plays where that name is missing (today's sounds, so a
-- client without the name still has one).
Coins.SOUNDS = {
    clink = { "LOOT_WINDOW_COIN_SOUND", 120 },  -- a coin lands
    thud = { "IG_BACKPACK_CLOSE", 120 },        -- an item lands
    finale = { "UI_EPICLOOT_TOAST", 120 },      -- one of the three most valuable lands
    tension = { "UI_BONUS_LOOT_ROLL_LOOP" },    -- under the finale, until the places
    fanfare = { "LFG_REWARDS", 878 },           -- the places
}

local plan             -- what falls in the race: see Coins.Plan
local lastT                -- the last moment drawn
local lastSound, lastThud  -- the last sound of a landing, and the last thud

-- Plays one of the race's sounds; returns its handle, to stop it with.
function Coins.Play(what)
    local s = Coins.SOUNDS[what]
    local kit = s and ((SOUNDKIT and SOUNDKIT[s[1]]) or s[2])
    if not kit then return end
    local ok, _, handle = pcall(PlaySound, kit, "SFX")
    return ok and handle or nil
end

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

-- How much of its tip is left `u` seconds after a piece landed.
local function Rock(u)
    return math.exp(-u / ROCK_T) * math.cos(ROCK * u)
end

-- How much of a piece its column's total has taken in, `u` seconds after
-- it landed: quickly at first, all of it after RISE.
local function Rise(u)
    if u >= RISE then return 1 end
    local left = 1 - u / RISE
    return 1 - left * left
end

-- A piece's bounces after it lands at `tl` from a fall of `drop` pixels,
-- keeping `keep` of its speed: its hops, and when it lies still.
local function Bounces(piece, drop, keep)
    local v = keep * math.sqrt(2 * G * drop)
    local peak = math.min(HOP, v * v / (2 * G))
    local hops, at = {}, piece.tl
    while peak >= 0.4 and #hops < 3 do
        local up = math.sqrt(2 * G * peak)
        hops[#hops + 1] = { at = at, len = 2 * up / G, v = up }
        at = at + 2 * up / G
        peak = peak * RATTLE * RATTLE
    end
    piece.hops, piece.still = hops, at
end

-- Where a piece is drawn `t` seconds into the race: x, y (its middle, from
-- its column's top left, y going down), width, height, how far turned.
local function Pose(p, t)
    if t < p.tl then
        local u = t - p.ts
        local x, y = p.x0 + (p.xi - p.x0) * u / (p.tl - p.ts), p.y0 + 0.5 * G * u * u
        if p.coin then
            return x, y, COIN_W, COIN_H * Tilt(p.phi + p.spin * (t - p.tl)), p.psi + p.turn * (t - p.tl)
        end
        return x, y, p.side, p.side, p.rest + p.wob + p.spin * (t - p.tl)
    end
    local u = t - p.tl
    local y = p.y1
    for _, hop in ipairs(p.hops) do
        local w = t - hop.at
        if w >= 0 and w < hop.len then y = y - (hop.v * w - 0.5 * G * w * w) end
    end
    local x = t < p.still and p.xi + (p.x1 - p.xi) * u / (p.still - p.tl) or p.x1
    local rock = Rock(u)
    if p.coin then
        return x, y, COIN_W, COIN_H * Tilt(p.phi * rock) * (1 - SQUASH * math.exp(-u / SQUASH_T)), p.psi * rock
    end
    return x, y, p.side, p.side, p.rest + p.wob * rock
end

-- A column's pieces, not timed yet: its shown items, most valuable first (a
-- piece for every copy, at its share of the value), its coins, and the
-- value of the copies it does not show. `k` is square pixels per copper.
local function Pieces(p, k, moneyAvg)
    local items, hidden = {}, 0
    for _, e in ipairs(p.held or {}) do
        local v = ns.EntryMarket(e)
        if v > 0 then
            local copies = math.max(1, ns.CountedCopies(e))
            local shown = math.min(copies, COPIES)
            for _ = 1, shown do items[#items + 1] = { v = v / copies, e = e } end
            hidden = hidden + v / copies * (copies - shown) -- more copies than a column shows
        end
    end
    table.sort(items, function(a, b) return a.v > b.v end)
    local list = {}
    for n, it in ipairs(items) do
        if n <= SHOW then
            local e = it.e
            list[#list + 1] = { v = it.v, e = e, link = e.link, name = e.link:match("%[(.-)%]") or "",
                                q = e.quality or tonumber(e.link:match("|cnIQ(%d+):")) or 1,
                                side = math.max(ICON_MIN, math.min(ICON_MAX, math.sqrt(it.v * k))) }
        else
            hidden = hidden + it.v -- not shown, but counted
        end
    end
    local coins, money = {}, p.money or 0
    if money > 0 and moneyAvg > 0 then
        local n = math.max(1, math.min(MAX_COINS, math.floor(COIN_FILL * money / moneyAvg + 0.5)))
        for j = 1, n do coins[j] = { v = money / n, coin = true } end
    end
    return list, coins, hidden
end

-- When a column's first drop lands, ending at `done`: its items cheapest
-- first, each as its share of the column's item value comes in (the copies
-- it does not show counted first), its coins evenly all through, a little
-- out of step, the last before its last item. In the order they land.
local function Time(items, coins, hidden, done, rnd)
    table.sort(items, function(a, b)
        if a.v ~= b.v then return a.v < b.v end
        return a.link < b.link
    end)
    local worth = hidden
    for _, piece in ipairs(items) do worth = worth + piece.v end
    local list, cum = {}, hidden
    for _, piece in ipairs(items) do
        cum = cum + piece.v
        piece.tl = LEAD + (done - LEAD) * (cum / worth) ^ ITEM_POW
        list[#list + 1] = piece
    end
    local n, shown = #coins, #items > 0
    local last = shown and done - COIN_END or done
    for j, coin in ipairs(coins) do
        local tl = LEAD + (last - LEAD) * (j - (shown and 0.5 or 0)) / n
        if j < n or shown then tl = math.max(LEAD, tl + rnd(-JITTER, JITTER)) end
        coin.tl = tl
        list[#list + 1] = coin
    end
    table.sort(list, function(a, b) return a.tl < b.tl end)
    -- A little time between two landings (less in a crowded column), the
    -- last one still at `done`.
    local gap = math.min(GAP, (done - LEAD) / (#list + 1))
    for m = 2, #list - 1 do list[m].tl = math.max(list[m].tl, list[m - 1].tl + gap) end
    for m = #list - 1, 1, -1 do list[m].tl = math.min(list[m].tl, list[m + 1].tl - gap) end
    return list
end

-- Where a piece `fw` pixels wide comes to rest on the pile `sky` (its
-- height at each pixel across a column `width` wide): let go somewhere
-- across, more often near the middle, it rolls into the lowest place
-- within reach, the lower and the nearer the better. What holds it up is
-- the highest point under its middle; its edges may sink into what is
-- around. Returns where (x) and how high it lies (base).
local function Settle(sky, width, fw, rnd)
    local lo, hi = fw / 2 + 2, width - fw / 2 - 2
    if hi < lo then lo, hi = width / 2, width / 2 end
    local aim = lo + (hi - lo) * (rnd(0, 1) + rnd(0, 1)) / 2
    local bestX, bestBase, bestScore = aim, 0, nil
    for k = 0, SPOTS do
        local x = k == SPOTS and aim or lo + (hi - lo) * k / (SPOTS - 1)
        local base = 0
        for px = math.max(0, math.floor(x - fw * 0.3)), math.min(math.ceil(width), math.ceil(x + fw * 0.3)) do
            base = math.max(base, sky[px])
        end
        local score = base + math.abs(x - aim) * ROLL
        if not bestScore or score < bestScore then bestX, bestBase, bestScore = x, base, score end
    end
    return bestX, bestBase
end

-- A worth as the head of a column writes it (in ink on receipts).
local function Worth(v, paper)
    local Breakdown = ns.Breakdown
    local was = Breakdown.ink
    Breakdown.ink = paper
    local text = ns.Money(v)
    Breakdown.ink = was
    return text
end

-- A column's bar and the name of a finale item, made the first time.
local function Extras(frame)
    if frame.raceBar then return end
    frame.raceBar = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    frame.raceLine = frame:CreateTexture(nil, "BACKGROUND", nil, 3) -- the bar's top edge
    local note = CreateFrame("Frame", nil, frame)
    note.name = note:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note.name:SetPoint("TOPLEFT")
    note.name:SetPoint("TOPRIGHT")
    note.name:SetJustifyH("CENTER")
    note.name:SetWordWrap(false)
    note.worth = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note.worth:SetPoint("TOP", note.name, "BOTTOM", 0, -2)
    note:Hide()
    frame.raceNote = note
end

-- Works the race out. `frames` are the columns, `players` their players
-- (summaries: market, money, held, rank, class), in the same order; `head`
-- is how much of a column its head takes, `room` the room under it for the
-- pile. `paper`: printed in ink, on receipts. Returns the plan: the pieces,
-- the finale's in the order they land, and when (in seconds) the first
-- drop ends (mainAt), each column's last piece lands (doneAt) and the
-- places are shown (endAt); each column's final total (final) and, as
-- Apply draws it, its total so far (live).
function Coins.Plan(frames, players, head, room, paper)
    local top, moneyAll, moneyN = 0, 0, 0
    for _, p in ipairs(players) do
        top = math.max(top, p.market)
        if (p.money or 0) > 0 then moneyAll, moneyN = moneyAll + p.money, moneyN + 1 end
    end
    local moneyAvg = moneyN > 0 and moneyAll / moneyN or 0
    local seed = #players
    for _, p in ipairs(players) do seed = seed + p.market * 7 + p.rank * 131 end
    local rnd = Random(seed)
    local main = LEAD + SPAN

    -- Each column's pieces, and the run's most valuable items (one copy
    -- of an item at most) for the finale.
    local columns, best = {}, {}
    for i, p in ipairs(players) do
        local col = { items = {}, coins = {}, hidden = 0 }
        if top > 0 and p.market > 0 then
            col.items, col.coins, col.hidden = Pieces(p, FILL * frames[i]:GetWidth() * SIZED / top, moneyAvg)
        end
        for _, piece in ipairs(col.items) do
            piece.col = i
            best[#best + 1] = piece
        end
        columns[i] = col
    end
    table.sort(best, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        if a.link ~= b.link then return a.link < b.link end
        return a.col < b.col
    end)
    local finale, held = {}, {}
    for _, piece in ipairs(best) do
        if #finale == FINALE then break end
        if not held[piece.e] then
            held[piece.e] = true
            finale[#finale + 1] = piece
        end
    end
    -- They land the least valuable of them first, the most valuable last.
    for k = 1, #finale do
        local piece = finale[#finale - k + 1]
        piece.finale = #finale - k + 1 -- 1: the most valuable
        piece.tl = main + FINALE_IN + (k - 1) * FINALE_GAP
    end
    table.sort(finale, function(a, b) return a.tl < b.tl end)
    local endAt = #finale > 0 and finale[#finale].tl + FINALE_OUT or main + FINALE_OUT

    local pieces, doneAt, final, live = {}, {}, {}, {}
    local start, floor = head + 4, head + room - 6
    for i, p in ipairs(players) do
        local frame, col = frames[i], columns[i]
        local width = frame:GetWidth()
        -- The first drop: all but the finale's, ending about together.
        local items, kept = {}, 0
        for _, piece in ipairs(col.items) do
            if not piece.finale then
                items[#items + 1] = piece
                kept = kept + piece.v
            end
        end
        local done = main - STAGGER * rnd(0, 1)
        local list = #items + #col.coins > 0 and Time(items, col.coins, col.hidden, done, rnd) or {}
        -- What each piece adds to the total as it lands: its worth, with the
        -- copies not shown spread over the first drop's items (or its coins,
        -- or the finale's), so the total ends at the player's.
        local all = 0
        for _, piece in ipairs(list) do
            piece.add = piece.v
            all = all + piece.v
        end
        for _, piece in ipairs(finale) do
            if piece.col == i then
                list[#list + 1] = piece
                piece.add = piece.v
                all = all + piece.v
            end
        end
        if col.hidden > 0 and all > 0 then
            local over, base = {}, 0
            for _, piece in ipairs(list) do
                if not piece.coin and not piece.finale then over[#over + 1] = piece end
            end
            if #over == 0 then
                for _, piece in ipairs(list) do
                    if not piece.finale then over[#over + 1] = piece end
                end
            end
            if #over == 0 then over = list end
            for _, piece in ipairs(over) do base = base + piece.v end
            for _, piece in ipairs(over) do piece.add = piece.add + col.hidden * piece.v / base end
            all = all + col.hidden
        end
        if all > 0 then
            for _, piece in ipairs(list) do piece.add = piece.add * p.market / all end
        end

        local sky = {} -- the pile's height at each pixel across
        for x = 0, math.ceil(width) do sky[x] = 0 end
        for n, piece in ipairs(list) do
            piece.col, piece.frame, piece.level = i, frame, n
            -- In the lowest place within reach (never past the room).
            local fw = piece.coin and COIN_W or piece.side
            local fh = piece.coin and COIN_STEP or piece.side
            local tall = piece.coin and COIN_H or piece.side
            local x1, base = Settle(sky, width, fw, rnd)
            base = math.min(base, room - 10 - tall)
            for x = math.max(0, math.floor(x1 - fw / 2 + 2)), math.min(math.ceil(width), math.ceil(x1 + fw / 2 - 2)) do
                sky[x] = base + fh
            end
            piece.x1, piece.y1 = x1, floor - base - tall / 2
            piece.y0, piece.x0 = start + tall / 2, x1 + rnd(-8, 8)
            piece.xi = n == #list and x1 or x1 + rnd(-2, 2)
            local drop = math.max(1, piece.y1 - piece.y0)
            piece.ts = math.max(0, piece.tl - math.sqrt(2 * drop / G))
            if piece.coin then
                Bounces(piece, drop, BOUNCE)
                piece.phi, piece.psi = rnd(-0.25, 0.25), rnd(-0.12, 0.12)
                piece.spin = rnd(11, 17) * (rnd(0, 1) < 0.5 and -1 or 1) -- tumbling, radians a second
                piece.turn = rnd(-2.5, 2.5)                              -- turning sideways as it goes
            else
                -- Heavier items bounce less, turn slower and lie straighter.
                local heavy = (piece.side - ICON_MIN) / (ICON_MAX - ICON_MIN)
                Bounces(piece, drop, BOUNCE * (1 - 0.85 * heavy))
                piece.rest = rnd(-0.14, 0.14) * (1 - 0.7 * heavy)
                piece.wob = rnd(-0.12, 0.12) * (1 - heavy)
                piece.spin = rnd(-1, 1) * (4 - 3 * heavy)
            end
            pieces[#pieces + 1] = piece
        end
        doneAt[i] = #list > 0 and list[#list].tl or 0
        final[i], live[i] = p.market, 0

        -- The column's bar, in its player's colour (in ink on receipts),
        -- and the name of a finale item, over its pile.
        Extras(frame)
        local r, g, b = ns.Breakdown.ClassRGB(p.class)
        if paper then r, g, b = INK[1], INK[2], INK[3] end
        local faint = paper and BAR_INK or BAR
        frame.raceBar:SetColorTexture(r, g, b, faint)
        frame.raceLine:SetColorTexture(r, g, b, faint * 2.5)
        frame.raceBar:Hide()
        frame.raceLine:Hide()
        local note = frame.raceNote
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(head + 6))
        note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(head + 6))
        note:SetHeight(28)
        note:SetFrameLevel(frame:GetFrameLevel() + #list + 2) -- over the pile
        note.name:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontNormalSmall")
        note.worth:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
        note.piece = nil
        note:Hide()
    end

    -- Their frames: each column keeps its own, from one race to the next.
    local used = {}
    for _, piece in ipairs(pieces) do
        local frame = piece.frame
        frame.coins = frame.coins or {}
        used[frame] = (used[frame] or 0) + 1
        local box = frame.coins[used[frame]]
        if not box then
            box = CreateFrame("Frame", nil, frame)
            box.edge = box:CreateTexture(nil, "BACKGROUND")
            box.edge:SetPoint("TOPLEFT", -1.5, 1.5)
            box.edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
            box.tex = box:CreateTexture(nil, "ARTWORK")
            box.tex:SetAllPoints()
            frame.coins[used[frame]] = box
        end
        if piece.coin then
            box.tex:SetTexture(COIN)
            box.tex:SetTexCoord(0, 1, 0, 1)
            box.edge:Hide()
        else
            box.tex:SetTexture(ns.ItemIcon(piece.link))
            box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local c = paper and INK or QUALITY[piece.q] or QUALITY[1]
            box.edge:SetColorTexture(c[1], c[2], c[3], 1)
            box.edge:Show()
        end
        box.tex:SetDesaturated(paper and true or false)
        if paper then box.tex:SetVertexColor(0.62, 0.58, 0.52) else box.tex:SetVertexColor(1, 1, 1) end
        piece.box, piece.tex = box, box.tex
    end
    for _, frame in ipairs(frames) do
        for k = (used[frame] or 0) + 1, #(frame.coins or {}) do frame.coins[k]:Hide() end
    end
    if plan and plan.frames ~= frames then Coins.Hide() end
    plan = { pieces = pieces, finale = finale, frames = frames, mainAt = main, doneAt = doneAt, endAt = endAt,
             final = final, live = live, top = top, room = room, floor = floor, reach = floor - start,
             paper = paper }
    lastT, lastSound, lastThud = nil, nil, nil
    return plan
end

-- A column's bar, as high as its total so far against the richest final
-- total, at `alpha`.
local function DrawBar(i, frame, alpha)
    local bar, line = frame.raceBar, frame.raceLine
    local h = plan.top > 0 and plan.reach * plan.live[i] / plan.top or 0
    if h < 0.5 or alpha <= 0 then
        bar:Hide()
        line:Hide()
        return
    end
    local w = frame:GetWidth() - 12
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", frame, "TOPLEFT", frame:GetWidth() / 2, -plan.floor)
    bar:SetSize(w, h)
    bar:SetAlpha(alpha)
    bar:Show()
    line:ClearAllPoints()
    line:SetPoint("BOTTOM", bar, "TOP")
    line:SetSize(w, 1)
    line:SetAlpha(alpha)
    line:Show()
end

-- The name and worth of the finale item that last landed in column `i`,
-- for a moment after it lands, at `alpha`.
local function DrawNote(i, frame, t, alpha)
    local note, shown = frame.raceNote, nil
    for _, p in ipairs(plan.finale) do
        if p.col == i and t >= p.tl and t < p.tl + NOTE then shown = p end
    end
    if not shown or alpha <= 0 then
        note:Hide()
        return
    end
    if note.piece ~= shown then
        note.piece = shown
        local c = plan.paper and INK or QUALITY[shown.q] or QUALITY[1]
        note.name:SetText(shown.name)
        note.name:SetTextColor(c[1], c[2], c[3])
        note.worth:SetText(Worth(shown.v, plan.paper))
    end
    note:SetAlpha(alpha * math.min(1, (t - shown.tl) / 0.1) * math.min(1, (shown.tl + NOTE - t) / 0.3))
    note:Show()
end

-- Draws the race as it is `t` seconds in (before it, nothing), at `alpha`:
-- the pieces, each column's total so far (`plan.live`) and its bar, and
-- the finale's names. With `sound`, landings are heard: of what landed
-- since the last frame, the heaviest (one of the finale's above all), a
-- thud for an item, a clink for a coin, never two too close together and
-- the coins giving way to the items. Each
-- piece keeps what it was drawn as (x, y, w, h, rot, drawn: its drawing
-- level), for the tests.
function Coins.Apply(t, alpha, sound)
    if not plan then return end
    if lastT and t < lastT then lastSound, lastThud = nil, nil end -- drawn back in time: nothing heard yet
    local live, heard = plan.live, nil
    for i in ipairs(plan.frames) do live[i] = 0 end
    for _, p in ipairs(plan.pieces) do
        local box = p.box
        if t < p.ts then
            box:Hide()
        else
            local x, y, w, h, rot = Pose(p, t)
            p.x, p.y, p.w, p.h = x, y, w, h
            box:SetSize(w, h)
            box:ClearAllPoints()
            box:SetPoint("CENTER", p.frame, "TOPLEFT", x, -y)
            box:SetAlpha(alpha * math.min(1, (t - p.ts) / math.min(FADE_IN, 0.3 * (p.tl - p.ts) + 0.001)))
            if rot ~= p.rot then
                p.rot = rot
                p.tex:SetRotation(rot)
                if not p.coin then box.edge:SetRotation(rot) end
            end
            if p.level ~= p.drawn then
                p.drawn = p.level
                box:SetFrameLevel(p.frame:GetFrameLevel() + p.level)
            end
            box:Show()
            if t >= p.tl then live[p.col] = live[p.col] + p.add * Rise(t - p.tl) end
            if lastT and p.tl > lastT and p.tl <= t then
                local weight = p.finale and 1e9 + p.v or p.coin and 0 or p.side
                if not heard or weight > heard.weight then heard = { piece = p, weight = weight } end
            end
        end
    end
    for i, frame in ipairs(plan.frames) do
        if t >= plan.doneAt[i] + RISE then live[i] = plan.final[i] end -- exactly, once all is in
        DrawBar(i, frame, alpha)
        DrawNote(i, frame, t, alpha)
    end
    if heard and sound then
        local p = heard.piece
        local since = lastSound and t - lastSound or math.huge
        if p.finale then
            lastSound = t
            Coins.Play("finale")
        elseif p.coin then
            if since >= CLINK_GAP then
                lastSound = t
                Coins.Play("clink")
            end
        elseif not lastThud or t - lastThud >= THUD_GAP then
            lastSound, lastThud = t, t
            Coins.Play("thud")
        end
    end
    lastT = t
end

-- Puts every piece away, with the bars and the names.
function Coins.Hide()
    if not plan then return end
    for _, p in ipairs(plan.pieces) do p.box:Hide() end
    for _, frame in ipairs(plan.frames) do
        if frame.raceBar then
            frame.raceBar:Hide()
            frame.raceLine:Hide()
            frame.raceNote:Hide()
        end
    end
end

-- What the race is doing (for the tests): the last plan.
function Coins.Current()
    return plan
end
