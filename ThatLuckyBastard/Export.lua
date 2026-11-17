local _, ns = ...

-- Export window: a box of text, already selected, to be copied with
-- Ctrl+C. Comma-separated text for a spreadsheet (from Data.lua), or a
-- run's share code (from Code.lua). Nothing is written to disk and
-- nothing is sent anywhere.

local WIDTH, HEIGHT = 640, 420

local ex, ui, title, skins = ns.MakeWindow("ThatLuckyBastardExportFrame", WIDTH, HEIGHT, "FULLSCREEN_DIALOG", true)
ex:SetPoint("CENTER", 0, 10)

local hint = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetJustifyH("LEFT")

local scroll = CreateFrame("ScrollFrame", nil, ui, "UIPanelScrollFrameTemplate")
local box = CreateFrame("EditBox", nil, scroll)
box:SetMultiLine(true)
box:SetMaxLetters(0) -- no limit: a code or an export can be long
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
    local _, top = ns.ApplyWindowTheme(skins, title)
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", 16, top)
    hint:SetPoint("TOPRIGHT", -16, top)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 16, top - 24)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
end

-- kind: "run" (every item of the run `s`), "all" (one line per player of
-- every run that is kept) or "code" (the share code of the run `s`).
function ns.ShowExport(kind, s)
    local text
    if kind == "all" then
        text = ns.ExportAll()
        title:SetText(ns.Title("Export  -  all runs"))
    elseif s and kind == "code" then
        text = ns.EncodeRun(s)
        title:SetText(ns.Title("Share code  -  " .. (s.name or "Run")))
    elseif s then
        text = ns.ExportRun(s)
        title:SetText(ns.Title("Export  -  " .. (s.name or "Run")))
    else
        return
    end
    if kind == "code" then
        hint:SetText(("%d characters selected. |cffffd100Ctrl+C|r to copy, then paste it anywhere."):format(#text))
    else
        local _, lines = text:gsub("\n", "\n")
        hint:SetText(("%d lines selected. |cffffd100Ctrl+C|r to copy."):format(lines + 1))
    end
    ApplyTheme()
    ex:Show()
    ex:Raise()
    box:SetText(text)
    box:SetFocus()
    box:HighlightText()
end

ns.OnRerender(function()
    if ex:IsShown() then ApplyTheme() end
end)
