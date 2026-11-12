local _, ns = ...

-- Minimap button: left-click opens the window, right-click the options,
-- drag moves it around the minimap. Shown or hidden by the showMinimap
-- option; its position is saved as an angle.

local b = CreateFrame("Button", "FairShareMinimapButton", Minimap)
b:SetSize(32, 32)
b:SetFrameStrata("MEDIUM")
b:SetFrameLevel(8)
b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
b:RegisterForDrag("LeftButton")
b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
b:Hide()

local background = b:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local icon = b:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = b:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function Place()
    local angle = math.rad(ns.db.options.minimapAngle or 215)
    local radius = Minimap:GetWidth() / 2 + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.options.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place()
end

b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        ns.ToggleOptions()
    else
        ns.ToggleWindow()
    end
end)

b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("FairShare")
    GameTooltip:AddLine("Left-click: loot breakdown", 1, 1, 1)
    GameTooltip:AddLine("Right-click: options", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
    GameTooltip:Show()
end)
b:SetScript("OnLeave", GameTooltip_Hide)

function ns.UpdateMinimapButton()
    if ns.db.options.showMinimap then
        Place()
        b:Show()
    else
        b:Hide()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", ns.UpdateMinimapButton)
