local _, ns = ...

-- The meter: a small window that follows the loot the way a damage meter
-- follows damage. One row per player, sorted by loot: the rank, a bar in
-- the class colour as long as the player's loot is next to the leader's,
-- the name, the total and the share; once the run is over, the award
-- beside the name. It shows the run in progress, else the run on show in
-- the main window (the latest while that is shut), and keeps up with the
-- loot as it comes in: bars glide to their new length, and rows slide
-- past one another when someone overtakes.
--
-- It stays open while you play (Escape leaves it alone), can be moved and
-- sized, or locked with the padlock in its corner, and is where it was,
-- as big as it was, locked and open if it was, from one session to the
-- next (db.meter). Its height is always whole rows; rows that do not fit
-- are a turn of the mouse wheel away. The options say whether a row shows
-- the rank, the share and the award, and whether the meter opens by
-- itself as a run starts and shuts as you leave (see ns.MeterAuto). Its
-- title bar is slimmer than the other windows', and names the dungeon the
-- way players do: RFC, SFK, ZF.

local WIDTH = 270
local BAR_H = 22      -- the title bar, in the Modern and Receipt themes
local ROW_H, ROW_GAP = 20, 2
local PITCH = ROW_H + ROW_GAP
local PAD = 4         -- around the rows, the same on every side
local CORNER = 12     -- the grip that sizes the window, and the padlock beside it
local LOCK = "Interface\\AddOns\\ThatLuckyBastard\\Media\\lock" -- locked on the left half, open on the right
local ROWS = 5        -- how many it is tall enough for, to begin with
local SPEED = 8       -- how quickly bars and rows close in on where they are going, per second
local CHECK = 1       -- seconds between two looks at which run to show
local BAR = "Interface\\TargetingFrame\\UI-StatusBar" -- the game's own bar, for the Classic theme

local frame, ui, title, skins = ns.MakeWindow("ThatLuckyBastardMeterFrame", WIDTH, 100, "MEDIUM", false, nil, BAR_H)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, -120)
frame:SetResizable(true)
frame.meterTitle = title

-- The rows sit on a frame inside a scroll frame, which shows the part of
-- them that fits.
local scroll = CreateFrame("ScrollFrame", nil, ui)
local rowsFrame = CreateFrame("Frame", nil, scroll)
scroll:SetScrollChild(rowsFrame)
scroll:EnableMouseWheel(true)

local emptyText = ui:CreateFontString(nil, "OVERLAY", "GameFontDisable")

local rowsByName, spare = {}, {} -- the rows on show, by player; and the ones put aside
local shownRun, shownLive        -- the run the rows are for, and whether it was going on
local top = -(BAR_H + 2)         -- where the rows start under the title bar (the theme's)
local offset = 0                 -- rows scrolled past
local moving = false             -- bars or rows still on their way
local sizing = false             -- the grip held: the height follows the mouse until let go
local Draw

-- How tall the window is for `n` rows, and how many rows fit it.
local function Height(n)
    return -top + PAD + n * PITCH - ROW_GAP + PAD
end
local function Visible()
    return math.max(1, math.floor((frame:GetHeight() + top - 2 * PAD + ROW_GAP) / PITCH))
end
local function Count()
    local n = 0
    for _ in pairs(rowsByName) do n = n + 1 end
    return n
end

-- The run to show: the one in progress, else the main window's.
local function MeterRun()
    return ns.db.active or ns.ViewedRun()
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function RowTip(self)
    local p = self.p
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ClassColored(ns.DisplayName(p.name), p.class))
    GameTooltip:AddLine(ns.Money(p.market) .. (self.pct ~= "" and ("   " .. self.pct .. " of the loot") or ""), 1, 1, 1)
    if self.won then
        GameTooltip:AddLine(self.won.title, 1, 0.82, 0)
        if self.won.how then GameTooltip:AddLine(self.won.how, 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:AddLine("Click to open this run.", 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function NewRow()
    local r = table.remove(spare)
    if r then return r end
    r = CreateFrame("Button", nil, rowsFrame)
    r.meterRow = true
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    local function Text(justify)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        return fs
    end
    r.rank = Text("RIGHT")
    r.rank:SetPoint("LEFT", 2, 0)
    r.rank:SetWidth(14)
    r.share = Text("RIGHT")
    r.share:SetPoint("RIGHT", -4, 0)
    r.share:SetWidth(30)
    r.value = Text("RIGHT")
    r.value:SetPoint("RIGHT", r.share, "LEFT", -4, 0)
    r.label = Text("LEFT")
    r.label:SetPoint("LEFT", 22, 0)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r:SetScript("OnEnter", RowTip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function() if shownRun then ns.ShowRun(shownRun) end end)
    return r
end

local function Release(name)
    local r = rowsByName[name]
    rowsByName[name] = nil
    r:Hide()
    r.p, r.won = nil, nil
    spare[#spare + 1] = r
end

-- Gives a row the theme's look: Modern a flat bar in the class colour,
-- Classic the game's own bar texture in it, Receipt a strip of paper with
-- the bar printed in light ink and the text in ink.
local function Paint(r, theme, o)
    local p = r.p
    -- What the options leave out, the others close up on.
    r.rank:SetShown(o.meterRank and true or false)
    r.share:SetShown(o.meterShare and true or false)
    r.value:ClearAllPoints()
    if o.meterShare then r.value:SetPoint("RIGHT", r.share, "LEFT", -4, 0) else r.value:SetPoint("RIGHT", -4, 0) end
    r.label:ClearAllPoints()
    r.label:SetPoint("LEFT", o.meterRank and 22 or 6, 0)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    local cr, cg, cb = c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.6
    local paper = theme == "receipt"
    if theme == "classic" then
        r.bar:SetTexture(BAR)
        r.bar:SetVertexColor(cr, cg, cb, 0.9)
        r.bg:SetColorTexture(0, 0, 0, 0.35)
    elseif paper then
        r.bar:SetColorTexture(ns.INK[1], ns.INK[2], ns.INK[3], 0.16)
        r.bar:SetVertexColor(1, 1, 1, 1)
        r.bg:SetColorTexture(ns.PAPER[1], ns.PAPER[2], ns.PAPER[3], 1)
    else
        r.bar:SetColorTexture(cr, cg, cb, 0.6)
        r.bar:SetVertexColor(1, 1, 1, 1)
        r.bg:SetColorTexture(1, 1, 1, 0.04)
    end
    local font = paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall"
    local strong = paper and ns.INK or { 1, 1, 1 }
    local soft = paper and ns.INK_GREY or { 0.7, 0.7, 0.7 }
    for _, fs in ipairs({ r.rank, r.label, r.value, r.share }) do fs:SetFontObject(font) end
    r.label:SetTextColor(strong[1], strong[2], strong[3])
    r.value:SetTextColor(strong[1], strong[2], strong[3])
    r.rank:SetTextColor(soft[1], soft[2], soft[3])
    r.share:SetTextColor(soft[1], soft[2], soft[3])
end

-- Moves bars and rows `dt` seconds' worth closer to where they are going.
-- Returns whether any is still on its way.
local function Animate(dt)
    local k = math.min(1, dt * SPEED)
    local width = frame:GetWidth() - 2 * PAD
    local still = true
    for _, r in pairs(rowsByName) do
        r.y = r.y + (r.ty - r.y) * k
        if math.abs(r.ty - r.y) < 0.5 then r.y = r.ty else still = false end
        r.w = r.w + (r.tw - r.w) * k
        if math.abs(r.tw - r.w) < 0.002 then r.w = r.tw else still = false end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -r.y)
        r.bar:SetWidth(math.max(1, width * r.w))
        r.bar:SetShown(r.w > 0.002)
    end
    return not still
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Scroll()
    offset = math.max(0, math.min(offset, Count() - Visible()))
    scroll:SetVerticalScroll(offset * PITCH)
end

function Draw()
    local flat, t = ns.ApplyWindowTheme(skins, title)
    top = t
    local theme = ns.ThemeName()
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", PAD, top - PAD)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    if frame.SetResizeBounds then frame:SetResizeBounds(180, Height(1), 600, 900) end
    -- Whole rows, so the space under the last is the same as at the sides:
    -- a height in between (sized by hand, or another theme's title bar)
    -- goes to the nearest whole number of rows.
    if not sizing then
        local n = math.max(1, math.floor((frame:GetHeight() + top - 2 * PAD + ROW_GAP) / PITCH + 0.5))
        if math.abs(frame:GetHeight() - Height(n)) >= 0.5 then frame:SetHeight(Height(n)) end
    end
    if frame.corner then frame.corner.Paint(theme) end
    local width = frame:GetWidth() - 2 * PAD
    title:SetWidth(math.max(20, frame:GetWidth() - (flat and 36 or 54))) -- cut short before the cross
    title:SetWordWrap(false)
    title:SetJustifyH(flat and "LEFT" or "CENTER") -- at the start of the slim bar; in the middle of Classic's

    local s = MeterRun()
    if s ~= shownRun then
        -- Another run: its rows start afresh, their bars from nothing.
        for name in pairs(rowsByName) do Release(name) end
        shownRun, offset = s, 0
    end
    shownLive = s ~= nil and ns.InProgress(s)
    emptyText:ClearAllPoints()
    emptyText:SetPoint("TOP", 0, top - 16)
    emptyText:SetShown(s == nil)
    if not s then
        title:SetText(("|T%s:14:14:0:0|t Meter"):format(ns.LOGO))
        emptyText:SetText("No run yet.")
        return
    end

    local sum = ns.Summarize(s)
    local awards = ns.RunAwards(s, sum)
    local tag = ""
    if shownLive then
        local a = ns.ThemeAccent()
        tag = ("  |cff%02x%02x%02xlive|r"):format(a[1] * 255 + 0.5, a[2] * 255 + 0.5, a[3] * 255 + 0.5)
    end
    title:SetText(("|T%s:14:14:0:0|t %s%s"):format(ns.LOGO, ns.ShortName(s), tag))

    -- Everyone, the most loot first, whatever order the main window has.
    local list = {}
    for _, p in ipairs(sum.players) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    local lead = list[1] and list[1].market or 0
    local o = ns.db.options
    local paper = theme == "receipt"
    local stamp = paper and ("|cff%02x%02x%02x"):format(ns.RECEIPT_ACCENT[1] * 255 + 0.5,
        ns.RECEIPT_ACCENT[2] * 255 + 0.5, ns.RECEIPT_ACCENT[3] * 255 + 0.5) or "|cffffd100"
    local keep = {}
    for i, p in ipairs(list) do
        local r = rowsByName[p.name]
        if not r then
            r = NewRow()
            rowsByName[p.name] = r
            r.y, r.w = (i - 1) * PITCH, 0 -- a new row starts in its place, its bar empty
        end
        keep[p.name] = true
        r.p, r.won = p, awards[p.name]
        r.ty = (i - 1) * PITCH
        r.tw = lead > 0 and p.market / lead or 0
        r.pct = sum.market > 0 and (math.floor(p.market / sum.market * 100 + 0.5) .. "%") or ""
        Paint(r, theme, o)
        local name = ns.DisplayName(p.name)
        if paper then name = name:upper() end
        name = ns.BetMark(s, p.name) .. name -- a star beside your call
        r.rank:SetText(i)
        r.label:SetText(name .. ((r.won and o.meterAward) and ("  " .. stamp .. r.won.title .. "|r") or ""))
        r.value:SetText(ns.MoneyPlain(p.market))
        r.share:SetText(r.pct)
        r:SetWidth(width)
        r:Show()
    end
    for name in pairs(rowsByName) do
        if not keep[name] then Release(name) end
    end
    rowsFrame:SetSize(width, math.max(1, #list * PITCH))
    Scroll()
    Animate(0)
    moving = true
end

----------------------------------------------------------------------
-- Keeping up
----------------------------------------------------------------------

-- Bars and rows on their way, and a look every second at which run to
-- show: one starts, ends, or another comes on show in the main window.
local clock = CreateFrame("Frame", nil, frame)
clock.meterClock = true
local since = 0
clock:SetScript("OnUpdate", function(_, dt)
    frame.corner.Follow()
    if moving then moving = Animate(dt) end
    since = since + dt
    if since >= CHECK then
        since = 0
        local s = MeterRun()
        if s ~= shownRun or (s ~= nil and ns.InProgress(s) ~= shownLive) then Draw() end
    end
end)

-- Loot comes in bursts: the meter is drawn once a burst is in. Called
-- with the main window's own refresh (see ns.Refresh).
local pending = false
function ns.MeterRefresh()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if frame:IsShown() then Draw() end
    end)
end
local function Redraw()
    if frame:IsShown() then Draw() end
end
ns.OnRerender(Redraw)
ns.OnRunShown(Redraw)
ns.OnAccent(Redraw)
frame:SetScript("OnShow", function()
    frame.corner.Show(false) -- until the mouse comes over it
    Draw()
end)
frame:SetScript("OnSizeChanged", function() ns.MeterRefresh() end)

scroll:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta
    Scroll()
end)

----------------------------------------------------------------------
-- Opening, moving, sizing, and remembering it all
----------------------------------------------------------------------

local function Save()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    local m = ns.db.meter or {}
    m.point, m.relPoint, m.x, m.y = point, relPoint, x, y
    m.w, m.h = frame:GetWidth(), frame:GetHeight()
    ns.db.meter = m
end
-- Locked, it stays where it is and as big as it is (db.meter.locked).
local function Locked() return ns.db and ns.db.meter and ns.db.meter.locked == true end
frame:SetScript("OnDragStart", function(self)
    if not Locked() then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Save()
end)

-- The corner: the grip that sizes the window and, beside it, the padlock.
-- Both sit over the last row, so they show only while the mouse is over
-- the meter (or the grip is held); locked, the grip stays away.
do
    local corner = {}
    frame.corner = corner
    local level = ui:GetFrameLevel() + 10 -- above the rows
    local grip = CreateFrame("Button", nil, ui)
    grip.meterGrip = true
    grip:SetSize(CORNER, CORNER)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(level)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if Locked() then return end
        sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        sizing = false
        Draw() -- to whole rows
        Save()
    end)

    local lock = CreateFrame("Button", nil, ui)
    lock.meterLock = true
    lock:SetSize(CORNER + 2, CORNER + 2)
    lock:SetPoint("RIGHT", grip, "LEFT", -1, 0)
    lock:SetFrameLevel(level)
    lock.icon = lock:CreateTexture(nil, "OVERLAY")
    lock.icon:SetTexture(LOCK)
    lock.icon:SetSize(CORNER, CORNER)
    lock.icon:SetPoint("CENTER")
    lock.icon:SetAlpha(0.75)
    local function Tip(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Locked() and "Unlock" or "Lock")
        GameTooltip:AddLine(Locked() and "Its place and size are locked." or "Keeps its place and size.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
    lock:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        Tip(self)
    end)
    lock:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.75)
        GameTooltip:Hide()
    end)

    local shown = false -- the corner on show
    function corner.Show(on)
        shown = on
        local locked = Locked()
        lock:SetShown(on)
        grip:SetShown(on and not locked)
        lock.icon:SetTexCoord(locked and 0 or 0.5, locked and 0.5 or 1, 0, 1)
    end
    -- Ink on the Receipt's paper, white on the others.
    function corner.Paint(theme)
        local ink = theme == "receipt" and ns.INK or { 1, 1, 1 }
        lock.icon:SetVertexColor(ink[1], ink[2], ink[3], 1)
    end
    -- At every frame (the clock): shown while the mouse is over the meter.
    function corner.Follow()
        local over = sizing or frame:IsMouseOver()
        if over ~= shown then corner.Show(over) end
    end
    lock:SetScript("OnClick", function(self)
        ns.db.meter = ns.db.meter or {}
        ns.db.meter.locked = not Locked() or nil
        corner.Show(true)
        Tip(self)
    end)
    corner.Show(false)
end

function ns.ToggleMeter()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        frame:Raise()
    end
end

-- What the options ask of the meter as a run starts (or you go back in),
-- and as you leave: opened, shut, or left as it is.
function ns.MeterAuto(moment)
    local o = ns.db.options
    if moment == "start" and o.meterOpen then
        frame:Show()
    elseif moment == "leave" and o.meterClose then
        frame:Hide()
    end
end

-- At login the meter is put back where it was, as big as it was, and
-- opened if it was open; at logout, whether it is open is noted.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGOUT" then
        ns.db.meter = ns.db.meter or {}
        ns.db.meter.shown = frame:IsShown() or nil
        return
    end
    local m = ns.db.meter or {}
    if m.point then
        frame:ClearAllPoints()
        frame:SetPoint(m.point, UIParent, m.relPoint or m.point, m.x or 0, m.y or 0)
    end
    local _, t = ns.ApplyWindowTheme(skins, title)
    top = t
    if m.w and m.h then frame:SetSize(m.w, m.h) else frame:SetHeight(Height(ROWS)) end
    if m.shown then frame:Show() end
end)
