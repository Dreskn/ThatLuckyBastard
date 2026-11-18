# Changelog

## Unreleased

- **Twenty new awards, so Tourist becomes rare.** Moments for odd things the dice did: Heartbreak, Lowball, Photo Finish, Deja Vu, Hot Streak, Dry Spell, Nemesis and Overkill. Consolation prizes for players nothing else fits: Collector, Busy Hands, Always Second, Average Joe, Magpie, Boss Magnet, Trash Panda, Leftovers, Booby Prize, Runner-up, First Dibs and Last Call. Each has a Front page story. Statistics › Awards lists them in three parts.
- **Analysis replaces Timeline** in the main window: one window with three tabs about the run on show, Timeline, Rolls and Numbers, following the main window from run to run. Statistics is now only about all your runs.
- **Statistics moves down beside Options**, so the top row is only about the run on show. Expand all moves up into it.
- **The whisper box suggests names** as you type, like the chat box: your group, friends, Battle.net friends in the game, guild, and the players you have run with. Tab or a click takes one; the arrow keys and Enter work too.

## 0.4.5

- **Regulars** show each player's total loot in your runs together and yours beside it, with the difference; so do player tooltips. Your side is worked out once from your kept runs.
- **A summary in chat** anyone can read, like a damage meter's report: in the Share window choose Summary and click a channel. Options › Share sets how many players and what the lines show. Nothing is posted without your click.
- **A third theme, Receipt.** Each player's loot is printed on a till receipt: typewriter type, items in ink, the award as a rubber stamp, a barcode and a torn edge. The buttons are till keys. Pick it in Options › Window or with `/tlb theme receipt`.

## 0.4.1

- More places to share a run's link: emote, raid warning, your communities, and a whisper to a player whose full name you type (it fills in with the player you target).
- The addon's version shows beside the Options button.
- **The options, reorganised** into Window, Players, Loot, End of run, While you play and General, in plainer words. What opens at the end of a run, how amounts are written and the valuable loot notice are now one choice each. Options that do nothing as things stand are greyed out, and a Defaults button puts them all back.
- Size now applies to every window, not only the main one.
- Lowering the number of runs to keep asks first, then deletes at once, instead of deleting later without a word.
- The Bingo button leaves the main window while bingo is switched off.
- New installs write amounts as 12g 34s, without copper.

## 0.4.0

New

- **Sharing runs.** The Share button posts the run on show as a link in chat, in a channel you pick (never General, Trade or the other global channels); you send it yourself. Players with the addon click it to see the run. Or copy the run as a code to paste anywhere, and import codes in the new Shared runs window (`/tlb share`, `/tlb import`). Runs shared with you sit among yours by date and count in none of your statistics.
- **Podium, Front page and Timeline** are windows of their own, opened from the main window. **Rolls** and **Numbers** are tabs of the Statistics window, for the run on show. The run details window is gone.
- The main window's top row has buttons of one size: Need only (was Need rolls only), Podium, Front page, Timeline, Statistics and Bingo, with Share on its own on the right. Each closes its window again on a second click. Delete is in red.
- New installs start with the Modern theme and players in podium order. Settings you already chose stay as they are.

Fixed

- Players who are out of sight or gone from the group show their class icon. The stand-ins built from their race and gear looked wrong, and their saved looks are removed from your saved data.
- Going straight from one dungeon into another (a queue that pops inside) now ends the first run like walking out: window, podium and streak notice.
- A roll win whose item never arrived no longer marks a later copy of that item as won.
- A window opened from another comes to the front: a run opened from Statistics, the bingo card.
- Item search shows grey and right-clicked items at the price they have in their run.
- The streak notice shows once per run, not each time you step out. Two runs in a row with the same partner count as a streak.
- Switching an item's price updates every open window. Switching to the list view stops the award reveal, sounds and screenshot included.

## 0.3.2

- No change to the addon. The Wago listing was set up again, so its ID changed once more.

## 0.3.1

- No change to the addon. It carries the ID of its new Wago listing, so addon managers match it to the right page.

## 0.3.0

- The addon is now called **That Lucky Bastard**. It was FairShare until now. Another addon for WoW Forever already uses that name, with the same folder and the same saved-data name, so the two could not be installed side by side.
- The commands are `/tlb` and `/lucky`. `/fs` and `/fairshare` are gone.
- Tooltip lines start with the die instead of the addon's name.
- Coming from FairShare: delete the old `FairShare` folder. To keep your runs, close the game, copy `SavedVariables\FairShare.lua` to `ThatLuckyBastard.lua` in the same folder, and change `FairShareDB` on the copy's first line to `ThatLuckyBastardDB`.

## 0.2.2

- No change to the addon. This release carries the screenshot and logo used by the addon listings.

## 0.2.1

- Junk (grey items) is valued at its vendor price by default; a right-click switches it to its auction price.

## 0.2.0

Recording

- The time of every pickup, every roll in full (who rolled what, who won) and the time of every boss kill are now recorded.
- Roll detection, written for the modern client's message format: items won on Need or Greed, and a "Need rolls only" view.
- The window opens when you leave a dungeon alive; last-boss detection is gone.
- Player names follow the game's "My Secondary Name" setting.

Run details

- End-of-run awards, revealed one by one: one per player out of about twenty, chosen by how far they stand out from the rest of the group. Each explains itself on hover, and `/fs awards` lists them all.
- Run details window: a podium scene with the group's characters, a mock newspaper front page, a timeline chart, the roll sheet, and numbers (fairness, loot by source, roll luck, streak, today's prices, award scores).
- Under the breakdown: run time, gold per hour, fairness, dungeon records, comparison with your average, and the streak the run belongs to.
- Everyone's roll in an item's tooltip.
- Right-click an item to switch it between auction and vendor price; markers show which values are auction prices.

Statistics

- Statistics panel: dungeons (averages and gold per hour), records, runs, luck, regulars, drops, roles and item search. Columns can be sorted.
- Export of a run, or of every run, as text for a spreadsheet.

While you play

- Live on-screen notices for valuable loot.
- Familiar faces: a notice when someone you have run with joins your group.
- One line in player tooltips and in item tooltips about what your runs know of them.
- Streak recap when you chain runs with the same group or in the same dungeon.
- Loot bingo: a private card dealt each run.

Other

- Pin a run so that it is never deleted, and delete a single run, from the main window or with `/fs pin` and `/fs delete`. `/fs clear` leaves pinned runs.
- A look of its own: a mark (a gold die showing five, with one lucky pip), the name in two tones in every window title, an accent colour, and tabs that show which page is open.
- Players keep a picture after the group is gone: their race, sex and gear are saved during the run, and a stand-in portrait or model is built from them.
- Quest items have their own category, always shown last.
- The number of runs to keep can be unlimited.
- The Retail theme and the "Compact rows" option are gone: Classic and Modern remain, and rows are always compact.
- Main window toolbar: "Need rolls only", "Run details", "Statistics" and "Bingo".
- A test rig in `tests/`.

## 0.1.0

First release.

- Tracks loot for every player in the group during dungeon and raid runs.
- Values loot at vendor price and, with Auctionator or TradeSkillMaster, at auction price.
- Breakdown window with a column view for small groups and a list view for larger ones.
- Item categories: epic, blue and green BoE, Bind on Pickup, quest items, profession materials, other, junk.
- Three themes: Classic, Retail and Modern.
- Options panel, minimap button and slash commands (`/fs`, `/fairshare`).
- Run history, saved between sessions.
- `FairShare_Example`: optional test addon with sample runs.
