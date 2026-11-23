-- Opens every window and tooltip on the simulated runs. The widgets are
-- stand-ins, so this proves the code runs without errors and shows the
-- text it writes; it cannot show what anything looks like.
Include("test_run.lua")
print("\n==== windows ====")
local ns = NS
local db = ThatLuckyBastardDB
local function step(what, fn)
    TEXTLOG = {}
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        print("  ok    " .. what)
    else
        print("  FAIL  " .. what .. "\n" .. tostring(err))
        FAILED = (FAILED or 0) + 1
    end
    RunTimers()
    return TEXTLOG
end
-- The texts a step wrote, colour codes stripped, a few per line.
local function show(log, limit)
    local out = {}
    for i = 1, math.min(#log, limit or 40) do
        local text = log[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("\n", " / ")
        out[#out + 1] = text
    end
    print("        " .. table.concat(out, "  |  "))
end

local old, cur = db.history[1], db.active

step("main window, column view", function() ns.ShowWindow() end)
show(step("main window, older run", function() ns.ShowRun(old) end), 60)
step("main window, list view", function() db.options.useColumns = false; ns.Rerender() end)
step("main window, back to columns, modern theme", function() db.options.useColumns = true; ns.SetTheme("modern") end)
step("main window, classic theme", function() ns.SetTheme("classic") end)

print("-- statistics")
for _, page in ipairs({ "dungeons", "records", "runs", "luck", "regulars", "drops", "roles", "search", "awards" }) do
    show(step("statistics: " .. page, function() ns.ShowBrowse(page, page == "search" and "cloth" or nil) end), 34)
end
step("statistics via slash commands", function()
    for _, cmd in ipairs({ "stats", "runs", "luck", "drops", "roles", "dungeons", "regulars", "records", "awards", "search silk" }) do
        SlashCmdList.THATLUCKYBASTARD(cmd)
    end
end)

print("-- the run windows")
for _, key in ipairs({ "paper", "analysis" }) do
    show(step(key .. " window (finished run)", function() ns.OpenRunWindow(key, old) end), 70)
    step(key .. " window (run in progress)", function() ns.OpenRunWindow(key, cur) end)
    step(key .. " window with no run", function() ns.OpenRunWindow(key, nil) end)
end

print("-- the tabs of the Analysis window")
for _, tab in ipairs({ "timeline", "rolls", "numbers" }) do
    ns.ShowRun(old)
    show(step("analysis: " .. tab .. " (finished run)", function() ns.ShowAnalysis(tab, old) end), 70)
    step("analysis: " .. tab .. " (run in progress)", function() ns.ShowRun(cur) end)
end
step("run windows and tabs via slash commands", function()
    for _, cmd in ipairs({ "paper", "analysis", "timeline", "rolls", "numbers" }) do
        SlashCmdList.THATLUCKYBASTARD(cmd)
    end
end)

print("-- export")
show(step("export this run", function() ns.ShowExport("run", old) end), 3)
step("export all runs", function() ns.ShowExport("all") end)
step("export via slash", function() SlashCmdList.THATLUCKYBASTARD("export"); SlashCmdList.THATLUCKYBASTARD("export all") end)

print("-- tooltips and notices")
step("item tooltip line", function()
    TIP = {}
    TOOLTIP_HOOKS[Enum.TooltipDataType.Item](GameTooltip, { id = 101 })
    assert(#TIP == 1, "expected one line")
    print("        " .. TIP[1])
    TIP = {}
    TOOLTIP_HOOKS[Enum.TooltipDataType.Item](GameTooltip, { id = 424242 })
    assert(#TIP == 0, "unknown item must add nothing")
end)
step("player tooltip line", function()
    -- (Kett's counts, as a run closed with him in it leaves them.)
    TIP = {}
    function GameTooltip:GetUnit() return "Kett Longstride", "party3" end
    TOOLTIP_HOOKS[Enum.TooltipDataType.Unit](GameTooltip, {})
    assert(#TIP == 1, "expected one line")
    print("        " .. TIP[1])
end)
show(step("familiar faces when a group forms", function()
    local party = WORLD.party
    WORLD.party = {}
    Fire("GROUP_ROSTER_UPDATE"); RunTimers()     -- no group: forget everyone
    WORLD.party = party
    -- Notices come one at a time: let the ones on screen run out.
    local toast = ThatLuckyBastardToast
    for _ = 1, 20 do
        if toast:IsShown() then toast.__scripts.OnUpdate(toast, 10) end
    end
    TEXTLOG = {}
    Fire("GROUP_ROSTER_UPDATE"); RunTimers()
    local met = 0
    for _, text in ipairs(TEXTLOG) do
        if text:find("met before", 1, true) then met = met + 1 end
    end
    assert(met >= 1, "expected at least one familiar-face notice, got " .. met)
    print("        notices queued for people met before; first shown: " .. TEXTLOG[1] .. "  /  " .. tostring(TEXTLOG[2]))
end), 0)
step("leaving the second run: window footer shows fairness and the streak", function()
    WORLD.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    local fair, streak
    for _, text in ipairs(TEXTLOG) do
        if text:find("Fairness", 1, true) then fair = text end
        if text:find("run in a row", 1, true) then streak = text end
    end
    assert(fair, "no fairness in the footer")
    assert(streak, "no streak line in the footer")
    print("        " .. fair:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    print("        " .. streak:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end)
step("main window item rows: hover every row", function()
    ns.ShowRun(old)
    local hovered = 0
    for _, w in ipairs(FRAMES) do
        local enter = w.__scripts.OnEnter
        if enter and rawget(w, "line") then
            enter(w)
            hovered = hovered + 1
        end
    end
    print("        hovered " .. hovered .. " rows; last tooltip: " .. table.concat(TIP, " / "))
end)
step("options, minimap", function()
    ns.ToggleOptions(); ns.ToggleOptions()
    SlashCmdList.THATLUCKYBASTARD("help")
end)

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed")

-- Called directly: at the end of a run it runs protected, which would hide a fault.
step("streak notice", function()
    local got
    local real = NS.Notice
    NS.Notice = function(title, text) got = title .. "  /  " .. text end
    NS.StreakNotice(ThatLuckyBastardDB.active or ThatLuckyBastardDB.history[1])
    NS.Notice = real
    assert(got and got:find("run in a row", 1, true), "no streak notice")
    print("        " .. got:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end)
print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (including the streak notice)")
