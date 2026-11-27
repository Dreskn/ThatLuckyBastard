local _, ns = ...

-- A note on a run: one line of the player's own (ns.SetRunNote, Core),
-- typed in a box that opens over what was clicked: the run's label at the
-- foot of the breakdown, or the note box of the solo page. Enter keeps
-- it, Escape (or clicking elsewhere) lets it go; an empty note removes
-- the one there was. Shown after the label, on the solo page, and in
-- Statistics. Kept with the run, never shared: no code carries it.

local Breakdown = ns.Breakdown
local f = Breakdown.f

local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
box.noteBox = true
box:SetAutoFocus(false)
box:SetHeight(20)
box:SetMaxLetters(ns.NOTE_MAX)
box:SetFrameLevel(f:GetFrameLevel() + 20)
box:Hide()

local editing -- the run whose note is being typed

local function Close()
    editing = nil
    box:ClearFocus()
    box:Hide()
end
box:SetScript("OnEnterPressed", function(self)
    local s = editing
    local text = self:GetText()
    Close()
    if s then ns.SetRunNote(s, text) end
end)
box:SetScript("OnEscapePressed", Close)
box:SetScript("OnEditFocusLost", Close)

-- Opens the box over `anchor`, for run `s`.
function ns.EditNote(s, anchor)
    if not s or s.example then return end
    editing = s
    box:ClearAllPoints()
    box:SetPoint("LEFT", anchor, "LEFT", 6, 0)
    box:SetPoint("RIGHT", anchor, "RIGHT", -2, 0)
    box:SetText(s.note or "")
    box:Show()
    box:SetFocus()
end
ns.NoteBox = box -- for the tests

-- The run's label at the foot of the window: a click writes its note.
local label = CreateFrame("Button", nil, f)
label.noteLabel = true
label:SetPoint("TOPLEFT", Breakdown.runLabel, "TOPLEFT", -2, 4)
label:SetPoint("BOTTOMRIGHT", Breakdown.runLabel, "BOTTOMRIGHT", 2, -4)
label:SetScript("OnClick", function(self)
    local s = Breakdown.CurrentRun()
    if s and not s.example then ns.EditNote(s, self) end
end)
label:SetScript("OnEnter", function(self)
    local s = Breakdown.CurrentRun()
    if not s or s.example then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(s.note and "Edit the note" or "Write a note")
    GameTooltip:AddLine("One line of your own about this run. Never shared.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
label:SetScript("OnLeave", function() GameTooltip:Hide() end)
f.footRow[#f.footRow + 1] = label -- not in the mini window, like the label
Breakdown.noteLabel = label
