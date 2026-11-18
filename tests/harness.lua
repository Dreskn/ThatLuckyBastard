-- Stand-ins for the game, so the addon's files can be loaded and driven
-- outside it. Widgets accept any method; the few whose results the code
-- computes with return plausible values.

NOW = 1800000000          -- the clock, moved by the tests
function time() return NOW end
function GetTime() return NOW end
date = os.date
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
format, strsplit = string.format, nil
unpack = unpack or table.unpack

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------
local Widget = {}
local known = {}

local function NewWidget(kind, name)
    local w = { __kind = kind, __name = name, __scripts = {}, __shown = true, __text = "" }
    return setmetatable(w, Widget)
end

-- What a call to an unknown method returns, going by its name.
local function Default(key)
    if key:match("^Create") then return function() return NewWidget(key) end end
    if key:match("^Get") then return function() return 100 end end
    if key:match("^Is") or key:match("^Has") or key:match("^Can") then return function() return false end end
    return function() end
end

Widget.__index = function(self, key)
    if known[key] then return known[key] end
    if type(key) ~= "string" or not key:match("^[A-Z]") then return nil end
    -- Unknown capitalised member: usable both as a method and as a child
    -- widget (template parts such as CloseButton or ScrollBar).
    local member = NewWidget("member:" .. key)
    member.__call = Default(key)
    rawset(self, key, member)
    return member
end
Widget.__call = function(self, ...)
    local fn = rawget(self, "__call")
    if fn then return fn(...) end
    error("called a widget that is not a method: " .. tostring(self.__kind))
end

function known.SetScript(self, name, fn) self.__scripts[name] = fn end
function known.GetScript(self, name) return self.__scripts[name] end
function known.HookScript(self, name, fn) self.__scripts[name] = fn end
function known.Show(self)
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function known.Hide(self)
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function known.SetShown(self, on) if on then self:Show() else self:Hide() end end
function known.IsShown(self) return self.__shown end
function known.IsVisible(self) return self.__shown end
function known.SetText(self, text)
    self.__text = text == nil and "" or tostring(text)
    if TEXTLOG and self.__text ~= "" then TEXTLOG[#TEXTLOG + 1] = self.__text end
end
function known.GetText(self) return self.__text end
function known.SetAttribute(self, key, value)
    self.__attributes = self.__attributes or {}
    self.__attributes[key] = value
end
function known.GetAttribute(self, key) return self.__attributes and self.__attributes[key] end
-- The edit box that has the keyboard, if any.
function known.SetFocus(self) FOCUSED = self end
function known.ClearFocus(self) if FOCUSED == self then FOCUSED = nil end end
-- Anchors, as { point, relativeTo, relativePoint, x, y }.
function known.SetPoint(self, point, rel, relPoint, x, y)
    self.__points = self.__points or {}
    self.__points[#self.__points + 1] = { point, rel, relPoint, x, y }
end
function known.ClearAllPoints(self) self.__points = {} end
function known.SetWidth(self, w) self.__w = w end
function known.SetHeight(self, h) self.__h = h end
function known.SetSize(self, w, h) self.__w, self.__h = w, h end
function known.GetWidth(self) return self.__w or 700 end
function known.GetHeight(self) return self.__h or 400 end
function known.GetSize(self) return self.__w or 700, self.__h or 400 end
function known.GetStringHeight() return 12 end
function known.GetStringWidth(self) return #(self.__text or "") * 6 end
function known.GetFrameLevel() return 1 end
function known.SetScale(self, scale) self.__scale = scale end
function known.GetScale(self) return self.__scale or 1 end
-- The font a text was last given (a font object or its name), and whether
-- a picture is drawn in grey.
function known.SetFontObject(self, font) self.__font = font end
function known.GetFontObject(self) return self.__font end
function known.SetDesaturated(self, on) self.__desaturated = on and true or false end
function known.IsDesaturated(self) return self.__desaturated == true end
-- Whether a button can be clicked (greyed-out options cannot).
function known.SetEnabled(self, on) self.__enabled = on and true or false end
function known.IsEnabled(self) return self.__enabled ~= false end
function known.GetEffectiveScale() return 1 end
function known.GetFont() return "font", 12, "" end
function known.GetName(self) return self.__name end
function known.GetParent() return UIParent end
function known.GetCenter() return 500, 400 end
function known.GetLeft() return 100 end
function known.GetTop() return 600 end
function known.GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function known.GetNumPoints() return 1 end
function known.GetValue() return 1 end
function known.GetChecked() return false end
function known.GetUnit() return nil end
-- What players' pictures were drawn from: "model:<unit>", "portrait:<unit>"
-- or "class" (the class icon).
PICTURES = {}
function known.SetUnit(self, unit) PICTURES[#PICTURES + 1] = "model:" .. tostring(unit) end
function known.SetTexture(self, path)
    if path == "Interface\\TargetingFrame\\UI-Classes-Circles" then PICTURES[#PICTURES + 1] = "class" end
end
-- Which window is in front: its strata, then the latest to be raised.
RAISES = 0
function known.SetFrameStrata(self, strata) self.__strata = strata end
function known.Raise(self) RAISES = RAISES + 1; self.__raised = RAISES end
function known.GetItem() return nil end
function known.RegisterEvent(self, event) self.__events = self.__events or {}; self.__events[event] = true end
function known.CreateFontString() return NewWidget("FontString") end
function known.CreateTexture() return NewWidget("Texture") end
function known.CreateLine() return NewWidget("Line") end
function known.CreateMaskTexture() return NewWidget("Mask") end
function known.GetThumbTexture() return NewWidget("Texture") end
function known.GetFontString() return NewWidget("FontString") end
function known.GetHighlightTexture() return NewWidget("Texture") end
function known.GetNormalTexture() return NewWidget("Texture") end
function known.GetPushedTexture() return NewWidget("Texture") end

FRAMES = {}
function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name)
    w.__template, w.__parent = template, parent
    FRAMES[#FRAMES + 1] = w
    if name then _G[name] = w end
    return w
end

function CreateFont(name)
    local font = NewWidget("Font", name)
    _G[name] = font
    return font
end

UIParent = NewWidget("UIParent")
GameTooltip = NewWidget("GameTooltip")
ItemRefTooltip = NewWidget("GameTooltip")
Minimap = NewWidget("Minimap")
TIP = {}   -- lines added to the tooltip since it was last cleared
function GameTooltip:AddLine(text) TIP[#TIP + 1] = tostring(text) end
function GameTooltip:AddDoubleLine(a, b) TIP[#TIP + 1] = tostring(a) .. " | " .. tostring(b) end
function GameTooltip:SetOwner() TIP = {} end
function GameTooltip:SetHyperlink(link) TIP[#TIP + 1] = "<" .. tostring(link) .. ">" end
function GameTooltip_Hide() end

UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
-- The confirmations asked for: { which, a, b, data }. Answering one is
-- calling StaticPopupDialogs[which].OnAccept.
POPUPS = {}
function StaticPopup_Show(which, a, b, data)
    POPUPS[#POPUPS + 1] = { which = which, a = a, b = b, data = data }
    return NewWidget("StaticPopup")
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
YES, NO, UNKNOWNOBJECT = "Yes", "No", "Unknown"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
SOUNDKIT = {}
function PlaySound() end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function Screenshot() end
function IsModifiedClick() return false end
function GetCursorPosition() return 0, 0 end
function UIFrameFadeIn() end
function GetCoinTextureString(c) return tostring(c) .. "c" end
function GetCVar() return "1" end
function GetCVarBool() return true end
function SetPortraitTexture(tex, unit) PICTURES[#PICTURES + 1] = "portrait:" .. tostring(unit) end
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 0.25, 0, 0.25 } end })
function GetRealZoneText() return "Somewhere" end

TIMERS = {}
C_Timer = { After = function(delay, fn) TIMERS[#TIMERS + 1] = fn end }
function RunTimers()
    for round = 1, 20 do
        if #TIMERS == 0 then return end
        local batch = TIMERS
        TIMERS = {}
        for _, fn in ipairs(batch) do fn() end
    end
end

-- The tooltip hooks: remember what the addon registers.
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TOOLTIP_HOOKS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TOOLTIP_HOOKS[kind] = fn end }

----------------------------------------------------------------------
-- The world: who we are, where we are, who is with us
----------------------------------------------------------------------
WORLD = { inInstance = false, instance = "Test Keep", instanceID = 9001, dead = false,
          me = "Mira Vale", party = {} } -- party: { { name, class, role }, ... }

local function PartyMember(unit)
    local i = tonumber(unit:match("^party(%d+)$"))
    return i and WORLD.party[i]
end
function UnitName(unit) if unit == "player" then return "Mira", "Vale" end local m = PartyMember(unit) return m and m[1] end
function GetUnitName(unit)
    if unit == "player" then return WORLD.me end
    if unit == "target" then return WORLD.target end
    local m = PartyMember(unit)
    return m and m[1]
end
function UnitClass(unit) if unit == "player" then return "Shaman", "SHAMAN" end local m = PartyMember(unit) return m and m[2], m and m[2] end
function UnitExists(unit) return unit == "player" or PartyMember(unit) ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsPlayer() return true end
function UnitGUID(unit) return 'Player-1-' .. tostring(unit) end
function UnitIsVisible() return WORLD.visible == true end -- close enough to be drawn
function UnitIsDeadOrGhost() return WORLD.dead end
function UnitGroupRolesAssigned(unit) if unit == "player" then return "HEALER" end local m = PartyMember(unit) return m and m[3] or "NONE" end
function GetNumGroupMembers() return #WORLD.party end
function IsInRaid() return false end
function IsInGroup() return #WORLD.party > 0 end
function IsInInstance() return WORLD.inInstance, WORLD.inInstance and "party" or "none" end
function GetInstanceInfo() return WORLD.instance, "party", 1, "Normal", 5, 0, false, WORLD.instanceID end

-- Items: [id] = { quality, sell price, classID, bindType }. An item
-- string (no link) gets a full link back, as in the game.
ITEMS = {}
function GetItemInfo(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    local it = id and ITEMS[id]
    if not it then return end
    if not tostring(link):find("|H", 1, true) then
        link = ("|cnIQ%d:|H%s|h[Thing %d]|h|r"):format(it[1], link, id)
    end
    return "Item " .. id, link, it[1], 30, 25, "Type", "Sub", 1, "", 134400, it[2], it[3], 0, it[4]
end
function ItemLink(id, name, quality)
    return ("|cnIQ%d:|Hitem:%d::::::::38:1489:::::::::|h[%s]|h|r"):format(quality or 1, id, name)
end

-- Chat and addon messages, recorded so the tests can deliver them.
SENT = {}         -- addon messages: { prefix, text, channel, target }
CHAT_FILTERS = {} -- [event] = the filter the addon added
OPENED_CHAT = {}  -- text put in the chat box
CHAT_SENT = {}    -- chat lines the addon sent itself: { text, chatType, target }
function SendChatMessage(text, chatType, _, target) CHAT_SENT[#CHAT_SENT + 1] = { text, chatType, target } end
C_Club = { SendMessage = function(club, stream, text) CHAT_SENT[#CHAT_SENT + 1] = { text, "CLUB", club .. ":" .. stream } end }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target) SENT[#SENT + 1] = { prefix, text, channel, target } end,
}
function ChatFrame_AddMessageEventFilter(event, fn) CHAT_FILTERS[event] = fn end
function ChatFrame_OpenChat(text) OPENED_CHAT[#OPENED_CHAT + 1] = text end
function SetItemRef() end
function hooksecurefunc(name, fn)
    local real = _G[name]
    _G[name] = function(...) real(...); fn(...) end
end
function Ambiguate(name) return name end
function IsInGuild() return WORLD.guild == true end
C_GuildInfo = { IsGuildOfficer = function() return WORLD.officer == true end }
-- Friends and guild members: WORLD.friends = { name, ... }, WORLD.roster
-- = { { name, classFile }, ... }.
C_FriendList = {
    GetNumFriends = function() return #(WORLD.friends or {}) end,
    GetFriendInfoByIndex = function(i)
        local name = (WORLD.friends or {})[i]
        return name and { name = name, connected = true }
    end,
}
function GetNumGuildMembers() return #(WORLD.roster or {}) end
function GetGuildRosterInfo(i)
    local m = (WORLD.roster or {})[i]
    if m then return m[1], "Member", 1, 60, "Class", "Zone", "", "", true, 0, m[2] end
end
LE_PARTY_CATEGORY_INSTANCE = 2
function EnumerateServerChannels() return "General", "Trade", "LocalDefense" end
function GetChannelList()
    return 1, "General", false, 2, "Trade", false, 5, "Dungeon Pals", false, 7, "Community:4242:1", false
end
function ChatFrame_ResolveChannelName(name) return name == "Community:4242:1" and "Our Club" or name end
function UnitIsGroupLeader(unit) return unit == "player" and WORLD.leader == true end
function UnitIsGroupAssistant() return false end
-- The chat box: what the addon set on it.
CHAT_BOX = CreateFrame("EditBox", "ChatFrame1EditBox")
function ChatEdit_ChooseBoxForSend() return CHAT_BOX end
function ChatEdit_UpdateHeader() end
C_AddOns = { GetAddOnMetadata = function(addon, field) return field == "Version" and "9.9.9" or nil end }

-- The modern client's wording for loot and roll messages.
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
INSTANCE_RESET_SUCCESS = "%s has been reset."
local H = "|HlootHistory:%d|h[Loot]|h: "
LOOT_ROLL_NEED = H .. "%s has selected Need for: %s"
LOOT_ROLL_NEED_SELF = H .. "You have selected Need for: %s"
LOOT_ROLL_GREED = H .. "%s has selected Greed for: %s"
LOOT_ROLL_GREED_SELF = H .. "You have selected Greed for: %s"
LOOT_ROLL_PASSED = H .. "%s passed on: %s"
LOOT_ROLL_PASSED_SELF = H .. "You passed on: %s"
LOOT_ROLL_ROLLED_NEED = H .. "Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_GREED = H .. "Greed Roll - %d for %s by %s"
LOOT_ROLL_ALL_PASSED = H .. "Everyone passed on: %s"
LOOT_ROLL_PASSED_AUTO = H .. "%s automatically passed on: %s because he cannot loot that item."
LOOT_ROLL_PASSED_AUTO_FEMALE = H .. "%s automatically passed on: %s because she cannot loot that item."
LOOT_ROLL_PASSED_SELF_AUTO = H .. "You automatically passed on: %s because you cannot loot that item."
LOOT_ROLL_WON = H .. "%s won: %s"
LOOT_ROLL_YOU_WON = H .. "You won: %s"

----------------------------------------------------------------------
-- Loading and driving the addon
----------------------------------------------------------------------
NS = {}
function LoadAddonFile(path, source)
    local chunk, err = loadstring(source, "@" .. path)
    if not chunk then error(err, 0) end
    chunk("ThatLuckyBastard", NS)
end

-- Sends an event to every frame that registered for it.
function Fire(event, ...)
    for _, w in ipairs(FRAMES) do
        if w.__events and w.__events[event] and w.__scripts.OnEvent then
            w.__scripts.OnEvent(w, event, ...)
        end
    end
end

function Loot(text) Fire("CHAT_MSG_LOOT", text) end
