-- Fake runs for testing the That Lucky Bastard window. Only WHO looted WHAT is
-- made up: every item is given as an item ID and a count, and the addon values it
-- exactly like real loot (vendor price and category from the game client,
-- auction price from Auctionator / TSM). Item IDs that do not exist on this
-- client are skipped.
--
-- The runs live in memory only: remove this addon and they are gone.

if not ThatLuckyBastard or not ThatLuckyBastard.AddExampleRun then return end

local me = (GetUnitName and GetUnitName("player", true)) or UnitName("player") or "You"
local myClass = select(2, UnitClass("player"))

----------------------------------------------------------------------
-- Run 1: an unfair dungeon. One player skins everything, another wins
-- the epic BoE.
----------------------------------------------------------------------

ThatLuckyBastard.AddExampleRun({
    name = "The Deadmines",
    startedAt = time() - 3600,
    players = {
        [me] = { class = myClass, role = "DAMAGER", loot = {
            { 2589, 14 },  -- Linen Cloth
            { 2592, 6 },   -- Wool Cloth
            { 5191, 1 },   -- Cruel Barb (BoP)
            { 4865, 4 },   -- Ruined Pelt (junk)
        } },
        Skinnyjoe = { class = "HUNTER", role = "DAMAGER", loot = {
            { 2318, 38 },  -- Light Leather
            { 2319, 22 },  -- Medium Leather
            { 783, 5 },    -- Light Hide
            { 4232, 3 },   -- Medium Hide
            { 2589, 9 },   -- Linen Cloth
            { 7073, 7 },   -- Broken Fang (junk)
        } },
        Vexia = { class = "ROGUE", role = "DAMAGER", loot = {
            { 873, 1 },    -- Staff of Jordan (epic BoE)
            { 2447, 8 },   -- Peacebloom
            { 2589, 11 },  -- Linen Cloth
            { 7074, 5 },   -- Chipped Claw (junk)
        } },
        Thorgrim = { class = "WARRIOR", role = "TANK", loot = {
            { 7230, 1 },   -- Smite's Mighty Hammer (BoP)
            { 2770, 12 },  -- Copper Ore
            { 1482, 1 },   -- Shadowfang (blue BoE)
            { 858, 2 },    -- Lesser Healing Potion
        } },
        Elyndra = { class = "PRIEST", role = "HEALER", loot = {
            { 5201, 1 },   -- Emberstone Staff (BoP)
            { 2589, 7 },   -- Linen Cloth
            { 2592, 4 },   -- Wool Cloth
            { 1210, 1 },   -- Shadowgem
        } },
    },
})

----------------------------------------------------------------------
-- Run 2: a fairly even dungeon, with one player who looted nothing.
----------------------------------------------------------------------

ThatLuckyBastard.AddExampleRun({
    name = "Scarlet Monastery",
    startedAt = time() - 2 * 86400,
    players = {
        [me] = { class = myClass, role = "DAMAGER", loot = {
            { 4306, 18 },  -- Silk Cloth
            { 7720, 1 },   -- Whitemane's Chapeau (BoP)
            { 3827, 2 },   -- Mana Potion
        } },
        Thorgrim = { class = "WARRIOR", role = "TANK", loot = {
            { 4306, 16 },  -- Silk Cloth
            { 7717, 1 },   -- Ravager (BoP)
            { 3864, 1 },   -- Citrine
        } },
        Elyndra = { class = "PRIEST", role = "HEALER", loot = {
            { 4306, 20 },  -- Silk Cloth
            { 4338, 2 },   -- Mageweave Cloth
            { 1529, 1 },   -- Jade
        } },
        Vexia = { class = "ROGUE", role = "DAMAGER", loot = {
            { 4306, 15 },  -- Silk Cloth
            { 4338, 3 },   -- Mageweave Cloth
            { 3827, 1 },   -- Mana Potion
        } },
        Quietmage = { class = "MAGE", role = "DAMAGER", loot = {} },
    },
})

----------------------------------------------------------------------
-- Run 3: a 40-player raid with many items: columns for its top five, a
-- bench with more players than it has room for, awards held by three
-- players, and a long list to scroll. Who gets what is generated, but the
-- same every time.
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
    -- { itemID, kind }: "stack" = common material, many players get a pile;
    -- "rare" = lands on very few players; "single" = one each for about half.
    local pool = {
        { 14047, "stack" },   -- Runecloth
        { 8170, "stack" },    -- Rugged Leather
        { 11370, "stack" },   -- Dark Iron Ore
        { 7078, "single" },   -- Essence of Fire
        { 12800, "single" },  -- Azerothian Diamond
        { 13444, "single" },  -- Major Mana Potion
        { 18335, "single" },  -- Pristine Black Diamond
        { 11938, "single" },  -- Sack of Gems
        { 13468, "rare" },    -- Black Lotus
        { 12811, "rare" },    -- Righteous Orb
        { 14513, "rare" },    -- Pattern: Robe of the Archmage (epic BoE)
        { 13036, "rare" },    -- Assassination Blade (blue BoE)
        { 16867, "rare" },    -- Legplates of Might (BoP)
    }
    local players = {}
    for p, who in ipairs(roster) do
        local loot = {}
        for i, def in ipairs(pool) do
            -- The third term keeps players ten apart from getting the same loot.
            local roll = (p * 7 + i * 13 + math.floor((p - 1) / 10) * (i + 3)) % 10
            if def[2] == "stack" and roll < 8 then
                loot[#loot + 1] = { def[1], (roll + 2) * 3 }
            elseif def[2] == "single" and roll < 6 then
                loot[#loot + 1] = { def[1], 1 }
            elseif def[2] == "rare" and roll == 0 then
                loot[#loot + 1] = { def[1], 1 }
            end
        end
        players[who[1]] = { class = who[2], role = who[3], loot = loot }
    end
    ThatLuckyBastard.AddExampleRun({
        name = "Molten Core",
        startedAt = time() - 5 * 86400,
        players = players,
    })
end

print("|cff33ff99That Lucky Bastard|r: example data loaded - type /tlb to view it.")
