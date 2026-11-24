local _, ns = ...

local issecret = issecretvalue or function() return false end

local WIDTH, HEIGHT = 780, 540
local MAX_COLUMNS = 5     -- groups up to this size get one column per player
local MINI_W = 150        -- the mini window is at least this wide, for its title bar
local COL_GAP = 6
local ACCENT = ns.ACCENT

----------------------------------------------------------------------
-- The Receipt theme's materials: paper, inks, the counter the receipts
-- lie on, till keys, and a typewriter font shipped in Media/ (Courier
-- Prime, under the SIL Open Font License: Media/CourierPrime-OFL.txt).
----------------------------------------------------------------------

local PAPER = { 0.953, 0.937, 0.894 }
local INK = { 0.165, 0.153, 0.141 }
local INK_GREY = { 0.431, 0.404, 0.361 }
local COUNTER = { 0.169, 0.149, 0.133 }
local KEY, KEY_EDGE = { 0.910, 0.882, 0.816 }, { 0.663, 0.624, 0.533 }
local RED_KEY, RED_KEY_EDGE = { 0.784, 0.267, 0.180 }, { 0.557, 0.176, 0.114 }
local STAMP_RED, STAMP_BLUE = { 0.698, 0.227, 0.165 }, { 0.169, 0.298, 0.608 }
ns.RECEIPT_ACCENT = { 0.878, 0.380, 0.290 } -- red ink, where Modern has its teal
local INK_CODE, INK_GREY_CODE = "|cff2a2724", "|cff6e675c"
-- Item qualities as inks that read on paper, by quality number.
local QUALITY_INK = {
    [0] = "|cff6e675c", [1] = "|cff2a2724", [2] = "|cff2f7a1f", [3] = "|cff1d4e9e",
    [4] = "|cff6a2c9e", [5] = "|cffa0520a", [6] = "|cff8a6d1f", [7] = "|cff1d6f8a",
}
-- Awards stamped in red; the others in blue.
local RED_STAMPS = { ninja = true, lionshare = true, empty = true, snakeeyes = true, colddice = true, window = true,
                     heartbreak = true, dryspell = true, nemesis = true, overkill = true, booby = true,
                     afk = true, dkp = true, classclown = true }

local MEDIA = "Interface\\AddOns\\ThatLuckyBastard\\Media\\"
local function ReceiptFont(name, file, size, color)
    if not CreateFont then return end
    local font = CreateFont(name)
    font:SetFont(MEDIA .. file, size, "")
    font:SetTextColor(color[1], color[2], color[3])
end
ReceiptFont("ThatLuckyBastardReceiptInk", "CourierPrime-Regular.ttf", 12, INK)
ReceiptFont("ThatLuckyBastardReceiptInkBold", "CourierPrime-Bold.ttf", 12, INK)
ReceiptFont("ThatLuckyBastardReceiptGrey", "CourierPrime-Regular.ttf", 12, INK_GREY)
ReceiptFont("ThatLuckyBastardReceiptSmall", "CourierPrime-Regular.ttf", 10, INK_GREY)
ReceiptFont("ThatLuckyBastardReceiptTotal", "CourierPrime-Bold.ttf", 19, INK)
ReceiptFont("ThatLuckyBastardReceiptKey", "CourierPrime-Bold.ttf", 11, { 0.165, 0.149, 0.133 })
ReceiptFont("ThatLuckyBastardReceiptKeyLight", "CourierPrime-Bold.ttf", 11, { 1.000, 0.957, 0.925 })
ReceiptFont("ThatLuckyBastardReceiptTitle", "CourierPrime-Bold.ttf", 15, { 0.929, 0.902, 0.839 })
ReceiptFont("ThatLuckyBastardReceiptTitleSmall", "CourierPrime-Bold.ttf", 12, { 0.929, 0.902, 0.839 })
ReceiptFont("ThatLuckyBastardReceiptCounter", "CourierPrime-Regular.ttf", 12, { 0.812, 0.776, 0.702 })

local THEMES = {
    -- toolbarY: top of the button row under the title. scrollTop leaves
    -- room for that row and for the list view's column headers.
    classic = { rowH = 14, font = "GameFontHighlightSmall", toolbarY = -28, scrollTop = -78, scrollRight = -32 },
    modern  = { rowH = 20, font = "GameFontHighlight",      toolbarY = -44, scrollTop = -92, scrollRight = -14,
                flat = true },
    -- Flat like Modern, on a dark counter, with each player's loot printed
    -- on paper (`paper`) and till keys for buttons.
    receipt = { rowH = 16, font = "ThatLuckyBastardReceiptInk", toolbarY = -44, scrollTop = -96, scrollRight = -14,
                flat = true, paper = true },
}

-- The theme in force: the saved one, or Modern if that is not a theme.
local function ThemeName()
    return THEMES[ns.db.theme] and ns.db.theme or "modern"
end
ns.ThemeName = ThemeName

-- The accent of the theme in force: Modern's teal, the Receipt's red ink.
function ns.ThemeAccent()
    return ThemeName() == "receipt" and ns.RECEIPT_ACCENT or ACCENT
end

-- What the main window's files share: this one, Receipt, Footer, Bench,
-- Columns and Race (they load after it, in that order). This file puts on
-- it, at its end, what the others use; they put back what it calls. Its
-- fields here are the drawing state more than one of them changes.
local Breakdown = {
    -- True while the window draws on paper (the Receipt theme): money,
    -- names and items are then written in dark inks rather than the game's
    -- bright colours. Only ever on during a redraw, so tooltips keep their
    -- colours.
    ink = false,
    -- The reveal of a run as it is left: due at the next draw (`pending`),
    -- the run being revealed, the GetTime() at which it is over, and a
    -- token raised when one starts or is called off, so its timers can tell.
    reveal = { pending = false, run = nil, ends = 0, token = 0 },
    race = { on = false }, -- the columns' race for their places (Race.lua)
    footLines = {},        -- font strings used by the column view, under it
    theme = nil,           -- the theme in force, as ApplyTheme set it
}
ns.Breakdown = Breakdown
local reveal, race, footLines = Breakdown.reveal, Breakdown.race, Breakdown.footLines

local CATS = {
    -- First: not items, one sum per player with nothing under it.
    { key = "coins",    label = "Coins",                         short = "Coins",       color = { 0.90, 0.72, 0.36 },
      coins = true },
    { key = "epic",     label = "Epic BoE",                      short = "Epic BoE",    color = { 0.64, 0.21, 0.93 } },
    { key = "rare",     label = "Blue BoE",                      short = "Blue BoE",    color = { 0.20, 0.55, 1.00 } },
    { key = "uncommon", label = "Green BoE",                     short = "Green BoE",   color = { 0.12, 1.00, 0.00 } },
    { key = "bop",      label = "Bind on Pickup (vendor value)", short = "BoP",         color = { 1.00, 0.50, 0.00 },
      name = "Bind on Pickup" }, -- name: what the options call it, when not by its label
    { key = "prof",     label = "Profession materials",          short = "Professions", color = { 1.00, 0.82, 0.00 } },
    { key = "other",    label = "Other",                         short = "Other",       color = { 0.85, 0.85, 0.85 } },
    { key = "junk",     label = "Junk",                          short = "Junk",        color = { 0.62, 0.62, 0.62 } },
    -- Always last: quest items are worth nothing to anyone else.
    { key = "quest",    label = "Quest items (vendor value)",    short = "Quest",       color = { 1.00, 1.00, 0.45 },
      name = "Quest items" },
}
for _, cat in ipairs(CATS) do
    if cat.coins then CATS.coins = cat end
end
local cols = {}

-- Podium mode: gold, silver, bronze, then grey.
local MEDALS = { { 1.00, 0.82, 0.00 }, { 0.78, 0.78, 0.82 }, { 0.80, 0.50, 0.20 }, { 0.50, 0.50, 0.50 } }

local expanded = {}   -- [playerName] = true
-- Runs shown as a list although the options ask for columns: switched
-- with the List button on their bench (see RenderBench). For this session
-- only, and the options are left alone.
local listRuns = setmetatable({}, { __mode = "k" })
local viewIndex = 1   -- 1 = current / most recent run
local rows = {}
local buttons = {}
local headers = {}
local pending = false
local theme, currentTheme
local currentRun      -- the run being displayed
local Render

-- The run on show, for the window's other files.
function Breakdown.CurrentRun() return currentRun end

-- Colour codes used all over the window.
local GREY, DIM = "|cff909090", "|cff8a8a8a" -- secondary text; subtotals
local GOOD, BAD = "|cff40d040", "|cffe05050" -- above / below

-- Appends one unit to a money text: zero-padded when it follows a larger
-- unit ("3g 05s"), in `color` if given.
local function AddUnit(text, value, color, suffix)
    local part = text and ("%02d"):format(value) or tostring(value)
    if color then part = color .. part .. "|r" end
    return (text and (text .. " ") or "") .. part .. suffix
end

-- Formats copper as gold / silver / copper, honouring the "show silver"
-- and "show copper" options. A unit that is switched off is still shown
-- when it is the largest one in the amount, so nothing reads as zero; and
-- copper is only shown next to silver, never straight after gold.
local function MoneyText(c, colored)
    c = math.floor((c or 0) + 0.5)
    if c <= 0 then return "-" end
    local o = ns.db.options
    local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local text
    if g > 0 then
        local gs = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
        text = (colored and ("|cffffd700" .. gs .. "|r") or gs) .. "g"
    end
    if (g > 0 and o.showSilver) or (g == 0 and s > 0) then
        text = AddUnit(text, s, colored and "|cffc7c7cf", "s")
    end
    if not text or (o.showCopper and (g == 0 or o.showSilver)) then
        text = AddUnit(text, k, colored and "|cffeda55f", "c")
    end
    return text
end

-- Gold, silver and copper in their colours; on paper, in plain ink.
local function Money(c)
    local text = MoneyText(c, not Breakdown.ink)
    if text == "-" then return (Breakdown.ink and INK_GREY_CODE or GREY) .. "-|r" end
    return text
end

-- Subtotals are shown in flat grey so they do not read as item values.
local function Grey(text)
    return (Breakdown.ink and INK_GREY_CODE or DIM) .. text .. "|r"
end

local function MoneyGrey(c)
    return Grey(MoneyText(c, false))
end

local function CatColored(text, cat)
    if Breakdown.ink then return text:upper() end -- a receipt's heading
    local c = cat.color
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local function ClassRGB(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return ACCENT[1], ACCENT[2], ACCENT[3]
end

local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local function ItemIcon(link)
    return (GetItemIconByID and GetItemIconByID(link)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- An item's link as written on paper: the game's bright quality colour
-- swapped for a darker ink of the same quality. Still a working link.
local function InkLink(e)
    local link = e.link or ""
    local part = link:match("(|H.-|h.-|h)")
    if not part then return link end
    return (QUALITY_INK[ns.Quality(e)] or INK_CODE) .. part .. "|r"
end

-- What an item row says: "3x [Item]", or on paper "3 [Item]" in ink.
local function ItemLabel(e, count)
    if Breakdown.ink then return (count > 1 and (count .. " ") or "") .. InkLink(e) end
    return (count > 1 and (count .. "x ") or "") .. e.link
end

----------------------------------------------------------------------
-- Price markers: a small dot next to an item's value.
--   "ah"   (blue)   the value is an auction price
--   "noah" (orange) the item could be auctioned but no price is known,
--                   so the vendor price was used
--   "off"  (grey)   an auction price is known but the vendor price is
--                   used: the default for junk, or the player's choice
--                   for anything else (right-click switches)
-- Items that are never priced at auction (bound and quest items), junk
-- with no auction price, and everything in vendor-only mode get no marker.
----------------------------------------------------------------------

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MARK_COLORS = { ah = { 0.35, 0.70, 1.00 }, noah = { 1.00, 0.55, 0.15 }, off = { 0.55, 0.55, 0.55 } }
local LEGEND = "|cff59b3ffBlue dot|r: auction price    "
    .. "|cffff8c26Orange|r: no auction price, vendor used    "
    .. "|cff8c8c8cGrey|r: auction price not used (right-click)"
local LEGEND_INK = "|cff1d5fc4Blue dot|r: auction price    "
    .. "|cffb05a10Orange|r: no auction price, vendor used    "
    .. "|cff6e675cGrey|r: auction price not used (right-click)"

local function PriceMark(e)
    if ns.db.options.valueMode == "vendor" then return end
    if e.ah then return e.noAH and "off" or "ah" end
    if ns.CanAuction(e) and not ns.VendorByDefault(e) and ns.HasPriceSource() then return "noah" end
end

-- `dominant`: this one item is more than half of the run's value.
local function PriceNote(e, mark, dominant)
    local note
    if mark == "ah" then
        note = (e.now and "Auction price today: " or "Auction price: ") .. Money(e.now or e.ah) .. " each."
    elseif mark == "off" then
        note = "Auction price (" .. Money(e.ah) .. " each) not used."
    elseif mark == "noah" then
        note = "No auction price known: vendor price used."
    end
    if note and dominant then
        note = note .. "\n|cffff8c26More than half of the run's value on its own.|r"
    end
    return note
end

-- Tooltip line saying how an item was won, if it was rolled for.
local function RollNote(e)
    local need, greed = e.need or 0, e.greed or 0
    if need > 0 and greed > 0 then
        return ("Won on rolls: %d Need, %d Greed"):format(need, greed)
    elseif need > 0 then
        return need > 1 and ("Won on Need rolls (%d)"):format(need) or "Won on a Need roll"
    elseif greed > 0 then
        return greed > 1 and ("Won on Greed rolls (%d)"):format(greed) or "Won on a Greed roll"
    end
end

-- True when an auction-priced item alone outweighs the rest of the run:
-- the case where one bad price decides the result.
local function IsDominant(mark, market, total)
    return mark == "ah" and total > 0 and market > total / 2
end

-- Row background: a faint white band (a faint grey one on paper), or
-- orange for a dominant item.
local function SetRowBg(tex, line)
    if line.warn then
        tex:SetColorTexture(1, 0.55, 0.15, 0.20)
    elseif Breakdown.ink then
        tex:SetColorTexture(INK[1], INK[2], INK[3], (line.bg or 0) * 0.5)
    else
        tex:SetColorTexture(1, 1, 1, line.bg or 0)
    end
end

local function SetMark(tex, mark)
    local c = mark and MARK_COLORS[mark]
    if c then
        tex:SetVertexColor(c[1], c[2], c[3])
        tex:Show()
    else
        tex:Hide()
    end
end

-- Over / under an equal split, as coloured text. On paper, the way a till
-- prints it: "+28g 65s" over, "10g 88s-" under.
local function DiffText(diff)
    if math.abs(diff) < 1 then return "" end
    if Breakdown.ink then
        return diff > 0 and ("+" .. Money(diff)) or (Money(-diff) .. "-")
    end
    return (diff > 0 and (GOOD .. "+|r") or (BAD .. "-|r")) .. Money(math.abs(diff))
end

-- Above / below, as colour codes: brighter ones on the dark windows,
-- darker inks on paper.
local function GoodCode() return Breakdown.ink and "|cff2f7a1f" or GOOD end
local function BadCode() return Breakdown.ink and "|cffb23a2a" or BAD end
-- Headings and secondary text in the footer, likewise.
local function HeadCode() return Breakdown.ink and INK_CODE or "|cffffd100" end
local function LowCode() return Breakdown.ink and INK_GREY_CODE or "|cff909090" end

-- Answers that cannot change while the window is being drawn are worked
-- out once per redraw and kept here: who is in the group, and how names
-- are shown. Empty outside a redraw, so other windows always get fresh
-- answers.
local drawing, drawCache = false, {}

-- "+1.6" in green, "-0.8" in red, "0.0" plain.
local function Signed(v)
    if math.abs(v) < 0.05 then return "0.0" end
    return ("%s%+.1f|r"):format(v > 0 and GOOD or BAD, v)
end

-- Whether the game is set to show second names (Options > Nameplates >
-- My Secondary Name). Assumed on when the client cannot tell us.
local function GameShowsSurname()
    if drawCache.surname ~= nil then return drawCache.surname end
    local shown = true
    local fn = C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname
    if fn then
        local ok, value = pcall(fn)
        if ok and value ~= nil and not issecret(value) then shown = value and true or false end
    end
    if drawing then drawCache.surname = shown end
    return shown
end

-- The name to show for a player. Names are stored in full ("First Second"
-- or "First-Second"); the nameStyle option decides whether the second
-- name is displayed.
local function FirstName(name)
    return name:match("^([^%s%-]+)") or name
end

local function DisplayName(name)
    local style = ns.db.options.nameStyle
    if style == "full" or (style ~= "first" and GameShowsSurname()) then return name end
    return FirstName(name)
end

-- A name in its class colour. On paper, class colours (yellow, pink) do
-- not read: the name is printed in ink, in capitals.
local function ClassColored(name, class)
    if Breakdown.ink then return INK_CODE .. name:upper() .. "|r" end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

-- Every run the window can show: yours and those shared with you, newest
-- first by when they started, then the example runs. Your run in
-- progress stays first whatever the other player's clock said.
local function Runs()
    local shared = ns.SharedByDate()
    local runs, j = {}, 1
    for _, s in ipairs(ns.AllRuns()) do
        while shared[j] and not ns.InProgress(s) and (shared[j].startedAt or 0) > (s.startedAt or 0) do
            runs[#runs + 1] = shared[j]
            j = j + 1
        end
        runs[#runs + 1] = s
    end
    for k = j, #shared do runs[#runs + 1] = shared[k] end
    for _, s in ipairs(ns.exampleRuns) do runs[#runs + 1] = s end
    return runs
end

-- Runs recorded by early versions, and the example runs, know you by your
-- first name only.
local function IsMe(name)
    return name == ns.playerName or name == UnitName("player")
end

----------------------------------------------------------------------
-- Base frame. The look comes from one of two "skin" child frames;
-- everything interactive lives on `ui`, which sits above the skins.
----------------------------------------------------------------------

local f = CreateFrame("Frame", "ThatLuckyBastardFrame", UIParent)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetFrameStrata("HIGH") -- shared with the run windows and statistics (see ns.MakeWindow)
f:SetToplevel(true)
f:SetMovable(true)
f:SetResizable(true)
if f.SetResizeBounds then
    f:SetResizeBounds(620, 320, 1100, 1000)
elseif f.SetMinResize then
    f:SetMinResize(620, 320)
end
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
-- The window's place and size are remembered between sessions. In mini
-- mode it is only as big as its cards (see Render): the size kept is the
-- one it has otherwise, set aside in f.full meanwhile.
local function SaveWindow()
    local point, _, relPoint, x, y = f:GetPoint(1)
    local full = f.full
    ns.db.window = { point = point, relPoint = relPoint, x = x, y = y,
                     w = full and full[1] or f:GetWidth(), h = full and full[2] or f:GetHeight() }
end

local windowRestored = false
local function RestoreWindow()
    if windowRestored then return end
    windowRestored = true
    local w = ns.db.window
    if not w or not w.point then return end
    f:ClearAllPoints()
    f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    if w.w and w.h then f:SetSize(w.w, w.h) end
end

f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindow()
end)
f:Hide()
tinsert(UISpecialFrames, "ThatLuckyBastardFrame")

-- Builds the skins on a frame and returns them keyed by theme name.
-- Every window of the addon uses it, so they all follow the theme.
-- Fades a texture from one transparency to another in one colour. Returns
-- false where the client cannot do gradients, leaving the texture alone.
local function SetFade(tex, orientation, r, g, b, fromAlpha, toAlpha)
    if not (tex.SetGradient and CreateColor) then return false end
    tex:SetColorTexture(1, 1, 1, 1)
    return (pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha)))
end

local TITLE_BAR_H = 36 -- the Modern skin's header

-- `barH`: how tall the title bar of the Modern and Receipt skins is, if
-- not TITLE_BAR_H. A slimmer bar has a smaller cross.
local function BuildSkins(frame, onClose, barH)
    local skins = {}
    barH = barH or TITLE_BAR_H
    local slim = barH < TITLE_BAR_H

    -- Classic: the old grey metal panel.
    do
        local s = CreateFrame("Frame", nil, frame, "BasicFrameTemplateWithInset")
        s:SetAllPoints()
        if s.CloseButton then s.CloseButton:SetScript("OnClick", onClose) end
        skins.classic = s
    end

    -- Modern: flat dark panel, no game art.
    do
        local s = CreateFrame("Frame", nil, frame)
        s:SetAllPoints()
        local bg = s:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.075, 0.085, 0.105, 0.97)
        local bar = s:CreateTexture(nil, "BORDER")
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("TOPRIGHT")
        bar:SetHeight(barH)
        local line = s:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 0, -barH)
        line:SetPoint("TOPRIGHT", 0, -barH)
        line:SetHeight(2)
        s.accentLine = line
        -- The header carries the accent colour, strongest on the left
        -- where the name is (plain where the client cannot do gradients),
        -- and so does the line under it: now, and whenever it changes.
        local function Tint()
            if not SetFade(bar, "HORIZONTAL", ACCENT[1], ACCENT[2], ACCENT[3], 0.26, 0.03) then
                bar:SetColorTexture(1, 1, 1, 0.04)
            end
            line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        end
        Tint()
        ns.OnAccent(Tint)
        local function Edge(p1, p2, w, h)
            local t = s:CreateTexture(nil, "OVERLAY")
            t:SetPoint(p1)
            t:SetPoint(p2)
            if w then t:SetWidth(w) else t:SetHeight(h) end
            t:SetColorTexture(1, 1, 1, 0.12)
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

        local close = CreateFrame("Button", nil, s)
        local size = slim and 18 or 24
        close:SetSize(size, size)
        close:SetPoint("TOPRIGHT", slim and -3 or -6, slim and -(barH - size) / 2 or -6)
        local hl = close:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.9, 0.25, 0.25, 0.55)
        local x = close:CreateFontString(nil, "OVERLAY", slim and "GameFontHighlightSmall" or "GameFontHighlight")
        x:SetPoint("CENTER")
        x:SetText("X")
        close:SetScript("OnClick", onClose)
        skins.modern = s
    end

    -- Receipt: a dark counter, a thin rule under the title, a till key to
    -- close.
    do
        local s = CreateFrame("Frame", nil, frame)
        s:SetAllPoints()
        local bg = s:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(COUNTER[1], COUNTER[2], COUNTER[3], 0.98)
        local line = s:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 0, -barH)
        line:SetPoint("TOPRIGHT", 0, -barH)
        line:SetHeight(1)
        line:SetColorTexture(1, 1, 1, 0.10)
        local function Edge(p1, p2, w, h)
            local t = s:CreateTexture(nil, "OVERLAY")
            t:SetPoint(p1)
            t:SetPoint(p2)
            if w then t:SetWidth(w) else t:SetHeight(h) end
            t:SetColorTexture(0, 0, 0, 0.6)
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

        local close = CreateFrame("Button", nil, s)
        close:SetSize(slim and 20 or 24, slim and 16 or 22)
        close:SetPoint("TOPRIGHT", slim and -4 or -7, slim and -(barH - 16) / 2 or -7)
        local face = close:CreateTexture(nil, "BACKGROUND")
        face:SetAllPoints()
        face:SetColorTexture(KEY[1], KEY[2], KEY[3], 1)
        local low = close:CreateTexture(nil, "BORDER")
        low:SetPoint("BOTTOMLEFT")
        low:SetPoint("BOTTOMRIGHT")
        low:SetHeight(3)
        low:SetColorTexture(KEY_EDGE[1], KEY_EDGE[2], KEY_EDGE[3], 1)
        local hl = close:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        local x = close:CreateFontString(nil, "OVERLAY", "ThatLuckyBastardReceiptKey")
        x:SetPoint("CENTER", 0, 1)
        x:SetText("X")
        close:SetScript("OnClick", onClose)
        skins.receipt = s
    end

    return skins
end

-- A movable window in the addon's skins, hidden to begin with. Returns
-- the frame, the frame its content goes on (above the skins), its title
-- text and its skins. `closeOnEscape` puts it among the windows Escape
-- closes. The caller places it on the screen.
--
-- The main window, the run windows and the statistics share the HIGH
-- level: each comes to the front when it opens or is
-- clicked. The options sit above them, on DIALOG.
--
-- Every window follows the Size option (see ns.ApplyScale), unless it has
-- `fixedSize`: the options window, whose slider would move under the mouse.
--
-- `barH`: a title bar slimmer than the others (the meter's), in the Modern
-- and Receipt themes; Classic's is the game's own.
local scaledWindows, appliedScale = {}, nil
local slimBars = {} -- the windows with one, by their skins: { h = its height, on = the frame its title is on }
function ns.MakeWindow(name, width, height, strata, closeOnEscape, fixedSize, barH)
    local w = CreateFrame("Frame", name, UIParent)
    if not fixedSize then
        scaledWindows[#scaledWindows + 1] = w
        if appliedScale then w:SetScale(appliedScale) end
    end
    w:SetSize(width, height)
    w:SetFrameStrata(strata)
    w:SetToplevel(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:SetClampedToScreen(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    if closeOnEscape then tinsert(UISpecialFrames, name) end
    local windowSkins = BuildSkins(w, function() w:Hide() end, barH)
    local content = CreateFrame("Frame", nil, w)
    content:SetAllPoints()
    content:SetFrameLevel(w:GetFrameLevel() + 10)
    if barH then slimBars[windowSkins] = { h = barH, on = content } end
    return w, content, content:CreateFontString(nil, "OVERLAY", "GameFontNormal"), windowSkins
end

-- Sizes the main window and every window made by ns.MakeWindow (but the
-- options) by the Size option.
function ns.ApplyScale()
    local scale = ns.db and ns.db.options.scale or 1
    if scale == appliedScale then return end
    appliedScale = scale
    f:SetScale(scale)
    for _, w in ipairs(scaledWindows) do w:SetScale(scale) end
end

-- Shows the skin of the theme in force and places the title for it.
-- Returns whether the theme is flat, and the y at which a window's own
-- content starts under the title.
function ns.ApplyWindowTheme(windowSkins, title)
    local name = ThemeName()
    local flat = THEMES[name].flat == true
    for key, skin in pairs(windowSkins) do skin:SetShown(key == name) end
    title:ClearAllPoints()
    local slim = slimBars[windowSkins]
    if slim and flat then
        -- A slim bar: a smaller title, in the middle of its height.
        title:SetFontObject(name == "receipt" and "ThatLuckyBastardReceiptTitleSmall" or "GameFontHighlight")
        title:SetPoint("LEFT", slim.on, "TOPLEFT", 8, -slim.h / 2)
        return flat, -(slim.h + 2)
    end
    if name == "receipt" then
        title:SetFontObject("ThatLuckyBastardReceiptTitle")
        title:SetPoint("TOPLEFT", 14, -11)
    elseif flat then
        title:SetFontObject("GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -10)
    else
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOP", 0, -5)
    end
    return flat, flat and -46 or -30
end

local skins = BuildSkins(f, function() f:Hide() end)

local ui = CreateFrame("Frame", nil, f)
ui:SetAllPoints()
ui:SetFrameLevel(f:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")

-- The list view's figure columns, measured from the right edge of a row.
-- The gap to the right of "market" holds the price marker.
local LIST_COLS = {
    { key = "share",  right = -4,   width = 46, header = "Share" },
    { key = "diff",   right = -56,  width = 92, header = "vs equal" },
    { key = "market", right = -160, width = 92, header = "Market" },
    { key = "vendor", right = -258, width = 92, header = "Vendor" },
    { key = "count",  right = -356, width = 40, header = "Qty" },
}

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 44, 1)
scroll:SetScrollChild(content)

-- Receipt theme: the till's printer slot the receipts come out of (column
-- view), and the paper the list view is printed on.
local slot = ui:CreateTexture(nil, "ARTWORK")
slot:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", -6, 1)
slot:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", 6, 1)
slot:SetHeight(10)
slot:SetColorTexture(0.071, 0.063, 0.063, 1)
slot:Hide()
local slotLip = ui:CreateTexture(nil, "ARTWORK", nil, 1)
slotLip:SetPoint("TOPLEFT", slot, "BOTTOMLEFT")
slotLip:SetPoint("TOPRIGHT", slot, "BOTTOMRIGHT")
slotLip:SetHeight(1)
slotLip:SetColorTexture(0.290, 0.259, 0.227, 1)
slotLip:Hide()
local listPaper = content:CreateTexture(nil, "BACKGROUND", nil, -8)
listPaper:SetAllPoints()
listPaper:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
listPaper:Hide()

-- A gold outline around the breakdown, shown while the run on display is
-- pinned. It follows the scroll area, so it fits both themes and both
-- layouts.
local pinOutline = CreateFrame("Frame", "ThatLuckyBastardPinOutline", ui)
pinOutline:SetPoint("TOPLEFT", scroll, "TOPLEFT", -5, 5)
pinOutline:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 5, -5)
pinOutline:SetFrameLevel(scroll:GetFrameLevel() + 5)
pinOutline:Hide()
do
    local function Edge(point1, point2, width, height)
        local t = pinOutline:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 0.9)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if width then t:SetWidth(width) else t:SetHeight(height) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 2)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    Edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
end
-- The game says so when the scroll area changes size: when the window
-- is dragged wider, what is in it is laid out again. Render sizes the
-- window itself at times (mini mode) and lays things out for the width it
-- gives it, in the same go: a size that comes in while it draws, or that
-- is the one it drew for, asks for nothing more.
scroll:SetScript("OnSizeChanged", function(_, w)
    if drawing or math.abs(content:GetWidth() - w) < 0.5 then return end
    content:SetWidth(w)
    if ns.Refresh then ns.Refresh() end -- defined at the end of this file
end)

do
    local h = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 4, 4)
    h:SetText("Player / item")
    headers[1] = h
    for _, col in ipairs(LIST_COLS) do
        h = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", col.right, 4)
        h:SetWidth(col.width)
        h:SetJustifyH("RIGHT")
        h:SetText(col.header)
        headers[#headers + 1] = h
        headers[col.key] = h
    end
end

-- Resize grip
do
    local grip = CreateFrame("Button", nil, ui)
    f.grip = grip
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveWindow()
    end)
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function RowOnClick(self, button)
    local line = self.line
    if not line then return end
    if button == "RightButton" then
        -- The item's menu: its price, ignore it, split it (ItemMenu.lua).
        if line.e and currentRun and ns.ShowItemMenu then
            GameTooltip:Hide()
            ns.ShowItemMenu(currentRun, line.e)
        end
        return
    end
    if line.player then
        expanded[line.player] = not expanded[line.player] or nil
        Render()
    elseif line.link and IsModifiedClick("CHATLINK") then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if insert then insert(line.link) end
    end
end

local AWARDS_HINT = "Click for all awards."
local shownAwards = {} -- the award of each player of the run on show, by name

local function AwardTitle(award)
    -- On paper, stamped in red or blue ink.
    if Breakdown.ink then
        return (RED_STAMPS[award.key] and "|cffb23a2a" or "|cff2b4c9b") .. award.title:upper() .. "|r"
    end
    return "|cffffd100" .. award.title .. "|r" -- every award in the same gold: none is a verdict
end

-- Adds one award to the tooltip being built: its name, what earned it,
-- and (in grey) the rule behind it.
local function AddAwardLines(award)
    GameTooltip:AddLine(AwardTitle(award))
    if award.text then GameTooltip:AddLine(award.text, 1, 1, 1, true) end
    if award.link then GameTooltip:AddLine(award.link) end
    if award.amount then GameTooltip:AddLine(Money(award.amount), 1, 1, 1) end
    if award.how and award.how:gsub("%.$", "") ~= award.text then
        GameTooltip:AddLine(award.how, 0.7, 0.7, 0.7, true)
    end
end

-- Tooltip for a player: what is known about them from earlier runs, and
-- with `award` what they won in this one.
local function PersonTooltip(owner, p, award)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassColored(p.name, p.class))
    local who = ns.db.people[p.name]
    if IsMe(p.name) then
        GameTooltip:AddLine("That's you.", 0.7, 0.7, 0.7)
    elseif who and who.runs > 0 then
        GameTooltip:AddLine(("Runs together: %d"):format(who.runs), 1, 1, 1)
        GameTooltip:AddLine("Their loot: " .. Money(who.value), 1, 1, 1)
        if who.mine then GameTooltip:AddLine("Yours: " .. Money(who.mine), 1, 1, 1) end
        local awards = ns.AwardsText(who, 3) -- the three they had most often
        if awards then GameTooltip:AddLine("Awards: " .. awards, 1, 1, 1, true) end
    else
        GameTooltip:AddLine("No earlier runs together.", 0.7, 0.7, 0.7)
    end
    if award then
        GameTooltip:AddLine(" ")
        AddAwardLines(award)
    end
    GameTooltip:Show()
end

local function RowOnEnter(self)
    local line = self.line
    if line and line.p then
        -- The list view has no award cards, so they are explained here.
        PersonTooltip(self, line.p, shownAwards[line.p.name])
    elseif line and line.link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(line.link)
        if line.note or line.roll then GameTooltip:AddLine(" ") end
        if line.roll then GameTooltip:AddLine(line.roll, 1, 0.82, 0, true) end
        if line.note then GameTooltip:AddLine(line.note, 0.6, 0.8, 1, true) end
        -- Everyone's roll on this item, when the run has them.
        if line.e and currentRun and ns.AddRollLines then
            ns.AddRollLines(currentRun, ns.ItemKey(line.e))
        end
        if line.e and currentRun then GameTooltip:AddLine("Right-click: price, ignore, split", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end
end

local function StyleHighlight(r)
    if theme.paper then
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        r:GetHighlightTexture():SetVertexColor(INK[1], INK[2], INK[3], 0.07)
    elseif theme.flat then
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    else
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 1)
    end
end

local function StyleRow(r)
    r.label:SetFontObject(theme.font)
    for _, col in ipairs(LIST_COLS) do r[col.key]:SetFontObject(theme.font) end
    StyleHighlight(r)
end

-- A round picture: a ring (coloured per player), a dark disc, and the
-- picture itself clipped to a circle. Sizes and the picture's place are
-- set by the caller; the ring and disc follow the picture.
local DISC = { 0.05, 0.05, 0.07 }
local function NewRoundPicture(parent)
    local portrait = parent:CreateTexture(nil, "ARTWORK")
    local ring = parent:CreateTexture(nil, "BORDER", nil, 1)
    ring:SetTexture(CIRCLE)
    ring:SetPoint("CENTER", portrait)
    local disc = parent:CreateTexture(nil, "BORDER", nil, 2)
    disc:SetTexture(CIRCLE)
    disc:SetVertexColor(DISC[1], DISC[2], DISC[3])
    disc:SetPoint("CENTER", portrait)
    if parent.CreateMaskTexture then
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
    end
    return portrait, ring, disc
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
    for _, col in ipairs(LIST_COLS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", col.right, 0)
        fs:SetWidth(col.width)
        fs:SetJustifyH("RIGHT")
        r[col.key] = fs
    end
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    -- Item rows: icon and price marker. Category rows: colour chip.
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(CIRCLE)
    r.mark:SetSize(7, 7)
    r.mark:SetPoint("LEFT", r.market, "RIGHT", 3, 0)

    -- Player rows: round picture with a class-coloured ring.
    r.portrait, r.ring, r.ringInner = NewRoundPicture(r)
    r.portrait:SetPoint("LEFT", 8, 0)

    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleRow(r)
    rows[i] = r
    return r
end

local function Pct(part, whole)
    if not whole or whole <= 0 then return "" end
    return ("%.0f%%"):format(part / whole * 100)
end

----------------------------------------------------------------------
-- Column view (small groups): one column per player with a portrait,
-- their totals, then their items by category.
----------------------------------------------------------------------

-- The unit a player of a run is right now, if they are in the group.
local function UnitForName(name)
    if IsMe(name) then return "player" end
    local roster = drawCache.roster
    if not roster then
        roster = {}
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, GetNumGroupMembers() do
            local unit = prefix .. i
            if UnitExists(unit) then
                local n = GetUnitName(unit, true)
                if n and not issecret(n) then roster[n] = unit end
            end
        end
        if drawing then drawCache.roster = roster end
    end
    return roster[name]
end

-- In the group and close enough for the game to draw them.
local function InSight(unit)
    return UnitIsUnit(unit, "player") or UnitIsVisible(unit)
end

-- Draws a player's flat picture: their live portrait when `unit` is given,
-- otherwise their class icon. The game cannot save a portrait or a model,
-- so a player who is not around has no picture of their own.
local function FillPortrait(tex, p, unit)
    local coords = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
    if unit then
        SetPortraitTexture(tex, unit)
        tex:SetTexCoord(0, 1, 0, 1)
    elseif coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- mode: "3d" model, "2d" portrait, "class" icon or "none". A model or a
-- portrait needs the player in the group and in sight right now; anyone
-- else gets their class icon.
--
-- Pictures are framed in the player's class colour: a ring around the
-- round 2D portrait / class icon, a square frame around the 3D model
-- (model frames cannot be masked to a circle).
local function SetPortrait(c, p, mode)
    local tex, model = c.portrait, c.model
    local unit = (mode == "2d" or mode == "3d") and UnitForName(p.name) or nil
    if unit and not InSight(unit) then unit = nil end -- still inside the dungeon, say
    local useModel = mode == "3d" and unit ~= nil
    local useTexture = mode ~= "none" and not useModel

    local r, g, b = ClassRGB(p.class)
    c.ring:SetVertexColor(r, g, b)
    c.box:SetColorTexture(r, g, b, 1)
    c.ring:SetShown(useTexture)
    c.ringInner:SetShown(useTexture)
    c.box:SetShown(useModel)
    c.boxInner:SetShown(useModel)
    tex:SetShown(useTexture)
    model:SetShown(useModel)

    if not useModel then
        c.modelFor = nil
        if useTexture then FillPortrait(tex, p, unit) end
        return
    end
    -- c.modelFor: whose model the frame holds, so that it is only loaded
    -- again when that changes (reloading makes it flicker).
    if c.modelFor ~= p.name then
        model:SetUnit(unit)
        if model.SetPortraitZoom then model:SetPortraitZoom(1) end
        c.modelFor = p.name
    end
end

local function GetCol(i)
    local c = cols[i]
    if c then return c end
    c = CreateFrame("Frame", nil, content)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    -- The header's parts are placed by RenderColumns, which knows what the
    -- options show; here they are only made.
    c.portrait, c.ring, c.ringInner = NewRoundPicture(c)
    c.portrait:SetSize(48, 48)
    c.ring:SetSize(54, 54)
    c.ringInner:SetSize(50, 50)
    c.model = CreateFrame("PlayerModel", nil, c)
    c.model:SetSize(52, 52)
    c.model:Hide()

    -- 3D model: class-coloured square frame with a dark backdrop.
    c.box = c:CreateTexture(nil, "BORDER", nil, 1)
    c.box:SetSize(56, 56)
    c.box:SetPoint("CENTER", c.model)
    c.boxInner = c:CreateTexture(nil, "BORDER", nil, 2)
    c.boxInner:SetColorTexture(DISC[1], DISC[2], DISC[3], 1)
    c.boxInner:SetSize(52, 52)
    c.boxInner:SetPoint("CENTER", c.model)
    local function Text(font)
        local fs = c:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        return fs
    end
    c.name = Text("GameFontNormal")
    c.market = Text("GameFontHighlight")
    c.vendor = Text("GameFontHighlightSmall")
    c.share = Text("GameFontHighlightSmall")
    -- Modern-theme decoration: class-coloured glow and strip at the top,
    -- a pill behind the over/under figure, and a bar whose length is the
    -- player's share of the run, split into category colours.
    c.top = c:CreateTexture(nil, "BORDER")
    c.top:SetPoint("TOPLEFT")
    c.top:SetPoint("TOPRIGHT")
    c.strip = c:CreateTexture(nil, "ARTWORK")
    c.strip:SetPoint("TOPLEFT")
    c.strip:SetPoint("TOPRIGHT")
    c.strip:SetHeight(2)
    c.pill = c:CreateTexture(nil, "BORDER")
    c.pill:SetHeight(14)
    c.track = c:CreateTexture(nil, "BORDER")
    c.track:SetHeight(5)
    c.track:SetColorTexture(1, 1, 1, 0.08)
    c.segs = {}
    for k = 1, #CATS do
        local seg = c:CreateTexture(nil, "ARTWORK")
        seg:SetHeight(5)
        c.segs[k] = seg
    end
    -- Podium mode: medal-coloured line across the top and a rank label.
    c.medal = c:CreateTexture(nil, "OVERLAY")
    c.medal:SetPoint("TOPLEFT")
    c.medal:SetPoint("TOPRIGHT")
    c.medal:SetHeight(3)
    c.rank = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.rank:SetPoint("TOPLEFT", 6, -8)
    -- Invisible hover area over the picture and name, for the tooltip
    -- with what is known about this player from earlier runs.
    c.hover = CreateFrame("Button", nil, c)
    c.hover:SetPoint("TOPLEFT")
    c.hover:SetPoint("TOPRIGHT")
    c.hover:SetScript("OnEnter", function(self)
        if self.p then PersonTooltip(self, self.p) end -- the award card below explains itself
    end)
    c.hover:SetScript("OnLeave", GameTooltip_Hide)
    c.rows = {}
    cols[i] = c
    return c
end

----------------------------------------------------------------------
-- Awards: small cards under each player's totals (column view), or
-- titles after the name (list view). A run shown as it is left is
-- revealed: by the race (further down) when the columns stand in podium
-- order, else by the cards coming up one after another.
----------------------------------------------------------------------

local AWARD_H = 30
local REVEAL_STEP = 0.5       -- seconds between two cards
local REVEAL_FADE = 0.4       -- seconds a card takes to appear
local FANFARE_DELAY = 0.3     -- after the last card
local SCREENSHOT_DELAY = 1.2  -- after the last card, or the race

-- Plays one of the game's own interface sounds, by name with the numeric
-- id as a fallback. A missing sound is not worth an error.
local function PlayKit(name, id)
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT[name]) or id, "SFX")
end

-- Calls off a reveal in progress: its timers do nothing from now on.
local function CancelReveal()
    reveal.token = reveal.token + 1
    reveal.run, reveal.ends = nil, 0
    race.Cancel()
end

-- The one line that fits under the title; the tooltip has the rest.
local function AwardShort(award)
    if award.link then return award.link end
    if award.amount then return Money(award.amount) end
    return award.text or ""
end

local function AwardOnEnter(self)
    local award = self.award
    if not award then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    AddAwardLines(award)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(AWARDS_HINT, 0.6, 0.8, 1)
    GameTooltip:Show()
end

-- A column's award card.
local function GetAwardFrame(c)
    local af = c.awardFrame
    if af then return af end
    af = CreateFrame("Button", nil, c)
    af:SetHeight(AWARD_H - 3)
    local bg = af:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.07)
    af.icon = af:CreateTexture(nil, "ARTWORK")
    af.icon:SetSize(22, 22)
    af.icon:SetPoint("LEFT", 3, 0)
    af.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    af.title = af:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    af.title:SetPoint("TOPLEFT", 30, -2)
    af.title:SetPoint("TOPRIGHT", -2, -2)
    af.title:SetJustifyH("LEFT")
    af.title:SetWordWrap(false)
    af.detail = af:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    af.detail:SetPoint("BOTTOMLEFT", 30, 2)
    af.detail:SetPoint("BOTTOMRIGHT", -2, 2)
    af.detail:SetJustifyH("LEFT")
    af.detail:SetWordWrap(false)
    af.bg = bg
    -- Receipt theme: the card is a rubber stamp, a border in ink.
    af.edges = {}
    for k, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = af:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1])
        t:SetPoint(pts[2])
        if k <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        t:Hide()
        af.edges[k] = t
    end
    af:SetScript("OnEnter", AwardOnEnter)
    af:SetScript("OnLeave", GameTooltip_Hide)
    af:SetScript("OnClick", function() ns.ShowBrowse("awards") end)
    c.awardFrame = af
    return af
end

local function GetColRow(c, j)
    local r = c.rows[j]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -13, 0) -- leaves room for the price marker
    r.value:SetJustifyH("RIGHT")
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(CIRCLE)
    r.mark:SetSize(7, 7)
    r.mark:SetPoint("RIGHT", -3, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetPoint("TOPLEFT")
    r.chip:SetPoint("BOTTOMLEFT")
    r.chip:SetWidth(3)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowOnClick)
    r:SetScript("OnEnter", RowOnEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    StyleHighlight(r)
    c.rows[j] = r
    return r
end

----------------------------------------------------------------------
-- Receipt theme: the award card as a rubber stamp, and the end of each
-- receipt under its last line (a double rule, a barcode, a thank-you and
-- the torn edge).
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Footer: the text lines under the breakdown. Totals, run time, dungeon
-- records, comparison with your average, and the legend for the dots.
----------------------------------------------------------------------


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

local function PlaceText(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 2, y)
    fs:SetPoint("TOPRIGHT", -2, y)
end

-- A column-view item row. `count` and `market` are passed separately
-- because aligned mode merges several entries of the same item.
-- `total` is the run's total value.
-- An ignored item, or one given to the others (`e.away`), is listed but
-- worth nothing here; a share of a split item says which share it is,
-- and a stack partly ignored how much of it.
local function ItemLine(e, count, market, total)
    local names = {}
    for i, name in ipairs(e.split or {}) do names[i] = DisplayName(name) end
    local split = table.concat(names, ", ")
    local ways = e.ways or 1
    -- The roll was the looter's, not a sharer's.
    local roll = not e.from and RollNote(e) or nil
    local none = e.ignored and ns.CountedCopies(e) == 0 -- every copy ignored
    if none or e.away then
        return {
            link = e.link, e = e,
            label = ItemLabel(e, count),
            value = Grey(none and "ignored" or "given"),
            dim = true,
            note = none and (ns.EnchantingMaterial(e.link) and "Ignored: most come from disenchanting."
                             or "Ignored: not counted.") or ("Given to " .. split .. "."),
            roll = roll,
        }
    end
    local mark = PriceMark(e)
    local dominant = IsDominant(mark, market, total)
    local note = PriceNote(e, mark, dominant)
    local part
    if ways > 1 then
        part = Grey(" 1/" .. ways)
        note = ("Split %d ways: %s."):format(ways, split) .. (note and ("\n" .. note) or "")
    elseif e.from then
        note = "Given by " .. DisplayName(e.from) .. "." .. (note and ("\n" .. note) or "")
    end
    if e.ignored then
        local real = ns.RealEntry(e)
        note = ("%d of %d ignored."):format(ns.IgnoredCopies(real), real.count) .. (note and ("\n" .. note) or "")
    end
    return {
        link = e.link, e = e,
        label = ItemLabel(e, count) .. (part or ""),
        part = part, -- the share, after the item
        value = Money(market),
        mark = mark,
        warn = dominant,
        note = note,
        roll = roll,
    }
end

-- What a column or an opened player row says when there is nothing in it.
local function NoLootLabel(sum)
    return (Breakdown.ink and INK_GREY_CODE or GREY) .. "No loot seen|r"
end

-- A player's items for one category, or all of them when `cat` is false
-- (the "group by category" option is off).
local function GroupOf(p, cat)
    if cat then return p.cats[cat.key] end
    return p.all
end

-- Returns one list of lines per player. With `alignItems` every column
-- gets the same rows in the same order (a dash where the player has none
-- of that item), so a line can be compared straight across.
local function BuildColumnLines(sum, o)
    local out = {}
    for i = 1, #sum.players do out[i] = {} end
    local function add(i, line) out[i][#out[i] + 1] = line end

    local function Header(cat, cs)
        -- On paper, a heading and its sum in the same bold ink.
        local value = cs and (Breakdown.ink and Money(cs.market) or MoneyGrey(cs.market)) or Grey("-")
        return { label = CatColored(cat.short, cat), cat = cat, bg = 0.08, value = value }
    end

    -- Each player's own items, in their own order.
    local function Plain(cat)
        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            if cs then
                if cat then add(i, Header(cat, cs)) end
                for _, e in ipairs(cs.items) do
                    add(i, ItemLine(e, e.count, ns.EntryMarket(e), sum.market))
                end
            end
        end
    end

    -- The same rows for everyone: every item anyone has in this group,
    -- ordered by name or by combined value.
    local function Aligned(cat)
        local union, order = {}, {}
        for _, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ns.ItemKey(e)
                local u = union[k]
                if not u then
                    u = { key = k, name = ns.ItemName(e), total = 0, quest = e.cat == "quest" }
                    union[k] = u
                    order[#order + 1] = u
                end
                u.total = u.total + ns.EntryMarket(e)
            end
        end
        if #order == 0 then return end
        table.sort(order, function(a, b)
            if a.quest ~= b.quest then return b.quest end -- quest items last
            if o.sortItems == "name" and a.name ~= b.name then return a.name < b.name end
            if a.total ~= b.total then return a.total > b.total end
            return a.key < b.key
        end)

        for i, p in ipairs(sum.players) do
            local cs = GroupOf(p, cat)
            local mine = {} -- this player's items by key (same item merged)
            for _, e in ipairs(cs and cs.items or {}) do
                local k = ns.ItemKey(e)
                local m = mine[k]
                if m then
                    m.count, m.market = m.count + e.count, m.market + ns.EntryMarket(e)
                else
                    mine[k] = { e = e, count = e.count, market = ns.EntryMarket(e) }
                end
            end
            if cat then add(i, Header(cat, cs)) end
            for _, u in ipairs(order) do
                local m = mine[u.key]
                if m then
                    add(i, ItemLine(m.e, m.count, m.market, sum.market))
                else
                    add(i, { label = "|cff505050-|r" })
                end
            end
        end
    end

    -- Coins are one sum with no items under it: a heading of their own
    -- when the loot is grouped, else a line before the items.
    local anyCoins = false
    for _, p in ipairs(sum.players) do
        if p.cats.coins then anyCoins = true end
    end
    local function Coins(grouped)
        if not anyCoins then return end
        local cat = CATS.coins
        for i, p in ipairs(sum.players) do
            local cs = p.cats.coins
            if grouped then
                if cs or o.alignItems then add(i, Header(cat, cs)) end
            elseif cs then
                add(i, { label = CatColored(cat.short, cat), value = Money(cs.market) })
            elseif o.alignItems then
                add(i, { label = "|cff505050-|r" })
            end
        end
    end

    -- `false` stands for "no categories": one group holding everything.
    for _, cat in ipairs(o.groupByCategory and CATS or { false }) do
        if cat and cat.coins then
            Coins(true)
        else
            if not cat then Coins(false) end
            if o.alignItems then Aligned(cat) else Plain(cat) end
        end
    end

    -- With aligned items an empty-handed player has a column of dashes,
    -- which says it already; unless nobody has anything.
    for i, p in ipairs(sum.players) do
        -- (Nothing counted, and nothing listed either: an ignored item is.)
        if p.count == 0 and p.money == 0 and #p.all.items == 0
                and (not o.alignItems or (sum.count == 0 and sum.money == 0)) then
            add(i, { label = NoLootLabel(sum) })
        end
    end
    return out
end

-- The order players stand in on a podium: most loot in the middle, 2nd on
-- its left, 3rd on its right, then outwards. `ranked` is in rank order.
local function PodiumOrder(ranked)
    local arranged = {}
    for rank, p in ipairs(ranked) do
        if rank % 2 == 0 then
            table.insert(arranged, 1, p)
        else
            arranged[#arranged + 1] = p
        end
    end
    return arranged
end

local HEADER_GLOW_H = 72 -- Modern theme: the class-coloured glow at the top of a column

-- The bench (see below) keeps its many constants and helpers to itself:
-- a Lua function, this file included, can hold 200 local variables.
local RenderBench, HideBench, ShowBackButton, BenchRoom
do
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
end

----------------------------------------------------------------------
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
----------------------------------------------------------------------
do
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
end

local function RenderColumns(sum, awards, insights)
    local theme = Breakdown.theme
    -- A bigger group: columns for its top five, the bench for the others.
    -- `view` is the summary with the columns' players only; every total
    -- and the equal split stay the whole run's.
    local view, bench = sum, {}
    if #sum.players > MAX_COLUMNS then
        local top = {}
        for _, p in ipairs(sum.players) do
            if p.rank <= MAX_COLUMNS then top[#top + 1] = p else bench[#bench + 1] = p end
        end
        table.sort(bench, function(a, b) return a.rank < b.rank end)
        view = setmetatable({ players = top }, { __index = sum })
    end
    local n = #view.players
    -- Receipt theme: each column is a receipt, printed in ink and lying a
    -- little apart from the next on the counter.
    local paper = theme.paper and true or false
    local gap = paper and 12 or COL_GAP
    local colW = (content:GetWidth() - gap * (n - 1)) / n
    local rowH = theme.rowH
    local equal = sum.market / #sum.players
    local maxH = 0
    Breakdown.ink = paper -- the footer under the receipts is on the counter: see below

    -- Header layout depends on what the options show.
    local o = ns.db.options
    local showBar = theme.flat and o.showBar
    local y = -8
    local yRank, yPortrait, yName, yMarket, yVendor, yShare, yBar
    if paper then yRank = y; y = y - 18 end -- "*** 1ST ***"
    if o.portrait ~= "none" then yPortrait = y; y = y - 58 end
    yName = y; y = y - 18
    yMarket = y; y = y - (paper and 24 or theme.flat and 20 or 18)
    if o.showVendor and o.valueMode ~= "vendor" then yVendor = y; y = y - 14 end
    if o.showShare then yShare = y; y = y - 16 end
    if showBar then yBar = y; y = y - 9 end

    -- The award card goes under the totals. Every column keeps room for
    -- one when anyone has one, so the item rows stay level.
    local yAward = y - 4
    if next(awards) then y = yAward - AWARD_H end
    local headerH = 4 - y

    -- Podium: columns in podium order, stepping down by rank unless items
    -- are aligned. (Summarize leaves the players in rank order for it.)
    local podium = o.sortPlayers == "podium"
    if podium then view.players = PodiumOrder(view.players) end

    -- The reveal: in podium order the columns race for their places (if
    -- there is anything to race for), else the award cards come up one
    -- after another.
    local revealIndex = 0
    local racing = false
    if reveal.pending then
        CancelReveal() -- an earlier one, if any
        reveal.run = Breakdown.CurrentRun()
        racing = (o.race and podium and n > 1 and sum.market > 0) and true or false
        if racing then race.Start() end
    end
    local token = reveal.token
    -- Receipts all come out of the printer at the same height.
    local step = (podium and not o.alignItems and not paper) and 14 or 0
    local colLines = BuildColumnLines(view, o)
    local tint = theme.flat and 0.045 or 0.03 -- how bright a column's panel is

    for i, p in ipairs(view.players) do
        local c = GetCol(i)
        c:ClearAllPoints()
        c.offset = step * math.min(p.rank - 1, 3)
        c:SetPoint("TOPLEFT", (i - 1) * (colW + gap), -c.offset)
        c:SetWidth(colW)
        if paper then
            c.bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
        else
            c.bg:SetColorTexture(1, 1, 1, tint + ((podium and p.rank == 1) and 0.04 or 0))
        end
        c.rank:ClearAllPoints()
        if paper then
            -- Every receipt says its place, podium order or not.
            c.rank:SetFontObject("ThatLuckyBastardReceiptInkBold")
            c.rank:SetTextColor(INK[1], INK[2], INK[3])
            c.rank:SetPoint("TOP", 0, yRank)
            c.rank:SetText("*** " .. ns.Ordinal(p.rank):upper() .. " ***")
        else
            c.rank:SetFontObject("GameFontNormalSmall")
            c.rank:SetPoint("TOPLEFT", 6, -8)
            if podium then
                local medal = MEDALS[p.rank] or MEDALS[4]
                c.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
                c.rank:SetText(ns.Ordinal(p.rank))
                c.rank:SetTextColor(medal[1], medal[2], medal[3])
            end
        end
        c.medal:SetShown(podium and not paper)
        c.rank:SetShown(podium or paper)

        SetPortrait(c, p, o.portrait)
        -- On paper the picture is printed: in grey, ringed in grey ink.
        c.portrait:SetDesaturated(paper)
        if paper then
            c.ring:SetVertexColor(INK_GREY[1], INK_GREY[2], INK_GREY[3])
            c.ringInner:SetVertexColor(0.851, 0.824, 0.761)
        else
            c.ringInner:SetVertexColor(DISC[1], DISC[2], DISC[3])
        end
        if yPortrait then
            c.portrait:ClearAllPoints()
            c.portrait:SetPoint("TOP", 0, yPortrait)
            c.model:ClearAllPoints()
            c.model:SetPoint("TOP", 0, yPortrait + 2)
        end
        PlaceText(c.name, yName)
        c.name:SetFontObject(paper and "ThatLuckyBastardReceiptInkBold" or "GameFontNormal")
        c.name:SetText(ns.BetMark(ns.ViewedRun(), p.name) .. ClassColored(DisplayName(p.name), p.class))
        c.hover.p = p
        c.hover:SetHeight(-yMarket) -- from the top down to just under the name
        PlaceText(c.market, yMarket)
        c.market:SetText(Money(p.market))
        c.vendor:SetShown(yVendor ~= nil)
        if yVendor then
            PlaceText(c.vendor, yVendor)
            if paper then
                c.vendor:SetFontObject("ThatLuckyBastardReceiptGrey")
                c.vendor:SetText("VENDOR " .. Money(p.vendor))
            else
                c.vendor:SetFontObject("GameFontHighlightSmall")
                c.vendor:SetText("|cff909090Vendor|r " .. Money(p.vendor))
            end
        end
        c.share:SetShown(yShare ~= nil)
        c.share:SetFontObject(paper and "ThatLuckyBastardReceiptInk" or "GameFontHighlightSmall")
        if yShare then PlaceText(c.share, yShare) end

        -- Modern's decoration: the glow, the strip and the pill. None on paper.
        local flat = theme.flat and not paper
        local cr, cg, cb = ClassRGB(p.class)
        c.top:SetShown(flat)
        c.top:SetHeight(math.min(HEADER_GLOW_H, headerH))
        c.strip:SetShown(flat and not podium)
        c.track:SetShown(showBar)
        if showBar then
            c.track:ClearAllPoints()
            c.track:SetPoint("TOPLEFT", 8, yBar)
            c.track:SetPoint("TOPRIGHT", -8, yBar)
            if paper then
                c.track:SetColorTexture(0.839, 0.812, 0.749, 1)
            else
                c.track:SetColorTexture(1, 1, 1, 0.08)
            end
        end
        if flat and c.glowClass ~= (p.class or "") then -- only when the column changes hands
            c.glowClass = p.class or ""
            c.strip:SetColorTexture(cr, cg, cb, 0.9)
            if not SetFade(c.top, "VERTICAL", cr, cg, cb, 0, 0.30) then
                c.top:SetColorTexture(cr, cg, cb, 0.12)
            end
        end
        c.market:SetFontObject(paper and "ThatLuckyBastardReceiptTotal"
            or flat and "GameFontHighlightLarge" or "GameFontHighlight")

        local diff = p.market - equal
        local diffText = sum.market > 0 and DiffText(diff) or ""
        local showDiff = diffText ~= ""
        if sum.market > 0 then
            c.share:SetText((paper and "SHARE " or "") .. Pct(p.market, sum.market)
                .. (showDiff and ("  " .. diffText) or ""))
        else
            c.share:SetText("")
        end
        if flat and showDiff and yShare then
            c.pill:ClearAllPoints()
            c.pill:SetPoint("TOP", 0, yShare + 2)
            c.pill:SetWidth(math.min(colW - 4, c.share:GetStringWidth() + 14))
            if diff > 0 then
                c.pill:SetColorTexture(0.25, 0.82, 0.25, 0.16)
            else
                c.pill:SetColorTexture(0.88, 0.31, 0.31, 0.16)
            end
            c.pill:Show()
        else
            c.pill:Hide()
        end

        local award = awards[p.name]
        if award or c.awardFrame then
            local af = GetAwardFrame(c)
            af.award = award
            af:SetShown(award ~= nil)
            if award then
                af:ClearAllPoints()
                af:SetPoint("TOPLEFT", 4, yAward)
                af:SetPoint("TOPRIGHT", -4, yAward)
                af.icon:SetTexture("Interface\\Icons\\" .. award.icon)
                StyleAward(af, award, paper)
                af.title:SetText(AwardTitle(award))
                af.detail:SetText(AwardShort(award))
                if reveal.pending and not racing then
                    -- Hidden now, faded in a little later than the one before.
                    revealIndex = revealIndex + 1
                    af:SetAlpha(0)
                    C_Timer.After(REVEAL_STEP * revealIndex, function()
                        if token ~= reveal.token or not af.award then return end
                        if UIFrameFadeIn then UIFrameFadeIn(af, REVEAL_FADE, 0, 1) else af:SetAlpha(1) end
                        if o.ceremonySound and f:IsShown() then PlayKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) end
                    end)
                elseif GetTime() >= reveal.ends then
                    af:SetAlpha(1)
                end
            end
        end

        -- Share bar: total length = share of the run, segments = categories.
        local x = 8
        local full = (colW - 16) * (sum.market > 0 and p.market / sum.market or 0)
        for k, cat in ipairs(CATS) do
            local seg, cs = c.segs[k], p.cats[cat.key]
            if showBar and cs and cs.market > 0 and p.market > 0 then
                local w = full * cs.market / p.market
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", x, yBar)
                seg:SetWidth(math.max(w, 1))
                if paper then -- one bar in ink: a till prints in one colour
                    seg:SetColorTexture(INK[1], INK[2], INK[3], 1)
                else
                    seg:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 0.95)
                end
                seg:Show()
                x = x + w
            else
                seg:Hide()
            end
        end

        local lines = colLines[i]

        for j, line in ipairs(lines) do
            local r = GetColRow(c, j)
            r.line = line
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(headerH + (j - 1) * rowH))
            r:SetPoint("TOPRIGHT", 0, -(headerH + (j - 1) * rowH))
            r:SetHeight(rowH)
            local left = 4
            -- A receipt prints no icons and no colour chips.
            if line.link and o.showIcons and not paper then
                r.icon:SetSize(rowH - 4, rowH - 4)
                r.icon:SetTexture(ItemIcon(line.link))
                r.icon:Show()
                left = rowH + 4
            else
                r.icon:Hide()
            end
            if line.cat and not paper then
                r.chip:SetColorTexture(line.cat.color[1], line.cat.color[2], line.cat.color[3], 0.9)
                r.chip:Show()
                left = 8
            else
                r.chip:Hide()
            end
            local font = paper and (line.cat and "ThatLuckyBastardReceiptInkBold" or "ThatLuckyBastardReceiptInk")
                or "GameFontHighlightSmall"
            r.label:SetFontObject(font)
            r.value:SetFontObject(font)
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", left, 0)
            r.label:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
            r.label:SetText(line.label or "")
            r.value:SetText(line.value or "")
            -- An item worth nothing here (ignored, given away) is faded.
            r.label:SetAlpha(line.dim and 0.5 or 1)
            r.icon:SetAlpha(line.dim and 0.5 or 1)
            SetMark(r.mark, line.mark)
            SetRowBg(r.bg, line)
            r:EnableMouse(line.link ~= nil)
            r:Show()
        end
        for j = #lines + 1, #c.rows do c.rows[j]:Hide() end

        -- A receipt ends where its print does, with its tail; the other
        -- looks keep the columns level.
        c.ownH = headerH + #lines * rowH + (paper and TAIL_H or 6)
        ShowTail(c, paper, p.name, colW)
        maxH = math.max(maxH, c.offset + c.ownH + (paper and EDGE_H or 0))
        c:Show()
    end
    for i = 1, n do
        local c = cols[i]
        c:SetHeight(paper and c.ownH or (maxH - c.offset))
    end
    for i = n + 1, #cols do cols[i]:Hide() end
    Breakdown.ink = false -- the footer is written on the counter, not on paper
    if reveal.pending then
        reveal.pending = false
        local length = REVEAL_STEP * revealIndex
        reveal.ends = GetTime() + length + REVEAL_FADE
        if revealIndex > 0 then
            -- A fanfare once the last card is up, then the souvenir photo.
            if o.ceremonySound then
                C_Timer.After(length + FANFARE_DELAY, function()
                    if token == reveal.token and f:IsShown() then PlayKit("IG_QUEST_LIST_COMPLETE", 878) end
                end)
            end
            if o.ceremonyScreenshot and Screenshot then
                C_Timer.After(length + SCREENSHOT_DELAY, function()
                    if token == reveal.token and f:IsShown() then Screenshot() end
                end)
            end
        end
    end

    local bottom = RenderBench(bench, awards, maxH + 10, paper)
    local texts = FooterTexts(sum, insights, true)
    for i, text in ipairs(texts) do
        local fs = footLines[i]
        if not fs then
            fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            footLines[i] = fs
        end
        fs:SetFontObject(paper and "ThatLuckyBastardReceiptCounter" or "GameFontHighlightSmall")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -bottom)
        fs:SetText(text)
        fs:Show()
        bottom = bottom + 16
    end
    for i = #texts + 1, #footLines do footLines[i]:Hide() end
    content:SetHeight(bottom + 4)

    -- A race in progress takes the columns from here.
    if race.on then
        local tall = maxH
        if paper then
            tall = 0
            for i = 1, n do tall = math.max(tall, cols[i].ownH) end
        end
        race.Lay(view.players, colW + gap, tall, paper, tint, headerH)
    end
end

----------------------------------------------------------------------
-- List view (larger groups)
----------------------------------------------------------------------

-- Line kinds, told apart by their fields:
--   player row    `p` (the player's summary) - taller, with their picture
--   category row  `cat`
--   item row      `link`, plus `icon`, `mark` and `note`
local function BuildLines(sum, awards, insights)
    local o = ns.db.options
    local lines = {}
    local function add(t) lines[#lines + 1] = t end

    local n = #sum.players
    local equal = n > 0 and sum.market / n or 0

    for _, p in ipairs(sum.players) do
        local open = expanded[p.name]
        local award = awards[p.name]
        add({
            player = p.name, p = p, bg = 0.12,
            label = HeadCode() .. (open and "-" or "+") .. "|r "
                .. ns.BetMark(ns.ViewedRun(), p.name) .. ClassColored(DisplayName(p.name), p.class)
                .. (award and ("   " .. AwardTitle(award)) or ""),
            count = p.count, vendor = Money(p.vendor), market = Money(p.market),
            share = Pct(p.market, sum.market),
            diff = sum.market > 0 and DiffText(p.market - equal) or "",
            frac = sum.market > 0 and p.market / sum.market or 0,
        })
        if open then
            if p.count == 0 and p.money == 0 and #p.all.items == 0 then
                add({ indent = 24, wide = true, label = NoLootLabel(sum) })
            end
            for _, cat in ipairs(o.groupByCategory and CATS or { false }) do
                local group = GroupOf(p, cat)
                -- Coins have no items: with no categories, a line of their own first.
                local coins = not cat and p.cats.coins
                if coins then
                    add({ indent = 24, label = CatColored(CATS.coins.label, CATS.coins),
                          vendor = Money(coins.vendor), market = Money(coins.market) })
                end
                if group then
                    if cat then
                        add({
                            indent = 24, bg = 0.05, cat = cat,
                            label = CatColored(cat.label, cat),
                            count = cat.coins and "" or Grey(tostring(group.count)), vendor = MoneyGrey(group.vendor),
                            market = MoneyGrey(group.market),
                            share = Grey(Pct(group.market, p.market)),
                        })
                    end
                    for _, e in ipairs(group.items) do
                        -- The column view's item line, with the list's own columns.
                        local line = ItemLine(e, e.count, ns.EntryMarket(e), sum.market)
                        line.indent, line.icon = cat and 36 or 24, true
                        line.label = (Breakdown.ink and InkLink(e) or e.link) .. (line.part or "")
                        line.count = "x" .. e.count
                        line.vendor, line.market = line.dim and "" or Money(ns.EntryVendor(e)), line.value
                        add(line)
                    end
                end
            end
        end
    end

    if n > 0 and o.showTotals then
        add({})
        add({ indent = 4, bg = 0.12, label = HeadCode() .. "Total|r", count = sum.count,
              vendor = Money(sum.vendor), market = Money(sum.market), share = "100%" })
        add({ indent = 4, label = "Equal split (" .. n .. " players)",
              vendor = Money(sum.vendor / n), market = Money(sum.market / n), share = Pct(1, n) })
    end
    local texts = FooterTexts(sum, insights, false)
    if #texts > 0 then add({}) end
    for _, text in ipairs(texts) do
        add({ indent = 4, label = text, wide = true })
    end
    return lines
end

----------------------------------------------------------------------
-- Buttons. Each has a game-styled and a flat variant; the theme decides
-- which one is visible.
----------------------------------------------------------------------

-- `parent` defaults to this window, which then switches the button's
-- variant itself. Other windows pass their own frame and call SetFlat
-- when they apply the theme.
local fontCount = 0 -- font objects made by SetTextColor, which each need a name

local function MakeButton(text, width, onClick, parent)
    local b = CreateFrame("Frame", nil, parent or ui)
    b:SetSize(width, 22)

    b.tpl = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    b.tpl:SetAllPoints()
    b.tpl:SetText(text)
    b.tpl:SetScript("OnClick", onClick)

    -- The flat variant serves two looks: Modern's flat button, and the
    -- Receipt theme's till key (a pale key with a darker lower edge, its
    -- label in capitals in the typewriter font). Paint draws whichever is
    -- in force from the button's state.
    b.flat = CreateFrame("Button", nil, b)
    b.flat:SetAllPoints()
    local bg = b.flat:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    b.flat.bg = bg
    local edge = b.flat:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(3)
    b.flat.edge = edge

    -- A line in the accent colour under the button, for the selected state.
    local function Mark(owner)
        local t = owner:CreateTexture(nil, "OVERLAY")
        t:SetPoint("BOTTOMLEFT", 3, 1)
        t:SetPoint("BOTTOMRIGHT", -3, 1)
        t:SetHeight(2)
        t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        t:Hide()
        return t
    end
    b.tpl.mark, b.flat.mark = Mark(b.tpl), Mark(b.flat)
    local hl = b.flat:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    b.flat.hl = hl
    b.flat.text = b.flat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.flat.text:SetPoint("CENTER")
    b.flat:SetScript("OnClick", onClick)
    b.label, b.on = text, true

    function b:Paint()
        local fb = self.flat
        self.tpl.mark:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        fb.mark:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        if self.key then
            -- Delete (tinted) and Share (loud) are red keys.
            local red = self.loud or self.tint ~= nil
            local face, low = red and RED_KEY or KEY, red and RED_KEY_EDGE or KEY_EDGE
            local dim = self.selected and 0.86 or 1 -- a selected key is held down
            fb.bg:SetColorTexture(face[1] * dim, face[2] * dim, face[3] * dim, 1)
            fb.edge:SetColorTexture(low[1], low[2], low[3], 1)
            fb.edge:SetShown(not self.selected)
            fb.hl:SetColorTexture(1, 1, 1, 0.22)
            fb.mark:Hide()
            fb.text:SetFontObject(red and "ThatLuckyBastardReceiptKeyLight" or "ThatLuckyBastardReceiptKey")
            fb.text:SetText(self.label:upper())
            fb.text:SetAlpha(self.on and 1 or 0.4)
        else
            fb.bg:SetColorTexture(1, 1, 1, self.selected and 0.16 or 0.08)
            fb.edge:Hide()
            fb.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.30)
            fb.mark:SetShown(self.selected and true or false)
            fb.text:SetFontObject("GameFontHighlightSmall")
            if self.tint then fb.text:SetTextColor(self.tint[1], self.tint[2], self.tint[3]) end
            fb.text:SetText(self.label)
            local alpha = (self.selected or not self.isTab) and 1 or 0.7
            fb.text:SetAlpha(self.on and alpha or 0.35)
        end
    end

    function b:SetLabel(label)
        self.label = label
        self.tpl:SetText(label)
        self:Paint()
    end
    function b:SetOn(on)
        self.on = on and true or false
        self.tpl:SetEnabled(on)
        self.flat:SetEnabled(on)
        self:Paint()
    end
    function b:SetFlat(flat)
        self.tpl:SetShown(not flat)
        self.flat:SetShown(flat)
        self.key = flat and ThemeName() == "receipt"
        self:Paint()
    end
    -- Colours the label in both looks (a little lighter under the mouse on
    -- the game-styled one, which keeps the game's grey while it is off).
    function b:SetTextColor(r, g, bl)
        self.tint = { r, g, bl }
        self:Paint()
        if not CreateFont then return end
        local function Tinted(base, lighten)
            fontCount = fontCount + 1
            local font = CreateFont("ThatLuckyBastardButtonFont" .. fontCount)
            font:CopyFontObject(base)
            font:SetTextColor(r + (1 - r) * lighten, g + (1 - g) * lighten, bl + (1 - bl) * lighten)
            return font
        end
        self.tpl:SetNormalFontObject(Tinted(GameFontNormal, 0))
        self.tpl:SetHighlightFontObject(Tinted(GameFontHighlight, 0.3))
    end
    -- For tabs and toggles: marks the button as the current choice. The
    -- other buttons of the set stay fully readable.
    function b:SetSelected(selected)
        self.selected = selected and true or false
        self.tpl.mark:SetShown(selected)
        if selected then self.tpl:LockHighlight() else self.tpl:UnlockHighlight() end
        self:Paint()
    end
    b:Paint()
    ns.OnAccent(function() b:Paint() end)
    if not parent then buttons[#buttons + 1] = b end
    return b
end

-- Moves to an older (+1) or newer (-1) run.
local function Step(by)
    viewIndex = viewIndex + by
    currentRun = nil -- a deliberate move: do not follow the run that was on show
    if ns.HideItemMenu then ns.HideItemMenu() end -- it was for the run that was on show
    Render()
end

local older = MakeButton("< Older", 70, function() Step(1) end)
older:SetPoint("BOTTOMLEFT", 12, 10)
local newer = MakeButton("Newer >", 70, function() Step(-1) end)
newer:SetPoint("LEFT", older, "RIGHT", 4, 0)

-- Pin: the run on show is never deleted, whatever clears the history.
-- Delete: remove just that run (asks first; not for a pinned run).
local pinBtn = MakeButton("Pin", 60, function() ns.TogglePin(currentRun) end)
pinBtn:SetPoint("LEFT", newer, "RIGHT", 12, 0)
local deleteBtn = MakeButton("Delete", 60, function() ns.AskDeleteRun(currentRun) end)
deleteBtn:SetPoint("LEFT", pinBtn, "RIGHT", 4, 0)
deleteBtn:SetTextColor(1, 0.36, 0.32)
-- Reprice: today's auction prices put on the run on show (asks first; your
-- own runs, with a price addon). Kept on deleteBtn: this file is short of
-- names (Lua allows 200).
deleteBtn.reprice = MakeButton("Reprice", 70, function() ns.AskRepriceRun(currentRun) end)
deleteBtn.reprice:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

-- Bottom right, what is about the whole addon rather than the run on
-- show: Statistics (the tables over all runs) and the cogwheel that opens
-- the options (made further down), with the addon's version quietly
-- beside them.
local RIGHT_EDGE = -24 -- right margin of the buttons on the right, clear of the resize grip
local COG = 22         -- the cogwheel's side, as high as a button
local statsBtn = MakeButton("Statistics", 80, function() ns.ToggleBrowse() end)
statsBtn:SetPoint("BOTTOMRIGHT", RIGHT_EDGE - COG - 4, 10)

local versionLabel = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
versionLabel:SetPoint("RIGHT", statsBtn, "LEFT", -10, 0)
versionLabel:SetText(ns.VERSION ~= "" and ("v" .. ns.VERSION) or "")

-- Top row, all about the run on show: buttons of one size side by side
-- (the first is placed by ApplyTheme):
--   Front page, Analysis
--                a window of its own each (Analysis: its timeline, rolls
--                and numbers; who needed what is under its Rolls)
--   Meter        the loot meter (Meter.lua), for the run in progress
--   Bet          your call on the lucky bastard (Bets.lua; not there
--                while bets are switched off)
--   Expand all   opens every player's loot (only in the list view)
-- and on its own on the right, Share: the run on show as a link in chat
-- or as a code (Share.lua). Each button closes its window again on a
-- second click. Six of them and Share fit the narrowest window.
local TOP_W, TOP_GAP = 80, 4
local topRow = {}
local function TopButton(label, onClick)
    local b = MakeButton(label, TOP_W, onClick)
    if topRow[1] then b:SetPoint("LEFT", topRow[#topRow], "RIGHT", TOP_GAP, 0) end
    topRow[#topRow + 1] = b
    return b
end
local pageBtn = TopButton("Front page", function() ns.ToggleRunWindow("paper", ns.ViewedRun()) end)
local analysisBtn = TopButton("Analysis", function() ns.ToggleRunWindow("analysis", ns.ViewedRun()) end)
f.meterBtn = TopButton("Meter", function() ns.ToggleMeter() end)
local betBtn = TopButton("Bet", function() ns.ToggleBet(ns.ViewedRun()) end)
local shareBtn = MakeButton("Share", TOP_W, function() ns.ToggleShare(ns.ViewedRun()) end)
shareBtn.loud = true -- a red key in the Receipt theme

-- Placed in Render, after the last button shown (Bet may be hidden); in
-- the list view only.
local expandAll = MakeButton("Expand all", TOP_W, function()
    local s = currentRun
    if not s then return end
    local anyClosed = false
    for name in pairs(s.players) do
        if not expanded[name] then anyClosed = true end
    end
    for name in pairs(s.players) do expanded[name] = anyClosed or nil end
    Render()
end)

local runLabel = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
runLabel:SetPoint("LEFT", deleteBtn.reprice, "RIGHT", 10, 0)
runLabel:SetPoint("RIGHT", versionLabel, "LEFT", -10, 0)
runLabel:SetJustifyH("LEFT")
runLabel:SetWordWrap(false)
-- What the mini window does without: the bar at the foot of the window.
f.footRow = { older, newer, pinBtn, deleteBtn, deleteBtn.reprice, runLabel, versionLabel, statsBtn, f.grip }
-- The cogwheel that opens the options: at the foot of the full window,
-- right of Statistics; in the mini window, which has no foot, in the
-- title bar beside the cross (and so the way out of mini mode). Render
-- places and draws it: the game's gear icon in Classic, our own flat gear
-- elsewhere (white in Modern, ink on a till key in Receipt), with a wash
-- under the mouse.
do
    local cog = CreateFrame("Button", nil, ui)
    cog.cog = true
    cog.face = cog:CreateTexture(nil, "BACKGROUND")
    cog.face:SetAllPoints()
    cog.edge = cog:CreateTexture(nil, "BORDER")
    cog.edge:SetPoint("BOTTOMLEFT")
    cog.edge:SetPoint("BOTTOMRIGHT")
    cog.edge:SetHeight(3)
    cog.hl = cog:CreateTexture(nil, "HIGHLIGHT")
    cog.hl:SetAllPoints()
    cog.icon = cog:CreateTexture(nil, "ARTWORK")
    -- Its look in `theme`, at the size Render gave it. Under the mouse: a
    -- wash of the accent in Modern, of white elsewhere.
    function cog:Style(theme)
        local side, icon = self:GetHeight(), self.icon
        local flat, paper = theme.flat and true or false, theme.paper and true or false
        icon:ClearAllPoints()
        icon:SetTexture(flat and MEDIA .. "gear.tga" or "Interface\\Icons\\INV_Misc_Gear_01")
        if flat then icon:SetTexCoord(0, 1, 0, 1) else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        local inset = paper and 8 or flat and 6 or 4
        icon:SetSize(side - inset, side - inset)
        icon:SetPoint("CENTER", 0, paper and 1 or 0) -- on a key, above its lower edge
        self.face:SetShown(paper)
        self.edge:SetShown(paper)
        if paper then -- a till key, like the cross beside it in mini mode
            icon:SetVertexColor(INK[1], INK[2], INK[3], 1)
            self.face:SetColorTexture(KEY[1], KEY[2], KEY[3], 1)
            self.edge:SetColorTexture(KEY_EDGE[1], KEY_EDGE[2], KEY_EDGE[3], 1)
            self.hl:SetColorTexture(1, 1, 1, 0.22)
        else
            icon:SetVertexColor(1, 1, 1, 1)
            if flat then
                self.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
            else
                self.hl:SetColorTexture(1, 1, 1, 0.25)
            end
        end
    end
    cog:SetScript("OnClick", function() ns.ToggleOptions() end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Options")
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.cog = cog
end

----------------------------------------------------------------------
-- Themes
----------------------------------------------------------------------

local function ApplyTheme()
    currentTheme = ThemeName()
    theme = THEMES[currentTheme]
    Breakdown.theme = theme
    ns.ApplyWindowTheme(skins, title)

    for _, c in ipairs(cols) do c.glowClass = nil end -- the glow is drawn afresh

    pageBtn:ClearAllPoints()
    pageBtn:SetPoint("TOPLEFT", 12, theme.toolbarY)
    shareBtn:ClearAllPoints()
    shareBtn:SetPoint("TOPRIGHT", RIGHT_EDGE, theme.toolbarY)

    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, theme.scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", theme.scrollRight, 42)
    if scroll.ScrollBar then scroll.ScrollBar:SetAlpha(theme.flat and 0 or 1) end

    for _, h in ipairs(headers) do
        if theme.flat then h:SetTextColor(0.60, 0.63, 0.68) else h:SetTextColor(1, 0.82, 0) end
    end
    runLabel:SetFontObject(theme.paper and "ThatLuckyBastardReceiptCounter" or "GameFontHighlightSmall")
    for _, b in ipairs(buttons) do b:SetFlat(theme.flat) end
    for _, r in ipairs(rows) do StyleRow(r) end
    for _, c in ipairs(cols) do
        for _, r in ipairs(c.rows) do StyleHighlight(r) end
    end
end

function ns.SetTheme(name)
    if not THEMES[name] then return false end
    ns.db.theme = name
    ns.ApplyAccent() -- the accent is the Modern theme's to choose
    ns.Rerender()
    if ns.SyncOptions then ns.SyncOptions() end
    return true
end

----------------------------------------------------------------------
-- Render
----------------------------------------------------------------------

-- Draws the list view: one row per line of BuildLines.
local RenderList

-- Windows that follow the run on show (the Analysis window), and
-- the run they were last told about.
local runFollowers, followedRun = {}, nil
function ns.OnRunShown(fn)
    runFollowers[#runFollowers + 1] = fn
end

function Render()
    local o = ns.db.options
    drawing = true
    wipe(drawCache)
    if currentTheme ~= ThemeName() then ApplyTheme() end
    ns.ApplyScale()
    headers.market:SetText(o.valueMode == "vendor" and "Value" or "Market")

    -- The window shows a run, not a position: when the list shifts under
    -- it (a new run starts, another is deleted) it stays on its run.
    -- Position 1 is "the latest", and follows whatever that becomes.
    local runs = Runs()
    if currentRun and viewIndex > 1 and runs[viewIndex] ~= currentRun then
        for i, run in ipairs(runs) do
            if run == currentRun then viewIndex = i end
        end
    end
    viewIndex = math.max(1, math.min(viewIndex, math.max(#runs, 1)))
    local s = runs[viewIndex]
    currentRun = s
    if s ~= reveal.run then CancelReveal() end
    -- A run left while the window was not showing it (the core names it
    -- in ns.fresh) is revealed the first time it is on show, however it
    -- got there: the window opened, or stepped back to it.
    if s ~= nil and s == ns.fresh then
        ns.fresh = nil
        reveal.pending = true
    end

    older:SetOn(viewIndex < #runs)
    newer:SetOn(viewIndex > 1)
    local stored = s ~= nil and not s.example
    pinBtn:SetOn(stored and not s.sharedBy)
    pinBtn:SetLabel(s and s.pinned and "Unpin" or "Pin")
    pinOutline:SetShown(s ~= nil and s.pinned == true)
    deleteBtn:SetOn(stored and not s.pinned)
    deleteBtn.reprice:SetOn(ns.CanReprice(s))

    local sum
    if s then
        local tag = ""
        if s.example then
            tag = "  example data"
        elseif s.sharedBy then
            tag = "  shared by " .. ns.DisplayName(s.sharedBy)
        elseif ns.InProgress(s) then
            tag = "  in progress"
        end
        title:SetText(ns.Title(s.name or "Run"))
        runLabel:SetText(("%s  |cff909090(%d/%d)%s|r%s"):format(
            ns.DateText(s.startedAt), viewIndex, #runs, tag,
            s.pinned and "  |cffffd100pinned|r" or ""))
        sum = ns.Summarize(s)
    end

    -- Awards only once the run is over (or for past and example runs).
    local awards = s and ns.RunAwards(s, sum) or {}
    shownAwards = awards
    local insights = s and o.showInsights and ns.RunInsights(s, sum) or nil
    if insights then
        insights.fair = ns.Fairness(sum)
        insights.streak = o.streak and ns.Streak(s) or nil
    end

    if not s then
        title:SetText(ns.Title())
        runLabel:SetText("")
    end

    -- One column per player; in a bigger group, for its top five, with the
    -- others on a bench under them. The list is for whoever chose it: in
    -- the options for every run, or with the bench's button for this one.
    local big = sum ~= nil and #sum.players > MAX_COLUMNS
    local mini = o.mini and true or false
    local useColumns = sum ~= nil and o.useColumns and #sum.players > 0 and not (big and listRuns[s])
    -- Mini mode: in place of the columns, a row of small cards (the
    -- bench's: picture, name, award, total) for up to five players, under
    -- the title bar alone. The window has no rows of buttons then, only
    -- the cogwheel beside its cross, and is as big as its cards. With more
    -- players the row ends with an arrow that shows the run as a list, in
    -- the full window, whose Columns arrow leads back.
    local small = useColumns and mini
    for _, b in ipairs(topRow) do b:SetShown(not small) end
    betBtn:SetShown(not small and o.bets and true or false)
    shareBtn:SetShown(not small)
    for _, w in ipairs(f.footRow) do w:SetShown(not small) end
    scroll:ClearAllPoints()
    if small then
        scroll:SetPoint("TOPLEFT", 12, theme.flat and -46 or -30)
        scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    else
        scroll:SetPoint("TOPLEFT", 12, theme.scrollTop)
        scroll:SetPoint("BOTTOMRIGHT", theme.scrollRight, 42)
        -- Out of mini mode, the window first takes back the size it had,
        -- so that what follows is drawn for it.
        if f.full then
            if f.SetResizeBounds then f:SetResizeBounds(620, 320, 1100, 1000) end
            f:SetSize(f.full[1], f.full[2])
            f.full = nil
            title:SetWidth(0) -- as long as it is
        end
        -- The width there is to draw in: the window's, less its margins.
        content:SetWidth(f:GetWidth() - 12 + theme.scrollRight)
    end
    if scroll.ScrollBar then scroll.ScrollBar:SetAlpha((theme.flat or small) and 0 or 1) end
    -- The cogwheel: at the foot of the full window, where its buttons are;
    -- in the mini window, beside the cross (smaller and nearer the corner
    -- on Classic's title bar, which is the game's own and lower).
    local cog = f.cog
    cog:ClearAllPoints()
    if not small then
        cog:SetSize(COG, COG)
        cog:SetPoint("BOTTOMRIGHT", RIGHT_EDGE, 10)
    elseif theme.flat then
        cog:SetSize(COG, COG)
        cog:SetPoint("TOPRIGHT", -34, -7)
    else
        cog:SetSize(18, 18)
        cog:SetPoint("TOPRIGHT", -26, -2)
    end
    cog:Style(theme)
    -- The list view honours the same "show" options as the columns.
    local showVendor = o.showVendor and o.valueMode ~= "vendor"
    local showShare = o.showShare
    for _, h in ipairs(headers) do h:SetShown(not useColumns) end
    headers.vendor:SetShown(not useColumns and showVendor)
    headers.share:SetShown(not useColumns and showShare)
    headers.diff:SetShown(not useColumns and showShare)
    expandAll:SetShown(not useColumns)
    expandAll:ClearAllPoints()
    expandAll:SetPoint("LEFT", betBtn:IsShown() and betBtn or f.meterBtn, "RIGHT", TOP_GAP, 0)
    -- Receipt theme: receipts come out of a printer slot; the list is
    -- printed on one long sheet.
    local paper = theme.paper and true or false
    slot:SetShown(paper and useColumns and not small)
    slotLip:SetShown(paper and useColumns and not small)
    listPaper:SetShown(paper and not useColumns)
    if small then
        -- No columns, so no reveal either.
        reveal.pending = false
        CancelReveal()
        for _, r in ipairs(rows) do r:Hide() end
        for _, c in ipairs(cols) do c:Hide() end
        for _, fs in ipairs(footLines) do fs:Hide() end
        ShowBackButton(false)
        -- As many cards as there are players, up to the columns' five,
        -- and the title bar says where: there is no room for more.
        local n = math.min(#sum.players, MAX_COLUMNS)
        local wide = math.max(MINI_W - 24, BenchRoom(n, #sum.players > n))
        content:SetWidth(wide)
        local high = RenderBench(sum.players, awards, 0, paper, true) - 10
        content:SetHeight(high)
        title:SetText(("|T%s:16:16:0:0|t %s"):format(ns.LOGO, ns.ShortName(s)))
        title:SetWidth(math.max(20, wide - 54)) -- cut short before the cogwheel and the cross
        -- The window is as big as its cards, there and then: its own size
        -- is set aside for when they are no longer on show (the list, or
        -- the mode switched off). It may be smaller than a window can be
        -- dragged to.
        f.full = f.full or { f:GetWidth(), f:GetHeight() }
        if f.SetResizeBounds then f:SetResizeBounds(MINI_W, 80, 1100, 1000) end
        f:SetSize(wide + 24, high + (theme.flat and 46 or 30) + 12)
    elseif useColumns then
        for _, r in ipairs(rows) do r:Hide() end
        ShowBackButton(false)
        RenderColumns(sum, awards, insights)
    else
        -- The reveal only exists in the column view: one under way stops,
        -- sounds and screenshot included.
        reveal.pending = false
        CancelReveal()
        for _, c in ipairs(cols) do c:Hide() end
        for _, fs in ipairs(footLines) do fs:Hide() end
        HideBench()
        -- Only its bench can have made a list of a run the options give
        -- columns to: that run gets the way back.
        local top = ShowBackButton(big and o.useColumns and true or false)
        Breakdown.ink = paper
        RenderList(sum and BuildLines(sum, awards, insights) or {
            { indent = 4, wide = true, label = "No run recorded yet. Enter a dungeon, or type /tlb start." },
        }, showVendor, showShare, top)
        Breakdown.ink = false
    end
    title:SetWordWrap(false)
    drawing = false
    wipe(drawCache)
    if s ~= followedRun then
        followedRun = s
        for _, fn in ipairs(runFollowers) do fn(s) end
    end
end

local PLAYER_ROW_EXTRA = 14 -- player rows are taller, to hold the picture

-- `top`: room to leave above the first line (see ShowBackButton).
function RenderList(lines, showVendor, showShare, top)
    local o = ns.db.options
    local rowH = theme.rowH
    local playerH = rowH + PLAYER_ROW_EXTRA
    local width = content:GetWidth()
    local y = top or 0
    for i, line in ipairs(lines) do
        local r = GetRow(i)
        local h = line.p and playerH or rowH
        r.line = line
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", 0, -y)
        r:SetHeight(h)
        y = y + h

        -- Whatever sits left of the label pushes it to the right.
        local left = line.indent or 4

        local showPicture = line.p ~= nil and o.portrait ~= "none"
        if showPicture then
            local size = h - 10
            r.portrait:SetSize(size, size)
            r.ring:SetSize(size + 6, size + 6)
            r.ringInner:SetSize(size + 2, size + 2)
            r.ring:SetVertexColor(ClassRGB(line.p.class))
            -- No 3D models in the list: both picture modes use the portrait.
            local unit = o.portrait ~= "class" and UnitForName(line.p.name) or nil
            if unit and not InSight(unit) then unit = nil end
            FillPortrait(r.portrait, line.p, unit)
            left = size + 18
        end
        r.portrait:SetShown(showPicture)
        r.portrait:SetDesaturated(theme.paper and true or false) -- printed, on paper
        r.ring:SetShown(showPicture)
        r.ringInner:SetShown(showPicture)

        -- Paper has no icons and no colour chips.
        if line.icon and o.showIcons and not theme.paper then
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", left, 0)
            r.icon:SetSize(h - 4, h - 4)
            r.icon:SetTexture(ItemIcon(line.link))
            r.icon:Show()
            left = left + h
        else
            r.icon:Hide()
        end

        if line.cat and not theme.paper then
            r.chip:ClearAllPoints()
            r.chip:SetPoint("LEFT", left - 8, 0)
            r.chip:SetSize(3, h - 4)
            r.chip:SetColorTexture(line.cat.color[1], line.cat.color[2], line.cat.color[3], 0.9)
            r.chip:Show()
        else
            r.chip:Hide()
        end

        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", left, 0)
        if line.wide then
            r.label:SetPoint("RIGHT", -4, 0) -- a note: no figures to make room for
        else
            r.label:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
        end
        r.label:SetText(line.label or "")
        r.count:SetText(line.count or "")
        r.vendor:SetText(showVendor and line.vendor or "")
        r.market:SetText(line.market or "")
        r.diff:SetText(showShare and line.diff or "")
        r.share:SetText(showShare and line.share or "")
        r.label:SetAlpha(line.dim and 0.5 or 1)
        r.icon:SetAlpha(line.dim and 0.5 or 1)
        SetMark(r.mark, line.mark)
        SetRowBg(r.bg, line)
        if theme.flat and line.frac and line.frac > 0 then
            if theme.paper then
                r.bar:SetColorTexture(INK[1], INK[2], INK[3], 0.10)
            else
                r.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
            end
            r.bar:SetWidth(math.max(1, width * line.frac))
            r.bar:Show()
        else
            r.bar:Hide()
        end
        r:EnableMouse(line.player ~= nil or line.link ~= nil)
        r:Show()
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(y, 1))
end

-- Redraws soon. Loot arrives in bursts, so several requests become one draw.
local REFRESH_DELAY = 0.1

function ns.Refresh()
    if ns.MeterRefresh then ns.MeterRefresh() end -- the meter keeps up, whether this window is open or not
    if pending or not f:IsShown() then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, function()
        pending = false
        if f:IsShown() then Render() end
    end)
end

-- The other windows register a "redraw if shown" function here.
local redraws = {}
function ns.OnRerender(fn)
    redraws[#redraws + 1] = fn
end

-- Immediate redraw of every window that is open: used when an option or
-- the theme changes, when a run is pinned or deleted, and when an item is
-- switched to its other price. (New loot only redraws this window: see
-- ns.Refresh.)
-- A new accent colour: the theme is applied afresh at the next draw,
-- for what it paints in that colour.
ns.OnAccent(function() currentTheme = nil end)

function ns.Rerender()
    ns.ApplyScale()
    if f:IsShown() then Render() end
    for _, fn in ipairs(redraws) do fn() end
end

-- Opens the window on the latest run, or on run `s`. ceremony: reveal
-- the run (used when the window opens by itself as a run is left; a run
-- left unseen is revealed when it comes on show: see Render).
function ns.ShowWindow(ceremony, s)
    viewIndex, currentRun = 1, nil
    for i, run in ipairs(s and Runs() or {}) do
        if run == s then viewIndex = i end
    end
    reveal.pending = ceremony and true or false
    if ns.HideItemMenu then ns.HideItemMenu() end
    RestoreWindow()
    f:Show()
    f:Raise() -- above the other windows, which may have been opened since
    Render()
end

function ns.ToggleWindow()
    if f:IsShown() then f:Hide() else ns.ShowWindow() end
end

-- Opens the window on one particular run (used by the statistics).
function ns.ShowRun(s)
    ns.ShowWindow(false, s)
end

-- The run on show in this window; the most recent one when the window is
-- closed, or if its run has been deleted since.
function ns.ViewedRun()
    local runs = Runs()
    if f:IsShown() then
        for _, run in ipairs(runs) do
            if run == currentRun then return run end
        end
    end
    return runs[1]
end

-- Shared with the other panels.
ns.MoneyPlain = function(copper) return MoneyText(copper, false) end
ns.Signed, ns.FirstName = Signed, FirstName
ns.PlayKit = PlayKit
ns.CATS = CATS
ns.PAPER, ns.INK, ns.INK_GREY = PAPER, INK, INK_GREY
ns.Money = Money
ns.Duration = Duration
ns.ClassColored = ClassColored
ns.DisplayName = DisplayName
ns.ItemIcon = ItemIcon
ns.MakeButton = MakeButton
