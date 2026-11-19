-- Sharing runs: the code, importing it, the link in chat and the hidden
-- exchange between two players' addons that a click on it starts.
Include("test_run.lua")
print("\n==== sharing ====")
local ns = NS
local db = ThatLuckyBastardDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
-- Clicks the button with this label.
local function click(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == label and w.__scripts.OnClick then
            w.__scripts.OnClick(w, "LeftButton")
            return true
        end
    end
    return false
end
-- A button of the share window (other windows have buttons of the same
-- name: the options have a "General" page).
local function hasButton(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == label then
            local up = w
            while up do
                if up == ThatLuckyBastardShareFrame then return true end
                up = rawget(up, "__parent")
            end
        end
    end
    return false
end
local function drew(pattern)
    for _, t in ipairs(TEXTLOG) do
        if t:find(pattern, 1, true) then return true end
    end
    return false
end
-- What the window would show of a run: each player's count, vendor and market value.
local function figures(s)
    local out = {}
    for _, p in ipairs(ns.Summarize(s).players) do out[p.name] = ("%d/%d/%d"):format(p.count, p.vendor, p.market) end
    return out
end
local function same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local run = db.history[1] -- the first Test Keep run, over
local id = ns.ShareId(run)

print("-- the code")
local code = ns.EncodeRun(run)
print("        " .. #code .. " characters: " .. code:sub(1, 90) .. "...")
check(code:sub(1, 5) == "TLB1!" and not code:find("[|*_~`:\n]"), "plain text, safe in game chat and on Discord")
local back, err = ns.DecodeRun(code)
check(back ~= nil, "reads back (" .. tostring(err) .. ")")
check(back and same(figures(run), figures(back)), "every player's totals are the same")
local awardsA, awardsB = ns.Awards(run, ns.Summarize(run)), back and ns.Awards(back, ns.Summarize(back)) or {}
local sameAwards = next(awardsA) ~= nil
for name, a in pairs(awardsA) do
    if not awardsB[name] or awardsB[name].key ~= a.key then sameAwards = false end
end
check(sameAwards, "so are the awards")
local function points(s)
    local n = 0
    for _, line in ipairs(ns.Timeline(s).series) do n = n + #line.points end
    return n
end
check(back and #ns.RunRolls(back) == #ns.RunRolls(run) and points(back) == points(run) and points(run) > 0,
      "and the roll sheet and the timeline")
check(ns.DecodeRun("  \n" .. code:sub(1, 100) .. "\r\n" .. code:sub(101) .. "\n ") ~= nil,
      "spaces around it and line breaks inside it do not matter")

print("-- codes that are not right")
local _, e1 = ns.DecodeRun("hello there")
check(e1 and e1:find("not a That Lucky Bastard code", 1, true), "not a code: " .. tostring(e1))
local _, e2 = ns.DecodeRun(code:sub(1, #code - 40))
check(e2 and e2:find("incomplete", 1, true), "cut short: " .. tostring(e2))
local swapped = code:sub(1, 60) .. (code:sub(61, 61) == "a" and "b" or "a") .. code:sub(62)
check(ns.DecodeRun(swapped) == nil, "one character changed: refused")
local _, e3 = ns.DecodeRun("TLB2!" .. code:sub(6))
check(e3 and e3:find("newer version", 1, true), "from a newer version: " .. tostring(e3))

print("-- text from a code cannot draw anything")
local evil = { name = "Bad|cffff0000Red!;,.'%", startedAt = NOW, endedAt = NOW + 100, owner = "Mira Vale",
               players = { ["Mira Vale"] = { class = "SHAMAN", items = {} }, ["Odd|Tname"] = { class = "MAGE", items = {} } } }
local evilBack = ns.DecodeRun(ns.EncodeRun(evil))
check(evilBack and evilBack.name == "Badcffff0000Red!;,.'%" and evilBack.players["OddTname"] ~= nil,
      "escape sequences are dropped, separators in names survive")

print("-- importing")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 777777 end } } }
local records, runs = db.records[9001].runs, #ns.AllRuns()
run.owner = "Lichy Val" -- the run as Lichy Val would have recorded it
local theirs = ns.EncodeRun(run)
run.owner = "Mira Vale"
local got, why = ns.ImportCode(theirs)
check(got and got ~= run and got.sharedBy == "Lichy Val" and db.shared[1] == got, "kept as shared by Lichy Val (" .. tostring(why) .. ")")
check(got and same(figures(run), figures(got)), "valued as they saw it, not with your auction prices")
check(#ns.AllRuns() == runs and db.records[9001].runs == records and ns.Streak(got) == nil,
      "none of your statistics, records or streaks count it")
local insights = ns.RunInsights(got, ns.Summarize(got))
check(insights.groupPct == nil and insights.records == nil, "and it is not compared with your records")
Auctionator = nil
TEXTLOG = {}
ns.ShowRun(got)
check(ns.ViewedRun() == got and drew("shared by Lichy Val"), "the window shows it, marked as shared")
check(not ns.TogglePin(got), "it cannot be pinned")
check(ns.ImportCode(theirs) and #db.shared == 1, "importing it again replaces it")
check(ns.ImportCode(code) == run and #db.shared == 1, "a code of your own run opens the run itself")
local unknown = { name = "Odd Place", startedAt = NOW, endedAt = NOW + 60, owner = "Kett Longstride",
                  players = { ["Kett Longstride"] = { class = "HUNTER", items = {
                      ["item:999"] = { link = ItemLink(999, "Lost Ring", 3), count = 1, vendor = 5, cat = "rare", quality = 3, id = 1 } } } } }
local lost = ns.ImportCode(ns.EncodeRun(unknown))
local lostEntry = lost and select(2, next(lost.players["Kett Longstride"].items))
check(lostEntry and lostEntry.link:find("[Item 999]", 1, true), "an item this client does not know yet gets a stand-in name")
check(ns.DeleteRun(db.shared[1]) and ns.DeleteRun(db.shared[1]) and #db.shared == 0, "shared runs can be deleted")

print("-- the import window")
ns.ToggleImport()
local box, pasteArea, after = nil, nil, false
for _, w in ipairs(FRAMES) do
    if w == ThatLuckyBastardImportFrame then
        after = true
    elseif after and w.__kind == "ScrollFrame" and not pasteArea then
        pasteArea = w
    elseif after and w.__kind == "EditBox" then
        box = w
        break
    end
end
check(FOCUSED == box, "opening the window puts the cursor in the paste box, ready for Ctrl+V")
box:ClearFocus()
pasteArea.__scripts.OnMouseDown(pasteArea)
check(FOCUSED == box, "and so does a click anywhere in the paste area")
TEXTLOG = {}
box:SetText("nonsense")
click("Import")
check(drew("not a That Lucky Bastard code") and #db.shared == 0, "a wrong code says so")
box:SetText(theirs)
TEXTLOG = {}
click("Import")
check(#db.shared == 1 and ns.ViewedRun() == db.shared[1] and drew("shared by Lichy Val") and box:GetText() == "",
      "a pasted code is imported, listed and opened")
ns.ToggleImport()
check(not ThatLuckyBastardImportFrame:IsShown(), "the window closes on a second toggle")

print("-- the share window")
WORLD.guild = true
OPENED_CHAT = {}
ns.ShowRun(run)
check(click("Share") and ThatLuckyBastardShareFrame:IsShown(), "the Share button opens it")
check(hasButton("Say") and hasButton("Party") and hasButton("Raid") and hasButton("Guild") and hasButton("Officer")
      and hasButton("Instance") and hasButton("Yell") and hasButton("Dungeon Pals"),
      "it offers Say, Yell, Party, Raid, Instance, Guild, Officer and your own channels")
check(not hasButton("General") and not hasButton("Trade") and not hasButton("LocalDefense"), "but no global channel")
check(click("Guild") and OPENED_CHAT[1] == "/g " .. ns.ShareTag(run) and run.shared == true,
      "Guild: the tag waits in the chat box, for you to send (" .. tostring(OPENED_CHAT[1]) .. ")")
check(not ThatLuckyBastardShareFrame:IsShown(), "and the window gets out of the way")
ns.ToggleShare(run)
check(click("Dungeon Pals") and OPENED_CHAT[2] == "/5 " .. ns.ShareTag(run), "a channel of your own, by its number")
ns.ToggleShare(run)
check(hasButton("Emote") and hasButton("Raid warning") and hasButton("Our Club"),
      "Emote, Raid warning and your communities are offered too")
check(click("Our Club") and OPENED_CHAT[#OPENED_CHAT] == "/7 " .. ns.ShareTag(run), "a community, under its own name")
ns.ToggleShare(run)
check(click("Emote") and OPENED_CHAT[#OPENED_CHAT] == "/e " .. ns.ShareTag(run), "an emote")
check(ns.VERSION == "9.9.9", "the version shown beside Options comes from the .toc file")

print("-- whispering a link")
local nameBox, afterShare = nil, false
for _, w in ipairs(FRAMES) do
    if w == ThatLuckyBastardShareFrame then
        afterShare = true
    elseif afterShare and w.__kind == "EditBox" then
        nameBox = w
        break
    end
end
WORLD.target = "Lichy Val"
ns.ToggleShare(run)
check(nameBox:GetText() == "Lichy Val", "the name box offers the player you target")
nameBox:SetText("  Kett   Longstride ")
local opened = #OPENED_CHAT
check(click("Whisper") and #OPENED_CHAT == opened + 1 and OPENED_CHAT[#OPENED_CHAT] == ns.ShareTag(run)
      and CHAT_BOX:GetAttribute("chatType") == "WHISPER" and CHAT_BOX:GetAttribute("tellTarget") == "Kett Longstride",
      "Whisper: the chat box whispers the whole two-word name, with the tag in it")
check(not ThatLuckyBastardShareFrame:IsShown(), "and the window gets out of the way")
WORLD.target = nil
ns.ToggleShare(run)
check(nameBox:GetText() == "Kett Longstride", "the name whispered last is offered again")
nameBox:SetText("")
opened = #OPENED_CHAT
click("Whisper")
check(#OPENED_CHAT == opened and ThatLuckyBastardShareFrame:IsShown(), "with no name, nothing opens")

print("-- names offered as you type")
local partyWas = WORLD.party
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" } }
WORLD.friends = { "Bobby Tables", "Kett Longstride" }
WORLD.guild, WORLD.roster = true, { { "Borax Stone", "MAGE" } }
local peopleWas = db.people["Bob Builder"]
db.people["Bob Builder"] = { runs = 3, value = 0, lucky = 0, ninja = 0, class = "PALADIN" }
local function names(list)
    local t = {}
    for _, s in ipairs(list) do t[#t + 1] = s.name end
    return t
end
local function has(list, name)
    for _, n in ipairs(names(list)) do
        if n == name then return true end
    end
    return false
end
local bo = names(ns.NameSuggestions("bo"))
check(bo[1] == "Borin Oak" and bo[2] == "Bobby Tables" and bo[3] == "Borax Stone" and has(ns.NameSuggestions("bob b"), "Bob Builder"),
      "your group first, then friends, guild, and the players you have run with: " .. table.concat(bo, ", "))
check(#bo <= 5, "five names at most")
check(has(ns.NameSuggestions("TAB"), "Bobby Tables"), "any word of the name, in any case")
check(not has(ns.NameSuggestions("Borin Oak"), "Borin Oak"), "a name typed in full is not offered again")
check(not has(ns.NameSuggestions("mira"), "Mira Vale") and #ns.NameSuggestions("") == 0, "never yourself, and nothing for an empty box")

local suggest
for _, w in ipairs(FRAMES) do
    if rawget(w, "__strata") == "DIALOG" and rawget(w, "__parent") and rawget(w, "__parent").__parent == ThatLuckyBastardShareFrame then
        suggest = w
    end
end
local function typed(text)
    nameBox:SetText(text)
    nameBox.__scripts.OnTextChanged(nameBox, true)
end
TEXTLOG = {}
typed("bob")
check(suggest and suggest:IsShown() and drew("Bobby Tables"), "typing opens the list under the box")
nameBox.__scripts.OnTabPressed(nameBox)
check(nameBox:GetText() == "Bobby Tables" and not suggest:IsShown(), "Tab takes the first name")
typed("bo")
nameBox.__scripts.OnArrowPressed(nameBox, "DOWN")
nameBox.__scripts.OnArrowPressed(nameBox, "DOWN")
opened = #OPENED_CHAT
nameBox.__scripts.OnEnterPressed(nameBox)
check(nameBox:GetText() == bo[2] and #OPENED_CHAT == opened, "the arrow keys pick one, Enter takes it")
nameBox.__scripts.OnEnterPressed(nameBox)
check(#OPENED_CHAT == opened + 1 and CHAT_BOX:GetAttribute("tellTarget") == bo[2], "and Enter again whispers them")
ns.ToggleShare(run)
typed("bor")
nameBox.__scripts.OnEscapePressed(nameBox)
check(not suggest:IsShown(), "Escape closes the list")
WORLD.party, WORLD.friends, WORLD.guild, WORLD.roster = partyWas, nil, nil, nil
db.people["Bob Builder"] = peopleWas
ns.ToggleShare(run)
TEXTLOG = {}
ns.ToggleShare(run)
check(click("Show the code") and ThatLuckyBastardExportFrame:IsShown() and drew(ns.EncodeRun(run)),
      "the code opens in its own window, selected for copying")
ns.ToggleShare(run)
check(not ThatLuckyBastardShareFrame:IsShown(), "a second click closes the share window")
TEXTLOG = {}
ns.ToggleShare(db.shared[1])
check(drew("Only runs you recorded can be shared."), "a run shared with you cannot be shared on")
ns.ToggleShare(db.shared[1])
SlashCmdList.THATLUCKYBASTARD("share")
check(ThatLuckyBastardShareFrame:IsShown(), "/tlb share opens it too")
ns.ToggleShare(ns.ViewedRun())

print("-- the tag in other players' chat")
local tag = ns.ShareTag(run)
local link = "|Haddon:ThatLuckyBastard:run:" .. id .. ":Lichy Val|h"
local _, out = CHAT_FILTERS.CHAT_MSG_GUILD(nil, "CHAT_MSG_GUILD", "gg all " .. tag, "Lichy Val", "", "", "", "", 0, 0, "")
check(out and out:find(link, 1, true) and out:find("^gg all "), "in guild chat it becomes a link to Lichy Val's run")
local _, inTrade = CHAT_FILTERS.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", tag, "Lichy Val", "", "2. Trade - City", "", "", 2, 2, "Trade")
check(inTrade == nil, "in Trade it stays plain text")
local _, inOwn = CHAT_FILTERS.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", tag, "Lichy Val", "", "5. Dungeon Pals", "", "", 0, 5, "Dungeon Pals")
check(inOwn and inOwn:find(link, 1, true), "in a channel of your own it is a link")
local _, told = CHAT_FILTERS.CHAT_MSG_WHISPER_INFORM(nil, "CHAT_MSG_WHISPER_INFORM", tag, "Lichy Val")
check(told and told:find(":Mira Vale|h", 1, true), "in a whisper you sent, it points to your own run")
check(CHAT_FILTERS.CHAT_MSG_SAY and CHAT_FILTERS.CHAT_MSG_PARTY and CHAT_FILTERS.CHAT_MSG_RAID and CHAT_FILTERS.CHAT_MSG_OFFICER
      and CHAT_FILTERS.CHAT_MSG_YELL and CHAT_FILTERS.CHAT_MSG_INSTANCE_CHAT and CHAT_FILTERS.CHAT_MSG_EMOTE
      and CHAT_FILTERS.CHAT_MSG_RAID_WARNING and CHAT_FILTERS.CHAT_MSG_COMMUNITIES_CHANNEL,
      "say, yell, emote, party, raid, raid warning, instance, officer and community chat too")
local _, inClub = CHAT_FILTERS.CHAT_MSG_COMMUNITIES_CHANNEL(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", tag, "Lichy Val")
check(inClub and inClub:find(link, 1, true), "in a community it is a link")

print("-- clicking a link")
local notices = {}
local realNotice = ns.Notice
ns.Notice = function(title) notices[#notices + 1] = title end
SENT = {}
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:" .. id .. ":Mira Vale")
check(#SENT == 0 and ns.ViewedRun() == run, "your own link opens your run, asking nobody")
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:" .. id .. ":Lichy Val")
check(#SENT == 1 and SENT[1][1] == "TLB" and SENT[1][2] == "Q" .. id and SENT[1][3] == "WHISPER" and SENT[1][4] == "Lichy Val",
      "someone else's asks them for the run, in a hidden whisper")

-- Lichy Val's addon answers. Here it is this same addon, holding the run
-- as if Lichy Val had recorded it and posted its link.
local request = SENT[1][2]
SENT = {}
run.owner = "Lichy Val"
Fire("CHAT_MSG_ADDON", "TLB", request, "WHISPER", "Mira Vale")
run.owner = "Mira Vale"
RunTimers()
local total = 0
for _, m in ipairs(SENT) do
    if m[2]:match("^D" .. id .. ",") and m[4] == "Mira Vale" then total = total + 1 end
end
check(total == #SENT and total == math.ceil(#theirs / 236), ("the run goes back in %d hidden messages"):format(total))
for i = #SENT, 1, -1 do -- in any order
    Fire("CHAT_MSG_ADDON", "TLB", SENT[i][2], "WHISPER", "Lichy Val")
end
local arrived = db.shared[1]
check(arrived and arrived.sharedBy == "Lichy Val" and arrived.shareId == id and ns.ViewedRun() == arrived,
      "the run arrives whole, is kept and opens")
check(arrived and same(figures(run), figures(arrived)), "exactly as Lichy Val sees it")
SENT = {}
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:" .. id .. ":Lichy Val")
check(#SENT == 0 and ns.ViewedRun() == arrived, "clicking it again opens the copy you have")

print("-- a long run goes out at the pace the game allows")
local big = { name = "Big Keep", instanceID = 4242, startedAt = NOW - 7200, endedAt = NOW - 3600, owner = "Mira Vale",
              shared = true, players = {}, names = {}, log = {} }
for i = 1, 5 do
    local name = "Player " .. i
    big.names[i] = name
    local items = {}
    for j = 1, 40 do
        local n = (i - 1) * 40 + j
        items["item:" .. (20000 + n)] = { link = ItemLink(20000 + n, "Thing " .. n, 2), count = j, vendor = 100 * n,
                                          cat = "uncommon", quality = 2, ah = 1000 * n, id = n }
        big.log[#big.log + 1] = ("%d:%d:%d:1"):format(n * 7, i, n)
    end
    big.players[name] = { class = "MAGE", items = items }
end
table.insert(db.history, 2, big)
SENT = {}
Fire("CHAT_MSG_ADDON", "TLB", "Q" .. ns.ShareId(big), "WHISPER", "Lichy Val")
local burst = #SENT
RunTimers()
RunTimers()
local longest = 0
for _, m in ipairs(SENT) do longest = math.max(longest, #m[2]) end
check(burst == 8 and #SENT == math.ceil(#ns.EncodeRun(big) / 236) and longest <= 255,
      ("%d messages of at most 255 characters: 8 at once, then one at a time"):format(#SENT))
table.remove(db.history, 2)

print("-- when it does not work out")
SENT = {}
Fire("CHAT_MSG_ADDON", "TLB", "Q" .. ns.ShareId(db.active), "WHISPER", "Snoop Dogg")
check(#SENT == 1 and SENT[1][2] == "N" .. ns.ShareId(db.active), "a run you never posted a link to is not sent")
Fire("CHAT_MSG_ADDON", "TLB", "D" .. id .. ",1,1,TLB1!junk", "WHISPER", "Stranger")
check(#db.shared == 1, "a run nobody asked for is ignored")
notices = {}
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:zzz:Ghost Player")
Fire("CHAT_MSG_ADDON", "TLB", "Nzzz", "WHISPER", "Ghost Player")
check(notices[#notices] and notices[#notices]:find("no longer has that run", 1, true), "a refusal says so: " .. tostring(notices[#notices]))
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:yyy:Nobody Home")
NOW = NOW + 20
RunTimers()
check(notices[#notices] and notices[#notices]:find("No answer from Nobody Home", 1, true), "no answer at all: " .. tostring(notices[#notices]))
NOW = NOW + 5
SetItemRef("addon:ThatLuckyBastard:run:www:Prankster")
Fire("CHAT_MSG_ADDON", "TLB", "Dwww,1,1,TLB1!rubbish!", "WHISPER", "Prankster")
check(notices[#notices] and notices[#notices]:find("could not be read", 1, true) and #db.shared == 1,
      "a damaged answer is refused: " .. tostring(notices[#notices]))
ns.Notice = realNotice

print("-- shared runs take their place by date")
wipe(db.shared)
-- A copy of the run, as recorded by Lichy Val at another time.
local function SharedAt(startedAt)
    local savedStart, savedEnd, savedOwner = run.startedAt, run.endedAt, run.owner
    run.startedAt, run.endedAt, run.owner = startedAt, startedAt + (run.endedAt - run.startedAt), "Lichy Val"
    local theirCode = ns.EncodeRun(run)
    run.startedAt, run.endedAt, run.owner = savedStart, savedEnd, savedOwner
    return ns.ImportCode(theirCode)
end
local active = db.active
check(ns.InProgress(active) and active.startedAt > run.startedAt, "(your run in progress started after your other run)")
local between = SharedAt(math.floor((run.startedAt + active.startedAt) / 2))
local newest = SharedAt(active.startedAt + 600)
local oldest = SharedAt(run.startedAt - 600)
local function position(s)
    TEXTLOG = {}
    ns.ShowRun(s)
    for _, t in ipairs(TEXTLOG) do
        local i, n = t:match("%((%d+)/(%d+)%)")
        if i then return tonumber(i) .. "/" .. n end
    end
end
check(position(active) == "1/5" and position(newest) == "2/5" and position(between) == "3/5"
      and position(run) == "4/5" and position(oldest) == "5/5",
      "newest first: your run in progress, then the rest by when they started, shared or not")
TEXTLOG = {}
ns.ToggleImport()
local order = {}
for _, t in ipairs(TEXTLOG) do
    local date = t:match("^(%d+%-%d+%-%d+ %d+:%d+)   ")
    if date then order[#order + 1] = date end
end
check(#order == 3 and order[1] > order[2] and order[2] > order[3], "the Shared runs list is in date order too")
ns.ToggleImport()

print("-- how many shared runs are kept")
local ownBefore = #db.history
db.options.maxHistory = 2
ns.TrimHistory() -- as when a run ends
check(#db.shared == 2 and db.shared[1] == oldest and db.shared[2] == newest and #db.history == ownBefore,
      "a lower number of runs to keep drops the shared runs that arrived first, and none of yours")
local latest = SharedAt(run.startedAt - 1200)
check(#db.shared == 2 and db.shared[1] == latest and db.shared[2] == oldest, "importing past the number drops the first to arrive")
db.options.maxHistory = 300
for i = 1, 5 do SharedAt(run.startedAt - 1200 - i * 600) end
check(#db.shared == 7, "with the default 300, they all stay")

print("-- names in other alphabets")
-- Written as bytes: UTF-8 letters whose second byte (0x81, 0x8D, 0x8F,
-- 0x90, 0x9D) some systems take for a control character.
local ANNA = "\208\144\208\189\208\189\208\176 \208\160\208\190\209\129\209\129"   -- Cyrillic, with 0x90 and 0x81
local ELISE = "\195\137lise No\195\171l"                                           -- accents
local ODD = "\208\157\208\143\208\141 \196\129"                                    -- 0x9D, 0x8F, 0x8D, 0x81
local abroad = { name = "Far Keep", startedAt = NOW - 7200, endedAt = NOW - 3600, owner = ANNA, players = {} }
for i, name in ipairs({ ANNA, ELISE, ODD }) do
    abroad.players[name] = { class = "MAGE", items = { x = { link = ItemLink(100, "Green Gloves", 2), id = i, count = 1,
                                                             vendor = 1500, cat = "uncommon", quality = 2, resolved = true } } }
end
local home = ns.DecodeRun(ns.EncodeRun(abroad))
check(home and home.players[ANNA] and home.players[ELISE] and home.players[ODD] and home.recordedBy == ANNA,
      "names in Cyrillic or with accents come back from a code byte for byte")

print("-- codes written to waste time")
-- A code comes from someone else. These are made by hand, with a checksum
-- that fits, the way someone who means harm would make them.
local B64 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
local function Base64(n)
    local out = ""
    repeat
        local d = n % 64
        out = B64:sub(d + 1, d + 1) .. out
        n = (n - d) / 64
    until n == 0
    return out
end
-- `code` with some of its eight sections replaced: Forge(code, { [7] = "..." }).
local function Forge(from, sections)
    local parts = {}
    for part in (from:match("^(.*)![%w+/]+$") .. "!"):gmatch("(.-)!") do parts[#parts + 1] = part end
    for i, text in pairs(sections) do parts[i + 1] = text end -- parts[1] is the "TLB1" in front
    local body, sum = table.concat(parts, "!"), 0
    for i = 1, #body do sum = (sum * 31 + body:byte(i)) % 16777213 end
    return body .. "!" .. Base64(sum)
end
-- What reading `text` gives, and whether it took under a second.
local function Timed(text)
    local t0 = os.clock()
    local s, why = ns.DecodeRun(text)
    return s, why, os.clock() - t0 < 1
end
check(ns.DecodeRun(Forge(code, {})) ~= nil, "a code put together by hand reads like the real one")

local s1, why1, fast1 = Timed("TLB" .. (" "):rep(150000) .. "x")
check(s1 == nil and fast1, "150,000 spaces in a code: refused at once (" .. tostring(why1) .. ")")
local s2, why2, fast2 = Timed(("x"):rep(1000000))
check(s2 == nil and fast2 and why2 == "This is too long to be a run's code.", "a megabyte of text: " .. tostring(why2))
local s3, why3, fast3 = Timed("TLB1!" .. ("a"):rep(210000))
check(s3 == nil and fast3 and why3 == "This is too long to be a run's code.", "a code past 200,000 characters: too long")

-- Bosses: sixty at most.
local sixty = ns.DecodeRun(Forge(code, { [7] = ("1,"):rep(59) .. "1" }))
check(sixty and #sixty.bosses == 60, "sixty boss kills are read")
local s4, _, fast4 = Timed(Forge(code, { [7] = ("1,"):rep(60) .. "1" }))
check(s4 == nil and fast4, "sixty-one are not")
local s5, _, fast5 = Timed(Forge(code, { [7] = ("1,"):rep(90000) .. "1" }))
check(s5 == nil and fast5, "ninety thousand: refused at once")

-- Items: one player holding the same item again and again. Reading used
-- to take the square of their number.
local function Hoard(n) return Forge(code, { [4] = "1.MAGE" .. (",.1"):rep(n), [5] = "", [6] = "" }) end
local some, _, fast6 = Timed(Hoard(3000))
local held = 0
for _ in pairs(some and some.players["Mira Vale"].items or {}) do held = held + 1 end
check(some and held == 3000 and fast6, "three thousand entries of one item: read, each kept, in no time")
local s7, _, fast7 = Timed(Hoard(6001))
check(s7 == nil and fast7, "six thousand and one item entries: refused")
local s8, _, fast8 = Timed(Hoard(60000))
check(s8 == nil and fast8, "sixty thousand: refused at once")

-- Rolls: a player is in a roll once.
check(ns.DecodeRun(Forge(code, { [5] = "", [6] = "1.0.1.n,1(5,2(7" })) ~= nil, "a roll with two players reads")
check(ns.DecodeRun(Forge(code, { [5] = "", [6] = "1.0.1.n,1(5,1(7" })) == nil, "the same player twice in a roll: refused")
local crowd = {}
for i = 1, 30000 do crowd[i] = "1(5" end
local s9, _, fast9 = Timed(Forge(code, { [5] = "", [6] = "1.0.1.n," .. table.concat(crowd, ",") }))
check(s9 == nil and fast9, "a roll with thirty thousand entries: refused at once")

-- None of this is too strict for a raid: forty players, thirteen bosses,
-- some two thousand items and two hundred rolls.
local raid = { name = "Big Raid", instanceID = 409, startedAt = NOW - 4 * 3600, endedAt = NOW - 600, players = {},
               names = {}, log = {}, rollLog = {}, bosses = {}, rollStats = {}, kills = 13 }
local entry, pick = 0, 0
for i = 1, 40 do
    local name = ("Raider Number%02d"):format(i)
    raid.names[i] = name
    raid.players[name] = { class = "MAGE", role = "DAMAGER", items = {} }
    raid.rollStats[name] = { sum = 50 * 40, n = 40, passes = 3, high = 99, low = 2 }
    for k = 1, 55 do
        entry = entry + 1
        local link = ItemLink(40000 + (i * 7 + k * 13) % 400, "Thing", 2)
        local key = ns.EntryKey(link)
        if not raid.players[name].items[key] then
            raid.players[name].items[key] = { link = link, id = entry, count = 2, vendor = 1200 + k, ah = 30000 + k,
                                             cat = "uncommon", quality = 2, resolved = true }
            pick = pick + 1
            raid.log[pick] = ("%d:%d:%d:2"):format(pick * 4, i, entry)
        end
    end
end
raid.owner = raid.names[1]
for b = 1, 13 do raid.bosses[b] = { t = b * 1000, name = "Boss Number " .. b } end
for r = 1, 200 do
    local parts = {}
    for i = 1, 25 do parts[i] = ((r + i) % 40 + 1) .. "n" .. ((r * i) % 100 + 1) end
    raid.rollLog[r] = { k = tostring(40000 + r), t = r * 60, w = (r + 1) % 40 + 1, m = "n", r = table.concat(parts, ",") }
end
local raidCode = ns.EncodeRun(raid)
local raidBack, raidWhy, raidFast = Timed(raidCode)
local raidItems = 0
for _, p in pairs(raidBack and raidBack.players or {}) do
    for _ in pairs(p.items) do raidItems = raidItems + 1 end
end
print(("        a raid's code: %d characters, %d link messages"):format(#raidCode, math.ceil(#raidCode / 236)))
check(raidBack and raidFast and raidItems == pick and #raidBack.log == pick and #raidBack.rollLog == 200
      and #raidBack.bosses == 13, ("a raid of forty reads back whole: %d items, 200 rolls, 13 bosses (%s)")
          :format(raidItems, tostring(raidWhy)))
check(#raidCode < 600 * 236, "and its code fits what a link carries (600 messages, 141,600 characters)")
-- Ten thousand roll entries in all: forty players in 250 rolls, not 251.
local everyone = {}
for i = 1, 40 do everyone[i] = Base64(i) .. "(5" end
local function Rolls(n) return Forge(raidCode, { [6] = (("1.0.1.n," .. table.concat(everyone, ",") .. ";"):rep(n)):sub(1, -2) }) end
local full, _, fast10 = Timed(Rolls(250))
check(full and #full.rollLog == 250 and fast10, "forty players in 250 rolls: read")
local s11, _, fast11 = Timed(Rolls(251))
check(s11 == nil and fast11, "one roll more is over the limit on entries: refused")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (sharing)")
