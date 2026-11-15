-- A simulated dungeon run, fed through the addon's real event handlers.
local ns = NS
local function check(ok, what)
    print((ok and "  ok    " or "  FAIL  ") .. what)
    if not ok then FAILED = (FAILED or 0) + 1 end
end
local function g(c) return ("%.2fg"):format(c / 10000) end

Fire("ADDON_LOADED", "FairShare")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
local db = FairShareDB
print("history runs at start: " .. #db.history)

-- Items: quality, sell price, classID (7 = trade goods), bindType (1 BoP, 2 BoE)
ITEMS[100] = { 2, 1500, 4, 2 }   -- green BoE
ITEMS[101] = { 3, 9000, 4, 2 }   -- blue BoE
ITEMS[102] = { 1, 50, 7, 0 }     -- cloth
ITEMS[103] = { 0, 300, 15, 0 }   -- junk
ITEMS[104] = { 3, 12000, 2, 1 }  -- blue BoP
local green, blue = ItemLink(100, "Green Gloves", 2), ItemLink(101, "Blue Blade", 3)
local cloth, junk, bop = ItemLink(102, "Silk Cloth", 1), ItemLink(103, "Broken Fang", 0), ItemLink(104, "Boss Mace", 3)

WORLD.party = { { "Borin Oak", "WARRIOR", "TANK" }, { "Sela Marrow", "MAGE", "DAMAGER" },
                { "Kett Longstride", "HUNTER", "DAMAGER" }, { "Juno Ash", "ROGUE", "DAMAGER" } }

local function runDungeon(id, name)
    WORLD.inInstance, WORLD.instanceID, WORLD.instance = true, id, name
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Fire("GROUP_ROSTER_UPDATE")
    local s = db.active
    check(s ~= nil and s.instanceID == id, "run started in " .. name)

    NOW = NOW + 60
    Loot(("You receive loot: %sx%d."):format(cloth, 3))
    Loot(("%s receives loot: %s."):format("Borin Oak", junk))
    NOW = NOW + 30
    -- A Greed roll: three greed, one pass, Sela wins with 88.
    Loot(("|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s"):format(7, green))
    Loot(("|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s"):format(7, "Sela Marrow", green))
    Loot(("|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s"):format(7, "Borin Oak", green))
    Loot(("|HlootHistory:%d|h[Loot]|h: %s passed on: %s"):format(7, "Kett Longstride", green))
    Loot(("|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"):format(7, 41, green, "Mira Vale"))
    Loot(("|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"):format(7, 88, green, "Sela Marrow"))
    Loot(("|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"):format(7, 12, green, "Borin Oak"))
    Loot(("|HlootHistory:%d|h[Loot]|h: %s won: %s"):format(7, "Sela Marrow", green))
    Loot(("%s receives loot: %s."):format("Sela Marrow", green))

    NOW = NOW + 240
    Fire("ENCOUNTER_END", 55, "Big Bad Boss", 1, 5, 1)
    NOW = NOW + 10
    -- A Need roll right after the boss: Kett needs, two greed, Kett wins.
    Loot(("|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"):format(8, "Kett Longstride", blue))
    Loot(("|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s"):format(8, blue))
    Loot(("|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s"):format(8, "Borin Oak", blue))
    Loot(("|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"):format(8, 3, blue, "Kett Longstride"))
    Loot(("|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"):format(8, 100, blue, "Mira Vale"))
    Loot(("|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"):format(8, 60, blue, "Borin Oak"))
    Loot(("%s receives loot: %s."):format("Kett Longstride", blue))          -- loot line first this time
    Loot(("|HlootHistory:%d|h[Loot]|h: %s won: %s"):format(8, "Kett Longstride", blue))
    Loot(("You receive loot: %s."):format(bop))
    NOW = NOW + 200
    Loot(("%s receives loot: %sx%d."):format("Juno Ash", cloth, 2))
    RunTimers()
    return s
end

local s = runDungeon(9001, "Test Keep")

print("-- recording")
check(#s.log == 6, "pickup log has 6 lines (got " .. #(s.log or {}) .. "): " .. table.concat(s.log or {}, "  "))
check(s.rollLog and #s.rollLog == 2, "roll log has 2 rolls")
for _, rec in ipairs(s.rollLog or {}) do print("        roll  k=" .. rec.k .. " t=" .. rec.t .. " w=" .. rec.w .. " m=" .. rec.m .. " r=" .. rec.r) end
check(s.bosses and s.bosses[1].name == "Big Bad Boss" and s.bosses[1].t == 330, "boss kill timed")
local st = s.rollStats["Mira Vale"]
check(st and st.n == 2 and st.high == 100 and st.low == 41, "my roll stats: 2 rolls, high 100, low 41")
check(s.rollStats["Kett Longstride"].passes == 1, "Kett's pass counted once")

print("-- derived")
local sum = ns.Summarize(s)
local kett, sela
for _, p in ipairs(sum.players) do
    if p.name == "Kett Longstride" then kett = p elseif p.name == "Sela Marrow" then sela = p end
end
check(kett.needWins == 1 and kett.needValue == 9000, "Kett's Need win tagged (9000c)")
check(sela.greedWins == 1, "Sela's Greed win tagged")
local rolls = ns.RunRolls(s)
check(#rolls == 2 and rolls[1].winner == "Sela Marrow" and rolls[2].method == "need", "roll sheet decodes")
for _, roll in ipairs(rolls) do
    local parts = {}
    for _, r in ipairs(roll.rolls) do parts[#parts + 1] = r.name .. " " .. r.choice .. " " .. tostring(r.roll) end
    print("        " .. roll.key .. " won by " .. roll.winner .. " (" .. roll.method .. "): " .. table.concat(parts, "; "))
end
local luck = ns.RunLuck(s)
check(math.abs(luck["Mira Vale"].expected - 1 / 3) < 1e-9 and luck["Mira Vale"].rolls == 2 and luck["Mira Vale"].wins == 0,
      "my luck: 2 rolls entered, expected 0.33 wins (a Greed against a Need counts for nothing), won 0")
check(luck["Kett Longstride"].expected == 1 and luck["Kett Longstride"].wins == 1, "Kett: expected 1, won 1")
local tl = ns.Timeline(s)
check(tl and #tl.series == 5, "timeline has 5 players")
for _, line in ipairs(tl.series) do
    local pts = {}
    for _, pt in ipairs(line.points) do pts[#pts + 1] = pt.t .. "s=" .. g(pt.v) end
    print("        " .. line.name .. ": " .. table.concat(pts, ", "))
end
local src = ns.Sources(s)
check(src and src.boss == 9000 + 12000 and src.mats == 250 and src.trash == 1800,
      ("sources: boss %s, mats %s, trash %s"):format(g(src.boss), g(src.mats), g(src.trash)))
print("        fairness " .. tostring(ns.Fairness(sum)) .. "/100")
local scores = ns.AwardScores(s, sum)
local awards = ns.Awards(s, sum)
for _, p in ipairs(sum.players) do
    local parts = {}
    for _, sc in ipairs(scores[p.name] or {}) do parts[#parts + 1] = ("%s %.2f"):format(sc.title, sc.fit) end
    print(("        %-18s %-14s <- %s"):format(p.name, awards[p.name].title, table.concat(parts, ", ")))
end
check(awards["Mira Vale"].key == "jackpot", "my best fit wins: Jackpot (1.51) over Natural 100 (0.75)")

print("-- leaving, and a second run with the same group")
WORLD.inInstance = false
Fire("PLAYER_ENTERING_WORLD", false, false)
check(s.leftAt ~= nil, "run marked as left")
NOW = NOW + 120
Fire("CHAT_MSG_SYSTEM", "Test Keep has been reset.")
check(db.active == nil and db.history[1] == s, "reset message closed the run")
check(s.statted and s.rolls == nil, "long-term figures counted; working data dropped")
local rec = db.records[9001]
check(rec and rec.tRuns == 1 and rec.tTime == 540 and rec.fairRuns == 1,
      ("dungeon record: timed runs %s, time %ss, fairness sum %s"):format(tostring(rec.tRuns), tostring(rec.tTime), tostring(rec.fairSum)))
check(db.drops[9001]["101"].n == 1 and db.drops[9001]["102"].c == 5 and db.drops[9001]["101"].by == "Kett Longstride",
      "drop table: blue seen once (last to Kett), 5 cloth")
check(db.me.rolls == 2 and db.me.rollN == 2 and db.people["Kett Longstride"].wins == 1, "luck added to the long-term figures")
check(db.roles.TANK and db.roles.TANK.n == 1 and db.classes.MAGE.n == 1, "role and class shares counted")
local runs, by = ns.ItemSeen(101)
check(runs == 1 and by == "Kett Longstride", "item tooltip data: seen in 1 run, last to Kett Longstride")

NOW = NOW + 300
local s2 = runDungeon(9001, "Test Keep")
check(s2 ~= s, "second run is a new run")
local streak = ns.Streak(s2)
check(streak and streak.count == 2 and streak.kind == "both", "streak: " .. (streak and ns.StreakLabel(streak) or "none"))
if streak then
    for _, row in ipairs(streak.standings) do print(("        %-18s %s over %d runs"):format(row.name, g(row.value), row.runs)) end
end

print("-- export")
local csv = ns.ExportRun(s)
print("        " .. csv:gsub("\n", "\n        "))
local all = ns.ExportAll()
local _, lines = all:gsub("\n", "\n")
check(lines >= 10, "all-runs export has " .. (lines + 1) .. " lines")

print(FAILED and (FAILED .. " check(s) FAILED") or "all checks passed")
