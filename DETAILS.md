# That Lucky Bastard: details

Everything the addon does, page by page, with its commands, options and limits. The [README](README.md) has the short version.

## The breakdown window

- **Per player:** total value, vendor value, share of the run, and how far above or below an equal split they are.
- **Per item:** every item with its count and value, grouped by category: epic, blue and green BoE, Bind on Pickup, quest items, profession materials, other, junk.
- **Two layouts:** one column per player for groups of five or fewer (with portraits), and an expandable list for larger groups.
- **Need rolls:** a button at the top switches the window to show only what each player won on Need rolls. Hovering an item shows whether it was won on Need or Greed, and everyone's roll on it.
- **Awards:** when a run ends, each player gets one light-hearted award, revealed one by one: the one that fits them best out of about twenty, such as Jackpot, Lion's Share, Fair Share, Loaded Dice, Natural 100, Window Shopper, The Farmer, The Saint or Empty Pockets. The further a player is from normal, the stronger the fit: an average roll of 51 earns nothing, an average of 95 is hard to miss. **Ninja** (most value won on Need rolls) and **Luckiest** (most value won on Greed rolls) count for more than the others, but a more striking award can take their place. Hover an award to see the rule behind it, or click it for the list of all awards.
- **Under the breakdown:** run time, group loot per hour, a fairness score, any dungeon record the run set, how it compares with your average there, and the streak it belongs to.
- **History:** past runs are kept and can be browsed. **Pin** a run and it is never deleted: not by the limit on runs to keep, not by `/tlb clear`. **Delete** removes just the run on show, after asking.

## Run details

One window about the run on show, with five pages:

- **Podium:** your group's characters stand on gold, silver and bronze blocks. The winner dances, last place cries, and the Ninja kneels.
- **Front page:** a mock newspaper written from the run, with a headline and a short story for every award.
- **Timeline:** a chart of every player's running total through the run, with boss kills marked. You see when someone pulled ahead, and which drop did it.
- **Rolls:** every roll that was won: the item, the winner, and what everyone else rolled.
- **Numbers:**
  - *Fairness*, from 0 (one player took everything) to 100 (everyone got the same).
  - *Where the loot came from:* after a boss kill, profession materials, or trash.
  - *Roll luck:* for each player, the rolls they entered, the wins they could expect, and the wins they had.
  - *Streak:* standings over the runs you have done in a row with the same group or in the same dungeon.
  - *At today's prices:* the run re-valued at current auction prices, against the prices recorded at the time.
  - *Award scores:* how well each player fitted each award.
  - A button to **export** the run as text for a spreadsheet.

## Statistics

Tables over everything recorded. Click a column title to sort.

- **Dungeons:** per dungeon, the number of runs, average group loot, your average, average time, gold per hour for the group and for you, and average fairness. Sort by "Group / hour" to pick tonight's dungeon.
- **Records:** your richest run, best personal haul, biggest single item and fastest run per dungeon.
- **Runs:** every run that is kept, with time, loot, your share, fairness and top looter. Filter by dungeon or player; click a run to open it.
- **Luck:** rolls entered, wins expected and wins had, for you and for everyone you run with, plus average rolls.
- **Regulars:** the people you run with: runs together, average loot, and how often they were Luckiest or Ninja.
- **Drops:** per dungeon, every item seen, in how many of your runs, how many of it, its average value, and who got it last.
- **Roles:** how loot shares turn out by role and by class, against an equal share.
- **Find item:** search past runs for an item to see when it dropped and who got it.
- **Awards:** what every award means.
- **Export all runs:** one line per player of every run, as text for a spreadsheet.

## While you play

- **Live notices:** a small on-screen notice when someone loots something valuable.
- **Familiar faces:** a notice when someone you have run with joins your group, with your history together.
- **Tooltips:** one line in the tooltip of a player you have run with, and one in the tooltip of an item seen in your runs ("seen in 3 runs, last to ...").
- **Streak recap:** when you chain runs with mostly the same group, or in the same dungeon, each starting within half an hour of the one before, the end of a run brings a notice with the standings so far.
- **Loot bingo:** a private 4x4 card dealt each run ("a blue item drops", "someone passes", "you die"...). Squares tick themselves off, and a completed line is announced on your screen.

## Sharing a run

The **Share** button (or `/tlb share`) shares the run on show, in two ways:

- **A link in chat.** Pick a channel: say, yell, party, raid, instance, guild, officer, or a channel you joined. The link goes into your chat box and you send it yourself. Players with the addon click it to see the run; others see plain text. Global channels (General, Trade, LocalDefense and the like) are not offered, and links posted there stay plain text.
- **A code.** The run as text to copy out of the game and paste anywhere: about 3,000 to 5,000 characters for a five-player dungeon. Anyone with the addon imports it in the **Shared runs** window (`/tlb import`).

A click on a link asks the player who posted it for the run. Their addon sends it back through hidden addon messages, never through chat, at the pace the game allows: a few seconds to about 15. It works while they are online, and only for runs they posted a link to.

Runs shared with you look as they did for their owner, prices included. They are listed in the Shared runs window, and after your own runs in the breakdown window, marked "shared by". They count in none of your statistics, records or streaks and cannot be pinned. The last 20 are kept.

## How loot is valued

- **Vendor price** comes from the game.
- **Auction price** comes from [Auctionator](https://www.curseforge.com/wow/addons/auctionator) if installed, with TradeSkillMaster as a fallback. Without either, only vendor prices are used.
- **Market value** is the auction price when one is known, and the vendor price otherwise.
- **Bind on Pickup and quest items** count at vendor price, since they cannot be sold to other players.
- **Junk** (grey items) counts at vendor price by default, since a stray auction listing for a grey means little. Right-click one to use its auction price instead.
- All loot counts the same, whether it came from a boss, a roll or a profession.
- A **blue dot** next to a value means it is an auction price. An **orange dot** means the item could be auctioned but no price is known, so its vendor price was used. Hover the item for details.
- Prices are recorded when the item is looted and do not change afterwards.

## Commands and runs

A run starts automatically when you enter a dungeon (and raids, if enabled). The window opens by itself when you leave the dungeon alive, as a summary of the run, and can be opened at any time:

| Command | Effect |
| --- | --- |
| `/tlb` or `/lucky` | Open or close the window |
| `/tlb options` | Open the options |
| `/tlb details` | Run details for the run on show (also `/tlb podium`, `paper`, `timeline`, `rolls`, `numbers`) |
| `/tlb stats` | Statistics (also `/tlb dungeons`, `records`, `runs`, `luck`, `regulars`, `drops`, `roles`) |
| `/tlb search <item name>` | Find an item in past runs |
| `/tlb awards` | What every award means |
| `/tlb export` | The run on show as text for a spreadsheet; `/tlb export all` for every run |
| `/tlb share` | Share the run on show: a link in chat, or a code |
| `/tlb import` | The Shared runs window: import a code, and the runs shared with you |
| `/tlb bingo` | Your loot bingo card |
| `/tlb theme classic` / `modern` | Change the look |
| `/tlb start` | Track a run manually, outside a dungeon |
| `/tlb stop` | End the current run |
| `/tlb pin` | Pin the run on show so that it is never deleted; again to unpin |
| `/tlb delete` | Delete the run on show (asks first; not for a pinned run) |
| `/tlb clear` | Delete all recorded runs, except pinned ones |
| `/tlb capture` | Record raw loot and roll messages, for troubleshooting |

The minimap button does the same: left-click for the window, right-click for the options, drag to move it.

### Starting a new run

- Entering a different dungeon starts a new run.
- Running back in as a ghost after a wipe continues the same run.
- If you come back into the same dungeon within 20 minutes without having died out of it, That Lucky Bastard asks whether it is a new run. With the prompt turned off, it always starts a new run.
- If you reset the instance yourself, the run is closed automatically.
- A reload or a short disconnect inside the dungeon continues the run.

## Options

- **Appearance:** two themes (Classic and Modern), player picture (3D model, 2D portrait, class icon or none), window scale.
- **Layout:** columns or list, group items by category, align the same item across players to compare line by line, and which details to show.
- **Items and values:** switch categories on or off, auction or vendor-only pricing, show or hide silver and copper, item order.
- **Players:** order by role (tank, healer, damage), podium (top looter in the middle), value or name; optionally always show yourself first. Names follow the game's "My Secondary Name" setting, or can be forced to full or first name only.
- **Behaviour:** when the window opens by itself, raid tracking, a one-line chat summary, how many runs to keep, the minimap button.
- **Extras:** the podium, awards and their sounds, run time and records, bingo, familiar faces, the streak recap, the two tooltip lines, and the live loot notices with their minimum value.

## Limitations

- **Range.** The game only reports another player's loot when you are reasonably close to them. Loot picked up far away from you is missed.
- **Not counted:** coin (it is split evenly by the game), quest rewards, trades and crafted items.
- **Trades after the run are invisible.** If someone hands an item on, That Lucky Bastard still counts it for the player who looted it.
- **New figures start now.** The timeline, the roll sheet, roll luck and loot by source rely on details recorded from version 0.2.0 on. Runs recorded before have none of them.
- **Boss loot is a rule of thumb:** whatever was picked up within 90 seconds of a boss kill, profession materials aside.
- **Roll luck counts what the game reports.** A roll nobody won (everyone passed) is not counted, and a roll whose messages you were too far away to receive is missed.
- **Portraits and models need the player nearby.** The game cannot save either, so a player who is out of sight or gone from the group shows their class icon.
- **Item search and the Runs page only cover the runs that are kept** (300 by default; any number up to unlimited). A run takes about 25 to 150 KB in the saved file. Dungeon figures, records, regulars, luck, drops and roles are kept separately and are not affected by that limit.
- **People met once are forgotten after 90 days.** Regulars would otherwise fill up with strangers from random groups.
- **Lowering the number of runs to keep takes effect when the next run ends,** so a misclick deletes nothing.
- **Deleting runs does not change the statistics.** Dungeon figures, regulars, luck, drops and roles are added up when a run is closed, and keep what a deleted run contributed.
- **Fastest run** only compares runs with the most boss kills seen for that dungeon, so an abandoned run cannot take the record.
- **Auction prices are taken as they are.** A rarely traded item with an unrealistic listing can distort a run. Items valued at an auction price carry a blue dot, and an item worth more than half of the run on its own is highlighted in orange. Right-click an item to switch it to its vendor price for that run (and again to switch back).

## Privacy

That Lucky Bastard never sends chat messages. Everything it shows, including the awards, the notices and what it knows about the people you run with, appears only on the screen of the player who has it installed. The one exception is a run you share: you post its link in chat yourself, and when someone with the addon clicks it, your addon sends them that run, and nothing else, through hidden addon messages. The export and the share code are text you copy yourself; nothing is written anywhere else.

## Compatibility

- Built for WoW Forever (interface 16001), which runs on the modern game client.
- Optional: Auctionator or TradeSkillMaster for auction prices.
- English interface text only. Loot detection uses the game's own message formats and is not tied to English, but other languages have not been tested.

## Data

Runs, statistics and settings are saved account-wide in `WTF\Account\<account>\SavedVariables\ThatLuckyBastard.lua`. The game writes this file on logout and on `/reload`.

## Coming from FairShare

Versions up to 0.2.2 were called FairShare. To move over:

1. Delete the old `FairShare` folder from `Interface\AddOns`, and install `ThatLuckyBastard`.
2. To keep your runs, close the game first. In `WTF\Account\<account>\SavedVariables`, copy `FairShare.lua` to `ThatLuckyBastard.lua`, open the copy, and change `FairShareDB` on its first line to `ThatLuckyBastardDB`.

The commands changed with the name: `/fs` is now `/tlb`.

## Example data

`ThatLuckyBastard_Example` is an optional test addon, found in the source repository rather than in the download. It adds three fake runs so the window can be tried without running a dungeon. Its runs are never saved; disable or delete it to remove them.

## Development

`tests/` holds a small test rig that loads the addon into a real Lua 5.1 engine with stand-ins for the game, plays a dungeon run through its event handlers, and opens every window. It needs Python with the `lupa` package.

```bash
python tests/luacheck.py ThatLuckyBastard/*.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_ui.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_pin.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_looks.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_audit.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_share.lua
```

`tools/make_logo.py` draws the addon's mark (needs Pillow); the brand colours live at the top of `ThatLuckyBastard/Core.lua`.

The rig proves that the code runs and computes the right figures. It cannot show what a window looks like; that still needs the game.
