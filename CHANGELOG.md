# Changelog

All notable changes to Gristle will be documented here.

## [1.4.0] — 2026-11-27

### Added

- **Pick your font.** A new Font setting under Readouts switches every piece of text on the bars -
  your name, your level and both numbers - between Verdana, Trajan Pro, Book Antiqua, Arial, Lucida
  Console and Fixedsys. Your sizes are kept; if a font doesn't come in the size you chose, the
  nearest one it has is used. Book Antiqua runs noticeably smaller than the others at the same
  number, so you may want to turn its sizes up.

### Fixed

- **The numbers on the morale bar have their outline back.** With bold switched on, the readouts
  were drawn in a bold Verdana the game never outlines, so they had no dark edge and were hard to
  read on a bright bar. Verdana readouts are now always drawn in regular weight, which keeps the
  outline. If you want bold numbers, pick Trajan Pro or Book Antiqua - both have bold versions that
  keep the outline.

## [1.3.0] — 2026-11-21

### Added

- **The bars have some depth now.** A faint light band runs along the top of each bar and a faint
  shadow along the bottom, so they read as solid bars rather than flat paint. The new Sheen setting
  under Appearance turns it up, down, or off entirely at 0.

- **Marks at your warning and danger points.** Two thin lines on the morale bar show where it will
  change colour, so you can see how far you are from trouble before you get there. They move with
  your temporary morale, and can be switched off.

- **Readable numbers on a bright bar.** White text on a yellow or pale bar is hard to read. A number
  sitting on a bright colour now turns dark and goes back to white once the bar drains out from
  under it. The dark colour is yours to pick ("Text on bright fill"), and the whole behaviour can be
  switched off.

- **Smooth colour changes.** Optionally, the morale bar can slide gradually from its normal colour
  to the warning colour as you lose morale, instead of jumping between them. Danger is never faded
  into: the moment you cross the danger line the bar turns fully to the danger colour, so it can't
  creep up on you.

- **Class icons.** Your class emblem now sits beside your name, and when you target another player
  (or a creep in the Ettenmoors) theirs sits beside theirs. Monsters and NPCs have no class, so
  their name simply starts at the edge as before. Each frame has its own switch for it. With the
  icon on, the name line is never shorter than the icon, so at small name sizes the bars sit a
  couple of pixels lower.

- **Any colour you like.** Every colour row has a box for a six-digit colour code such as #F9C229,
  next to the preset swatches. It takes effect as soon as the code is complete.

### Changed

- **Sinew is now called Gristle.** The plugin has a new name, so it is loaded with
  `/plugins load Gristle` and its commands start with `/gristle` (the old `/sinew` command is
  gone). If you were set to load Sinew automatically, tick Gristle in the plugin manager instead.
  Your settings come across on their own: the first time Gristle loads on a character, it picks up
  that character's Sinew settings and carries on from there.

- **The percentage is now bold whenever the number is.** The two readouts inside the bar share one
  weight, so they read as a pair instead of a headline and a footnote. The game only has bold text
  at size 16, so bold readouts are always drawn at that size.

- **No more double border at a gap of 0.** With the gap set to 0, the morale and power bars now
  share a single border line between them instead of drawing two side by side, so the pair reads as
  one frame.

## [1.2.0] — 2026-11-17

### Added

- **The readouts are now yours to write.** Each frame has four of them — two inside the morale bar
  and two on the name row — and each one is a line of text you type, with tags in it for the things
  Gristle knows. `[cur]  [perc]` gives you `12,480  74%`. `[cur] / [max]` gives you
  `12,480 / 16,800`. `[name]` inside the bar puts the name on the bar rather than above it. There
  are eleven tags and `/gristle format` lists them all with what each one does.

  This replaces the three switches that were there before — show the absolute number, show the
  percentage, show the level — and it keeps whatever you had them set to, so nothing looks any
  different until you change something. Turning a readout off is now done by clearing its box.

  The player frame and the target frame have their own four, which is the thing the switches could
  not do: you can have your own morale as a big absolute number and the target's as nothing but a
  percentage.

  A tag with nothing to say prints nothing, and a line whose every tag came back empty disappears
  altogether. That is what makes `Level [level]` print nothing at all when you have a chest
  selected rather than a bare "Level", and what makes the gap in `[cur]  [temp]` close itself when
  the bubble is gone.

- **The level's label is a word you choose.** `[level]` is the bare number, so the name row's
  default of `Level [level]` can become `Stufe [level]`, or `L[level]`, or just `[level]`.

- **Power can be shown as a number.** The hairline under the morale bar is a few pixels tall and
  there was never anywhere to put a number on it. `[pow]`, `[maxpow]` and `[powperc]` work in the
  morale bar's own readouts, so your power can read as a number beside your morale — and it keeps
  working with the hairline itself switched off, if you would rather have the figure than the bar.

- **A deficit readout.** `[deficit]` is how much morale you are missing, as `-3,240`, and it stays
  out of the way entirely while you are at full. It is the number that actually tells you how big a
  heal you need.

- **Abbreviated numbers.** A new switch under Readouts turns `12,480` into `12.5k` and `1,240,000`
  into `1.24M`, everywhere at once. It is off to begin with, so upgrading changes nothing until you
  ask it to. Individual readouts can override it either way — `[cur:short]` is always abbreviated
  and `[cur:full]` never is — which is worth knowing for a deficit, where the last three digits are
  the whole point.

- **Percentages can have a decimal place.** `[perc:1]` reads `74.3%`, `[perc:2]` reads `74.30%`.

### Changed

- **The target frame's two morale readouts now read from the opposite end to yours.** The target's
  name already sat at the right of its frame with the level at the left, mirroring your own; the
  number and the percentage inside the bar did not, and stayed left and right on both frames. Now
  they flip too, so the whole target frame is the reflection of the player frame rather than only
  the line above the bar. Mirror the target frame across the screen and the pair reads as one
  symmetric set.

- The three size steppers under Readouts are now named for the boxes they belong to rather than for
  what those boxes used to hold: "First box size", "Second box size", "Name row size". The first box
  is the one that reads inward from the frame's own end — the left on your frame, the right on the
  target's.

## [1.1.0] — 2026-11-17

### Added

- **Name row** — a bar can now carry a line above it naming who it is describing, with their level
  on the right. Your own name over your bars, whatever you are fighting over the target bars. The
  player bars and the target bars decide separately whether they want one, the level can be turned
  off on its own, and the text has its own size and its own colour so it can sit quieter than the
  morale number without washing out.

  A name longer than the bar is cut off at the end of the bar rather than running out across the
  screen, which matters the first time you target something with a very long name.

  One thing to expect the first time you load this: the window grows downwards to make room for the
  row, so your bars will sit a little lower than they did and may want nudging back into place with
  `/gristle move`.

- **Mirrored target frame** — a new option under Window places the target bars as the reflection of
  your own bars across the middle of the screen, the same distance in from the opposite edge and at
  the same height. Drag either frame and both move, so the pair stays symmetric without you having
  to line them up by eye.

  The target frame's own saved position is kept while this is on and comes back untouched if you
  turn it off. Worth knowing before you try it: a frame already sitting in the middle of the screen
  reflects onto roughly itself, so move your own bars off to one side first or the two will land on
  top of each other.

- **Clickable frames** — the game's own entity element now sits under both frames, so they behave
  the way the stock vitals panels did: click to target, right-click for the context menu, hover for
  the tooltip. This is the one part of Gristle that takes the mouse rather than letting clicks through
  to the world, so there is a switch for it under Behaviour if you would rather have the bars be
  holes you can click straight through.

- **Fine positioning** — dragging a frame lands it wherever the mouse happened to be released, which
  is not good enough for lining a bar up against a quickslot bar or another plugin's window. The
  options panel can now move either frame one pixel at a time, in either direction. Mirroring is
  respected: nudge either frame and the pair stays symmetric.

- **The two name rows read outward from opposite ends** — your name from the left of your frame,
  the target's from the right of theirs, each with the level at the other end. The pair reads as a
  mirrored set, which is what it looks like once the target frame is mirrored across the screen and
  still reads correctly when it is not.

- **Anything you select now gets a frame.** A chest, a door, a crafting station or a quest object
  has no morale at all, and previously the target frame simply vanished for them. Now you get the
  name over an empty background: what you have selected is worth seeing even when there is nothing
  to report about it. The same goes for a target that stops answering — it keeps its name while the
  bar and the numbers go, rather than the whole frame disappearing out from under you.

- **Every readout is outlined in black**, the morale number and percentage included, so the text
  stays legible over a full bright bar, an empty dark track and the scenery alike. The outline was
  being drawn in a colour the game chose rather than one Gristle asked for.

### Changed

- **One opacity instead of two.** The separate in-combat and out-of-combat opacities are gone,
  replaced by a single opacity that stays where you put it. The HUD no longer fades when a fight
  ends — which was hardest to read at exactly the moment you were checking whether the fight really
  had ended. It defaults to fully opaque, and drag mode still ignores it, so a HUD turned right down
  is still something you can find in order to move it.

- **The target's power bar is now shown by default.** It was there all along but switched off. A
  character that already has settings saved gets it turned on once, and it can be turned straight
  back off in the options panel if you preferred it without.

- **The target's power bar now takes itself off screen for a target that has no power at all** —
  which is most of the monsters in the game — instead of showing an empty strip under its morale.
  The window keeps its height while it does, so nothing on screen jumps as you tab between a
  caster and a bear.

### Fixed

- **The morale bar was empty, with no numbers on it**, while the power bar right beneath it worked
  and moved. The morale bar was being drawn correctly the whole time — full width, right colour,
  numbers and percentage and all — into a container the game had never been told to put on screen.
  Nothing inside a hidden container is drawn, however visible the things inside it believe
  themselves to be. The power bar escaped the same fate by accident, because the code that lays the
  window out happens to show that one explicitly. Both are now shown deliberately.

  Two further robustness fixes came out of chasing it, neither of which turned out to be the cause
  but both of which are real:

  - The game can report a maximum morale of zero while reporting your actual morale quite happily,
    and there is no way to draw a share of zero. Gristle now falls back to your base maximum.
  - The game hands a plugin an entity slightly before that entity's details have arrived, so the
    first attempt to read can come back with nothing. Gristle treated that as final, and since nothing
    redraws a bar until the value next *changes* — which for a character at full morale out of
    combat, or a target you are not fighting, may be never — the bar could stay blank. It now waits
    for the reading and fills itself in when it arrives.

- **Added `/gristle debug`.** If a bar is ever blank again, this prints what the client actually
  reports for your vitals and what Gristle drew from it, which is the difference between a fix and a
  guess.

- **The first time you targeted something, its bar was often blank.** The same cause, and worse on a
  target: a monster you are not fighting may never change its morale at all, so the bar stayed empty
  for as long as you kept that target. Gristle had also been deciding whether something *had* morale by
  asking it there and then, which meant a target whose details had not loaded was written off
  entirely and never watched again. It now decides from what the target is rather than from what it
  answers in that first instant — the approach VitalTarget used — and waits for the numbers.

- **The options panel now scrolls.** It had grown to more than twice the height the Plugin Manager
  will draw, and everything past that point was simply not on screen — the readouts section was cut
  off in the middle, and the behaviour, colour, shared-settings and reset sections below it could
  not be reached at all. There is now a scrollbar down the right-hand side, and the mouse wheel
  works over the panel as well.

## [1.0.0] — 2026-11-08

Initial release.

Gristle replaces the morale and power bars for your character and your current target with bars
built for reading at a glance mid-fight. It is the successor to VitalTarget, which only covered
the target.

The layout puts everything into one dominant morale bar — the absolute number on the left, the
percentage on the right — and demotes power to a thin hairline underneath it. The intent is that
you read morale and merely feel power draining.

Gristle needs the **NoVitals** skin that ships alongside it. The skin is what actually hides the
stock frames, and it exists because the one plugin command that can hide them takes your buff and
debuff icons down at the same time. A skin can erase the bars and leave every effect icon exactly
where it was.

### Added

- **Morale bar** with the absolute value and the percentage side by side, recolouring from green
  to amber below half morale and to red below a quarter. Both thresholds are configurable.
- **Power hairline** under the morale bar, four pixels tall by default. Shown for your character,
  hidden for the target, either way switchable.
- **Temporary morale** — a bubble claims a proportional slice of the right-hand end of the bar and
  the morale fill shrinks into what remains, with the bubble's own value shown next to your morale
  number. An absurdly large bubble can no longer squeeze the morale bar down to nothing: it is
  capped at half the bar.
- **Incoming damage flash** — the morale you just lost stays lit for a moment and fades out, so a
  big hit reads as a big hit rather than just a lower number. Overlapping hits each get their own
  flash. Healing, a change in maximum morale, and a bubble appearing all correctly refuse to
  flash.
- **Two independent windows** for your bars and the target's, each dragged and saved separately,
  so the target bar can sit near the crosshair while your own sits low.
- **Combat opacity** — the bars recede out of combat and come back when something starts hitting
  you.
- **Target handling** for anything with morale, including monsters, NPCs and other players. The
  bar hides itself for chests, doors and other objects that have no morale at all, rather than
  erroring, and hides when a target dies or goes out of range instead of leaving a stale value on
  screen.
- **Options panel** covering both windows' sizes, the readouts, the border, the flash, the warning
  and danger thresholds, both opacities, and every colour. Everything applies the moment you
  change it — the bars are the preview.
- **Drag mode** via `/gristle move` or the options panel. The target bars stay visible while drag
  mode is on even with nothing targeted, so there is always something to grab.
- **Per-character settings** with a shared copy that can be saved once and loaded onto every other
  character.
- `/gristle`, `/gristle move`, `/gristle self`, `/gristle target` and `/gristle reset`.
- Window positions are stored as a fraction of the screen rather than in pixels, so changing
  resolution moves the bars with it instead of stranding them off the edge.
- Non-English clients are handled: German and French clients cannot store numbers in a savefile
  intact, so every number is converted on the way in and out.

### Notes

- Mounted combat is not covered. On a war-steed the morale and power that matter belong to the
  steed rather than to you, and Gristle keeps showing yours.
- The small secondary-target frame is left alone by the skin.
- If you also run Gibberish3, load Gristle after it. Gibberish3 claims the target-changed event
  outright instead of sharing it, so loading Gristle first means the target bar stops updating.
  Reloading Gristle fixes it.
