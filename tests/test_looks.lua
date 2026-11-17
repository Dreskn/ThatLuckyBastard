-- Pictures of players during and after the run, quest items last, and
-- the unlimited history.
Include("test_run.lua")
print("\n==== pictures, quest order, unlimited ====")
local ns = NS
local db = ThatLuckyBastardDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
-- How many pictures were drawn from `what` ("class", "model:party", ...).
local function drawn(what)
    local n = 0
    for _, p in ipairs(PICTURES) do
        if p:sub(1, #what) == what then n = n + 1 end
    end
    return n
end

local old = db.history[1]
check(old.players["Kett Longstride"].gear == nil and old.players["Mira Vale"].race == nil,
      "nothing of the players' looks is saved")

-- The group is still together and in sight: everyone gets their own
-- picture. (The podium, which opens as the run in progress is left, is
-- closed so that only the main window draws.)
WORLD.inInstance, WORLD.visible = false, true
Fire("PLAYER_ENTERING_WORLD", false, false)
ThatLuckyBastardPodiumFrame:Hide()
db.options.useColumns = true
db.options.portrait = "3d"
PICTURES = {}
ns.ShowRun(old)
check(drawn("model:party") == 4 and drawn("model:player") == 1 and drawn("class") == 0,
      "3D, group in sight: five live models (" .. table.concat(PICTURES, " ") .. ")")
PICTURES = {}
ns.Rerender()
check(#PICTURES == 0, "and they are not loaded again on the next redraw")

-- The group is gone: everyone but me gets their class icon.
WORLD.party, WORLD.visible = {}, false
local MINE = { ["2d"] = "portrait:player", ["3d"] = "model:player" }
for _, mode in ipairs({ "2d", "class", "3d" }) do
    db.options.portrait = mode
    PICTURES = {}
    ns.Rerender()
    local icons = mode == "class" and 5 or 4
    check(drawn("class") == icons and (mode == "class" or drawn(MINE[mode]) == 1)
          and drawn("model:party") + drawn("portrait:party") == 0,
          mode .. ", group gone: everyone else gets their class icon (" .. table.concat(PICTURES, " ") .. ")")
end

-- The podium likewise.
PICTURES = {}
ns.OpenRunWindow("podium", old)
check(drawn("class") == 4 and drawn("model:player") == 1, "podium, group gone: four class icons, and my own model")

-- Saved looks from earlier versions are dropped when the addon loads.
old.players["Kett Longstride"].race, old.players["Kett Longstride"].gear = "Orc", { [1] = 5001 }
Fire("ADDON_LOADED", "ThatLuckyBastard")
check(old.players["Kett Longstride"].race == nil and old.players["Kett Longstride"].gear == nil,
      "saved looks from earlier versions are dropped at load")

-- Quest items last.
print("-- quest items")
ITEMS[200] = { 1, 0, 12, 4 }      -- a quest item
ITEMS[201] = { 2, 90000, 4, 2 }   -- an expensive green, named to sort after it
WORLD.inInstance, WORLD.party = true, { { "Borin Oak", "WARRIOR", "TANK" } }
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
Loot(("You receive loot: %s."):format(ItemLink(200, "Aaa Quest Thing", 1)))
Loot(("You receive loot: %s."):format(ItemLink(201, "Zzz Green", 2)))
Loot(("You receive loot: %s."):format(ItemLink(103, "Broken Fang", 0)))
local function lastItem(sortItems, grouped)
    db.options.sortItems, db.options.groupByCategory = sortItems, grouped
    local sum = ns.Summarize(db.active)
    for _, p in ipairs(sum.players) do
        if p.name == "Mira Vale" then
            local items = p.all.items
            return ns.ItemName(items[#items])
        end
    end
end
check(lastItem("value", false) == "Aaa Quest Thing", "ungrouped, by value: the quest item is last")
check(lastItem("name", false) == "Aaa Quest Thing", "ungrouped, by name: still last, despite its name")
db.options.sortItems, db.options.groupByCategory = "value", true
TEXTLOG = {}
ns.ShowWindow()
-- Within my own column: the group titles in the order they were drawn.
local seen, mine = {}, false
for i, text in ipairs(TEXTLOG) do
    if text:find("Mira Vale", 1, true) then
        mine = true
    elseif mine and (text:find("Juno Ash", 1, true) or text:find("Kett Longstride", 1, true)) then
        mine = false
    elseif mine then
        for _, word in ipairs({ "Junk", "Quest", "Green BoE" }) do
            if text:find(word, 1, true) and not seen[word] then seen[word] = i end
        end
    end
end
check(seen.Quest and seen.Junk and seen["Green BoE"] and seen.Quest > seen.Junk and seen.Junk > seen["Green BoE"],
      "grouped: the Quest group comes last, after Junk")
db.options.alignItems = true
ns.Rerender()
db.options.groupByCategory = false
ns.Rerender()
db.options.alignItems, db.options.groupByCategory = false, true

-- Unlimited history.
print("-- unlimited")
db.options.maxHistory = 99999
for i = 1, 500 do table.insert(db.history, { players = {}, startedAt = i }) end
ns.TrimHistory()
check(#db.history >= 500, "unlimited keeps everything (" .. #db.history .. " runs)")
db.options.maxHistory = 30
ns.TrimHistory()
check(#db.history == 30, "back to 30 trims again")
ns.ToggleOptions(); ns.ToggleOptions()

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (pictures, quest order, unlimited)")
