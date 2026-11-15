local _, ns = ...

-- Export window: a box of comma-separated text, already selected, to be
-- copied with Ctrl+C and pasted into a spreadsheet. Nothing is written
-- to disk and nothing is sent anywhere. The text comes from Data.lua.

local WIDTH, HEIGHT = 640, 420

local ex = CreateFrame("Frame", "FairShareExportFrame", UIParent)
ex:SetSize(WIDTH, HEIGHT)
ex:SetPoint("CENTER", 0, 10)
ex:SetFrameStrata("FULLSCREEN_DIALOG")
ex:SetMovable(true)
ex:EnableMouse(true)
ex:SetClampedToScreen(true)
ex:RegisterForDrag("LeftButton")
ex:SetScript("OnDragStart", ex.StartMoving)
ex:SetScript("OnDragStop", ex.StopMovingOrSizing)
ex:Hide()
tinsert(UISpecialFrames, "FairShareExportFrame")

local skins = ns.BuildSkins(ex, function() ex:Hide() end)

local ui = CreateFrame("Frame", nil, ex)
ui:SetAllPoints()
ui:SetFrameLevel(ex:GetFrameLevel() + 10)

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local hint = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetJustifyH("LEFT")

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local box = CreateFrame("EditBox", nil, scroll)
box:SetMultiLine(true)
box:SetAutoFocus(false)
box:SetFontObject("ChatFontNormal")
box:SetWidth(WIDTH - 60)
box:SetScript("OnEscapePressed", function() ex:Hide() end)
scroll:SetScrollChild(box)

local boxBg = ui:CreateTexture(nil, "BACKGROUND")
boxBg:SetColorTexture(0, 0, 0, 0.35)
boxBg:SetPoint("TOPLEFT", scroll, -4, 4)
boxBg:SetPoint("BOTTOMRIGHT", scroll, 4, -4)

local function ApplyTheme()
    local flat = ns.db.theme == "modern"
    local active = flat and skins.modern or skins.classic
    for _, skin in pairs(skins) do skin:SetShown(skin == active) end

    title:ClearAllPoints()
    if flat then
        title:SetFontObject("GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -10)
    else
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOP", 0, -5)
    end

    local top = flat and -46 or -32
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", 16, top)
    hint:SetPoint("TOPRIGHT", -16, top)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 16, top - 24)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
end

-- kind: "run" (every item of the run `s`) or "all" (one line per player
-- of every run that is kept).
function ns.ShowExport(kind, s)
    local text
    if kind == "all" then
        text = ns.ExportAll()
        title:SetText("FairShare - Export - all runs")
    elseif s then
        text = ns.ExportRun(s)
        title:SetText("FairShare - Export - " .. (s.name or "Run"))
    else
        return
    end
    local _, lines = text:gsub("\n", "\n")
    hint:SetText(("%d lines, selected. Press |cffffd100Ctrl+C|r to copy, then paste into a spreadsheet."):format(lines + 1))
    ApplyTheme()
    ex:Show()
    ex:Raise()
    box:SetText(text)
    box:SetFocus()
    box:HighlightText()
end
