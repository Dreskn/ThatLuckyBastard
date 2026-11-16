local _, ns = ...

-- On-screen notices: a small box near the top of the screen, used for
-- valuable loot during a run and for bingo lines. It is drawn by the
-- addon itself and seen only by the player running it; nothing is sent
-- to chat. Several notices in a row are shown one after another.

local FADE_IN, HOLD, FADE_OUT = 0.25, 4, 0.6
local MAX_QUEUE = 5

local toast = CreateFrame("Frame", "ThatLuckyBastardToast", UIParent)
toast:SetSize(340, 40)
toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
toast:SetFrameStrata("DIALOG") -- above the addon's windows, which open as a run ends
toast:Hide()

local bg = toast:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.06, 0.07, 0.09, 0.88)

local edge = toast:CreateTexture(nil, "BORDER")
edge:SetPoint("TOPLEFT")
edge:SetPoint("BOTTOMLEFT")
edge:SetWidth(3)

local icon = toast:CreateTexture(nil, "ARTWORK")
icon:SetSize(30, 30)
icon:SetPoint("LEFT", 9, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local titleText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("TOPLEFT", 46, -6)
titleText:SetPoint("TOPRIGHT", -8, -6)
titleText:SetJustifyH("LEFT")
titleText:SetWordWrap(false)

local bodyText = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bodyText:SetPoint("BOTTOMLEFT", 46, 7)
bodyText:SetPoint("BOTTOMRIGHT", -8, 7)
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(false)

local queue = {}
local elapsed = 0

local function ShowNext()
    local item = table.remove(queue, 1)
    if not item then
        toast:Hide()
        return
    end
    edge:SetColorTexture(item.r, item.g, item.b, 1)
    icon:SetTexture(item.icon)
    titleText:SetText(item.title)
    bodyText:SetText(item.text)
    elapsed = 0
    toast:SetAlpha(0)
    toast:Show()
end

toast:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < FADE_IN then
        self:SetAlpha(elapsed / FADE_IN)
    elseif elapsed < FADE_IN + HOLD then
        self:SetAlpha(1)
    elseif elapsed < FADE_IN + HOLD + FADE_OUT then
        self:SetAlpha(1 - (elapsed - FADE_IN - HOLD) / FADE_OUT)
    else
        ShowNext() -- the next notice, or hide when there is none
    end
end)

-- A two-line notice with an icon. r, g, b colour its left edge (the
-- addon's accent colour by default). Dropped when too many are waiting.
function ns.Notice(title, text, iconTexture, r, g, b)
    if #queue >= MAX_QUEUE then return end
    queue[#queue + 1] = {
        title = title, text = text, icon = iconTexture,
        r = r or ns.ACCENT[1], g = g or ns.ACCENT[2], b = b or ns.ACCENT[3],
    }
    if not toast:IsShown() then ShowNext() end
end

-- Loot notice. value: what this pickup is worth, in copper.
function ns.Toast(name, class, link, count, value)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    ns.Notice(
        ns.ClassColored(ns.DisplayName(name), class) .. " |cffb0b0b0looted|r",
        (count > 1 and (count .. "x ") or "") .. link .. "   " .. ns.Money(value),
        ns.ItemIcon(link),
        c and c.r, c and c.g, c and c.b)
end
