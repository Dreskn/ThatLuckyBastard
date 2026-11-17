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
local function hasButton(label)
    for _, w in ipairs(FRAMES) do
        local t = rawget(w, "text")
        if type(t) == "table" and t.__text == label then return true end
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
      and CHAT_FILTERS.CHAT_MSG_YELL and CHAT_FILTERS.CHAT_MSG_INSTANCE_CHAT, "say, yell, party, raid, instance and officer chat too")

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

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (sharing)")
