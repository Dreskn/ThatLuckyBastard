# Changelog

## 0.8.1

### New

- Reprice a run with today's auction prices, next to the Delete button.

### Changes

- Ignore reworked, and enchanting mats are now ignored automatically.
- Small tweaks to options and UI.

## 0.8.0

### New

- Bets: call the lucky bastard as each run starts.
- Lock the meter's place and size.

### Changes

- Need only moved to Analysis › Rolls.
- Loot bingo has retired in a cozy Elwynn farmstead.
- Small tweaks to options and UI.

## 0.7.0

### New

- Right-click an item to switch its price, ignore it, or split it between players.

### Changes

- Options layout reworked.

## 0.6.1

### New

- Coins looted from mobs now count, as a Coins line under each player (Options › Loot).

## 0.6.0

### New

- Loot meter: a live bar per player, like a damage meter. Open it with the Meter button or `/tlb meter`, or have it open with each run (Options › While you play).
- The meter and mini mode show dungeons by their short names (RFC, ZF, BRD).

### Changes

- The end-of-run race now drops gold coins into each column.
- Ninja and Luckiest no longer outrank other awards.
- Player tooltips and Regulars count every award, not only Ninja and Luckiest.
- The Front page headline goes to the run's most notable award.

## 0.5.6

- **Mini mode.** A new box beside the themes, under Options › Window, for a small window: one card per player with their picture, name, award and total, and nothing else. No loot, no footer, and a single button, the cogwheel beside the cross; the window is exactly as big as its cards (about 570 by 150 for five players) in every theme. Past five players, an arrow after the top five counts the others and shows the run as a list in the full window, where Columns leads back.
- **Your own accent colour.** A Color section under the themes, in Options › Window, changes the Modern theme's teal: pick Class (your class colour), Amber, Light or Dark, or choose Custom and set red, green and blue yourself. It tints the title bars, the middle word of the titles, the marks under selected buttons, the arrows and what lights up under the mouse. The other themes keep their own colours.
- **Options is a cogwheel.** It stands where the Options button was, at the foot of the window; the mini window has it beside its cross.
- **The race is run with bars.** A bar grows under each player, all at the same speed, and stops at that player's total, which is shown at that moment: no more numbers spinning. The bench stays out of sight until it is over.

## 0.5.5

- **The race replaces the Podium window.** When you leave a run, its columns race for their places: every total counts up at the same speed, the smallest stops first, and the last one still counting has won. The columns then move to their places and the loot, shares and awards appear. It takes about five seconds and a click skips it; `/tlb race` plays it again for the run on show. It needs the columns in podium order (the default) and can be switched off under Options › End of run. The Podium window, its button and `/tlb podium` are gone: its characters could only be shown in the moment before the group broke up. If the Podium was all you had open at the end of a run, the breakdown now opens in its place.
- **Bingo: pick a line.** The card is dealt as the run starts, and you bet on one row, column or diagonal by clicking its marker. A line can be picked as long as none of its squares is ticked, and the pick is for good. It wins if it fills before the run is over, and the card counts the lines you have won. A line you did not pick is no longer announced. A notice says when a new card is waiting.
- **Item tooltips: choose the kinds of item.** Under Options › While you play, the line about items seen in your runs has one box per category. Epic, blue and green BoE and Bind on Pickup are ticked to begin with, so materials, junk, quest items and the rest no longer get the line unless you tick them.

## 0.5.0

- **Awards for raids.** An award now goes to one player in a party, two in a group of up to ten and three in anything bigger, numbered from the second: Hoarder, Hoarder II, Hoarder III.
- **Ten new awards,** for groups of any size: AFK, Hunter Loot, Need Before Greed, 50 DKP Minus, Tank Tax, Healer's Tip, Top DPS, Class Act, Class Clown and Boss's Pet (one per boss; one in all in a party).
- **Ties are shared.** Two players with the same score and the same loot both get the award; before, the name that came first had it.
- **Hot Streak, Loaded Dice and Cursed Dice count contested rolls only.** A win nobody rolled against, or a Greed number against someone's Need, no longer counts. The dice awards also ask for more: five rolls, and an average of about 65 (or 36) over 15 rolls. Before, fair dice qualified someone in two runs out of three.
- **Codes from other players are read with care.** A code's length is checked before anything else, every list in it has a limit (well above what a raid of forty needs), and reading one no longer slows down with its size: a code written to freeze the game is refused at once. A link now carries up to 141,600 characters, room for a busy raid.
- **Room for thousands of runs.** A finished run is now saved as one code, the one sharing uses, in place of a table of every pickup and item: about a tenth of the text. The saved file used to fill up at some 300 runs, which could have kept it from loading. Runs are converted by themselves the first time the game saves, each one only after checking that it reads back the same; one that would not stays as it was. Nothing changes in the windows. Versions before 0.5.0 cannot read the converted runs.
- **`/tlb clear` asks first,** saying how many runs would go: yours, the one in progress, and those shared with you.
- **Names in other alphabets survive sharing.** A code could lose bytes of a name written in Cyrillic or with accents on some systems.
- **A bench for bigger groups.** A run of more than five players keeps its columns: the top five by loot get one each, and the others follow under them on small cards, side by side (picture, name, award and loot value, as the options say). The row ends with an arrow marked List, with the number of players left out under it, which shows that run as a list; its mirror at the top of the list, marked Columns, brings the columns back. The example addon's raid now has forty players, to show it. The Podium names them under the stage too. Before, a sixth player turned the whole window into a list.
- **Historical or current prices.** A new choice under Options › Loot: runs keep the auction prices recorded when their loot dropped (the default), or are valued at today's.
- **Coming back to life outside ends the run on screen.** Leaving dead used to show nothing, ever; the window and the podium now open once you are alive again outside the dungeon.
- **Another group is another run.** A group that forms while you are still inside, or that you come back in with, is no longer added to the run before it. Players replaced one or two at a time stay one run. Whoever joined in a run's last two minutes and did nothing is left out.
- **"Earlier runs" are the earlier ones.** A run is compared with the dungeon's average as it stood before it, not with runs made since.
- **Consolation prizes say what the player did** ("Won 2 rolls or more"), since whoever gets one is not always the best of the group at it.

## 0.4.6

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
