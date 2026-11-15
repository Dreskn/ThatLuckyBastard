-- Pictures of players after the group is gone, quest items last, and the
-- unlimited history.
Include("test_run.lua")
print("\n==== looks, quest order, unlimited ====")
local ns = NS
local db = FairShareDB
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function reset() ATLASES, TRYONS, CUSTOM_RACES = {}, {}, {} end

local old = db.history[1]
local kett = old.players["Kett Longstride"]
check(kett.race == "Orc" and kett.raceID == 2 and kett.sex == 2, "race and sex saved for a party member")
check(kett.gear and kett.gear[1] == 5001 and kett.gear[16] == 5016, "their visible gear saved")
check(old.players["Mira Vale"].sex == 3, "and my own")

-- The group is gone.
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
WORLD.party = {}

db.options.useColumns = true
db.options.portrait = "2d"
reset()
ns.ShowRun(old)
check(#ATLASES == 4 and ATLASES[1] == "raceicon128-orc-male", "2D: the four absent players get their race picture (" .. #ATLASES .. ")")

db.options.portrait = "class"
reset()
ns.Rerender()
check(#ATLASES == 0, "class icon mode stays the class icon")

db.options.portrait = "3d"
reset()
ns.Rerender()
check(#CUSTOM_RACES == 4 and CUSTOM_RACES[1] == "2:0", "3D: four models rebuilt as male orcs")
check(#TRYONS == 4 * 13, "each dressed in the 13 saved pieces (" .. #TRYONS .. " items put on)")
reset()
ns.Rerender()
check(#TRYONS == 0, "and not rebuilt again on the next redraw")

-- A model that loads late comes up bare: the gear goes on once more, once.
reset()
local model
for _, w in ipairs(FRAMES) do
    if w.__kind == "DressUpModel" and rawget(w, "look") then model = w end
end
check(model ~= nil, "a rebuilt model is waiting for its body to load")
if model then
    model.__scripts.OnModelLoaded(model)
    check(#TRYONS == 13, "gear put on again when the body has loaded")
    model.__scripts.OnModelLoaded(model)
    check(#TRYONS == 13, "but only once")
end

-- The podium uses the same stand-ins. It opened by itself when the run
-- ended, so close it first: models are set up afresh each time it opens.
FairShareShowFrame:Hide()
reset()
ns.OpenShow(old, false, "podium")
check(#CUSTOM_RACES == 4, "podium: four look-alikes, and my own live model (" .. #CUSTOM_RACES .. ")")

-- Too little gear is no likeness: back to the flat picture.
old.players["Kett Longstride"].gear = { [1] = 5001 }
db.options.portrait = "3d"
reset()
ns.ShowRun(db.active or old) -- another run first, so the columns are redrawn from scratch
ns.ShowRun(old)
check(#CUSTOM_RACES <= 3, "a player with one piece of gear saved is not rebuilt")

-- A run from before looks were saved: class icons, as before.
for _, p in pairs(old.players) do p.race, p.raceID, p.sex, p.gear = nil, nil, nil, nil end
db.options.portrait = "2d"
reset()
ns.Rerender()
check(#ATLASES == 0 and #CUSTOM_RACES == 0, "a run without saved looks falls back to class icons")

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

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed (looks, quest order, unlimited)")
