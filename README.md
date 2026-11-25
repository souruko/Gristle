# Gristle

Replacement morale and power bars for your character and your current target, built for reading at
a glance mid-fight rather than for looking like the rest of the UI.

One dominant morale bar carrying the absolute number and the percentage, with power demoted to a
thin hairline underneath it. The idea is that you *read* morale and you *feel* power.

```
  Souru                        Level 150    name row
  ┌──────────────────────────────────────┐
  │                                      │
  │  ███████████████████▏ 12,480    74%  │   morale
  │                                      │
  └──────────────────────────────────────┘
    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀               power
```

## This needs a companion skin

Gristle only *draws*. Hiding the stock frames is done by a UI skin, and that split is forced rather
than chosen.

The only Lua call that can hide the vitals frames is
`Turbine.UI.Lotro.LotroUI.SetEnabled( LotroUIElement.Vitals, false )`, and it has no sub-element
granularity — it takes the buff and debuff icons down with the bars. That is why PrimePlugins has
to ship its own `EffectBox.lua`. A skin can be selective where the API cannot, because in both
panels the effect display is a *sibling* of the bar hierarchy rather than a child of it.

Skins live in `<Documents>/The Lord of the Rings Online/ui/skins/` and are selected with
**Ctrl-O → UI Settings → Current User Skin → Accept**, followed by a full client restart. Selecting
it in that dropdown is the step that actually does anything — restarting on its own leaves you on
the default skin, and a skin missing from the list failed to parse without the client saying so.

**The companion skin is [`EffectsOnly`](https://github.com/souruko/EffectsOnly)** (`ui/skins/EffectsOnly/`, formerly `BlankVitals`). It
removes everything on both stock plates — bars, numbers, names, portraits, level, rank icons and the
animated rank flames on elite targets — and leaves only the buff and debuff trays, which keep their
tooltips and their separate debuff row. So Gristle's bars are the only ones on screen. The skin's own
`README.md` carries the full account of how it works.

## Features

- **Morale bar** — recolouring from green to amber below 50% and to red below 25%.
- **Readouts you write yourself** — four per frame, two inside the morale bar and two on the name
  row, each one a line of text with tags in it. `[cur]  [perc]` is the default and gives
  `12,480  74%`; `[cur] / [max]`, `[deficit]`, `[name]`, `Stufe [level]` and `[powperc]` are all
  equally valid. Eleven tags, listed by `/gristle format`. The two frames have their own four, so your
  own morale can be a number while the target's is only a percentage. Clearing a box drops that
  readout; numbers can be abbreviated to `12.5k` globally or per tag.
- **Power hairline** — a thin strip under the morale bar, for your character and your target
  alike. On the target it hides itself for anything that has no power at all, which is most
  monsters, rather than sitting there as an empty track. It is too thin to carry a number, so
  `[pow]` and `[powperc]` work in the morale bar's readouts instead.
- **Name row** — who the window is describing, above the bar, with their level at the other end.
  Your name reads inward from the left and the target's inward from the right, so the pair reads as
  a mirrored set. Either window can have it, both ends are readouts like the bar's, and the row
  itself switches off.
- **Anything you select gets a frame** — a chest, a door or a crafting station has no morale at all,
  so it gets its name over an empty background rather than no frame. What you have selected is
  worth seeing even when there is nothing to report about it.
- **Clickable frames** — the game's own entity element sits under each frame, so clicking targets,
  right-clicking opens the context menu and hovering gives the entity tooltip, exactly as the stock
  panels do. It is the one part of Gristle that takes the mouse, so it can be switched off to get a
  wholly click-through HUD back.
- **Fine positioning** — a drag lands wherever the mouse was released; the options panel moves
  either frame a pixel at a time for lining up against a quickslot bar or another plugin's window.
- **Temporary morale** — a bubble takes a proportional slice off the right-hand end and the morale
  fill shrinks into what is left. The bubble's own value is shown next to the morale number.
- **Depth and marks** — a faint light band along the top of each bar and a shadow along the
  bottom fake the gradient the game cannot draw, and two thin marks on the morale bar sit at the
  warn and danger percentages. Both are under Appearance; a sheen of 0 is a flat bar again.
- **Readable on any colour** — a readout sitting on a bright fill turns dark ("Text on bright
  fill") and goes back to white once the bar drains out from under it.
- **Class icons** — the game's class emblem at the outer end of the name row, at its own 20px, for
  you and for any player target. Monsters and objects show none. A switch per frame.
- **Colours** — nine preset swatches per colour, or any colour typed as a six-digit code. The
  morale bar can either switch colour at the warn and danger lines or slide smoothly down to the
  warn colour, with danger still landing all at once.
- **Incoming damage flash** — the chunk of morale just lost stays lit for a moment and fades, so
  you can see how hard a hit landed rather than only where you ended up.
- **The target frame is the player frame's reflection** — its name, its level and both of its
  morale readouts read inward from the right where the player's read inward from the left, so the
  two frames mirror each other rather than being two copies of the same thing.
- **Two independent windows** — the player's bars and the target's bars drag and save separately,
  or **mirror** the target frame across the screen's centre line so it tracks the player frame as
  its reflection. Dragging either one then moves both.
- **Opacity** — one fixed value for both windows. Drag mode ignores it, so a HUD turned down to a
  faint shadow is still something you can find in order to move it.
- **Per-character settings** with a shared copy you can hand to every character.

## Readouts

Each frame has four: two inside the morale bar and two on the name row. Each one is a line of text
with tags in it, and whatever the line renders to is what is drawn.

The first of each pair reads inward from the frame's own end and the second from the other, so the
player frame reads left to right and the target frame right to left — name row and bar readouts
alike. That is fixed per frame rather than a setting: it makes the pair a reflection, which is what
they look like once the target frame is mirrored across the screen and still reads correctly when it
is not.

| | |
|---|---|
| `[cur]` `[max]` | the vital and its maximum |
| `[perc]` | `74%`. `[perc:1]` and `[perc:2]` add decimal places |
| `[deficit]` | how much is missing, as `-3,240`. Blank at full |
| `[temp]` `[maxtemp]` | temporary morale, as `+125`. Blank when there is none |
| `[pow]` `[maxpow]` `[powperc]` | power, which the hairline is too thin to carry a number for |
| `[name]` | who the frame is describing |
| `[level]` | their level, as a bare number. Blank for a chest or a door |

`[cur:short]` is always abbreviated to `12.5k`, `[cur:full]` never is, and with neither it follows
the Abbreviate switch. An unknown tag is drawn exactly as you typed it — the game has no log, so a
typo that rendered as nothing would look identical to a tag that correctly had nothing to say.

Two rules make a template behave the way you want rather than the way plain substitution would. A
tag with nothing to say renders as nothing. And if *every* tag in a line came back empty the whole
line goes, and what is left is trimmed — which is why `Level [level]` prints nothing at all for a
chest instead of a bare "Level", and why the gap in `[cur]  [temp]` closes itself when the bubble is
gone. A line with no tags in it is literal text and always shows.

Clearing a box is how a readout is switched off. There is no separate switch, because an empty
template and a switched-off readout are the same thing.

## Commands

| | |
|---|---|
| `/gristle` | the command list |
| `/gristle move` | toggle drag mode for both windows |
| `/gristle self` | show or hide the player bars |
| `/gristle target` | show or hide the target bars |
| `/gristle format` | every tag a readout can contain, and what the four frames are set to now |
| `/gristle debug` | print what the client reports for your vitals, and what the bar did with it |
| `/gristle reset` | restore every setting to its default |

`/gristle format` exists because the options panel has room for the tag names and not for what they
mean, and the game has no tooltip to put the rest in. A readout is typed, so looking up what can be
typed into it has to be possible from inside the game.

`/gristle debug` exists because this game has no log file and runtime errors only ever reach the chat
window. When a bar is blank there are three possible reasons and they look identical on screen: the
engine answered nothing, the arithmetic came out at zero width, or the fill was drawn in a colour
you cannot see against the track. It prints all three — the raw getter answers, what Gristle made of
them, and the bar's actual width, z-order and colours.

Everything else is in the options panel, via the in-game Plugin Manager. Changes apply
immediately — the bars are the preview.

## Known limitations

- **Mounted combat is not covered.** On a war-steed the relevant vitals live on the `CombatMount`
  entity rather than on the player, which has its own separate events. Gristle keeps showing your
  own morale and power.
- **The secondary target frame is untouched** by the skin. `ID_UISkin_GamePlay_SelectionTarget`
  has its own vitals field and is left stock.
- **A target's class and rank are not shown** on the name row, only its level. Level is on `Actor`,
  so everything with a morale bar reports one; class is on `Player` only.
- **Load order matters next to Gibberish3.** Gibberish3 assigns `LocalPlayer.TargetChanged`
  directly, which overwrites the event slot rather than appending to it. Gristle appends, so loading
  Gristle *after* Gibberish3 leaves both working; loading it first means Gibberish3 drops Gristle's
  target handler. If the target bar stops updating, reload Gristle.

## Tests

There is an offline harness that runs the real source against a hand-written Turbine stub under a
desktop Lua 5.1 — the version the game ships:

```
cd Gristle && sh tests/run_all.sh     # both locales
cd Gristle && lua tests/run.lua       # English client only
cd Gristle && lua tests/run.lua euro  # German / French client only
```

The second pass matters: German and French clients cannot store numbers in a savefile intact, so
every number takes a different route through load, normalise and save. Running the whole suite
under that flag exercises it.

It cannot test drawing. It tests the bar arithmetic, the bubble geometry, the conditions under
which the damage flash is and is not allowed to fire, the dirty flags, the event plumbing, the
click-through invariant, the drag clamping, the idle cost, the readout templates and the savefile
round trip. Nothing imports `tests/` from `Main.lua`, so the folder is inert in the client.

Template rendering is pure, so most of it is tested without a window in the way; what needs a window
is the part the design turns on — that a tag works wherever it is typed, because the context lives
on the window and both widgets read it. The suite also walks the tag list `/gristle format` prints and
checks every entry resolves, so the documentation cannot drift from the code.

## File overview

| File | Role |
|---|---|
| `Main.lua` | entry point, save/load, defaults and clamping, commands, boot, unload |
| `Constants.lua` | the `GRISTLE` namespace, fonts, palette, default settings |
| `Utils.lua` | euro conversion, colours, positions, forced setters, callbacks, vitals reads |
| `Format.lua` | the readout tags, and the two rules that make a template behave on a HUD |
| `Bar.lua` | the one bar widget: border, track, clipping window, fill, bubble, flash pool, sheen, threshold marks, labels and their contrast |
| `NameRow.lua` | the line above a bar, clipped to the bar's width. Holds no data of its own |
| `VitalWindow.lua` | a click-through window holding a name row, a morale bar, a power hairline and a drag handle, and the one render context they all read |
| `SelfWindow.lua` | the player's bars and their event subscriptions |
| `TargetWindow.lua` | the target's bars, and re-subscribing on every target change |
| `Updater.lua` | the single throttled updater: fades the damage flash, and re-reads a vital that was not ready |
| `OptionsPanel.lua` | the settings panel |

## Version

**1.3.0** — see CHANGELOG.md.
