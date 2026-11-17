-- The summary in chat: plain lines anyone can read, built as the Share
-- options say, and posted only when a channel is clicked.
Include("test_run.lua")
print("\n==== summary in chat ====")
local ns = NS
local db = ThatLuckyBastardDB
local o = db.options
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
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
-- A channel button of the share window, by its label.
local function button(label)
    for _, w in ipairs(FRAMES) do
        local tpl = rawget(w, "tpl")
        if type(tpl) == "table" and tpl.__text == label then return w end
    end
end
local function drew(text)
    for _, t in ipairs(TEXTLOG) do
        if t:find(text, 1, true) then return true end
    end
    return false
end
local function any(lines, pattern)
    for _, line in ipairs(lines) do
        if line:find(pattern) then return true end
    end
    return false
end

local run = db.history[1]
WORLD.inInstance, WORLD.guild = false, true
WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { "Kett Longstride", "HUNTER", "DAMAGER" }, { "Lichy Val", "PRIEST", "HEALER" } }
local players = #ns.Summarize(run).players
local awards = ns.RunAwards(run, ns.Summarize(run))
local anAward
for _, a in pairs(awards) do anAward = a.title end

print("-- the lines")
check(o.shareMode == "link" and o.summaryLines == 5 and o.summaryLink and o.summaryAward and not o.summaryGap,
      "defaults: Link mode; a summary lists the top 5 with their share and award")
local lines = ns.SummaryLines(run)
check(#lines == math.min(players, 5) + 1, "a first line, then one per player (" .. #lines .. " lines)")
check(lines[1]:find("^%[That Lucky Bastard: ") and lines[1]:find("in all", 1, true),
      "the first line is the run's link, with the group's total: " .. lines[1])
check(lines[2]:find("^1%. ") and lines[2]:find("%d+%%"), "then 1. name, amount and share: " .. lines[2])
check(anAward ~= nil and any(lines, anAward), "with each player's award")
local bars = false
for _, line in ipairs(lines) do if line:find("|", 1, true) then bars = true end end
check(not bars, "no escape codes: chat would refuse them")

o.summaryLines = 3
lines = ns.SummaryLines(run)
check(#lines == 5 and lines[5] == ("and %d more"):format(players - 3), "Top 3: three players, and how many more")
o.summaryLines, o.summaryLink, o.summaryGap, o.summaryShare, o.summaryAward = 5, false, true, false, false
lines = ns.SummaryLines(run)
check(lines[1]:find("^That Lucky Bastard: ") ~= nil, "without the link, the first line just names the run")
check(any(lines, "%(%+") and not any(lines, "%%") and not (anAward and any(lines, anAward)),
      "the gap to an equal split instead of the share, and no awards")
o.summaryLink, o.summaryGap, o.summaryShare, o.summaryAward = true, false, true, true
lines = ns.SummaryLines(run)

print("-- posting")
CHAT_SENT, OPENED_CHAT = {}, {}
run.shared = nil
ns.ToggleShare(run)
check(#CHAT_SENT == 0, "opening the window posts nothing")
TEXTLOG = {}
check(click("Summary") and o.shareMode == "summary" and drew(lines[2]), "Summary shows the lines it will post")
check(button("Emote").on == false and button("Raid warning").on == false and button("Party").on == true,
      "Emote and Raid warning are not offered for several lines")
click("Party")
local same = #CHAT_SENT == #lines
for i, sent in ipairs(CHAT_SENT) do
    if sent[1] ~= lines[i] or sent[2] ~= "PARTY" then same = false end
end
check(same and #OPENED_CHAT == 0, "a click on Party sends the lines to the party, nothing waits in the chat box")
check(run.shared == true, "and the run's link answers clicks")
check(not ThatLuckyBastardShareFrame:IsShown(), "the window closes")

CHAT_SENT = {}
ns.ToggleShare(run)
click("Dungeon Pals")
check(#CHAT_SENT == #lines and CHAT_SENT[1][2] == "CHANNEL" and CHAT_SENT[1][3] == 5, "a channel of yours, by its number")
CHAT_SENT = {}
ns.ToggleShare(run)
click("Our Club")
check(#CHAT_SENT == #lines and CHAT_SENT[1][2] == "CLUB" and CHAT_SENT[1][3] == "4242:1",
      "a community, through its own chat")

local nameBox, afterShare = nil, false
for _, w in ipairs(FRAMES) do
    if w == ThatLuckyBastardShareFrame then
        afterShare = true
    elseif afterShare and w.__kind == "EditBox" then
        nameBox = w
        break
    end
end
CHAT_SENT = {}
ns.ToggleShare(run)
nameBox:SetText("Kett Longstride")
click("Whisper")
check(#CHAT_SENT == #lines and CHAT_SENT[1][2] == "WHISPER" and CHAT_SENT[1][3] == "Kett Longstride",
      "Whisper sends the lines to the whole two-word name")

print("-- link mode is unchanged")
CHAT_SENT = {}
ns.ToggleShare(run)
click("Link")
click("Party")
check(o.shareMode == "link" and #CHAT_SENT == 0 and OPENED_CHAT[#OPENED_CHAT] == "/p " .. ns.ShareTag(run),
      "Link leaves the tag in the chat box, for you to send")

print("-- nothing on its own")
CHAT_SENT = {}
o.shareMode = "summary"
WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, 77, "Another Place"
Fire("PLAYER_ENTERING_WORLD", false, false)
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
check(#CHAT_SENT == 0, "a run ending posts nothing, even with Summary chosen")

print("-- options")
ns.ToggleOptions()
-- The box where the number of players is typed: the options' only edit box.
local count
for _, w in ipairs(FRAMES) do
    local up = w
    while up and up ~= ThatLuckyBastardOptionsFrame do up = rawget(up, "__parent") end
    if up and w.__kind == "EditBox" then count = w end
end
check(count and count:GetText() == "5", "Options > Share: a box with the number of players, 5")
count:SetText("8")
count.__scripts.OnEditFocusLost(count)
check(o.summaryLines == 8 and #ns.SummaryLines(run) == math.min(players, 8) + 1, "typing 8 lists up to 8")
count:SetText("99")
count.__scripts.OnEditFocusLost(count)
check(o.summaryLines == 25 and count:GetText() == "25", "at most 25")
count:SetText("0")
count.__scripts.OnEditFocusLost(count)
check(o.summaryLines == 1, "at least 1")
count:SetText("")
count.__scripts.OnEditFocusLost(count)
check(o.summaryLines == 1 and count:GetText() == "1", "an empty box keeps the number")
count:SetText("5")
count.__scripts.OnEditFocusLost(count)
TEXTLOG = {}
ns.SyncOptions()
check(drew("1. "), "with a preview of the lines")
ns.ToggleOptions()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (summary in chat)")
