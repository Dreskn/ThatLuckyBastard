-- Fake runs for testing the That Lucky Bastard window. Only WHAT HAPPENED is
-- made up: who looted what and when, the rolls, the boss kills and the
-- coins. Every item is given as an item ID, and the addon values it exactly
-- like real loot (vendor price and category from the game client, auction
-- price from Auctionator / TSM). Item IDs that do not exist on this client
-- are skipped, with their rolls.
--
-- A run: name, startedAt, length (minutes), players[name] = { class, role },
-- bosses = { { minute, name } }, coins[name] = copper, and loot, in order:
--   { minute, who, itemID, count }                    a pickup
--   { minute, who, itemID, 1, { [name] = "n98" } }    won in a roll: everyone's
--     choice (n Need, g Greed, p pass) and number; `who` won it.
--
-- The runs live in memory only: remove this addon and they are gone.

if not ThatLuckyBastard or not ThatLuckyBastard.AddExampleRun then return end

local me = (GetUnitName and GetUnitName("player", true)) or UnitName("player") or "You"
local myClass = select(2, UnitClass("player"))

----------------------------------------------------------------------
-- Run 1: an unfair dungeon. The hunter skins everything, the rogue
-- Needs an epic staff with a 98 against the tank's 97.
----------------------------------------------------------------------

ThatLuckyBastard.AddExampleRun({
    name = "The Deadmines",
    startedAt = time() - 3600,
    length = 52,
    players = {
        [me] = { class = myClass, role = "DAMAGER" },
        Skinnyjoe = { class = "HUNTER", role = "DAMAGER" },
        Vexia = { class = "ROGUE", role = "DAMAGER" },
        Thorgrim = { class = "WARRIOR", role = "TANK" },
        Elyndra = { class = "PRIEST", role = "HEALER" },
    },
    bosses = {
        { 6, "Rhahk'Zor" }, { 14, "Sneed" }, { 19, "Gilnid" }, { 27, "Mr. Smite" },
        { 38, "Captain Greenskin" }, { 44, "Edwin VanCleef" }, { 48, "Cookie" },
    },
    coins = { [me] = 18240, Skinnyjoe = 15960, Vexia = 18240, Thorgrim = 18240, Elyndra = 17110 },
    loot = {
        { 3, "Skinnyjoe", 2318, 4 },    -- Light Leather
        { 4, me, 2589, 5 },             -- Linen Cloth
        { 5, "Skinnyjoe", 2589, 4 },
        { 6, "Elyndra", 2589, 7 },
        { 7, "Vexia", 2447, 3 },        -- Peacebloom
        { 8, "Skinnyjoe", 2318, 5 },
        { 9, "Skinnyjoe", 7073, 3 },    -- Broken Fang (junk)
        { 10, "Skinnyjoe", 783, 2 },    -- Light Hide
        { 11, me, 4865, 2 },            -- Ruined Pelt (junk)
        { 12, "Skinnyjoe", 2318, 6 },
        { 13, "Vexia", 2589, 6 },
        { 15, "Thorgrim", 2770, 5 },    -- Copper Ore
        { 16, me, 2589, 5 },
        { 17, "Skinnyjoe", 2318, 4 },
        { 18, "Vexia", 7074, 5 },       -- Chipped Claw (junk)
        { 19, "Elyndra", 1210, 1 },     -- Shadowgem
        { 20, "Skinnyjoe", 2589, 5 },
        { 21, "Vexia", 873, 1,          -- Staff of Jordan (epic BoE)
          { Vexia = "n98", Thorgrim = "n97", Skinnyjoe = "g88", [me] = "g41", Elyndra = "g9" } },
        { 22, "Vexia", 2447, 5 },
        { 23, "Skinnyjoe", 2318, 5 },
        { 24, "Thorgrim", 2770, 7 },
        { 25, "Skinnyjoe", 783, 2 },
        { 26, "Skinnyjoe", 7073, 4 },
        { 27, "Thorgrim", 7230, 1,      -- Smite's Mighty Hammer (BoP)
          { Thorgrim = "n64", Vexia = "n12", [me] = "g33", Skinnyjoe = "p", Elyndra = "p" } },
        { 28, "Vexia", 2589, 5 },
        { 29, "Skinnyjoe", 2318, 6 },
        { 30, me, 2589, 4 },
        { 31, "Skinnyjoe", 2319, 5 },   -- Medium Leather
        { 33, "Skinnyjoe", 1482, 1,     -- Shadowfang (blue BoE)
          { Skinnyjoe = "n55", Thorgrim = "n31", [me] = "g71", Vexia = "g40", Elyndra = "g1" } },
        { 33.5, "Skinnyjoe", 4232, 1 }, -- Medium Hide
        { 34, me, 2592, 3 },            -- Wool Cloth
        { 35, "Skinnyjoe", 2318, 4 },
        { 36, me, 4865, 2 },
        { 37, "Skinnyjoe", 2319, 6 },
        { 38, "Elyndra", 5201, 1,       -- Emberstone Staff (BoP)
          { Elyndra = "n77", [me] = "g50", Vexia = "g30", Thorgrim = "p", Skinnyjoe = "p" } },
        { 39, "Thorgrim", 858, 2 },     -- Lesser Healing Potion
        { 40, "Skinnyjoe", 783, 1 },
        { 41, "Skinnyjoe", 2318, 4 },
        { 42, "Elyndra", 2592, 4 },
        { 43, "Skinnyjoe", 2319, 5 },
        { 44, me, 5191, 1,              -- Cruel Barb (BoP)
          { [me] = "n100", Vexia = "n61", Thorgrim = "g72", Skinnyjoe = "g15", Elyndra = "p" } },
        { 45, me, 2592, 3 },
        { 46, "Skinnyjoe", 4232, 2 },
        { 47, "Skinnyjoe", 2319, 6 },
    },
})

----------------------------------------------------------------------
-- Run 2: an even dungeon with a close top three, and a mage who stayed
-- at the entrance: nothing looted, nothing rolled on, no coins.
----------------------------------------------------------------------

ThatLuckyBastard.AddExampleRun({
    name = "Scarlet Monastery",
    startedAt = time() - 2 * 86400,
    length = 38,
    players = {
        [me] = { class = myClass, role = "DAMAGER" },
        Thorgrim = { class = "WARRIOR", role = "TANK" },
        Elyndra = { class = "PRIEST", role = "HEALER" },
        Vexia = { class = "ROGUE", role = "DAMAGER" },
        Quietmage = { class = "MAGE", role = "DAMAGER" },
    },
    bosses = {
        { 9, "High Inquisitor Fairbanks" }, { 24, "Scarlet Commander Mograine" },
        { 27, "High Inquisitor Whitemane" },
    },
    coins = { [me] = 9470, Thorgrim = 9470, Elyndra = 9470, Vexia = 9470 },
    loot = {
        { 4, "Elyndra", 4306, 7 },      -- Silk Cloth
        { 5, me, 4306, 6 },
        { 7, "Vexia", 4306, 5 },
        { 8, "Thorgrim", 4306, 8 },
        { 12, "Thorgrim", 3864, 1 },    -- Citrine
        { 14, "Elyndra", 4306, 7 },
        { 15, me, 4306, 6 },
        { 18, "Elyndra", 1529, 1 },     -- Jade
        { 19, "Vexia", 4306, 5 },
        { 20, me, 3827, 2 },            -- Mana Potion
        { 22, "Thorgrim", 4306, 8 },
        { 24, "Thorgrim", 7723, 1,      -- Mograine's Might (BoP)
          { Thorgrim = "n45", [me] = "g90", Elyndra = "g22", Vexia = "g67" } },
        { 25, "Vexia", 4338, 3 },       -- Mageweave Cloth
        { 27, me, 7720, 1,              -- Whitemane's Chapeau (BoP)
          { [me] = "n87", Elyndra = "n85", Vexia = "p", Thorgrim = "p" } },
        { 29, "Elyndra", 4306, 6 },
        { 31, me, 4306, 6 },
        { 33, "Vexia", 4306, 5 },
        { 35, "Elyndra", 4338, 2 },
        { 36, "Vexia", 3827, 1 },
    },
})

----------------------------------------------------------------------
-- Run 3: a 40-player raid: columns for its top five, a bench with more
-- players than it has room for, awards held by three players, a roll on
-- every boss drop, and a long list to scroll. Who gets what is generated,
-- but the same every time.
----------------------------------------------------------------------

do
    local roster = {
        { me, myClass, "DAMAGER" }, { "Thorgrim", "WARRIOR", "TANK" }, { "Elyndra", "PRIEST", "HEALER" },
        { "Vexia", "ROGUE", "DAMAGER" }, { "Skinnyjoe", "HUNTER", "DAMAGER" }, { "Quietmage", "MAGE", "DAMAGER" },
        { "Bramblehoof", "DRUID", "HEALER" }, { "Lighthammer", "PALADIN", "HEALER" },
        { "Zulrokk", "SHAMAN", "HEALER" }, { "Nethersip", "WARLOCK", "DAMAGER" },
        { "Grumbar", "WARRIOR", "TANK" }, { "Ironhide", "WARRIOR", "TANK" }, { "Moonwhisper", "DRUID", "HEALER" },
        { "Stabbington", "ROGUE", "DAMAGER" }, { "Frostina", "MAGE", "DAMAGER" }, { "Mendwell", "PRIEST", "HEALER" },
        { "Petwrangler", "HUNTER", "DAMAGER" }, { "Totemic", "SHAMAN", "HEALER" }, { "Doomsayer", "WARLOCK", "DAMAGER" },
        { "Shieldwall", "PALADIN", "HEALER" }, { "Cleavehard", "WARRIOR", "DAMAGER" }, { "Emberly", "MAGE", "DAMAGER" },
        { "Nightstep", "ROGUE", "DAMAGER" }, { "Barkskin", "DRUID", "DAMAGER" }, { "Longshot", "HUNTER", "DAMAGER" },
        { "Soulsiphon", "WARLOCK", "DAMAGER" }, { "Stormcaller", "SHAMAN", "DAMAGER" }, { "Dawnbringer", "PALADIN", "HEALER" },
        { "Whisperwind", "PRIEST", "DAMAGER" }, { "Arcanist", "MAGE", "DAMAGER" }, { "Backstabber", "ROGUE", "DAMAGER" },
        { "Hoofbeat", "DRUID", "DAMAGER" }, { "Trueshot", "HUNTER", "DAMAGER" }, { "Hexweaver", "WARLOCK", "DAMAGER" },
        { "Earthshaker", "SHAMAN", "DAMAGER" }, { "Gravelord", "WARRIOR", "DAMAGER" }, { "Sunward", "PRIEST", "HEALER" },
        { "Pyroclasm", "MAGE", "DAMAGER" }, { "Quickfinger", "ROGUE", "DAMAGER" }, { "Wildgrowth", "DRUID", "HEALER" },
    }
    -- A fixed series of numbers (Park-Miller), so the raid is the same every time.
    local seed = 20261126
    local function Random(n)
        seed = (seed * 16807) % 2147483647
        return seed % n
    end

    local bosses = {
        { 14, "Lucifron" }, { 27, "Magmadar" }, { 41, "Gehennas" }, { 58, "Garr" }, { 72, "Shazzrah" },
        { 88, "Baron Geddon" }, { 104, "Golemagg the Incinerator" }, { 121, "Sulfuron Harbinger" },
        { 139, "Majordomo Executus" }, { 166, "Ragnaros" },
    }
    -- { minute, itemID }: rolled for by part of the raid.
    local drops = {
        { 28, 17069 },   -- Striker's Mark (Magmadar)
        { 28, 18203 },   -- Eskhandar's Right Claw (Magmadar)
        { 42, 16863 },   -- Gauntlets of Might (Gehennas)
        { 50, 14513 },   -- Pattern: Robe of the Archmage (BoE, from trash)
        { 59, 18822 },   -- Obsidian Edged Blade (Garr)
        { 59, 17105 },   -- Aurastone Hammer (Garr)
        { 95, 13036 },   -- Assassination Blade (blue BoE, from trash)
        { 105, 17103 },  -- Azuresong Mageblade (Golemagg)
        { 105, 16867 },  -- Legplates of Might (Golemagg)
        { 122, 17077 },  -- Crimson Shocker (Sulfuron)
        { 167, 17076 },  -- Bonereaver's Edge (Ragnaros)
        { 167, 18814 },  -- Choker of the Fire Lord (Ragnaros)
        { 167, 17063 },  -- Band of Accuria (Ragnaros)
        { 167, 17102 },  -- Cloak of the Shrouded Mists (Ragnaros)
    }
    -- { itemID, kind }: "stack" = common material, many players get a pile;
    -- "single" = one each for about half; "rare" = lands on very few.
    local pool = {
        { 14047, "stack" },   -- Runecloth
        { 8170, "stack" },    -- Rugged Leather
        { 11370, "stack" },   -- Dark Iron Ore
        { 7078, "single" },   -- Essence of Fire
        { 17010, "single" },  -- Fiery Core
        { 17011, "single" },  -- Lava Core
        { 13444, "single" },  -- Major Mana Potion
        { 12800, "single" },  -- Azerothian Diamond
        { 11938, "single" },  -- Sack of Gems
        { 11382, "rare" },    -- Blood of the Mountain
        { 18335, "rare" },    -- Pristine Black Diamond
    }

    local players, coins, loot = {}, {}, {}
    for p, who in ipairs(roster) do
        players[who[1]] = { class = who[2], role = who[3] }
        -- Coins (few in Molten Core) are shared out evenly among whoever is
        -- close; a few players strayed.
        coins[who[1]] = 91500 - (p % 9 == 0 and 23000 or 0) - Random(4) * 700
        for i, def in ipairs(pool) do
            -- The third term keeps players ten apart from getting the same loot.
            local roll = (p * 7 + i * 13 + math.floor((p - 1) / 10) * (i + 3)) % 10
            local minute = 5 + (p * 17 + i * 29) % 170
            if def[2] == "stack" and roll < 8 then
                loot[#loot + 1] = { minute, who[1], def[1], (roll + 2) * 3 }
            elseif def[2] == "single" and roll < 6 then
                loot[#loot + 1] = { minute, who[1], def[1], 1 }
            elseif def[2] == "rare" and roll == 0 then
                loot[#loot + 1] = { minute, who[1], def[1], 1 }
            end
        end
    end
    -- Each drop: three to eight players Need, a few Greed, the rest pass
    -- (left out); the highest Need wins.
    for _, drop in ipairs(drops) do
        local roll, best, winner = {}, 0, nil
        local needers = 3 + Random(6)
        while needers > 0 do
            local name = roster[1 + Random(#roster)][1]
            if not roll[name] then
                local n = 1 + Random(100)
                if n == best then n = n > 1 and n - 1 or 2 end
                roll[name] = "n" .. n
                if n > best then best, winner = n, name end
                needers = needers - 1
            end
        end
        for _ = 1, 2 + Random(4) do
            local name = roster[1 + Random(#roster)][1]
            if not roll[name] then roll[name] = "g" .. (1 + Random(100)) end
        end
        loot[#loot + 1] = { drop[1], winner, drop[2], 1, roll }
    end
    table.sort(loot, function(a, b) return a[1] < b[1] end)

    ThatLuckyBastard.AddExampleRun({
        name = "Molten Core",
        startedAt = time() - 5 * 86400,
        length = 178,
        players = players,
        bosses = bosses,
        coins = coins,
        loot = loot,
    })
end

print("|cff33ff99That Lucky Bastard|r: example data loaded - type /tlb to view it.")
