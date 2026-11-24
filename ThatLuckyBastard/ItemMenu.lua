local _, ns = ...

-- The item menu: a right-click on an item in the run window opens it, for
-- that player's copies of the item in that run.
--   Auction price / Vendor price   the item's price, for every copy in the run
--   Ignore                         listed, but worth nothing
--   Split with                     its value shared equally by the players
--                                  ticked, its looter among them or not
-- A change shows at once in every window. It is drawn by the addon in the
-- theme in force, and nothing is sent anywhere.

local ROW_H = 20
local PAD = 14
local MIN_W = 230
local COL_W = 160    -- a column of players
local PER_COLUMN = 10

local menu, ui, title, skins = ns.MakeWindow("ThatLuckyBastardItemMenu", MIN_W, 160, "DIALOG", true)

local run, entry, looter -- the run, the item entry (a real one) and who looted it
local open = false       -- the list of players to split with is open

local checks, links = {}, {}
local rule = ui:CreateTexture(nil, "ARTWORK")
rule:SetHeight(1)

local function Changed()
    ns.Rerender() -- every window, this one included (see the end of this file)
end

----------------------------------------------------------------------
-- Controls: a tick box or round button with a label, and a plain
-- clickable word.
----------------------------------------------------------------------

local function Check(i)
    local b = checks[i]
    if b then return b end
    b = CreateFrame("Button", nil, ui)
    b:SetHeight(ROW_H)
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetPoint("CENTER", b.box)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.text:SetAlpha(1) end end)
    b:SetScript("OnLeave", function(self) if self:IsEnabled() then self.text:SetAlpha(0.9) end end)
    checks[i] = b
    return b
end

-- As the options draw them: flat squares in the flat themes, the game's
-- own boxes in Classic.
local function StyleCheck(b, flat, radio)
    b.box:ClearAllPoints()
    if flat then
        b.box:SetPoint("LEFT", 5, 0)
        b.box:SetSize(12, 12)
        b.box:SetTexCoord(0, 1, 0, 1)
        b.box:SetColorTexture(1, 1, 1, 0.12)
        b.tick:SetSize(radio and 6 or 8, radio and 6 or 8)
        b.tick:SetTexCoord(0, 1, 0, 1)
        local accent = ns.ThemeAccent()
        b.tick:SetColorTexture(accent[1], accent[2], accent[3], 1)
    elseif radio then
        b.box:SetPoint("LEFT", 3, 0)
        b.box:SetSize(16, 16)
        b.box:SetTexture("Interface\\Buttons\\UI-RadioButton")
        b.box:SetTexCoord(0, 0.25, 0, 1)
        b.tick:SetSize(16, 16)
        b.tick:SetTexture("Interface\\Buttons\\UI-RadioButton")
        b.tick:SetTexCoord(0.25, 0.5, 0, 1)
    else
        b.box:SetPoint("LEFT", -1, 0)
        b.box:SetSize(22, 22)
        b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        b.box:SetTexCoord(0, 1, 0, 1)
        b.tick:SetSize(22, 22)
        b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b.tick:SetTexCoord(0, 1, 0, 1)
    end
end

local function Link(i)
    local b = links[i]
    if b then return b end
    b = CreateFrame("Button", nil, ui)
    b:SetHeight(ROW_H)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT")
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    b:SetScript("OnEnter", function(self) self.text:SetAlpha(1) end)
    b:SetScript("OnLeave", function(self) self.text:SetAlpha(self.rest or 0.75) end)
    links[i] = b
    return b
end

----------------------------------------------------------------------
-- What the item is now, and the changes
----------------------------------------------------------------------

-- The players its value goes to now: its split, or its looter alone.
local function Holders()
    local set = {}
    for _, name in ipairs(entry.split or { looter }) do set[name] = true end
    return set
end

local function SplitWith(set)
    local names = {}
    for name in pairs(set) do names[#names + 1] = name end
    ns.SetSplit(run, entry, looter, names)
    Changed()
end

-- The run's players, its looter first, then by name.
local function Players()
    local names = {}
    for name in pairs(run.players) do
        if name ~= looter then names[#names + 1] = name end
    end
    table.sort(names)
    table.insert(names, 1, looter)
    return names
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Build()
    local flat, top = ns.ApplyWindowTheme(skins, title)
    title:SetText(entry.link)
    ns.MarkPrice(run, entry)
    local nCheck, nLink = 0, 0
    local y = top - 4
    local function Add(label, on, click, radio, enabled, x, width, at)
        nCheck = nCheck + 1
        local b = Check(nCheck)
        StyleCheck(b, flat, radio)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x or PAD, at or y)
        b:SetWidth(width or (MIN_W - 2 * PAD))
        b.text:SetText(label)
        b.text:SetPoint("RIGHT", 0, 0)
        b.tick:SetShown(on)
        b:SetEnabled(enabled ~= false)
        b.text:SetAlpha(enabled ~= false and 0.9 or 0.4)
        b.box:SetAlpha(enabled ~= false and 1 or 0.4)
        b.onClick = click
        b:Show()
        return b
    end

    -- The price, for every copy in the run.
    local vendorMode = ns.db.options.valueMode == "vendor"
    local auction = entry.ah ~= nil and not vendorMode
    local onAuction = auction and not entry.noAH
    Add("Auction price", onAuction, function()
        if not onAuction then ns.ToggleAuctionPrice(run, entry) Changed() end
    end, true, auction)
    y = y - ROW_H
    Add("Vendor price", not onAuction, function()
        if onAuction then ns.ToggleAuctionPrice(run, entry) Changed() end
    end, true, auction)
    y = y - ROW_H - 6
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", PAD, y + 3)
    rule:SetPoint("TOPRIGHT", -PAD, y + 3)
    rule:SetColorTexture(1, 1, 1, 0.12)
    y = y - 4

    -- Ignore: the box for every copy; for a stack, - and + say how many.
    local ignored, count = ns.IgnoredCopies(entry), entry.count
    Add("Ignore", ignored >= count, function()
        ns.ToggleIgnore(entry)
        Changed()
    end, nil, nil, nil, count > 1 and 80 or nil)
    if count > 1 then
        local x = PAD + 84
        for _, step in ipairs({ { "-", -1 }, { ("%d/%d"):format(ignored, count) }, { "+", 1 } }) do
            nLink = nLink + 1
            local b = Link(nLink)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, y)
            b.text:SetText(step[1])
            b:SetWidth(b.text:GetStringWidth() + 8)
            local by = step[2]
            local stuck = by and (ignored + by < 0 or ignored + by > count)
            b.rest = (stuck and 0.3) or (by and 0.75) or 0.9
            b.text:SetAlpha(b.rest)
            b.onClick = by and not stuck and function()
                ns.SetIgnored(entry, ignored + by)
                Changed()
            end or nil
            b:Show()
            x = x + b:GetWidth() + 4
        end
    end
    y = y - ROW_H

    -- Split with: a heading that opens the list of players.
    nLink = nLink + 1
    local head = Link(nLink)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", PAD + 5, y)
    head.text:SetText(open and "Split with:" or "Split with...")
    head:SetWidth(head.text:GetStringWidth() + 4)
    head.rest = 0.9
    head.text:SetAlpha(head.rest)
    head.onClick = function()
        open = not open
        Build()
    end
    head:Show()
    y = y - ROW_H

    local width = MIN_W
    if open then
        local holders = Holders()
        local names = Players()
        local columns = math.ceil(#names / PER_COLUMN)
        for i, name in ipairs(names) do
            local col, row = math.floor((i - 1) / PER_COLUMN), (i - 1) % PER_COLUMN
            local p = run.players[name]
            Add(ns.ClassColored(ns.DisplayName(name), p.class), holders[name] == true, function()
                local set = Holders()
                set[name] = (not set[name]) or nil
                SplitWith(set)
            end, false, true, PAD + 8 + col * COL_W, COL_W - 8, y - row * ROW_H)
        end
        y = y - math.min(#names, PER_COLUMN) * ROW_H - 4
        width = math.max(MIN_W, 2 * PAD + 8 + columns * COL_W)

        -- Everyone, and back to its looter alone.
        local x = PAD + 13
        for _, choice in ipairs({ { "Everyone", function()
                                      local set = {}
                                      for name in pairs(run.players) do set[name] = true end
                                      SplitWith(set)
                                  end },
                                  { "Not split", function() SplitWith({}) end } }) do
            nLink = nLink + 1
            local b = Link(nLink)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, y)
            b.text:SetText(choice[1])
            b:SetWidth(b.text:GetStringWidth() + 4)
            b.text:SetAlpha(0.75)
            b.onClick = choice[2]
            b:Show()
            x = x + b:GetWidth() + 18
        end
        y = y - ROW_H
    end

    for i = nCheck + 1, #checks do checks[i]:Hide() end
    for i = nLink + 1, #links do links[i]:Hide() end
    menu:SetSize(math.max(width, title:GetStringWidth() + 70), -y + PAD - 4)
end

-- Opens the menu on item entry `e` (a summary's stand-in or the entry
-- itself) of run `s`, next to the mouse.
function ns.ShowItemMenu(s, e)
    local real = ns.RealEntry(e)
    local owner = ns.EntryOwner(s, real)
    if not owner then return end
    if not (menu:IsShown() and entry == real) then open = real.split ~= nil end
    run, entry, looter = s, real, owner
    Build()
    local x, y = GetCursorPosition()
    local scale = menu:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 6, y / scale + 6)
    menu:Show()
    menu:Raise()
end

-- Closed when the run window moves to another run (Older, Newer, a run
-- opened from elsewhere), so a click never changes a run off screen.
function ns.HideItemMenu()
    menu:Hide()
end

-- Redrawn with every other window; gone with the run window, or with its
-- run (deleted, or no longer the one on show).
ns.OnRerender(function()
    if not menu:IsShown() then return end
    if not (ThatLuckyBastardFrame and ThatLuckyBastardFrame:IsShown()) or run ~= ns.ViewedRun() then
        menu:Hide()
        return
    end
    Build()
end)
