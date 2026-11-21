---------------------------------------------------------------------------------------------------
-- Sinew - constants, fonts, palette and default settings
---------------------------------------------------------------------------------------------------
-- Sinew/ is a single package directory, so everything declared here without `local` is visible to
-- every other Sinew file. SINEW is the shared namespace; only a handful of genuinely session-wide
-- values (LOCALPLAYER, MOVE) sit beside it, matching the style of VitalTarget and FervourFocus.
---------------------------------------------------------------------------------------------------

SINEW = {}

SINEW.Version = "1.2.0"

LOCALPLAYER = Turbine.Gameplay.LocalPlayer:GetInstance()

-- move mode is deliberately not persisted: a saved "windows are draggable" state is a trap, since
-- the handles are opaque and block clicks on whatever is behind them
MOVE = false

SINEW.ScreenWidth, SINEW.ScreenHeight = Turbine.UI.Display:GetSize()

---------------------------------------------------------------------------------------------------
-- fonts
---------------------------------------------------------------------------------------------------
-- the API only exposes specific name+size pairs, and the sizes Verdana actually ships are
-- irregular, so they are listed rather than computed. Verdana is the clearest of the families at
-- small sizes; VerdanaBold exists at 16 only, which is why 16 is the default for the big number.
---------------------------------------------------------------------------------------------------

SINEW.FontSizes = { 10, 12, 14, 16, 18, 20, 22, 23 }

SINEW.Font = {
	[10] = Turbine.UI.Lotro.Font.Verdana10,
	[12] = Turbine.UI.Lotro.Font.Verdana12,
	[14] = Turbine.UI.Lotro.Font.Verdana14,
	[16] = Turbine.UI.Lotro.Font.Verdana16,
	[18] = Turbine.UI.Lotro.Font.Verdana18,
	[20] = Turbine.UI.Lotro.Font.Verdana20,
	[22] = Turbine.UI.Lotro.Font.Verdana22,
	[23] = Turbine.UI.Lotro.Font.Verdana23,
}

SINEW.FontBold = {
	[16] = Turbine.UI.Lotro.Font.VerdanaBold16,
}

-- nearest available size, so a size coming out of a savefile or a resize can never index nil
function SINEW.ResolveFont( size, bold )

	if bold and SINEW.FontBold[ size ] ~= nil then
		return SINEW.FontBold[ size ]
	end

	if SINEW.Font[ size ] ~= nil then
		return SINEW.Font[ size ]
	end

	local best, bestDistance = 14, 1000

	for i = 1, #SINEW.FontSizes do
		local candidate = SINEW.FontSizes[i]
		local distance = math.abs( candidate - ( tonumber( size ) or 14 ) )
		if distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end

	return SINEW.Font[ best ]

end

---------------------------------------------------------------------------------------------------
-- layout constants
---------------------------------------------------------------------------------------------------

SINEW.Border       = 1   -- painted border thickness around a bar
SINEW.LabelPadding = 5   -- inset of the label window, so text never touches the border
SINEW.HandleHeight = 14  -- height of the drag handle shown above a window in move mode
SINEW.FlashPool    = 4   -- flash segments per bar; overlapping hits each get their own
SINEW.NameLead     = 4   -- vertical breathing room added to the name font to get the row height

-- the name row has no height setting of its own: it is nothing but text, so its height follows its
-- font. A separate knob could only ever be set wrong - too small clips the glyphs, too large opens
-- a gap the user then has to close again with the gap setting.
function SINEW.NameHeight()
	return ( tonumber( SINEW.Settings.nameFontSize ) or 14 ) + SINEW.NameLead
end

---------------------------------------------------------------------------------------------------
-- palette
---------------------------------------------------------------------------------------------------
-- stored as plain { R, G, B } tables, never Turbine.UI.Color: a Color is a class instance and
-- cannot survive the savefile serialiser. SINEW.Color() rebuilds the real object on read.
---------------------------------------------------------------------------------------------------

SINEW.Palette = {
	track        = { R = 0.07, G = 0.07, B = 0.09 },  -- the deficit / empty part of a bar
	border       = { R = 0.00, G = 0.00, B = 0.00 },
	morale       = { R = 0.22, G = 0.78, B = 0.35 },
	moraleWarn   = { R = 0.98, G = 0.76, B = 0.16 },
	moraleDanger = { R = 0.92, G = 0.22, B = 0.20 },
	power        = { R = 0.25, G = 0.60, B = 0.95 },
	temp         = { R = 0.45, G = 0.85, B = 1.00 },  -- temporary morale ("bubble")
	flash        = { R = 1.00, G = 0.96, B = 0.88 },  -- the chunk just lost
	text         = { R = 1.00, G = 1.00, B = 1.00 },
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

SINEW.Defaults = {

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

	-- off by default: 12,480 is what Sinew has always shown, and a setting that changes every
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
	-- menu, entity tooltip. It is the one part of Sinew that takes the mouse, so it can be turned
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

	-- colours
	colorTrack        = SINEW.Palette.track,
	colorBorder       = SINEW.Palette.border,
	colorMorale       = SINEW.Palette.morale,
	colorMoraleWarn   = SINEW.Palette.moraleWarn,
	colorMoraleDanger = SINEW.Palette.moraleDanger,
	colorPower        = SINEW.Palette.power,
	colorTemp         = SINEW.Palette.temp,
	colorFlash        = SINEW.Palette.flash,
	colorText         = SINEW.Palette.text,
	colorName         = SINEW.Palette.name,

}

-- live settings; Main.lua replaces this with the loaded savefile before any window is built
SINEW.Settings = {}
