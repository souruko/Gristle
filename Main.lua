---------------------------------------------------------------------------------------------------
-- Gristle - replacement morale and power bars for the player and the current target
---------------------------------------------------------------------------------------------------
-- Gristle only draws the bars. Hiding the stock frames is the job of a companion UI skin, which lives
-- in <Documents>/The Lord of the Rings Online/ui/skins/ and is selected under Options -> UI
-- Settings. That skin is EffectsOnly (ui/skins/EffectsOnly/, formerly BlankVitals): it removes
-- everything on both stock plates except the buff and debuff trays. Its README is the reference.
--
-- That split is not a style choice. The one Lua call that can hide these frames,
-- Turbine.UI.Lotro.LotroUI.SetEnabled( LotroUIElement.Vitals, false ), has no sub-element
-- granularity: it takes the buff and debuff icons down with the bars. A skin can erase the bars and
-- leave the effects alone, because in both panels the effect display is a sibling of the bar
-- hierarchy rather than a child of it.
---------------------------------------------------------------------------------------------------

import "Turbine"
import "Turbine.Gameplay"
import "Turbine.UI"
import "Turbine.UI.Lotro"

-- load order is explicit and fragile: Constants declares the GRISTLE namespace everything else hangs
-- off, Utils is used by every module below it, and Bar needs the Updater to exist before it can
-- register a fade.
import "Gristle.Constants"
import "Gristle.Utils"
import "Gristle.Format"
import "Gristle.Updater"
import "Gristle.Bar"
import "Gristle.NameRow"
import "Gristle.VitalWindow"
import "Gristle.SelfWindow"
import "Gristle.TargetWindow"
import "Gristle.OptionsPanel"

---------------------------------------------------------------------------------------------------
-- persistence
---------------------------------------------------------------------------------------------------

local SAVE_KEY = "gristleSettings"

-- the plugin was called Sinew before 1.3.0. A scope with no Gristle save yet falls back to the old
-- file once; the next save writes it under the new key, and the old file is never touched again
local LEGACY_SAVE_KEY = "sinewSettings"

local euroClient = GRISTLE.IsEuroClient()

local function WriteScope( scope, data )

	if euroClient then
		data = GRISTLE.ConvertToEuro( data )
	end

	Turbine.PluginData.Save( scope, SAVE_KEY, data )

end

local function LoadScope( scope )

	local data = Turbine.PluginData.Load( scope, SAVE_KEY )

	if data == nil then
		data = Turbine.PluginData.Load( scope, LEGACY_SAVE_KEY )
	end

	if data ~= nil and euroClient then
		data = GRISTLE.ConvertFromEuro( data )
	end

	return data

end

-- Turbine.PluginData.Load is only synchronous while the plugin is loading. Called any later - from
-- the options panel, say - it insists on an async handler and throws. So the account copy is read
-- once, here, and every later read goes through this cache instead of the disk.
local globalCache = LoadScope( Turbine.DataScope.Account )

-- decided once, so mirroring cannot start or stop halfway through a session: either there was an
-- account copy to protect or there was not
local mirrorToGlobal = ( globalCache == nil )

function GRISTLE.Save()

	local data = GRISTLE.DeepCopy( GRISTLE.Settings )

	WriteScope( Turbine.DataScope.Character, data )

	if mirrorToGlobal then
		WriteScope( Turbine.DataScope.Account, data )
		globalCache = data
	end

end

function GRISTLE.HasGlobalSettings()
	return globalCache ~= nil
end

function GRISTLE.SaveGlobalSettings()

	local data = GRISTLE.DeepCopy( GRISTLE.Settings )

	WriteScope( Turbine.DataScope.Account, data )
	globalCache = data

	return true

end

function GRISTLE.LoadGlobalSettings()

	if globalCache == nil then
		return false
	end

	GRISTLE.Settings = GRISTLE.DeepCopy( globalCache )

	GRISTLE.NormaliseSettings()
	GRISTLE.Save()
	GRISTLE.ApplyAll()

	return true

end

---------------------------------------------------------------------------------------------------
-- defaults, validation and migrations
---------------------------------------------------------------------------------------------------
-- idempotent: every key is filled in only when missing, so this runs unchanged on a fresh install,
-- on an old savefile, or on the account copy. Values are clamped as well as defaulted, because a
-- savefile is user-editable and a zero width or a nil font size would take the plugin down.
---------------------------------------------------------------------------------------------------

local function clamp( value, low, high, fallback )

	local n = tonumber( value )

	if n == nil then
		return fallback
	end

	if n < low  then return low  end
	if n > high then return high end

	return n

end

---------------------------------------------------------------------------------------------------
-- a readout template
---------------------------------------------------------------------------------------------------
-- Coerced to a string because a German or French savefile turns anything that parses as a number
-- back into one, so a template of "100" would arrive here as 100. Capped because a savefile is
-- hand-editable and a template is the one setting with no natural upper bound; the bar clips what
-- does not fit, so a thousand characters would not be visible, only rendered.
---------------------------------------------------------------------------------------------------
local FORMAT_LIMIT = 120

local function clampFormat( value, fallback )

	if value == nil or type( value ) == "table" then
		return fallback
	end

	local text = tostring( value )

	if string.len( text ) > FORMAT_LIMIT then
		text = string.sub( text, 1, FORMAT_LIMIT )
	end

	return text

end

local function clampColor( value, fallback )

	if type( value ) ~= "table" then
		return GRISTLE.DeepCopy( fallback )
	end

	return {
		R = clamp( value.R, 0, 1, fallback.R ),
		G = clamp( value.G, 0, 1, fallback.G ),
		B = clamp( value.B, 0, 1, fallback.B ),
	}

end

function GRISTLE.NormaliseSettings()

	local settings = GRISTLE.Settings

	-- read before the defaults are filled in, or a savefile with no version at all looks current
	local from = tonumber( settings.version ) or 0

	for key, value in pairs( GRISTLE.Defaults ) do
		if settings[ key ] == nil then
			-- copied, not aliased: the defaults table holds the shared palette tables, and handing a
			-- live reference to the settings would let the options panel edit GRISTLE.Palette itself
			settings[ key ] = GRISTLE.DeepCopy( value )
		end
	end

	-----------------------------------------------------------------------------------------------
	-- migrations
	-----------------------------------------------------------------------------------------------
	-- 1 -> 2: the target power hairline went from off by default to on. Filling in a missing key is
	-- not enough here - a savefile written under version 1 already holds the old default, so it
	-- would never see the new one. Only a savefile that actually came from version 1 is touched, and
	-- only once: the version is stamped at the bottom of this function.
	if from > 0 and from < 2 then
		settings.targetShowPower = true
	end

	-- 2 -> 3: the in-combat / out-of-combat opacity pair became one fixed opacity. The two old keys
	-- are cleared rather than left to sit in the savefile forever as values nothing reads.
	if from > 0 and from < 3 then
		settings.opacityCombat = nil
		settings.opacityIdle   = nil
	end

	-- 3 -> 4: the three readout switches - show the number, show the percentage, show the level -
	-- became four templates per window. The switches are mapped onto templates rather than dropped,
	-- so an upgraded savefile keeps exactly the readout it had: a cleared template is how a readout
	-- is turned off now, so "it was off" becomes "the template is empty".
	--
	-- Assigned rather than filled in, because the loop above has already put the new defaults in
	-- place by the time this runs.
	if from > 0 and from < 4 then

		local barLeft  = ( settings.showValue   ~= false ) and "[cur]  [temp]"  or ""
		local barRight = ( settings.showPercent ~= false ) and "[perc]"         or ""
		local aside    = ( settings.showLevel   ~= false ) and "Level [level]"  or ""

		settings.selfFormatBarLeft    = barLeft
		settings.selfFormatBarRight   = barRight
		settings.selfFormatNameMain   = "[name]"
		settings.selfFormatNameAside  = aside

		settings.targetFormatBarLeft   = barLeft
		settings.targetFormatBarRight  = barRight
		settings.targetFormatNameMain  = "[name]"
		settings.targetFormatNameAside = aside

	end

	-- read by the migration above, then cleared rather than left in the savefile forever as values
	-- nothing looks at
	settings.showValue   = nil
	settings.showPercent = nil
	settings.showLevel   = nil

	-- Cleared unconditionally rather than behind a version gate: the name alignment was briefly a
	-- setting and is now fixed per frame, but it never reached a released version, so there is no
	-- version number that reliably identifies the savefiles carrying it.
	settings.nameAlignRight = nil

	-- geometry
	settings.selfWidth         = clamp( settings.selfWidth,         40, 1200, GRISTLE.Defaults.selfWidth )
	settings.selfBarHeight     = clamp( settings.selfBarHeight,      6,  160, GRISTLE.Defaults.selfBarHeight )
	settings.selfPowerHeight   = clamp( settings.selfPowerHeight,    1,   60, GRISTLE.Defaults.selfPowerHeight )
	settings.selfGap           = clamp( settings.selfGap,            0,   40, GRISTLE.Defaults.selfGap )

	settings.targetWidth       = clamp( settings.targetWidth,       40, 1200, GRISTLE.Defaults.targetWidth )
	settings.targetBarHeight   = clamp( settings.targetBarHeight,    6,  160, GRISTLE.Defaults.targetBarHeight )
	settings.targetPowerHeight = clamp( settings.targetPowerHeight,  1,   60, GRISTLE.Defaults.targetPowerHeight )
	settings.targetGap         = clamp( settings.targetGap,          0,   40, GRISTLE.Defaults.targetGap )

	-- positions are ratios of the screen
	settings.selfLeft   = clamp( settings.selfLeft,   0, 1, GRISTLE.Defaults.selfLeft )
	settings.selfTop    = clamp( settings.selfTop,    0, 1, GRISTLE.Defaults.selfTop )
	settings.targetLeft = clamp( settings.targetLeft, 0, 1, GRISTLE.Defaults.targetLeft )
	settings.targetTop  = clamp( settings.targetTop,  0, 1, GRISTLE.Defaults.targetTop )

	-- text
	settings.fontSize        = clamp( settings.fontSize,        8, 23, GRISTLE.Defaults.fontSize )
	settings.percentFontSize = clamp( settings.percentFontSize, 8, 23, GRISTLE.Defaults.percentFontSize )
	settings.nameFontSize    = clamp( settings.nameFontSize,    8, 23, GRISTLE.Defaults.nameFontSize )

	-- readout templates. An empty one is valid and means "nothing in this slot", so these are
	-- coerced and capped rather than defaulted: falling back on a blank would silently undo the one
	-- way of switching a readout off.
	for _, key in ipairs( {
		"selfFormatBarLeft",   "selfFormatBarRight",   "selfFormatNameMain",   "selfFormatNameAside",
		"targetFormatBarLeft", "targetFormatBarRight", "targetFormatNameMain", "targetFormatNameAside",
	} ) do
		settings[ key ] = clampFormat( settings[ key ], GRISTLE.Defaults[ key ] )
	end

	-- behaviour
	settings.flashDuration = clamp( settings.flashDuration, 0.05, 2.0,  GRISTLE.Defaults.flashDuration )
	settings.warnPercent   = clamp( settings.warnPercent,      2,  99,  GRISTLE.Defaults.warnPercent )
	settings.dangerPercent = clamp( settings.dangerPercent,    1,  98,  GRISTLE.Defaults.dangerPercent )

	-- floored at 0.05 rather than 0: a HUD turned all the way down is invisible, and the panel that
	-- would turn it back up is reached through a window you can no longer see
	settings.opacity       = clamp( settings.opacity,       0.05, 1.0,  GRISTLE.Defaults.opacity )

	-- appearance. Capped at half: past that the light strip stops reading as a sheen and starts
	-- reading as a second, white bar
	settings.sheen = clamp( settings.sheen, 0, 0.5, GRISTLE.Defaults.sheen )

	-- a savefile is hand-editable, and a switch holding anything but true or false would read as on
	for _, key in ipairs( { "showTicks", "textContrast", "colorBlend", "selfShowClassIcon", "targetShowClassIcon" } ) do
		if type( settings[ key ] ) ~= "boolean" then
			settings[ key ] = GRISTLE.Defaults[ key ]
		end
	end

	-- danger has to be the tighter of the two or the warn band can never be reached
	if settings.dangerPercent >= settings.warnPercent then
		settings.dangerPercent = math.max( 1, settings.warnPercent - 1 )
	end

	-- colours
	settings.colorTrack        = clampColor( settings.colorTrack,        GRISTLE.Palette.track )
	settings.colorBorder       = clampColor( settings.colorBorder,       GRISTLE.Palette.border )
	settings.colorMorale       = clampColor( settings.colorMorale,       GRISTLE.Palette.morale )
	settings.colorMoraleWarn   = clampColor( settings.colorMoraleWarn,   GRISTLE.Palette.moraleWarn )
	settings.colorMoraleDanger = clampColor( settings.colorMoraleDanger, GRISTLE.Palette.moraleDanger )
	settings.colorPower        = clampColor( settings.colorPower,        GRISTLE.Palette.power )
	settings.colorTemp         = clampColor( settings.colorTemp,         GRISTLE.Palette.temp )
	settings.colorFlash        = clampColor( settings.colorFlash,        GRISTLE.Palette.flash )
	settings.colorText         = clampColor( settings.colorText,         GRISTLE.Palette.text )
	settings.colorName         = clampColor( settings.colorName,         GRISTLE.Palette.name )
	settings.colorTextDark     = clampColor( settings.colorTextDark,     GRISTLE.Palette.textDark )

	settings.version = 4

end

function GRISTLE.ResetSettings()

	GRISTLE.Settings = {}
	GRISTLE.NormaliseSettings()
	GRISTLE.Save()
	GRISTLE.ApplyAll()

end

---------------------------------------------------------------------------------------------------
-- push settings into the live windows
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- reposition both windows without rebuilding them
-- ApplyLayout clears every bar's dirty-flag cache, which blanks the bars until the next vital
-- event. A move must not pay that, so turning the mirror on or dragging a window goes through here.
---------------------------------------------------------------------------------------------------
function GRISTLE.ApplyPositions()

	if GRISTLE.Self.window   ~= nil then GRISTLE.Self.window:ApplyPosition()   end
	if GRISTLE.Target.window ~= nil then GRISTLE.Target.window:ApplyPosition() end

end

---------------------------------------------------------------------------------------------------
-- re-render the readouts and nothing else
---------------------------------------------------------------------------------------------------
-- Editing a template has to be visible as it is typed, and ApplyAll cannot do that: it relayouts
-- both windows, which clears every dirty-flag cache and blanks the bars until the next vital event.
-- For your own morale at full health out of combat, that event is a long way off.
--
-- Nothing but four strings changed, so nothing but four strings are re-rendered. The widgets compare
-- the result against what is already on screen, so a keystroke that does not change the rendered
-- text costs nothing at all.
---------------------------------------------------------------------------------------------------
function GRISTLE.ApplyFormats()

	if GRISTLE.Self.window   ~= nil then GRISTLE.Self.window:RenderText()   end
	if GRISTLE.Target.window ~= nil then GRISTLE.Target.window:RenderText() end

end

function GRISTLE.ApplyAll()

	local windows = { GRISTLE.Self.window, GRISTLE.Target.window }

	for i = 1, #windows do

		local window = windows[i]

		if window ~= nil then
			window:ApplyColors()
			window:ApplyFonts()
			window:ApplyLayout()
			window:ApplyMove()
		end

	end

	-- the layout cleared every dirty-flag cache, so the bars are empty until the data is pushed again
	GRISTLE.Self.Refresh()
	GRISTLE.Target.Refresh()

	if GRISTLE.Self.window ~= nil then
		GRISTLE.Self.window:SetShown( true )
	end

	-- in move mode the target window stays up with nothing targeted, or changing a setting from the
	-- options panel would take away the thing you were about to drag
	if GRISTLE.Target.window ~= nil then
		if MOVE then
			GRISTLE.Target.window:ForceShown()
		else
			GRISTLE.Target.window:SetShown( GRISTLE.Target.entity ~= nil )
		end
	end

end

function GRISTLE.SetMoveMode( enabled )

	MOVE = enabled and true or false

	if GRISTLE.Self.window   ~= nil then GRISTLE.Self.window:ApplyMove()   end
	if GRISTLE.Target.window ~= nil then GRISTLE.Target.window:ApplyMove() end

	-- the target window is normally hidden without a target, which in move mode would leave nothing
	-- to grab, so it is forced visible for as long as the handles are up
	if GRISTLE.Target.window ~= nil then
		if MOVE then
			GRISTLE.Target.window:ForceShown()
		else
			GRISTLE.Target.window:SetShown( GRISTLE.Target.entity ~= nil )
		end
	end

end

---------------------------------------------------------------------------------------------------
-- start up
---------------------------------------------------------------------------------------------------

GRISTLE.Settings = LoadScope( Turbine.DataScope.Character )

if GRISTLE.Settings == nil then
	-- no character file yet: inherit the account copy if there is one, so a new character starts
	-- where the last one left off
	GRISTLE.Settings = globalCache ~= nil and GRISTLE.DeepCopy( globalCache ) or {}
end

GRISTLE.NormaliseSettings()

GRISTLE.Self.Create()
GRISTLE.Target.Create()

-- wired after both exist, because the target window does not exist while the player one is built.
-- This is the only coupling between the two: dragging the player frame has to carry its mirror.
GRISTLE.Self.window.mirrorFollower = GRISTLE.Target.window

-- the target's position depends on the player's once mirroring is on, and the player window was
-- laid out before the target existed to be mirrored
GRISTLE.ApplyPositions()

---------------------------------------------------------------------------------------------------
-- options panel
---------------------------------------------------------------------------------------------------

local optionsPanel = GRISTLE.CreateOptionsPanel()

if plugin ~= nil then
	plugin.GetOptionsPanel = function()
		return optionsPanel
	end
end

---------------------------------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------------------------------

local command = Turbine.ShellCommand()

local function Usage()
	Turbine.Shell.WriteLine( "Gristle v" .. GRISTLE.Version )
	Turbine.Shell.WriteLine( "  /gristle move    - toggle drag mode for both bars" )
	Turbine.Shell.WriteLine( "  /gristle self    - show or hide the player bars" )
	Turbine.Shell.WriteLine( "  /gristle target  - show or hide the target bars" )
	Turbine.Shell.WriteLine( "  /gristle format  - list the tags a readout can contain" )
	Turbine.Shell.WriteLine( "  /gristle debug   - print what the client reports for your vitals" )
	Turbine.Shell.WriteLine( "  /gristle reset   - restore every setting to its default" )
end

---------------------------------------------------------------------------------------------------
-- the tag reference
---------------------------------------------------------------------------------------------------
-- The options panel has room for the tag names and not for what they mean, and there is no tooltip
-- to put the rest in, so the full list lives here. A readout is typed, so it has to be possible to
-- look up what can be typed into it.
---------------------------------------------------------------------------------------------------

local function Formats()

	local line = Turbine.Shell.WriteLine

	line( "Gristle readouts - four per frame, each one a line of text with tags in it." )
	line( "Set them in the options panel. Clear one to drop that readout entirely." )

	line( "  tags:" )

	for i = 1, #GRISTLE.Format.Help do
		local entry = GRISTLE.Format.Help[i]
		line( "    " .. entry[1] .. string.rep( " ", math.max( 1, 11 - string.len( entry[1] ) ) )
			.. "- " .. entry[2] )
	end

	line( "  modifiers:" )

	for i = 1, #GRISTLE.Format.Modifiers do
		local entry = GRISTLE.Format.Modifiers[i]
		line( "    " .. entry[1] .. "  - " .. entry[2] )
	end

	line( "  a tag with nothing to say renders as nothing, and a line whose every tag came back" )
	line( "  empty is dropped - which is why 'Level [level]' prints nothing at all for a chest." )

	line( "  yours now:" )

	line( "    player bar   '" .. tostring( GRISTLE.Settings.selfFormatBarLeft ) .. "'  /  '"
		.. tostring( GRISTLE.Settings.selfFormatBarRight ) .. "'" )
	line( "    player name  '" .. tostring( GRISTLE.Settings.selfFormatNameMain ) .. "'  /  '"
		.. tostring( GRISTLE.Settings.selfFormatNameAside ) .. "'" )
	line( "    target bar   '" .. tostring( GRISTLE.Settings.targetFormatBarLeft ) .. "'  /  '"
		.. tostring( GRISTLE.Settings.targetFormatBarRight ) .. "'" )
	line( "    target name  '" .. tostring( GRISTLE.Settings.targetFormatNameMain ) .. "'  /  '"
		.. tostring( GRISTLE.Settings.targetFormatNameAside ) .. "'" )

end

---------------------------------------------------------------------------------------------------
-- why a blank bar is blank
---------------------------------------------------------------------------------------------------
-- There is no log file and runtime errors only ever reach the chat window, so a bar that draws
-- nothing gives you no way to tell apart the three things it could be: the engine answered nothing,
-- the arithmetic produced a zero width, or the fill was drawn in a colour that cannot be seen
-- against the track behind it. This prints all three at once.
---------------------------------------------------------------------------------------------------

local function Debug()

	local line = Turbine.Shell.WriteLine

	line( "Gristle v" .. GRISTLE.Version .. " - what the client reports" )

	---------------------------------------------------------------------------------------------
	-- the raw engine answers
	---------------------------------------------------------------------------------------------
	line( "  player, straight from the API:" )

	local getters = {
		"GetMorale", "GetMaxMorale", "GetBaseMaxMorale",
		"GetTemporaryMorale", "GetMaxTemporaryMorale",
		"GetPower", "GetMaxPower", "GetBaseMaxPower",
		"GetLevel", "GetName",
	}

	for i = 1, #getters do
		line( "    " .. getters[i] .. "  ->  " .. GRISTLE.DescribeGetter( LOCALPLAYER, getters[i] ) )
	end

	---------------------------------------------------------------------------------------------
	-- the class icon, on both frames
	---------------------------------------------------------------------------------------------
	-- A missing icon is one of four things: the entity has no GetClass, it answered something that
	-- is not a class number, the number has no emblem in GRISTLE.ClassIcons, or the icon was set and
	-- is simply not on screen. Each line below rules one of them in or out.
	---------------------------------------------------------------------------------------------
	local function describeIcon( label, entity, frame )

		line( "  " .. label .. " class icon:" )

		if entity == nil then
			line( "    no entity" )
			return
		end

		line( "    GetClass   ->  " .. GRISTLE.DescribeGetter( entity, "GetClass" ) )
		line( "    GetAlignment ->  " .. GRISTLE.DescribeGetter( entity, "GetAlignment" ) )

		local class = GRISTLE.ReadClass( entity )
		line( "    read as " .. tostring( class ) .. "  ->  emblem "
			.. tostring( class ~= nil and GRISTLE.ClassIcons[ class ] or nil ) )

		if frame == nil then
			line( "    the window does not exist" )
			return
		end

		local row = frame.nameRow
		local x, y = row.icon:GetPosition()
		line( "    wanted " .. tostring( row.wantedImage ) .. ", set " .. tostring( row.iconImage )
			.. ", shown " .. tostring( row.iconShown ) .. ", visible " .. tostring( row.icon:IsVisible() ) )
		line( "    at " .. tostring( x ) .. "," .. tostring( y ) .. "  size "
			.. row.icon:GetWidth() .. " x " .. row.icon:GetHeight()
			.. "  in a window " .. frame.window:GetWidth() .. " x " .. frame.window:GetHeight() )

	end

	describeIcon( "player", LOCALPLAYER, GRISTLE.Self.window )
	describeIcon( "target", GRISTLE.Target.entity, GRISTLE.Target.window )

	---------------------------------------------------------------------------------------------
	-- what Gristle made of them
	---------------------------------------------------------------------------------------------
	local morale, maxMorale = GRISTLE.ReadVital( LOCALPLAYER, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )
	local power,  maxPower  = GRISTLE.ReadVital( LOCALPLAYER, "GetPower",  "GetMaxPower",  "GetBaseMaxPower" )

	line( "  what Gristle read:" )
	line( "    morale  " .. tostring( morale ) .. " / " .. tostring( maxMorale ) )
	line( "    power   " .. tostring( power )  .. " / " .. tostring( maxPower ) )

	---------------------------------------------------------------------------------------------
	-- what the morale bar then did with them
	---------------------------------------------------------------------------------------------
	local window = GRISTLE.Self.window

	if window == nil then
		line( "  the player window does not exist" )
		return
	end

	local bar = window.moraleBar

	line( "  the morale bar:" )
	line( "    track      " .. bar.width .. " x " .. bar.height
		.. "   visible " .. tostring( bar.track:IsVisible() ) )
	line( "    fill       " .. bar.fill:GetWidth() .. " wide"
		.. "   visible " .. tostring( bar.fill:IsVisible() ) )
	line( "    fill z     " .. tostring( bar.fill:GetZOrder() )
		.. ", clip z " .. tostring( bar.clip:GetZOrder() )
		.. ", track z " .. tostring( bar.track:GetZOrder() ) )
	line( "    fill color " .. GRISTLE.DescribeColor( bar.fill:GetBackColor() ) )
	line( "    track color " .. GRISTLE.DescribeColor( bar.track:GetBackColor() ) )

	if bar.valueLabel ~= nil then
		-- both the template and what it rendered to: a blank readout is either an empty template or a
		-- template whose every tag came back empty, and those look identical on screen
		line( "    left  '" .. tostring( GRISTLE.Settings.selfFormatBarLeft ) .. "'  ->  '"
			.. tostring( bar.valueLabel:GetText() ) .. "'" )
		line( "    right '" .. tostring( GRISTLE.Settings.selfFormatBarRight ) .. "'  ->  '"
			.. tostring( bar.pctLabel:GetText() ) .. "'" )
		line( "    text color  " .. GRISTLE.DescribeColor( bar.valueLabel:GetForeColor() ) )
		line( "    labels z    " .. tostring( bar.labelBack:GetZOrder() )
			.. "   visible " .. tostring( bar.labelBack:IsVisible() ) )
	else
		line( "    the bar was built with no labels" )
	end

	---------------------------------------------------------------------------------------------
	-- the name row
	---------------------------------------------------------------------------------------------
	local row = window.nameRow

	line( "  the name row:" )
	line( "    shown      " .. tostring( window.showName )
		.. "   window visible " .. tostring( row.clip:IsVisible() ) )
	line( "    main  '" .. tostring( GRISTLE.Settings.selfFormatNameMain ) .. "'  ->  '"
		.. tostring( row.nameLabel:GetText() ) .. "'" )
	line( "    aside '" .. tostring( GRISTLE.Settings.selfFormatNameAside ) .. "'  ->  '"
		.. tostring( row.extraLabel:GetText() ) .. "'" )
	line( "    size       " .. row.width .. " x " .. row.height
		.. "   clip " .. row.clip:GetWidth() .. " x " .. row.clip:GetHeight() )

	---------------------------------------------------------------------------------------------
	-- the context every template above was rendered against
	---------------------------------------------------------------------------------------------
	local context = window.context

	line( "  the render context:" )
	line( "    cur " .. tostring( context.cur ) .. "  max " .. tostring( context.max )
		.. "  temp " .. tostring( context.temp ) .. "  maxtemp " .. tostring( context.maxtemp ) )
	line( "    pow " .. tostring( context.pow ) .. "  maxpow " .. tostring( context.maxpow )
		.. "  name '" .. tostring( context.name ) .. "'  level " .. tostring( context.level ) )

	line( "  settings: abbreviateNumbers " .. tostring( GRISTLE.Settings.abbreviateNumbers )
		.. ", opacity " .. tostring( GRISTLE.Settings.opacity ) )
	line( "  window: " .. window.window:GetWidth() .. " x " .. window.window:GetHeight()
		.. "  visible " .. tostring( window.window:IsVisible() )
		.. "  opacity " .. tostring( window.window:GetOpacity() ) )

end

function command:Execute( cmd, args )

	-- the argument string arrives raw, so "/gristle  move " has to reach the same branch as "/gristle move"
	local name = string.lower( string.match( args or "", "^%s*(%S*)" ) or "" )

	if name == "move" then

		GRISTLE.SetMoveMode( not MOVE )
		Turbine.Shell.WriteLine( "Gristle: drag mode " .. ( MOVE and "on" or "off" ) )

	elseif name == "self" then

		GRISTLE.Settings.selfVisible = not GRISTLE.Settings.selfVisible
		GRISTLE.Save()
		GRISTLE.Self.window:SetShown( true )
		Turbine.Shell.WriteLine( "Gristle: player bars " .. ( GRISTLE.Settings.selfVisible and "shown" or "hidden" ) )

	elseif name == "target" then

		GRISTLE.Settings.targetVisible = not GRISTLE.Settings.targetVisible
		GRISTLE.Save()
		GRISTLE.Target.window:SetShown( GRISTLE.Target.entity ~= nil )
		Turbine.Shell.WriteLine( "Gristle: target bars " .. ( GRISTLE.Settings.targetVisible and "shown" or "hidden" ) )

	elseif name == "format" or name == "formats" then

		Formats()

	elseif name == "debug" then

		-- never allowed to throw: this is the tool for when something is already wrong
		local ok, err = pcall( Debug )

		if not ok then
			Turbine.Shell.WriteLine( "Gristle: debug failed - " .. tostring( err ) )
		end

	elseif name == "reset" then

		GRISTLE.ResetSettings()
		Turbine.Shell.WriteLine( "Gristle: settings reset" )

	else
		Usage()
	end

end

function command:GetHelp()
	return "Gristle -- /gristle for the command list"
end

-- a reload can leave the previous registration pointing at a script state that no longer exists, so
-- AddCommand is allowed to fail. Losing the command is survivable; throwing out of Main.lua is not.
for _, name in ipairs( { "gristle" } ) do
	local ok, err = pcall( Turbine.Shell.AddCommand, name, command )
	if not ok then
		Turbine.Shell.WriteLine( "Gristle: /" .. name .. " unavailable (" .. tostring( err ) .. ")" )
	end
end

---------------------------------------------------------------------------------------------------
-- shutdown
---------------------------------------------------------------------------------------------------
-- the windows and the fade driver are top level, so nothing else tears them down. Without this they
-- survive a /plugins refresh as orphans: bars parked on screen, a driver still asking for an Update
-- every frame, and vital handlers still attached to LocalPlayer.
---------------------------------------------------------------------------------------------------

if plugin ~= nil then
	plugin.Unload = function()

		GRISTLE.Self.Dispose()
		GRISTLE.Target.Dispose()
		GRISTLE.Updater.Dispose()

		pcall( Turbine.Shell.RemoveCommand, command )

	end
end

Turbine.Shell.WriteLine( "Gristle v" .. GRISTLE.Version .. " loaded. /gristle for options." )
