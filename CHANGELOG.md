# Changelog

## 0.2.0

Not released yet.

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

- Quest items have their own category.
- The Retail theme is gone; Classic and Modern remain.
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
