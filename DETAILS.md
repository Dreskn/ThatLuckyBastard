# That Lucky Bastard: details

Everything the addon does, page by page, with its commands, options and limits. The [README](README.md) has the short version.

## The breakdown window

- **Per player:** total value, vendor value, share of the run, and how far above or below an equal split they are.
- **Per item:** every item with its count and value, grouped by category: epic, blue and green BoE, Bind on Pickup, quest items, profession materials, other, junk.
- **Two layouts:** one column per player (with portraits), or an expandable list. A group of more than five gets columns for its top five by loot, and the others on a *bench* under them: small cards side by side, each with a picture, the name, the award and the loot value one under the other (the options say which). One row of them is shown; it ends with an arrow marked **List**, with the number of players the row had no room for under it, which shows that run as a list without touching the option. At the top of the list its mirror, an arrow marked **Columns**, brings the columns back.
- **Mini mode:** an option beside the themes, for any of them. The window becomes a small one: under its title bar, one card per player with their picture, name, award and total (as far as the options show them), the biggest total first unless another order is chosen. There are no columns, no loot, no footer, and no buttons but the cogwheel beside the cross, which opens the options (in the full window it is at the foot, where the Options button was); the window is exactly as big as its cards: about 570 by 150 for five players, narrower for fewer, with only the dungeon's name in its title bar. A run of more than five players shows its top five, and the row then ends with an arrow that counts the others and shows the run as a list in the full window, where the Columns arrow leads back. There is no race in mini mode.
- **Need rolls:** a button at the top switches the window to show only what each player won on Need rolls. Hovering an item shows whether it was won on Need or Greed, and everyone's roll on it.
- **The race:** when you leave a run alive, its columns race for their places (each time you leave it: go back in, and it is run again on the way out). They start side by side in name order, with no total showing. Each player's loot falls into their column as gold coins, one at a time and all at the same pace: they fall, spin, bounce and settle into a stack, with a clink as they land. When a player's last coin is down, their total is shown with their place. So the smallest stack is done first and takes the last place, and the last one still growing has won. A winner with half as much again as the next player or more fills their column, and the rest pours over the top, faster, rolling down into a heap around the stack. The columns then move to their places on the podium, and the loot, the shares and the awards appear. It takes about five seconds, and a click on the columns skips it; `/tlb race` plays it again for the run on show. It needs one column per player in podium order (both are the defaults) and two players or more with some loot between them; it can be switched off under End of run.
- **Awards:** when a run ends, each player gets one light-hearted award (revealed one by one where there is no race): the one that fits them best out of about fifty, such as Jackpot, Lion's Share, Fair Share, Loaded Dice, Window Shopper, The Farmer, The Saint or Empty Pockets. The further a player is from normal, the stronger the fit: an average roll of 51 earns nothing, an average of 95 is hard to miss. Every award weighs the same: the most striking fit wins, whichever award it is. Hover an award to see the rule behind it, or click it for the list of all awards.
  - *How many players can have one award:* one in a party of up to five, two in a group of up to ten, three in anything bigger. The second and third are numbered: Hoarder, Hoarder II, Hoarder III. Players with the same score share a place (three players who each rolled a 100 are all Natural 100), and two players with the same score and the same loot share the award whatever the limit.
  - *Moments* are odd things the dice did: Natural 100, Snake Eyes, Heartbreak (lost with 95 or more), Lowball (won with 5 or less), Photo Finish (won by one point), Deja Vu (the same number twice in a row), Hot Streak, Dry Spell, Nemesis and Overkill (a Need win worth under 1s). Hot Streak, Loaded Dice and Cursed Dice only count rolls that were a contest: a win nobody rolled against, or a Greed number against someone's Need, decides nothing. The dice awards need five such rolls and an average far from 50: about 65 (or 36) over 15 rolls, 76 (or 25) over 5.
  - *From WoW lore, and for roles, classes and bosses:* AFK (picked up nothing, rolled on nothing), Hunter Loot (a hunter who won on Need), Need Before Greed (chose Need on two rolls more than the group's average), 50 DKP Minus (lost three rolls more than the group's average), Tank Tax, Healer's Tip and Top DPS (one and a half times the average of their role, two or more of it), Class Act and Class Clown (one and a half times, or half, the average of their class, three or more of it), and Boss's Pet (loot from a boss: one player per boss, one in all in a party; it ranks just above the consolation prizes).
  - *Consolation prizes* go only to players nothing else fits, the best of them first: Collector, Busy Hands, Always Second, Average Joe, Magpie, Boss Magnet, Trash Panda, Leftovers, Booby Prize, Runner-up, First Dibs and Last Call. They score below 0.3, so they never take another award's place. A player left with nothing at all is a Tourist.
- **Under the breakdown:** run time, group loot per hour, a fairness score, any dungeon record the run set, how it compares with your average over the earlier runs there, and the streak it belongs to.
- **History:** past runs are kept and can be browsed. **Pin** a run and it is never deleted: not by the limit on runs to keep, not by `/tlb clear`. **Delete** removes just the run on show, after asking; `/tlb clear` asks too.

## Front page and analysis

Two windows about the run on show, opened from the main window's top row. Each closes again on a second click.

- **Front page:** a mock newspaper written from the run, with a short story for every award. The headline goes to the run's most outstanding award: the one furthest from normal, whoever has it.
- **Analysis:** three tabs about the run, following the main window from run to run:
  - *Timeline:* a chart of every player's running total through the run, with boss kills marked. You see when someone pulled ahead, and which drop did it.
  - *Rolls:* every roll that was won: the item, the winner, and what everyone else rolled.
  - *Numbers:*
    - *Fairness*, from 0 (one player took everything) to 100 (everyone got the same).
    - *Where the loot came from:* after a boss kill, profession materials, or trash.
    - *Roll luck:* for each player, the rolls they entered, the wins they could expect, and the wins they had.
    - *Streak:* standings over the runs you have done in a row with the same group or in the same dungeon.
    - *At today's prices:* the run re-valued at current auction prices, against the prices recorded at the time.
    - *Award scores:* how well each player fitted each award.
    - A button to **export** the run as text for a spreadsheet.

## Statistics

Tables over all your runs, from the Statistics button beside Options. Click a column title to sort.

- **Dungeons:** per dungeon, the number of runs, average group loot, your average, average time, gold per hour for the group and for you, and average fairness. Sort by "Group / hour" to pick tonight's dungeon.
- **Records:** your richest run, best personal haul, biggest single item and fastest run per dungeon.
- **Runs:** every run that is kept, with time, loot, your share, fairness and top looter. Filter by dungeon or player; click a run to open it.
- **Luck:** rolls entered, wins expected and wins had, for you and for everyone you run with, plus average rolls.
- **Regulars:** the people you run with: runs together, their loot and yours in those runs, the difference, and the award they had most often in your runs. Every award counts alike.
- **Drops:** per dungeon, every item seen, in how many of your runs, how many of it, its average value, and who got it last.
- **Roles:** how loot shares turn out by role and by class, against an equal share.
- **Find item:** search past runs for an item to see when it dropped and who got it.
- **Awards:** what every award means.
- **Export all runs:** one line per player of every run, as text for a spreadsheet.

## While you play

- **The meter:** a small window like a damage meter, opened with the Meter button or `/tlb meter`. One row per player, the most loot first: the rank, a bar in the class colour as long as the player's loot is next to the leader's, the name, the total and the share. It follows the run in progress as the loot comes in: bars grow to their new length, and rows slide past one another when someone overtakes. Once the run is over, each player's award appears beside the name. With no run going, it shows the run on show in the main window, or the latest. Hover a row for the details, click it to open the run. It can be moved and sized (the mouse wheel scrolls rows that do not fit), Escape leaves it open, and it is where you left it, open if it was, at your next login. Each theme draws it its own way: flat bars in Modern, the game's own bars in Classic, a strip of paper in Receipt. Options › While you play › Meter says whether a row shows the rank, the share and the award, and has two boxes: Open when a run starts (going back into the dungeon counts), and Close when I leave.
- **Live notices:** a small on-screen notice when someone loots something valuable.
- **Familiar faces:** a notice when someone you have run with joins your group, with your history together.
- **Tooltips:** one line in the tooltip of a player you have run with (runs together, both your loot, and the award they had most often), and one in the tooltip of an item seen in your runs ("seen in 3 runs, last to ..."). The options say which kinds of item get theirs: epic, blue and green BoE and Bind on Pickup unless you choose otherwise.
- **Streak recap:** when you chain runs with mostly the same group, or in the same dungeon, each starting within half an hour of the one before, the end of a run brings a notice with the standings so far.
- **Loot bingo:** a private 4x4 card dealt as each run starts ("a blue item drops", "someone passes", "you die"...), whose squares tick themselves off. You bet on one line of it: click the marker of a row, a column or a diagonal. A line can be picked as long as none of its squares is ticked, and the pick is for good. If your line fills before the run is over, it is announced on your screen, and the card counts the lines you have won.

## Sharing a run

The **Share** button (or `/tlb share`) shares the run on show, in three ways:

- **A link in chat.** Pick a channel: say, yell, emote, party, raid, raid warning, instance, guild, officer, a channel or community you joined, or a whisper to a player whose full name you type (names are suggested as you type: your group, friends, guild, and the players you have run with). The link goes into your chat box and you send it yourself. Players with the addon click it to see the run; others see plain text. Global channels (General, Trade, LocalDefense and the like) are not offered, and links posted there stay plain text.
- **A summary in chat** anyone can read, like a damage meter's report. Choose **Summary** in the Share window, check the lines, and click a channel to post them. A first line names the run, then one line per player, most loot first. Options › Share sets how many players (5 by default) and what the lines show. Emote and raid warning are not offered for a summary.
- **A code.** The run as text to copy out of the game and paste anywhere: about 3,000 to 6,000 characters for a five-player dungeon, and 30,000 to 80,000 for a raid of forty. Anyone with the addon imports it in the **Shared runs** window (`/tlb import`).

A click on a link asks the player who posted it for the run. Their addon sends it back through hidden addon messages, never through chat, at the pace the game allows: a few seconds to about 15 for a dungeon, a few minutes for a raid. It works while they are online, and only for runs they posted a link to.

A code or a link from another player is read as data, never run. Its length is checked first, and one that holds more than a raid could (items, pickups, rolls, bosses) is refused, so a code written to slow the game down is turned away at once.

Runs shared with you keep the prices their owner recorded. The totals and awards are worked out on your side, with your own options (categories shown, auction or vendor prices), so they can differ from what the owner sees. They are listed in the Shared runs window, and among your own runs in the breakdown window, by date, marked "shared by". They count in none of your statistics, records or streaks and cannot be pinned. They are kept up to your number of runs to keep, counted apart from your own runs: importing never costs you a run of yours. Past that number, the ones that arrived first go.

## How loot is valued

- **Vendor price** comes from the game.
- **Auction price** comes from [Auctionator](https://www.curseforge.com/wow/addons/auctionator) if installed, with TradeSkillMaster as a fallback. Without either, only vendor prices are used.
- **Market value** is the auction price when one is known, and the vendor price otherwise.
- **Historical or current:** by default a run keeps the auction prices recorded when its loot dropped. With *Current auction prices* in the options, your runs are valued at today's prices where there is one. Statistics kept over all runs (dungeons, records, regulars) hold what was recorded when each run closed, whichever is chosen, and runs shared with you keep their owner's prices.
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
| `/tlb paper` | The front page of the run on show |
| `/tlb race` | The race again, for the run on show |
| `/tlb analysis` | Its timeline, rolls and numbers (also `/tlb timeline`, `rolls`, `numbers`) |
| `/tlb stats` | Statistics (also `/tlb dungeons`, `records`, `runs`, `luck`, `regulars`, `drops`, `roles`) |
| `/tlb search <item name>` | Find an item in past runs |
| `/tlb awards` | What every award means |
| `/tlb export` | The run on show as text for a spreadsheet; `/tlb export all` for every run |
| `/tlb share` | Share the run on show: a link in chat, or a code |
| `/tlb import` | The Shared runs window: import a code, and the runs shared with you |
| `/tlb bingo` | Your loot bingo card |
| `/tlb meter` | The loot meter |
| `/tlb theme modern` / `classic` / `receipt` | Change the look |
| `/tlb start` | Track a run manually, outside a dungeon |
| `/tlb stop` | End the current run |
| `/tlb pin` | Pin the run on show so that it is never deleted; again to unpin |
| `/tlb delete` | Delete the run on show (asks first; not for a pinned run) |
| `/tlb clear` | Delete all runs except pinned ones, those shared with you included (asks first, saying how many) |
| `/tlb capture` | Record raw loot and roll messages, for troubleshooting |

The minimap button does the same: left-click for the window, right-click for the options, drag to move it.

### Starting a new run

- Entering a different dungeon starts a new run.
- Running back in as a ghost after a wipe continues the same run.
- If you leave dead and come back to life outside (a spirit healer, a resurrection), the run is shown as when you leave alive.
- A player who is replaced stays in the run, and so does the replacement: one run, six players. When the group itself is another one (fewer than half the same people), what follows is a new run: at once if it forms while you are inside, and without asking when you come back in with it. Whoever joined in the last two minutes of a run and did nothing in it is left out of it.
- If you come back into the same dungeon within 20 minutes without having died out of it, That Lucky Bastard asks whether it is a new run. Set it to "Always a new run" and it no longer asks.
- If you reset the instance yourself, the run is closed automatically.
- A reload or a short disconnect inside the dungeon continues the run.

## Options

- **Window:** the theme (Modern, the default, Classic, or Receipt: each player's loot printed on a till receipt), mini mode (players, totals and awards only), the Modern theme's accent colour (Teal, your class colour, Amber, Light, Dark, or your own as red, green and blue values), the size of every window, one column per player (up to 5) or a list, what the players on the bench show (picture, award, gold), items grouped by category, the same item lined up across columns, item order (value or name), what to show (icons, shares, share bar, totals, run time and records), and amounts as 12g 34s (the default), 12g 34s 56c or 12g.
- **Players:** the picture (2D portrait by default, 3D model, class icon or none), names as the game shows them (its "My Secondary Name" setting), full or first name only, and the order: podium (top looter in the middle, the default), loot value, role or name, optionally with you first.
- **Loot:** auction or vendor prices, historical or current auction prices, with the addon the auction prices come from; vendor totals; which categories to show, and whether hidden ones still count.
- **End of run:** whether the breakdown opens when you leave a dungeon alive (if not, the reveal waits for the first time you open it), awards, the reveal (the race, its sounds and a screenshot), the streak recap, and a line in your chat window that only you see.
- **While you play:** the valuable loot notice (5 gold and up by default, or off), familiar faces, the meter (what its rows show, and whether it opens as a run starts and closes as you leave), the two tooltip lines, the kinds of item that get theirs, and loot bingo.
- **Share:** the chat summary: how many players (5 by default, up to 25), the first line (run link, run time, group total) and the player lines (share %, gap to equal split, award), with a preview.
- **General:** raid tracking, what happens when you come back into the same dungeon, how many runs to keep, the minimap button.

Options that do nothing as things stand are greyed out, such as the share bar in Classic. **Defaults** puts every option back except the number of runs to keep.

## Limitations

- **Range.** The game only reports another player's loot when you are reasonably close to them. Loot picked up far away from you is missed.
- **Not counted:** coin (it is split evenly by the game), quest rewards, trades and crafted items.
- **Trades after the run are invisible.** If someone hands an item on, That Lucky Bastard still counts it for the player who looted it.
- **New figures start now.** The timeline, the roll sheet, roll luck and loot by source rely on details recorded from version 0.2.0 on. Runs recorded before have none of them.
- **Boss loot is a rule of thumb:** whatever was picked up within 90 seconds of a boss kill, profession materials aside.
- **Roll luck counts what the game reports.** A roll nobody won (everyone passed) is not counted, and a roll whose messages you were too far away to receive is missed.
- **Portraits and models need the player nearby.** The game cannot save either, so a player who is out of sight or gone from the group shows their class icon.
- **Item search and the Runs page only cover the runs that are kept** (300 by default; any number up to unlimited). A finished run takes about 4 to 9 KB in the saved file, where it is kept as one code (the same code sharing uses) with its item names; a raid of forty takes 30 to 90 KB. Kept this way the file has room for thousands of runs. Versions before 0.5.0 cannot read runs saved this way. Dungeon figures, records, regulars, luck, drops and roles are kept separately and are not affected by that limit.
- **People met once are forgotten after 90 days.** Regulars would otherwise fill up with strangers from random groups.
- **Lowering the number of runs to keep asks first,** saying how many runs would go, then deletes them at once. Pinned runs stay.
- **Deleting runs does not change the statistics.** Dungeon figures, regulars, luck, drops and roles are added up when a run is closed, and keep what a deleted run contributed.
- **Fastest run** only compares runs with the most boss kills seen for that dungeon, so an abandoned run cannot take the record.
- **Auction prices are taken as they are.** A rarely traded item with an unrealistic listing can distort a run. Items valued at an auction price carry a blue dot, and an item worth more than half of the run on its own is highlighted in orange. Right-click an item to switch it to its vendor price for that run (and again to switch back).

## Privacy

That Lucky Bastard never sends chat messages on its own. Everything it shows, including the awards, the notices and what it knows about the people you run with, appears only on the screen of the player who has it installed. The exceptions are runs you share yourself: you post a link in chat, or click a channel to post a summary, and when someone with the addon clicks a link, your addon sends them that run, and nothing else, through hidden addon messages. Nothing is ever posted when a run ends or at any other time without your click. The export and the share code are text you copy yourself; nothing is written anywhere else.

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

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_options.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_receipt.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_summary.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_regulars.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_awards.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_lifecycle.lua
```

```bash
python tests/run_tests.py ThatLuckyBastard tests/test_storage.lua
```

`tools/make_logo.py` draws the addon's mark (needs Pillow); the brand colours live at the top of `ThatLuckyBastard/Core.lua`. `tools/make_receipt_edge.py` draws the torn edge of the Receipt theme's receipts, and `tools/make_coin.py` the race's coin, which is our own drawing.

The Receipt theme's typewriter font is Courier Prime, by the Courier Prime Project Authors, under the SIL Open Font License 1.1 (`ThatLuckyBastard/Media/CourierPrime-OFL.txt`).

The rig proves that the code runs and computes the right figures. It cannot show what a window looks like; that still needs the game.
