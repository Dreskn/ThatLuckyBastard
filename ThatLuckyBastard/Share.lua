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
local MAX_PARTS = 600      -- messages accepted for one run: 141,600 characters. A busy raid of forty takes some 350
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

----------------------------------------------------------------------
-- Summary in chat: a few plain lines anyone can read, like a damage
-- meter's report. They are sent only when you click a channel in the
-- Share window with Summary chosen: the addon never posts on its own.
----------------------------------------------------------------------

-- The lines of run `s`'s summary, as the Share options set them: a first
-- line naming the run, then one line per player, most loot first.
function ns.SummaryLines(s)
    if not s then return {} end
    local o = ns.db.options
    local sum = ns.Summarize(s)
    local awards = ns.RunAwards(s, sum)
    local limit = o.summaryLines or 5

    local facts = {}
    local duration = o.summaryTime and ns.RunDuration(s)
    if duration and duration >= ns.MIN_TIMED_RUN then facts[#facts + 1] = ns.Duration(duration) end
    if o.summaryTotal and sum.market > 0 then facts[#facts + 1] = ns.MoneyPlain(sum.market) .. " in all" end
    local first
    if o.summaryLink then
        -- Players with the addon can click it, as in Link mode.
        first = ns.ShareTag(s) .. (#facts > 0 and (" " .. table.concat(facts, ", ")) or "")
    else
        first = TAG .. ": " .. (s.name or "Run") .. (#facts > 0 and (", " .. table.concat(facts, ", ")) or "")
    end
    local lines = { first }

    local ranked = {}
    for _, p in ipairs(sum.players) do ranked[#ranked + 1] = p end
    table.sort(ranked, function(a, b) return (a.rank or 99) < (b.rank or 99) end)
    local equal = #ranked > 0 and sum.market / #ranked or 0
    for i = 1, math.min(#ranked, limit) do
        local p = ranked[i]
        local line = ("%d. %s %s"):format(i, ns.DisplayName(p.name), p.market > 0 and ns.MoneyPlain(p.market) or "0g")
        local extra = {}
        if o.summaryShare and sum.market > 0 then
            extra[#extra + 1] = ("%.0f%%"):format(p.market / sum.market * 100)
        end
        local diff = p.market - equal
        if o.summaryGap and sum.market > 0 and math.abs(diff) >= 1 then
            extra[#extra + 1] = (diff > 0 and "+" or "-") .. ns.MoneyPlain(math.abs(diff))
        end
        if #extra > 0 then line = line .. " (" .. table.concat(extra, ", ") .. ")" end
        local award = o.summaryAward and awards[p.name]
        if award then line = line .. " " .. award.title end
        lines[#lines + 1] = line
    end
    if #ranked > limit then lines[#lines + 1] = ("and %d more"):format(#ranked - limit) end

    -- Chat refuses escape codes in typed text: no "|" may get through.
    for i, line in ipairs(lines) do lines[i] = (line:gsub("|", "")) end
    return lines
end

-- Sends `lines` to channel `c` of the Share window, or as whispers to
-- `whisperTo`. Called from a click only: the game wants a click or a key
-- press for most channels, and all the lines go out in that same moment.
local function PostLines(lines, c, whisperTo)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if whisperTo then
            if send then send(line, "WHISPER", nil, whisperTo) end
        elseif c.club then
            -- A community's chat is not a numbered channel to the server.
            if C_Club and C_Club.SendMessage then C_Club.SendMessage(c.club, c.stream, line) end
        elseif c.channel then
            if send then send(line, "CHANNEL", nil, c.channel) end
        elseif send then
            send(line, c.chatType)
        end
    end
end

-- Where tags turn into links: every chat but the global channels.
local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
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
local BTN_W, BTN_GAP, PER_ROW = 118, 4, 3

-- The channels a link or a summary can be posted to. `command`: how the
-- link is typed in the chat box; `chatType`: where a summary is sent.
-- `usable`: whether you can talk there right now. `noSummary`: not for a
-- summary of several lines (an emote puts your name before each line,
-- and a burst of raid warnings fills everyone's screen).
local CHANNELS = {
    { label = "Say", command = "/s", chatType = "SAY" },
    { label = "Yell", command = "/y", chatType = "YELL" },
    { label = "Emote", command = "/e", chatType = "EMOTE", noSummary = true },
    { label = "Party", command = "/p", chatType = "PARTY", usable = function() return IsInGroup() end },
    { label = "Raid", command = "/ra", chatType = "RAID", usable = function() return IsInRaid() end },
    { label = "Raid warning", command = "/rw", chatType = "RAID_WARNING", noSummary = true, usable = function()
        return IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    end },
    { label = "Instance", command = "/i", chatType = "INSTANCE_CHAT",
      usable = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) end },
    { label = "Guild", command = "/g", chatType = "GUILD", usable = function() return IsInGuild() end },
    { label = "Officer", command = "/o", chatType = "OFFICER", usable = function()
        return IsInGuild() and not (C_GuildInfo and C_GuildInfo.IsGuildOfficer and not C_GuildInfo.IsGuildOfficer())
    end },
}

-- Channels and communities you joined yourself, by number: not the game's
-- zone and world channels. A community's channel is named by the game as
-- "Community:<ids>": it is shown under the community's own name.
local function CustomChannels()
    local global = {}
    for _, name in ipairs(EnumerateServerChannels and { EnumerateServerChannels() } or {}) do global[name] = true end
    local resolve = (ChatFrameUtil and ChatFrameUtil.ResolveChannelName) or ChatFrame_ResolveChannelName
    local out, list = {}, GetChannelList and { GetChannelList() } or {}
    for i = 1, #list, 3 do
        local id, name, disabled = list[i], list[i + 1], list[i + 2]
        if type(id) == "number" and type(name) == "string" and not disabled and not global[name]
                and not GLOBAL_CHANNELS[name] then
            local label = name
            local club, stream = name:match("^Community:(%d+):(%d+)")
            if name:find("^Community:") then
                label = resolve and resolve(name)
                if type(label) ~= "string" or label:find("^Community:") then label = nil end -- not one we can name
            end
            if label then
                out[#out + 1] = { label = Short(label, 17), command = "/" .. id,
                                  channel = not club and id or nil, club = club, stream = stream }
            end
        end
    end
    return out
end

-- Opens the chat box whispering `name`, with `text` in it. The target is
-- set on the chat box itself rather than typed as "/w name": on Forever
-- a name is two words, and the chat box would cut it at the space.
local function OpenWhisper(name, text)
    local choose = ChatEdit_ChooseBoxForSend or (ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend)
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    local box = choose and choose()
    if not (open and box and box.SetAttribute) then
        if open then open("/w " .. name .. " " .. text) end -- the old way: fine for one-word names
        return
    end
    open(text)
    box:SetAttribute("chatType", "WHISPER")
    box:SetAttribute("tellTarget", name)
    local update = ChatEdit_UpdateHeader or (ChatFrameUtil and ChatFrameUtil.UpdateHeader)
    if update then update(box) elseif box.UpdateHeader then box:UpdateHeader() end
end

-- The player you are targeting, if it is another player: offered as the
-- one to whisper.
local function TargetName()
    if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
        local name = GetUnitName("target", true)
        if type(name) == "string" and not issecret(name) then return name end
    end
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
linkHead:SetText("Chat")
codeHead:SetText("Code")
codeHint:SetText("The run as text, to paste outside the game.")
importHead:SetText("Shared with you")
importHint:SetText("Open a code someone gave you, or a run you received.")

-- What a channel button posts: "link" (one tag, left in the chat box for
-- you to send) or "summary" (the lines in the preview, sent at once).
local function Mode()
    return ns.db.options.shareMode == "summary" and "summary" or "link"
end

-- The summary, as it will be posted: the lines on a faint panel.
local preview = Text("GameFontHighlightSmall")
preview:SetWidth(WIDTH - 44)
local previewBg = ui:CreateTexture(nil, "BACKGROUND")
previewBg:SetPoint("TOPLEFT", preview, "TOPLEFT", -6, 5)
previewBg:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 6, -5)
previewBg:SetColorTexture(0, 0, 0, 0.3)

local Draw -- below
local modeTabs = {}
for i, m in ipairs({ { "Link", "link" }, { "Summary", "summary" } }) do
    local tab = ns.MakeButton(m[1], 90, function()
        ns.db.options.shareMode = m[2]
        Draw()
    end, ui)
    tab.isTab, tab.mode = true, m[2]
    modeTabs[i] = tab
end

-- Posts run `s` to channel `c` (or as a whisper to `whisperTo`) the way
-- the mode says, then closes the window.
local function Post(s, c, whisperTo)
    if Mode() == "summary" then
        -- The first line carries the link unless the options leave it out.
        if ns.db.options.summaryLink then s.shared = true end
        PostLines(ns.SummaryLines(s), c, whisperTo)
    else
        s.shared = true -- your addon answers clicks on this run's link from now on
        if whisperTo then
            OpenWhisper(whisperTo, ns.ShareTag(s))
        else
            local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
            if open then open(c.command .. " " .. ns.ShareTag(s)) end
        end
    end
    win:Hide()
end

local channelButtons = {}
local function ChannelButton(i)
    if not channelButtons[i] then
        channelButtons[i] = ns.MakeButton("", BTN_W, function()
            local c, s = channels[i], shareRun
            if not (c and s) then return end
            if Mode() == "summary" and c.noSummary then return end
            Post(s, c)
        end, ui)
    end
    return channelButtons[i]
end

-- Whisper: a box for the player's name, and its button.
local nameBox = CreateFrame("EditBox", nil, ui, "InputBoxTemplate")
nameBox:SetHeight(20)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(60)
local namePrompt = nameBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
namePrompt:SetPoint("LEFT", 2, 0)
namePrompt:SetText("Their full name")
local function UpdatePrompt()
    namePrompt:SetShown(nameBox:GetText() == "" and not nameBox:HasFocus())
end

local lastWhisper -- the name whispered last, offered again

-- Names to whisper, as you type: like the game's own chat box, from your
-- group, friends and guild, and also from the players you have run with.
local MAX_SUGGESTIONS = 5
local SUGGEST_H = 18 -- a row of the list

-- Everyone you might whisper, best first: your group, the name you
-- whispered last, friends, Battle.net friends in the game, your guild,
-- then the players you have run with, most runs first. Each is { name,
-- class } (the class file name, when known).
local function Candidates()
    local out, seen = {}, {}
    local function Add(name, class)
        if type(name) ~= "string" or issecret(name) or name == "" then return end
        if Ambiguate then name = Ambiguate(name, "none") end
        local key = name:lower()
        if seen[key] or IsMe(name) then return end
        seen[key] = true
        out[#out + 1] = { name = name, class = class }
    end
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            Add(GetUnitName(unit, true), select(2, UnitClass(unit)))
        end
    end
    Add(lastWhisper)
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info then Add(info.name) end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts then
        local wow, home = BNET_CLIENT_WOW or "WoW", GetRealmName and GetRealmName()
        for i = 1, (BNGetNumFriends()) or 0 do
            for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
                local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
                local name, realm = game and game.characterName, game and game.realmName
                if name and game.clientProgram == wow then
                    -- Another realm's player is whispered as Name-Realm.
                    if realm and realm ~= "" and realm ~= home then name = name .. "-" .. (realm:gsub("%s", "")) end
                    Add(name)
                end
            end
        end
    end
    if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers()) or 0 do
            local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
            Add(name, class)
        end
    end
    local regulars = {}
    for name, who in pairs(ns.db.people) do regulars[#regulars + 1] = { name = name, who = who } end
    table.sort(regulars, function(a, b)
        if (a.who.runs or 0) ~= (b.who.runs or 0) then return (a.who.runs or 0) > (b.who.runs or 0) end
        return a.name < b.name
    end)
    for _, r in ipairs(regulars) do Add(r.name, r.who.class) end
    return out
end

-- The names that `text` could be the start of: of the whole name, or of
-- one of its words ("ee" finds "Duke Ee"), ignoring case. A name typed in
-- full is not offered again. At most `max` of them.
function ns.NameSuggestions(text, max)
    text = (text or ""):gsub("^%s+", "")
    text = text:gsub("%s+", " "):lower()
    local out = {}
    if text == "" then return out end
    local ok, list = pcall(Candidates) -- a fault in a list of names must never break the box
    if not ok then return out end
    for _, c in ipairs(list) do
        local lower = c.name:lower()
        local fits = lower ~= text and lower:sub(1, #text) == text
        if not fits and lower ~= text then
            for at in lower:gmatch("[ %-]()") do
                if lower:sub(at, at + #text - 1) == text then fits = true end
            end
        end
        if fits then
            out[#out + 1] = c
            if #out >= (max or MAX_SUGGESTIONS) then break end
        end
    end
    return out
end

-- The list under the box. Tab or a click takes a name; the arrow keys
-- pick one, which Enter then takes; Escape closes the list.
local suggest = CreateFrame("Frame", nil, ui)
suggest:SetFrameStrata("DIALOG")
suggest:Hide()
local suggestEdge = suggest:CreateTexture(nil, "BACKGROUND")
suggestEdge:SetPoint("TOPLEFT", -1, 1)
suggestEdge:SetPoint("BOTTOMRIGHT", 1, -1)
suggestEdge:SetColorTexture(1, 1, 1, 0.18)
local suggestBg = suggest:CreateTexture(nil, "BORDER")
suggestBg:SetAllPoints()
suggestBg:SetColorTexture(0.06, 0.06, 0.08, 0.97)

local suggestions, picked = {}, 0 -- what is listed, and the row picked with the arrow keys
local suggestRows = {}
local function PaintSuggestions()
    for i, row in ipairs(suggestRows) do row.lit:SetShown(i == picked) end
end
local function HideSuggestions()
    suggestions, picked = {}, 0
    suggest:Hide()
end
-- Puts suggestion `i` in the box. False when there is none.
local function TakeSuggestion(i)
    local s = suggestions[i]
    if not s then return false end
    nameBox:SetText(s.name)
    HideSuggestions()
    return true
end
local function SuggestRow(i)
    local row = suggestRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, suggest)
    row:SetHeight(SUGGEST_H)
    row:SetPoint("TOPLEFT", 0, -2 - (i - 1) * SUGGEST_H)
    row:SetPoint("TOPRIGHT", 0, -2 - (i - 1) * SUGGEST_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.lit = row:CreateTexture(nil, "ARTWORK")
    row.lit:SetAllPoints()
    row.lit:SetColorTexture(1, 1, 1, 0.14)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row:SetScript("OnClick", function()
        TakeSuggestion(i)
        nameBox:SetFocus() -- Enter then whispers them
    end)
    suggestRows[i] = row
    return row
end
local function ShowSuggestions()
    suggestions, picked = ns.NameSuggestions(nameBox:GetText(), MAX_SUGGESTIONS), 0
    for i, s in ipairs(suggestions) do
        local row = SuggestRow(i)
        row.label:SetText(ns.ClassColored(s.name, s.class))
        row:Show()
    end
    for i = #suggestions + 1, #suggestRows do suggestRows[i]:Hide() end
    suggest:ClearAllPoints()
    suggest:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -2)
    suggest:SetPoint("TOPRIGHT", nameBox, "BOTTOMRIGHT", 0, -2)
    suggest:SetHeight(#suggestions * SUGGEST_H + 4)
    suggest:SetShown(#suggestions > 0)
    PaintSuggestions()
end

nameBox:SetScript("OnTextChanged", function(_, userInput)
    UpdatePrompt()
    if userInput then ShowSuggestions() end
end)
nameBox:SetScript("OnEditFocusGained", UpdatePrompt)
nameBox:SetScript("OnEditFocusLost", function()
    UpdatePrompt()
    -- Not at once: a click on the list takes the focus away first.
    C_Timer.After(0.2, function()
        if not nameBox:HasFocus() then HideSuggestions() end
    end)
end)
nameBox:SetScript("OnEscapePressed", function()
    if suggest:IsShown() then HideSuggestions() else nameBox:ClearFocus() end
end)
nameBox:SetScript("OnTabPressed", function()
    if suggest:IsShown() then TakeSuggestion(picked > 0 and picked or 1) end
end)
nameBox:SetScript("OnArrowPressed", function(_, key)
    local n = #suggestions
    if not suggest:IsShown() or n == 0 then return end
    if key == "DOWN" then
        picked = picked % n + 1
    elseif key == "UP" then
        picked = (picked - 2) % n + 1
    end
    PaintSuggestions()
end)

local function Whisper()
    local s = shareRun
    local name = (nameBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    HideSuggestions()
    if not s or name == "" then return nameBox:SetFocus() end
    lastWhisper = name
    nameBox:ClearFocus()
    Post(s, nil, name)
end
-- Enter takes the name picked in the list, if any; otherwise it whispers.
nameBox:SetScript("OnEnterPressed", function()
    if not (suggest:IsShown() and picked > 0 and TakeSuggestion(picked)) then Whisper() end
end)
local whisperBtn = ns.MakeButton("Whisper", BTN_W, Whisper, ui)

local codeBtn = ns.MakeButton("Show the code", 130, function() ns.ShowExport("code", shareRun) end, ui)
local importBtn = ns.MakeButton("Shared runs", 130, function() ns.ToggleImport() end, ui)

function Draw()
    local flat, top = ns.ApplyWindowTheme(skins, title)
    local s = shareRun
    title:SetText(ns.Title("Share  -  " .. (s and s.name or "Run")))
    local own = s ~= nil and not s.example and not s.sharedBy
    local summary = Mode() == "summary"
    if not own then
        linkHint:SetText("Only runs you recorded can be shared.")
    elseif summary then
        linkHint:SetText("Click a channel to post these lines.")
    else
        linkHint:SetText("Press Enter to post it. Players with the addon click it to see the run.")
    end

    local y = top
    local function Place(widget, x, height)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", x, y)
        y = y - height
    end
    Place(linkHead, 16, 22)
    for i, tab in ipairs(modeTabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", 16 + (i - 1) * 94, y)
        tab:SetFlat(flat)
        tab:SetSelected(Mode() == tab.mode)
    end
    y = y - 28
    Place(linkHint, 16, 22)
    preview:SetShown(summary and own)
    previewBg:SetShown(summary and own)
    if summary and own then
        preview:SetText(table.concat(ns.SummaryLines(s), "\n"))
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", 22, y - 5)
        y = y - (preview:GetStringHeight() + 20)
    end
    channels = {}
    for _, c in ipairs(CHANNELS) do channels[#channels + 1] = c end
    for _, c in ipairs(CustomChannels()) do channels[#channels + 1] = c end
    for i, c in ipairs(channels) do
        local b = ChannelButton(i)
        b:SetLabel(c.label)
        b:SetFlat(flat)
        b:SetOn(own and (not c.usable or c.usable()) and not (summary and c.noSummary) or false)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 16 + ((i - 1) % PER_ROW) * (BTN_W + BTN_GAP), y - math.floor((i - 1) / PER_ROW) * 26)
        b:Show()
    end
    for i = #channels + 1, #channelButtons do channelButtons[i]:Hide() end
    y = y - math.ceil(#channels / PER_ROW) * 26
    -- Whisper row: the name box across two columns, the button in the third.
    nameBox:ClearAllPoints()
    nameBox:SetPoint("TOPLEFT", 22, y - 1)
    nameBox:SetWidth(2 * BTN_W + BTN_GAP - 6)
    nameBox:SetEnabled(own)
    whisperBtn:ClearAllPoints()
    whisperBtn:SetPoint("TOPLEFT", 16 + 2 * (BTN_W + BTN_GAP), y)
    whisperBtn:SetFlat(flat)
    whisperBtn:SetOn(own)
    UpdatePrompt()
    y = y - 26 - 10
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
    nameBox:SetText(TargetName() or lastWhisper or "")
    HideSuggestions()
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
    local runs = ns.SharedByDate()
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
