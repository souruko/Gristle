---------------------------------------------------------------------------------------------------
-- Gristle - constants, fonts, palette and default settings
---------------------------------------------------------------------------------------------------
-- Gristle/ is a single package directory, so everything declared here without `local` is visible to
-- every other Gristle file. GRISTLE is the shared namespace; only a handful of genuinely session-wide
-- values (LOCALPLAYER, MOVE) sit beside it, matching the style of VitalTarget and FervourFocus.
---------------------------------------------------------------------------------------------------

GRISTLE = {}

GRISTLE.Version = "1.3.0"

LOCALPLAYER = Turbine.Gameplay.LocalPlayer:GetInstance()

-- move mode is deliberately not persisted: a saved "windows are draggable" state is a trap, since
-- the handles are opaque and block clicks on whatever is behind them
MOVE = false

GRISTLE.ScreenWidth, GRISTLE.ScreenHeight = Turbine.UI.Display:GetSize()

---------------------------------------------------------------------------------------------------
-- fonts
---------------------------------------------------------------------------------------------------
-- the API only exposes specific name+size pairs, and the sizes Verdana actually ships are
-- irregular, so they are listed rather than computed. Verdana is the clearest of the families at
-- small sizes; VerdanaBold exists at 16 only, which is why 16 is the default for the big number,
-- and why a bold readout is always drawn at 16 whatever its size setting says.
---------------------------------------------------------------------------------------------------

GRISTLE.FontSizes = { 10, 12, 14, 16, 18, 20, 22, 23 }

GRISTLE.Font = {
	[10] = Turbine.UI.Lotro.Font.Verdana10,
	[12] = Turbine.UI.Lotro.Font.Verdana12,
	[14] = Turbine.UI.Lotro.Font.Verdana14,
	[16] = Turbine.UI.Lotro.Font.Verdana16,
	[18] = Turbine.UI.Lotro.Font.Verdana18,
	[20] = Turbine.UI.Lotro.Font.Verdana20,
	[22] = Turbine.UI.Lotro.Font.Verdana22,
	[23] = Turbine.UI.Lotro.Font.Verdana23,
}

GRISTLE.FontBold = {
	[16] = Turbine.UI.Lotro.Font.VerdanaBold16,
}

-- nearest available size, so a size coming out of a savefile or a resize can never index nil
function GRISTLE.ResolveFont( size, bold )

	if bold and GRISTLE.FontBold[ size ] ~= nil then
		return GRISTLE.FontBold[ size ]
	end

	-- Verdana's only bold is 16, so a bold readout at any other size would quietly come out regular
	-- - which is how the percentage ended up visibly thinner than the number beside it. Bold wins
	-- over the size: a 14 or an 18 asked for in bold gets the 16.
	if bold and GRISTLE.FontBold[ 16 ] ~= nil then
		return GRISTLE.FontBold[ 16 ]
	end

	if GRISTLE.Font[ size ] ~= nil then
		return GRISTLE.Font[ size ]
	end

	local best, bestDistance = 14, 1000

	for i = 1, #GRISTLE.FontSizes do
		local candidate = GRISTLE.FontSizes[i]
		local distance = math.abs( candidate - ( tonumber( size ) or 14 ) )
		if distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end

	return GRISTLE.Font[ best ]

end

---------------------------------------------------------------------------------------------------
-- layout constants
---------------------------------------------------------------------------------------------------

GRISTLE.Border       = 1   -- painted border thickness around a bar
GRISTLE.LabelPadding = 5   -- inset of the label window, so text never touches the border
GRISTLE.HandleHeight = 14  -- height of the drag handle shown above a window in move mode
GRISTLE.FlashPool    = 4   -- flash segments per bar; overlapping hits each get their own
GRISTLE.NameLead     = 4   -- vertical breathing room added to the name font to get the row height

-- the name row has no height setting of its own: it is nothing but text, so its height follows its
-- font. A separate knob could only ever be set wrong - too small clips the glyphs, too large opens
-- a gap the user then has to close again with the gap setting.
function GRISTLE.NameHeight()
	return ( tonumber( GRISTLE.Settings.nameFontSize ) or 14 ) + GRISTLE.NameLead
end

-- space between the class icon and the name beside it
GRISTLE.ClassIconGap = 3

-- the class emblems' own size in the client's art. They are drawn at exactly this, never scaled:
-- see NameRow, where scaling them was tried and drew a tiled grid instead.
GRISTLE.ClassIconSize = 20

-- The name row's height for one frame: its font's, but never shorter than the class icon while that
-- frame's icon is switched on. Decided by the setting rather than by whether an icon is showing
-- right now, so the bars do not jump by two pixels each time you tab from a monster to a player.
function GRISTLE.NameRowHeight( iconKey )

	local height = GRISTLE.NameHeight()

	if iconKey ~= nil and GRISTLE.Settings[ iconKey ] ~= false then
		height = math.max( height, GRISTLE.ClassIconSize )
	end

	return height

end

---------------------------------------------------------------------------------------------------
-- class icons
---------------------------------------------------------------------------------------------------
-- The game's own round class emblems, 20x20 in the client's art. The IDs are the ones LootLogs
-- draws its character list with (LootLogs/Utils/Constants.lua), already proven in game; the PvMP
-- creep classes are included because a creep is a player as far as GetClass is concerned.
--
-- Built by name rather than as a literal table: a class this client's Turbine.Gameplay.Class does
-- not know would make "[ Class.X ] = id" a nil key, and a nil key in a table constructor throws -
-- which here would take the whole plugin down at load. Unknown names are skipped instead, so the
-- worst an outdated entry can cost is one missing icon.
---------------------------------------------------------------------------------------------------

GRISTLE.ClassIcons = {}

do
	local ids = {
		Hunter     = 0x41007DEA,
		Warden     = 0x410EA239,
		Burglar    = 0x41007DEB,
		Captain    = 0x41007DE7,
		Champion   = 0x41007DEC,
		Guardian   = 0x41007DE8,
		Minstrel   = 0x41007DE6,
		Beorning   = 0x4115370D,
		LoreMaster = 0x41007DE9,
		RuneKeeper = 0x410EA238,
		Brawler    = 0x411F516F,
		Mariner    = 0x4122F875,

		Weaver     = 0x41007DEE,
		Reaver     = 0x41007DED,
		Defiler    = 0x410E6BF4,
		Stalker    = 0x41007DF1,
		WarLeader  = 0x41007DF0,
		BlackArrow = 0x41007DEF,
	}

	local classes = Turbine.Gameplay.Class or {}

	for name, id in pairs( ids ) do
		local value = classes[ name ]
		if value ~= nil then
			GRISTLE.ClassIcons[ value ] = id
		end
	end
end

---------------------------------------------------------------------------------------------------
-- palette
---------------------------------------------------------------------------------------------------
-- stored as plain { R, G, B } tables, never Turbine.UI.Color: a Color is a class instance and
-- cannot survive the savefile serialiser. GRISTLE.Color() rebuilds the real object on read.
---------------------------------------------------------------------------------------------------

GRISTLE.Palette = {
	track        = { R = 0.07, G = 0.07, B = 0.09 },  -- the deficit / empty part of a bar
	border       = { R = 0.00, G = 0.00, B = 0.00 },
	morale       = { R = 0.22, G = 0.78, B = 0.35 },
	moraleWarn   = { R = 0.98, G = 0.76, B = 0.16 },
	moraleDanger = { R = 0.92, G = 0.22, B = 0.20 },
	power        = { R = 0.25, G = 0.60, B = 0.95 },
	temp         = { R = 0.45, G = 0.85, B = 1.00 },  -- temporary morale ("bubble")
	flash        = { R = 1.00, G = 0.96, B = 0.88 },  -- the chunk just lost
	text         = { R = 1.00, G = 1.00, B = 1.00 },
	textDark     = { R = 0.08, G = 0.08, B = 0.10 },  -- readouts over a bright fill
	name         = { R = 0.90, G = 0.87, B = 0.78 },  -- the name row; off-white, so it reads as
	                                                  -- secondary to the number inside the bar
	handle       = { R = 0.95, G = 0.40, B = 0.10 },  -- drag handle, deliberately loud
}

---------------------------------------------------------------------------------------------------
-- defaults
---------------------------------------------------------------------------------------------------
-- positions are screen *ratios*, not pixels, so changing resolution does not throw the windows
-- off-screen. They are converted to pixels on load and back on drag end.
--
-- the self window defaults low and centred, under where the eye already is; the target window
-- defaults high and centred, roughly where the stock opponent frame used to sit.
---------------------------------------------------------------------------------------------------

GRISTLE.Defaults = {

	version = 4,

	-- self window
	selfLeft          = 0.5 - ( 130 / 1920 ),
	selfTop           = 0.76,
	selfWidth         = 260,
	selfBarHeight     = 34,
	selfPowerHeight   = 4,
	selfGap           = 2,
	selfShowPower     = true,
	selfShowName      = true,
	selfShowClassIcon = true,
	selfVisible       = true,

	-- target window
	targetLeft        = 0.5 - ( 130 / 1920 ),
	targetTop         = 0.12,
	targetWidth       = 260,
	targetBarHeight   = 26,
	targetPowerHeight = 4,
	targetGap         = 2,
	targetShowPower   = true,
	targetShowName    = true,
	-- drawn only for a target that has a class - another player, or a creep in the Ettenmoors.
	-- A monster's name simply starts at the edge as it always did.
	targetShowClassIcon = true,
	targetVisible     = true,

	-------------------------------------------------------------------------------------------------
	-- readout templates, four per window. See Format.lua for the tags.
	-------------------------------------------------------------------------------------------------
	-- Per window rather than shared, unlike the font sizes beside them, because the two bars are
	-- genuinely asked different questions: your own morale is the number you act on and a target's
	-- is usually only a percentage. That is the one thing the three switches these replaced could
	-- not express.
	--
	-- The defaults are exactly what those switches produced, so nothing looks different until a
	-- template is edited. "[cur]  [temp]" keeps its two spaces: the gap closes itself when there is
	-- no bubble, so the padding is only ever seen when there is something to pad.
	--
	-- The first of each pair reads inward from the frame's own end and the second from the other,
	-- which is fixed per frame: the player frame reads left to right and the target frame right to
	-- left, name row and bar readouts alike. So "left" and "right" in these key names describe the
	-- player frame, and are the first and second box on the target. The name row's pair is named
	-- main / aside for that reason; the bar's kept its original names rather than earn a migration.
	-------------------------------------------------------------------------------------------------

	selfFormatBarLeft    = "[cur]  [temp]",
	selfFormatBarRight   = "[perc]",
	selfFormatNameMain   = "[name]",
	selfFormatNameAside  = "Level [level]",

	targetFormatBarLeft   = "[cur]  [temp]",
	targetFormatBarRight  = "[perc]",
	targetFormatNameMain  = "[name]",
	targetFormatNameAside = "Level [level]",

	-- off by default: 12,480 is what Gristle has always shown, and a setting that changes every
	-- number on screen the moment it is upgraded is not a setting, it is a surprise
	abbreviateNumbers = false,

	-- when on, the target window's own saved position is ignored and it is placed as the reflection
	-- of the player window across the screen's vertical centre line
	mirrorTarget      = false,

	-- shared appearance. The font sizes stay shared: they are what makes the two frames look like
	-- one HUD, and a size set differently per window reads as a mistake rather than a choice.
	showBorder        = true,
	fontSize          = 16,
	percentFontSize   = 14,
	nameFontSize      = 14,
	boldValue         = true,

	-- which end of the bar the name sits at is not a setting: it is fixed per frame, the player's
	-- reading inward from the left and the target's inward from the right. See NameRow.

	-- the game's own entity element under each frame: click to target, right-click for the context
	-- menu, entity tooltip. It is the one part of Gristle that takes the mouse, so it can be turned
	-- off to get a wholly click-through HUD back.
	entityControl     = true,

	-- behaviour
	flash             = true,
	flashDuration     = 0.35,
	warnPercent       = 50,
	dangerPercent     = 25,

	-- one fixed opacity for both windows. This replaced a pair of in-combat / out-of-combat values:
	-- a HUD that fades when the fight ends is a HUD that is hard to read exactly when you are
	-- checking whether the fight really has ended.
	opacity           = 1.0,

	-- appearance. The engine draws flat rectangles only, so the "gradient" is two see-through strips
	-- over the bar: a light one along the top and a dark one along the bottom. sheen is the light
	-- strip's alpha, and 0 turns both off.
	sheen             = 0.15,

	-- a one pixel mark on the morale bar at the warn and danger percentages
	showTicks         = true,

	-- a readout sitting on a bright fill switches to colorTextDark. White on amber is the weakest
	-- contrast a bar can have, and an outline only goes so far.
	textContrast      = true,

	-- off: the three colours switch at the thresholds. On: the fill slides from one to the next.
	colorBlend        = false,

	-- colours
	colorTrack        = GRISTLE.Palette.track,
	colorBorder       = GRISTLE.Palette.border,
	colorMorale       = GRISTLE.Palette.morale,
	colorMoraleWarn   = GRISTLE.Palette.moraleWarn,
	colorMoraleDanger = GRISTLE.Palette.moraleDanger,
	colorPower        = GRISTLE.Palette.power,
	colorTemp         = GRISTLE.Palette.temp,
	colorFlash        = GRISTLE.Palette.flash,
	colorText         = GRISTLE.Palette.text,
	colorTextDark     = GRISTLE.Palette.textDark,
	colorName         = GRISTLE.Palette.name,

}

-- live settings; Main.lua replaces this with the loaded savefile before any window is built
GRISTLE.Settings = {}
