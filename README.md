# FairShare

A World of Warcraft addon for **WoW Forever** that shows how fairly loot was shared in a dungeon run.

FairShare records what every player in your group looted — boss drops, rolls, skinning, herbs, ore, cloth — puts a gold value on it, and shows who came out ahead and who came out behind.

## What it shows

- **Per player:** total value, vendor value, share of the run, and how far above or below an equal split they are.
- **Per item:** every item with its count and value, grouped by category: epic, blue and green BoE, Bind on Pickup, quest items, profession materials, other, junk.
- **Two layouts:** one column per player for groups of five or fewer (with portraits), and an expandable list for larger groups.
- **History:** past runs are kept and can be browsed.

## How loot is valued

- **Vendor price** comes from the game.
- **Auction price** comes from [Auctionator](https://www.curseforge.com/wow/addons/auctionator) if installed, with TradeSkillMaster as a fallback. Without either, only vendor prices are used.
- **Market value** is the auction price when one is known, and the vendor price otherwise.
- **Bind on Pickup and quest items** count at vendor price, since they cannot be sold to other players.
- All loot counts the same, whether it came from a boss, a roll or a profession.
- Prices are recorded when the item is looted and do not change afterwards.

## Installation

1. Copy the `FairShare` folder into the Forever client's `Interface\AddOns` folder.
2. Restart the game or type `/reload`.

`FairShare_Example` is an optional test addon. It adds three fake runs so the window can be tried without running a dungeon. Its runs are never saved; disable or delete it to remove them.

## Usage

A run starts automatically when you enter a dungeon (and raids, if enabled). The window opens by itself after the last boss or when you leave, and can be opened at any time:

| Command | Effect |
| --- | --- |
| `/fs` or `/fairshare` | Open or close the window |
| `/fs options` | Open the options |
| `/fs theme classic` / `retail` / `modern` | Change the look |
| `/fs start` | Track a run manually, outside a dungeon |
| `/fs stop` | End the current run |
| `/fs clear` | Delete all recorded runs |

The minimap button does the same: left-click for the window, right-click for the options, drag to move it.

### Starting a new run

- Entering a different dungeon, or a dungeon you have finished, starts a new run.
- Running back in as a ghost after a wipe continues the same run.
- If you walk out alive and back in, FairShare asks whether it is a new run. The prompt can be turned off.
- If you reset the instance yourself, the run is closed automatically.

## Options

- **Appearance:** three themes (Classic, Retail, Modern), player picture (3D model, 2D portrait, class icon or none), window scale, compact rows.
- **Layout:** columns or list, group items by category, align the same item across players to compare line by line, and which details to show.
- **Items and values:** switch categories on or off, auction or vendor-only pricing, show or hide silver and copper, item order.
- **Players:** order by role (tank, healer, damage), podium (top looter in the middle), value or name; optionally always show yourself first.
- **Behaviour:** when the window opens by itself, raid tracking, a one-line chat summary, how many runs to keep, the minimap button.

## Limitations

- **Range.** The game only reports another player's loot when you are reasonably close to them. Loot picked up far away from you is missed.
- **Not counted:** coin (it is split evenly by the game), quest rewards, trades and crafted items.
- **Trades after the run are invisible.** If someone hands an item on, FairShare still counts it for the player who looted it.
- **The last boss is learned.** The window opens after the last boss only from the second time you run a dungeon.

## Compatibility

- Built for WoW Forever (interface 16001), which runs on the modern game client.
- Optional: Auctionator or TradeSkillMaster for auction prices.
- English interface text only. Loot detection uses the game's own message formats and is not tied to English, but other languages have not been tested.

## Data

Runs and settings are saved account-wide in `WTF\Account\<account>\SavedVariables\FairShare.lua`. The game writes this file on logout and on `/reload`.

## License

[MIT](LICENSE)
