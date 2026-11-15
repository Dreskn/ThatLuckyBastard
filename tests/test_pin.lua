-- Pinning and deleting runs.
Include("test_run.lua")
print("\n==== pinning and deleting ====")
local ns = NS
local db = ThatLuckyBastardDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end

function PinOutlineShown()
    return ThatLuckyBastardPinOutline ~= nil and ThatLuckyBastardPinOutline:IsShown()
end

-- After the simulated runs: one run in the history, one in progress.
local old, cur = db.history[1], db.active
check(old ~= nil and cur ~= nil, "one finished run and one in progress")

-- A third, finished run, to have something to trim and clear.
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
NOW = NOW + 5000
Fire("PLAYER_ENTERING_WORLD", false, false) -- long gone: the run is closed
check(db.active == nil and #db.history == 2, "second run closed: 2 in the history")
local newest = db.history[1]

check(ns.TogglePin(old) and old.pinned == true, "pin the older run")
ns.ShowRun(old)
check(PinOutlineShown(), "main window shows the gold outline for a pinned run")
ns.ShowRun(newest)
check(not PinOutlineShown(), "and no outline for a run that is not pinned")
ns.ShowBrowse("runs")
check(not ns.DeleteRun(old) and #db.history == 2, "a pinned run cannot be deleted")
ns.AskDeleteRun(old) -- only prints why

-- The limit on runs to keep neither drops nor counts a pinned run.
db.options.maxHistory = 1
ns.TrimHistory()
check(#db.history == 2, "limit of 1: the pinned run and one other remain")
db.options.maxHistory = 0
ns.TrimHistory()
check(#db.history == 1 and db.history[1] == old, "limit of 0: only the pinned run remains")
db.options.maxHistory = 30

-- Clearing leaves pinned runs.
table.insert(db.history, 1, newest)
SlashCmdList.THATLUCKYBASTARD("clear")
check(#db.history == 1 and db.history[1] == old, "/tlb clear leaves the pinned run")

-- The popup's Yes button deletes the run that was asked about.
table.insert(db.history, 1, newest)
ns.AskDeleteRun(newest)
StaticPopupDialogs.THATLUCKYBASTARD_DELETE_RUN.OnAccept()
check(#db.history == 1 and db.history[1] == old, "confirming the question deletes that run only")
StaticPopupDialogs.THATLUCKYBASTARD_DELETE_RUN.OnAccept()
check(#db.history == 1, "confirming twice deletes nothing more")

-- Unpinning makes it deletable again; the slash commands act on the run on show.
ns.ShowRun(old)
SlashCmdList.THATLUCKYBASTARD("pin")
check(old.pinned == nil, "/tlb pin unpins the run on show")
SlashCmdList.THATLUCKYBASTARD("delete")
StaticPopupDialogs.THATLUCKYBASTARD_DELETE_RUN.OnAccept()
RunTimers()
check(#db.history == 0, "/tlb delete, confirmed, deletes it")
check(db.records[9001] ~= nil and db.records[9001].runs == 2, "statistics keep what the deleted runs added")
ns.ShowWindow()
SlashCmdList.THATLUCKYBASTARD("pin")
SlashCmdList.THATLUCKYBASTARD("delete")

-- Deleting the run in progress starts a fresh one when still inside.
WORLD.inInstance = true
Fire("PLAYER_ENTERING_WORLD", false, false)
local running = db.active
check(running ~= nil, "a run is in progress")
check(ns.DeleteRun(running) and db.active ~= nil and db.active ~= running, "deleting it starts a fresh run")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (pinning and deleting)")
