local ADDON, ns = ...

-- Sharing runs with other players, two ways:
--   * a link in chat. You pick the channel and press Enter yourself: the
--     addon never sends a chat message. Players with the addon see the
--     tag as a link; a click asks your addon for the run, which answers
--     with its code (Code.lua) through hidden addon messages, a few at a
--     time. Global channels (General, Trade, LocalDefense...) are never
--     offered, and tags posted there are not turned into links.
--   * a code to copy out of the game and paste anywhere. Anyone with the
--     addon imports it in the Shared runs window.
-- Only runs you recorded can be shared, and your addon answers only for
-- runs you posted a link to.

local issecret = issecretvalue or function() return false end

local TAG = "That Lucky Bastard"
local TAG_PATTERN = "%[That Lucky Bastard: ([^%[%]|]-) #(%w+)%]"
local PREFIX = "TLB"       -- addon message prefix
local CHUNK = 236          -- characters of code per addon message, which holds 255 with its header
-- The game lets an addon send 10 messages at once, then 1 a second, and
-- drops the rest: stay under that.
local BURST, PACE = 8, 1.1
local MAX_QUEUE = 400      -- messages waiting to go out; requests beyond that are turned down
local MAX_PARTS = 400      -- messages accepted for one run
local TIMEOUT = 15         -- seconds without news before a request is given up

-- The game's own channels, in case the client does not list them.
local GLOBAL_CHANNELS = { General = true, Trade = true, LocalDefense = true, WorldDefense = true,
                          LookingForGroup = true, GuildRecruitment = true, Services = true, NewcomerChat = true }

-- A name without the realm when it is your own realm, for comparing.
local function Plain(name)
    return Ambiguate and Ambiguate(name, "none") or name
end

local function IsMe(name)
    name = Plain(name)
    return name == ns.playerName or name == UnitName("player")
end

local function Notice(title, text)
    ns.Notice(title, text or "", ns.LOGO)
end

-- Your own run with that link id: any of them, or only those you posted a
-- link to.
local function OwnRun(id, postedOnly)
    for _, s in ipairs(ns.AllRuns()) do
        if ns.ShareId(s) == id and (s.shared or not postedOnly) then return s end
    end
end

-- Shortens text to `max` bytes without cutting a letter in two.
local function Short(text, max)
    if #text <= max then return text end
    return (text:sub(1, max - 2):gsub("[\192-\255][\128-\191]*$", "")) .. ".."
end

----------------------------------------------------------------------
-- Addon messages: what goes out is queued and paced
----------------------------------------------------------------------

local queue, tokens, ticking = {}, BURST, false
local outgoing = {} -- ["name#id"] = true while that run is being sent to them
local Pump

local function Tick()
    ticking = false
    tokens = math.min(BURST, tokens + 1)
    Pump()
end

local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle

function Pump()
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    while tokens >= 1 and queue[1] and send do
        local m = table.remove(queue, 1)
        tokens = tokens - 1
        local ok, result = pcall(send, PREFIX, m.text, "WHISPER", m.to)
        if ok and THROTTLED and result == THROTTLED then
            -- Sent too fast after all: it goes again on the next tick.
            table.insert(queue, 1, m)
            tokens = 0
            break
        end
        if m.last then outgoing[m.last] = nil end
    end
    if not ticking and (queue[1] or tokens < BURST) then
        ticking = true
        C_Timer.After(PACE, Tick)
    end
end

-- last: the transfer this message completes.
local function Queue(text, to, last)
    queue[#queue + 1] = { text = text, to = to, last = last }
    Pump()
end

----------------------------------------------------------------------
-- Asking for a run, and answering
----------------------------------------------------------------------

local incoming = {} -- ["name#id"] = a run being received: { from, id, parts, got, total, at }
local DrawList      -- the list of shared runs, defined with its window

local function Watch(key)
    C_Timer.After(TIMEOUT, function()
        local want = incoming[key]
        if not want then return end
        if GetTime() - want.at < TIMEOUT then return Watch(key) end
        incoming[key] = nil
        Notice(("No answer from %s"):format(ns.DisplayName(Plain(want.from))),
               "They may be offline or inside a dungeon. Try again later.")
    end)
end

-- A click on a run's link posted by `from`.
function ns.RequestRun(from, id)
    if IsMe(from) then
        local s = OwnRun(id)
        if s then ns.ShowRun(s) else Notice("That run is no longer kept.") end
        return
    end
    for _, s in ipairs(ns.db.shared) do
        if s.shareId == id and Plain(s.sharedBy) == Plain(from) then return ns.ShowRun(s) end
    end
    local key = Plain(from) .. "#" .. id
    if incoming[key] then return end -- already asked
    incoming[key] = { from = from, id = id, parts = {}, got = 0, at = GetTime() }
    Queue("Q" .. id, from)
    Notice(("Asking %s for the run..."):format(ns.DisplayName(Plain(from))))
    Watch(key)
end

-- Someone clicked one of your links: send them the run's code.
local function Answer(from, id)
    local s = OwnRun(id, true)
    if not s or #queue > MAX_QUEUE then return Queue("N" .. id, from) end
    local key = Plain(from) .. "#" .. id
    if outgoing[key] then return end -- on its way already
    outgoing[key] = true
    local code = ns.EncodeRun(s)
    local total = math.ceil(#code / CHUNK)
    for i = 1, total do
        Queue(("D%s,%d,%d,%s"):format(id, i, total, code:sub((i - 1) * CHUNK + 1, i * CHUNK)), from,
              i == total and key or nil)
    end
end

local function Receive(from, id, part, total, chunk)
    local key = Plain(from) .. "#" .. id
    local want = incoming[key]
    if not want then return end -- nothing was asked for
    part, total = tonumber(part), tonumber(total)
    if total < 1 or total > MAX_PARTS or part < 1 or part > total or (want.total and want.total ~= total) then return end
    if not want.total then
        Notice(("Receiving the run from %s"):format(ns.DisplayName(Plain(want.from))),
               ("About %d seconds."):format(math.max(total - BURST, 1) * PACE + 0.5))
    end
    want.total, want.at = total, GetTime()
    if not want.parts[part] then
        want.parts[part] = chunk
        want.got = want.got + 1
    end
    if want.got < total then return end
    incoming[key] = nil
    local s, err = ns.ImportCode(table.concat(want.parts), want.from)
    if not s then
        return Notice(("The run from %s could not be read"):format(ns.DisplayName(Plain(want.from))), err)
    end
    s.shareId = id
    ns.ShowRun(s)
    DrawList()
end

local function Refused(from, id)
    local key = Plain(from) .. "#" .. id
    if not incoming[key] then return end
    incoming[key] = nil
    Notice(("%s no longer has that run"):format(ns.DisplayName(Plain(from))))
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if not ns.db or prefix ~= PREFIX or channel ~= "WHISPER" then return end
    if type(text) ~= "string" or type(sender) ~= "string" or issecret(text) or issecret(sender) then return end
    local kind, id = text:match("^([QDN])(%w+)")
    if kind == "Q" then
        Answer(sender, id)
    elseif kind == "N" then
        Refused(sender, id)
    elseif kind == "D" then
        local part, total, chunk = text:match("^D%w+,(%d+),(%d+),(.*)$")
        if part then Receive(sender, id, part, total, chunk) end
    end
end)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

----------------------------------------------------------------------
-- Chat: a run's tag, and the link it becomes
----------------------------------------------------------------------

-- The text posted in chat. Players without the addon read it as it is.
function ns.ShareTag(s)
    local name = (s.name or "Run"):gsub("[%[%]|#]", "")
    return ("[%s: %s #%s]"):format(TAG, name, ns.ShareId(s))
end

-- Where tags turn into links: every chat but the global channels.
local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}

local function Linkify(_, event, msg, author, ...)
    if type(msg) ~= "string" or type(author) ~= "string" or issecret(msg) or issecret(author) then return false end
    if not msg:find(TAG, 1, true) then return false end
    if event == "CHAT_MSG_CHANNEL" then
        local zoneChannel, _, baseName = select(5, ...)
        if (zoneChannel and zoneChannel ~= 0) or GLOBAL_CHANNELS[baseName or ""] then return false end
    end
    -- In a whisper you sent, `author` is who it went to; the run is yours.
    local from = event == "CHAT_MSG_WHISPER_INFORM" and ns.playerName or author
    local out = msg:gsub(TAG_PATTERN, function(name, id)
        return ("|Haddon:%s:run:%s:%s|h%s[%s: %s]|r|h"):format(ADDON, id, from, ns.ACCENT_HEX, TAG, name)
    end)
    if out == msg then return false end
    return false, out, author, ...
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then
    for _, event in ipairs(CHAT_EVENTS) do addFilter(event, Linkify) end
end

-- A click on a link. Clients report it through EventRegistry, SetItemRef
-- or both: the second report of one click is ignored.
local lastLink, lastAt
local function OnLink(link)
    if type(link) ~= "string" then return end
    local id, from = link:match("^addon:" .. ADDON .. ":run:(%w+):(.+)$")
    if not id then return end
    if link == lastLink and GetTime() - lastAt < 0.5 then return end
    lastLink, lastAt = link, GetTime()
    ns.RequestRun(from, id)
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link) OnLink(link) end, {})
end
if hooksecurefunc and SetItemRef then hooksecurefunc("SetItemRef", OnLink) end

----------------------------------------------------------------------
-- Share window: the run on show as a link in chat, or as a code
----------------------------------------------------------------------

local WIDTH = 400
local BTN_W, BTN_GAP, PER_ROW = 86, 4, 4

-- The channels a link can be posted to. `usable`: whether you can talk
-- there right now.
local CHANNELS = {
    { label = "Say", command = "/s" },
    { label = "Yell", command = "/y" },
    { label = "Party", command = "/p", usable = function() return IsInGroup() end },
    { label = "Raid", command = "/ra", usable = function() return IsInRaid() end },
    { label = "Instance", command = "/i", usable = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) end },
    { label = "Guild", command = "/g", usable = function() return IsInGuild() end },
    { label = "Officer", command = "/o", usable = function()
        return IsInGuild() and not (C_GuildInfo and C_GuildInfo.IsGuildOfficer and not C_GuildInfo.IsGuildOfficer())
    end },
}

-- Channels you joined yourself, by number: not the game's zone and world
-- channels, nor communities.
local function CustomChannels()
    local global = {}
    for _, name in ipairs(EnumerateServerChannels and { EnumerateServerChannels() } or {}) do global[name] = true end
    local out, list = {}, GetChannelList and { GetChannelList() } or {}
    for i = 1, #list, 3 do
        local id, name, disabled = list[i], list[i + 1], list[i + 2]
        if type(id) == "number" and type(name) == "string" and not disabled and not global[name]
                and not GLOBAL_CHANNELS[name] and not name:find("^Community:") then
            out[#out + 1] = { label = Short(name, 13), command = "/" .. id }
        end
    end
    return out
end

local win, ui, title, skins = ns.MakeWindow("ThatLuckyBastardShareFrame", WIDTH, 300, "HIGH", true)
win:SetPoint("CENTER", 0, 80)

local function Text(font)
    local fs = ui:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(WIDTH - 32)
    return fs
end

local shareRun, channels = nil, {}
local linkHead, linkHint = Text("GameFontNormal"), Text("GameFontDisableSmall")
local codeHead, codeHint = Text("GameFontNormal"), Text("GameFontDisableSmall")
local importHead, importHint = Text("GameFontNormal"), Text("GameFontDisableSmall")
linkHead:SetText("Link in chat")
codeHead:SetText("Code")
codeHint:SetText("The run as text, to paste outside the game.")
importHead:SetText("Shared with you")
importHint:SetText("Open a code someone gave you, or a run you received.")

local channelButtons = {}
local function ChannelButton(i)
    if not channelButtons[i] then
        channelButtons[i] = ns.MakeButton("", BTN_W, function()
            local c, s = channels[i], shareRun
            if not (c and s) then return end
            s.shared = true -- your addon answers clicks on this run's link from now on
            local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
            if open then open(c.command .. " " .. ns.ShareTag(s)) end
            win:Hide()
        end, ui)
    end
    return channelButtons[i]
end

local codeBtn = ns.MakeButton("Show the code", 130, function() ns.ShowExport("code", shareRun) end, ui)
local importBtn = ns.MakeButton("Shared runs", 130, function() ns.ToggleImport() end, ui)

local function Draw()
    local flat, top = ns.ApplyWindowTheme(skins, title)
    local s = shareRun
    title:SetText(ns.Title("Share  -  " .. (s and s.name or "Run")))
    local own = s ~= nil and not s.example and not s.sharedBy
    linkHint:SetText(own and "Press Enter to post it. Players with the addon click it to see the run."
                     or "Only runs you recorded can be shared.")

    local y = top
    local function Place(widget, x, height)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", x, y)
        y = y - height
    end
    Place(linkHead, 16, 18)
    Place(linkHint, 16, 22)
    channels = {}
    for _, c in ipairs(CHANNELS) do channels[#channels + 1] = c end
    for _, c in ipairs(CustomChannels()) do channels[#channels + 1] = c end
    for i, c in ipairs(channels) do
        local b = ChannelButton(i)
        b:SetLabel(c.label)
        b:SetFlat(flat)
        b:SetOn(own and (not c.usable or c.usable()) or false)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 16 + ((i - 1) % PER_ROW) * (BTN_W + BTN_GAP), y - math.floor((i - 1) / PER_ROW) * 26)
        b:Show()
    end
    for i = #channels + 1, #channelButtons do channelButtons[i]:Hide() end
    y = y - math.ceil(#channels / PER_ROW) * 26 - 10
    Place(codeHead, 16, 18)
    Place(codeHint, 16, 20)
    Place(codeBtn, 16, 34)
    codeBtn:SetFlat(flat)
    codeBtn:SetOn(own)
    Place(importHead, 16, 18)
    Place(importHint, 16, 20)
    Place(importBtn, 16, 30)
    importBtn:SetFlat(flat)
    win:SetHeight(16 - y)
end

-- The Share button: opens the window for run `s`, or closes it.
function ns.ToggleShare(s)
    if win:IsShown() and shareRun == s then return win:Hide() end
    shareRun = s
    win:Show()
    win:Raise()
    Draw()
end

----------------------------------------------------------------------
-- Shared runs window: import a code, and the runs shared with you
----------------------------------------------------------------------

local IMPORT_W, IMPORT_H = 460, 430
local ROW_H = 18

local imp, iui, ititle, iskins = ns.MakeWindow("ThatLuckyBastardImportFrame", IMPORT_W, IMPORT_H, "HIGH", true)
imp:SetPoint("CENTER", 0, 40)
ititle:SetText(ns.Title("Shared runs"))

local pasteHint = iui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pasteHint:SetJustifyH("LEFT")
pasteHint:SetText("Paste a code with |cffffd100Ctrl+V|r, then Import.")

local pasteScroll = CreateFrame("ScrollFrame", nil, iui, "UIPanelScrollFrameTemplate")
local box = CreateFrame("EditBox", nil, pasteScroll)
box:SetMultiLine(true)
box:SetMaxLetters(0) -- no limit: a code can be long
box:SetAutoFocus(false)
box:SetFontObject("ChatFontNormal")
box:SetWidth(IMPORT_W - 60)
box:SetScript("OnEscapePressed", box.ClearFocus)
pasteScroll:SetScrollChild(box)
-- An empty box is one line tall: a click anywhere in the paste area puts
-- the cursor in it, or Ctrl+V would go to the game's key bindings.
pasteScroll:EnableMouse(true)
pasteScroll:SetScript("OnMouseDown", function() box:SetFocus() end)
local boxBg = iui:CreateTexture(nil, "BACKGROUND")
boxBg:SetColorTexture(0, 0, 0, 0.35)
boxBg:SetPoint("TOPLEFT", pasteScroll, -4, 4)
boxBg:SetPoint("BOTTOMRIGHT", pasteScroll, 4, -4)

local status = iui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetJustifyH("LEFT")

local importCode = ns.MakeButton("Import", 90, function()
    local s, err = ns.ImportCode(box:GetText())
    if not s then return status:SetText("|cffff7070" .. err .. "|r") end
    box:SetText("")
    box:ClearFocus()
    status:SetText(s.sharedBy and "Imported." or "This is one of your own runs.")
    DrawList()
    ns.ShowRun(s)
end, iui)

local listHead = iui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listHead:SetText("Shared with you")
local listScroll = CreateFrame("ScrollFrame", nil, iui, "UIPanelScrollFrameTemplate")
local list = CreateFrame("Frame", nil, listScroll)
list:SetSize(IMPORT_W - 60, 1)
listScroll:SetScrollChild(list)
local emptyText = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
emptyText:SetPoint("TOPLEFT", 4, -2)
emptyText:SetText("Nothing yet. Click a run's link in chat, or import a code.")

local rows = {}
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self.run then ns.ShowRun(self.run) end end)
    rows[i] = r
    return r
end

function DrawList()
    local runs = ns.db.shared
    for i, s in ipairs(runs) do
        local r = Row(i)
        r.run = s
        r.text:SetText(("%s   |cffffd100%s|r   |cff909090shared by %s|r"):format(
            ns.DateText(s.startedAt), s.name or "Run", ns.DisplayName(s.sharedBy or "?")))
        r:Show()
    end
    for i = #runs + 1, #rows do rows[i]:Hide() end
    emptyText:SetShown(#runs == 0)
    list:SetHeight(math.max(#runs * ROW_H, 1))
end

local function DrawImport()
    local flat, top = ns.ApplyWindowTheme(iskins, ititle)
    pasteHint:ClearAllPoints()
    pasteHint:SetPoint("TOPLEFT", 16, top)
    pasteScroll:ClearAllPoints()
    pasteScroll:SetPoint("TOPLEFT", 16, top - 22)
    pasteScroll:SetPoint("TOPRIGHT", -34, top - 22)
    pasteScroll:SetHeight(90)
    importCode:ClearAllPoints()
    importCode:SetPoint("TOPLEFT", 14, top - 124)
    importCode:SetFlat(flat)
    status:ClearAllPoints()
    status:SetPoint("LEFT", importCode, "RIGHT", 10, 0)
    status:SetWidth(IMPORT_W - 140)
    listHead:ClearAllPoints()
    listHead:SetPoint("TOPLEFT", 16, top - 160)
    listScroll:ClearAllPoints()
    listScroll:SetPoint("TOPLEFT", 16, top - 182)
    listScroll:SetPoint("BOTTOMRIGHT", -34, 16)
    DrawList()
end

-- Opens or closes the Shared runs window.
function ns.ToggleImport()
    if imp:IsShown() then return imp:Hide() end
    status:SetText("")
    imp:Show()
    imp:Raise()
    DrawImport()
    box:SetFocus() -- ready for Ctrl+V
end

ns.OnRerender(function()
    if win:IsShown() then Draw() end
    if imp:IsShown() then DrawImport() end
end)
