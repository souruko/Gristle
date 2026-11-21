---------------------------------------------------------------------------------------------------
-- Sinew - replacement morale and power bars for the player and the current target
---------------------------------------------------------------------------------------------------
-- Sinew only draws the bars. Hiding the stock frames is the job of a companion UI skin, which lives
-- in <Documents>/The Lord of the Rings Online/ui/skins/ and is selected under Options -> UI
-- Settings. Which skin that is has changed more than once -- NoVitals, then EffectsOnly, now
-- BlankVitals -- so read that folder's README rather than trusting a name written down here.
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

-- load order is explicit and fragile: Constants declares the SINEW namespace everything else hangs
-- off, Utils is used by every module below it, and Bar needs the Updater to exist before it can
-- register a fade.
import "Sinew.Constants"
import "Sinew.Utils"
import "Sinew.Format"
import "Sinew.Updater"
import "Sinew.Bar"
import "Sinew.NameRow"
import "Sinew.VitalWindow"
import "Sinew.SelfWindow"
import "Sinew.TargetWindow"
import "Sinew.OptionsPanel"

---------------------------------------------------------------------------------------------------
-- persistence
---------------------------------------------------------------------------------------------------

local SAVE_KEY = "sinewSettings"

local euroClient = SINEW.IsEuroClient()

local function WriteScope( scope, data )

	if euroClient then
		data = SINEW.ConvertToEuro( data )
	end

	Turbine.PluginData.Save( scope, SAVE_KEY, data )

end

local function LoadScope( scope )

	local data = Turbine.PluginData.Load( scope, SAVE_KEY )

	if data ~= nil and euroClient then
		data = SINEW.ConvertFromEuro( data )
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

function SINEW.Save()

	local data = SINEW.DeepCopy( SINEW.Settings )

	WriteScope( Turbine.DataScope.Character, data )

	if mirrorToGlobal then
		WriteScope( Turbine.DataScope.Account, data )
		globalCache = data
	end

end

function SINEW.HasGlobalSettings()
	return globalCache ~= nil
end

function SINEW.SaveGlobalSettings()

	local data = SINEW.DeepCopy( SINEW.Settings )

	WriteScope( Turbine.DataScope.Account, data )
	globalCache = data

	return true

end

function SINEW.LoadGlobalSettings()

	if globalCache == nil then
		return false
	end

	SINEW.Settings = SINEW.DeepCopy( globalCache )

	SINEW.NormaliseSettings()
	SINEW.Save()
	SINEW.ApplyAll()

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
		return SINEW.DeepCopy( fallback )
	end

	return {
		R = clamp( value.R, 0, 1, fallback.R ),
		G = clamp( value.G, 0, 1, fallback.G ),
		B = clamp( value.B, 0, 1, fallback.B ),
	}

end

function SINEW.NormaliseSettings()

	local settings = SINEW.Settings

	-- read before the defaults are filled in, or a savefile with no version at all looks current
	local from = tonumber( settings.version ) or 0

	for key, value in pairs( SINEW.Defaults ) do
		if settings[ key ] == nil then
			-- copied, not aliased: the defaults table holds the shared palette tables, and handing a
			-- live reference to the settings would let the options panel edit SINEW.Palette itself
			settings[ key ] = SINEW.DeepCopy( value )
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
	settings.selfWidth         = clamp( settings.selfWidth,         40, 1200, SINEW.Defaults.selfWidth )
	settings.selfBarHeight     = clamp( settings.selfBarHeight,      6,  160, SINEW.Defaults.selfBarHeight )
	settings.selfPowerHeight   = clamp( settings.selfPowerHeight,    1,   60, SINEW.Defaults.selfPowerHeight )
	settings.selfGap           = clamp( settings.selfGap,            0,   40, SINEW.Defaults.selfGap )

	settings.targetWidth       = clamp( settings.targetWidth,       40, 1200, SINEW.Defaults.targetWidth )
	settings.targetBarHeight   = clamp( settings.targetBarHeight,    6,  160, SINEW.Defaults.targetBarHeight )
	settings.targetPowerHeight = clamp( settings.targetPowerHeight,  1,   60, SINEW.Defaults.targetPowerHeight )
	settings.targetGap         = clamp( settings.targetGap,          0,   40, SINEW.Defaults.targetGap )

	-- positions are ratios of the screen
	settings.selfLeft   = clamp( settings.selfLeft,   0, 1, SINEW.Defaults.selfLeft )
	settings.selfTop    = clamp( settings.selfTop,    0, 1, SINEW.Defaults.selfTop )
	settings.targetLeft = clamp( settings.targetLeft, 0, 1, SINEW.Defaults.targetLeft )
	settings.targetTop  = clamp( settings.targetTop,  0, 1, SINEW.Defaults.targetTop )

	-- text
	settings.fontSize        = clamp( settings.fontSize,        8, 23, SINEW.Defaults.fontSize )
	settings.percentFontSize = clamp( settings.percentFontSize, 8, 23, SINEW.Defaults.percentFontSize )
	settings.nameFontSize    = clamp( settings.nameFontSize,    8, 23, SINEW.Defaults.nameFontSize )

	-- readout templates. An empty one is valid and means "nothing in this slot", so these are
	-- coerced and capped rather than defaulted: falling back on a blank would silently undo the one
	-- way of switching a readout off.
	for _, key in ipairs( {
		"selfFormatBarLeft",   "selfFormatBarRight",   "selfFormatNameMain",   "selfFormatNameAside",
		"targetFormatBarLeft", "targetFormatBarRight", "targetFormatNameMain", "targetFormatNameAside",
	} ) do
		settings[ key ] = clampFormat( settings[ key ], SINEW.Defaults[ key ] )
	end

	-- behaviour
	settings.flashDuration = clamp( settings.flashDuration, 0.05, 2.0,  SINEW.Defaults.flashDuration )
	settings.warnPercent   = clamp( settings.warnPercent,      2,  99,  SINEW.Defaults.warnPercent )
	settings.dangerPercent = clamp( settings.dangerPercent,    1,  98,  SINEW.Defaults.dangerPercent )

	-- floored at 0.05 rather than 0: a HUD turned all the way down is invisible, and the panel that
	-- would turn it back up is reached through a window you can no longer see
	settings.opacity       = clamp( settings.opacity,       0.05, 1.0,  SINEW.Defaults.opacity )

	-- danger has to be the tighter of the two or the warn band can never be reached
	if settings.dangerPercent >= settings.warnPercent then
		settings.dangerPercent = math.max( 1, settings.warnPercent - 1 )
	end

	-- colours
	settings.colorTrack        = clampColor( settings.colorTrack,        SINEW.Palette.track )
	settings.colorBorder       = clampColor( settings.colorBorder,       SINEW.Palette.border )
	settings.colorMorale       = clampColor( settings.colorMorale,       SINEW.Palette.morale )
	settings.colorMoraleWarn   = clampColor( settings.colorMoraleWarn,   SINEW.Palette.moraleWarn )
	settings.colorMoraleDanger = clampColor( settings.colorMoraleDanger, SINEW.Palette.moraleDanger )
	settings.colorPower        = clampColor( settings.colorPower,        SINEW.Palette.power )
	settings.colorTemp         = clampColor( settings.colorTemp,         SINEW.Palette.temp )
	settings.colorFlash        = clampColor( settings.colorFlash,        SINEW.Palette.flash )
	settings.colorText         = clampColor( settings.colorText,         SINEW.Palette.text )
	settings.colorName         = clampColor( settings.colorName,         SINEW.Palette.name )

	settings.version = 4

end

function SINEW.ResetSettings()

	SINEW.Settings = {}
	SINEW.NormaliseSettings()
	SINEW.Save()
	SINEW.ApplyAll()

end

---------------------------------------------------------------------------------------------------
-- push settings into the live windows
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- reposition both windows without rebuilding them
-- ApplyLayout clears every bar's dirty-flag cache, which blanks the bars until the next vital
-- event. A move must not pay that, so turning the mirror on or dragging a window goes through here.
---------------------------------------------------------------------------------------------------
function SINEW.ApplyPositions()

	if SINEW.Self.window   ~= nil then SINEW.Self.window:ApplyPosition()   end
	if SINEW.Target.window ~= nil then SINEW.Target.window:ApplyPosition() end

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
function SINEW.ApplyFormats()

	if SINEW.Self.window   ~= nil then SINEW.Self.window:RenderText()   end
	if SINEW.Target.window ~= nil then SINEW.Target.window:RenderText() end

end

function SINEW.ApplyAll()

	local windows = { SINEW.Self.window, SINEW.Target.window }

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
	SINEW.Self.Refresh()
	SINEW.Target.Refresh()

	if SINEW.Self.window ~= nil then
		SINEW.Self.window:SetShown( true )
	end

	-- in move mode the target window stays up with nothing targeted, or changing a setting from the
	-- options panel would take away the thing you were about to drag
	if SINEW.Target.window ~= nil then
		if MOVE then
			SINEW.Target.window:ForceShown()
		else
			SINEW.Target.window:SetShown( SINEW.Target.entity ~= nil )
		end
	end

end

function SINEW.SetMoveMode( enabled )

	MOVE = enabled and true or false

	if SINEW.Self.window   ~= nil then SINEW.Self.window:ApplyMove()   end
	if SINEW.Target.window ~= nil then SINEW.Target.window:ApplyMove() end

	-- the target window is normally hidden without a target, which in move mode would leave nothing
	-- to grab, so it is forced visible for as long as the handles are up
	if SINEW.Target.window ~= nil then
		if MOVE then
			SINEW.Target.window:ForceShown()
		else
			SINEW.Target.window:SetShown( SINEW.Target.entity ~= nil )
		end
	end

end

---------------------------------------------------------------------------------------------------
-- start up
---------------------------------------------------------------------------------------------------

SINEW.Settings = LoadScope( Turbine.DataScope.Character )

if SINEW.Settings == nil then
	-- no character file yet: inherit the account copy if there is one, so a new character starts
	-- where the last one left off
	SINEW.Settings = globalCache ~= nil and SINEW.DeepCopy( globalCache ) or {}
end

SINEW.NormaliseSettings()

SINEW.Self.Create()
SINEW.Target.Create()

-- wired after both exist, because the target window does not exist while the player one is built.
-- This is the only coupling between the two: dragging the player frame has to carry its mirror.
SINEW.Self.window.mirrorFollower = SINEW.Target.window

-- the target's position depends on the player's once mirroring is on, and the player window was
-- laid out before the target existed to be mirrored
SINEW.ApplyPositions()

---------------------------------------------------------------------------------------------------
-- options panel
---------------------------------------------------------------------------------------------------

local optionsPanel = SINEW.CreateOptionsPanel()

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
	Turbine.Shell.WriteLine( "Sinew v" .. SINEW.Version )
	Turbine.Shell.WriteLine( "  /sinew move    - toggle drag mode for both bars" )
	Turbine.Shell.WriteLine( "  /sinew self    - show or hide the player bars" )
	Turbine.Shell.WriteLine( "  /sinew target  - show or hide the target bars" )
	Turbine.Shell.WriteLine( "  /sinew format  - list the tags a readout can contain" )
	Turbine.Shell.WriteLine( "  /sinew debug   - print what the client reports for your vitals" )
	Turbine.Shell.WriteLine( "  /sinew reset   - restore every setting to its default" )
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

	line( "Sinew readouts - four per frame, each one a line of text with tags in it." )
	line( "Set them in the options panel. Clear one to drop that readout entirely." )

	line( "  tags:" )

	for i = 1, #SINEW.Format.Help do
		local entry = SINEW.Format.Help[i]
		line( "    " .. entry[1] .. string.rep( " ", math.max( 1, 11 - string.len( entry[1] ) ) )
			.. "- " .. entry[2] )
	end

	line( "  modifiers:" )

	for i = 1, #SINEW.Format.Modifiers do
		local entry = SINEW.Format.Modifiers[i]
		line( "    " .. entry[1] .. "  - " .. entry[2] )
	end

	line( "  a tag with nothing to say renders as nothing, and a line whose every tag came back" )
	line( "  empty is dropped - which is why 'Level [level]' prints nothing at all for a chest." )

	line( "  yours now:" )

	line( "    player bar   '" .. tostring( SINEW.Settings.selfFormatBarLeft ) .. "'  /  '"
		.. tostring( SINEW.Settings.selfFormatBarRight ) .. "'" )
	line( "    player name  '" .. tostring( SINEW.Settings.selfFormatNameMain ) .. "'  /  '"
		.. tostring( SINEW.Settings.selfFormatNameAside ) .. "'" )
	line( "    target bar   '" .. tostring( SINEW.Settings.targetFormatBarLeft ) .. "'  /  '"
		.. tostring( SINEW.Settings.targetFormatBarRight ) .. "'" )
	line( "    target name  '" .. tostring( SINEW.Settings.targetFormatNameMain ) .. "'  /  '"
		.. tostring( SINEW.Settings.targetFormatNameAside ) .. "'" )

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

	line( "Sinew v" .. SINEW.Version .. " - what the client reports" )

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
		line( "    " .. getters[i] .. "  ->  " .. SINEW.DescribeGetter( LOCALPLAYER, getters[i] ) )
	end

	---------------------------------------------------------------------------------------------
	-- what Sinew made of them
	---------------------------------------------------------------------------------------------
	local morale, maxMorale = SINEW.ReadVital( LOCALPLAYER, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )
	local power,  maxPower  = SINEW.ReadVital( LOCALPLAYER, "GetPower",  "GetMaxPower",  "GetBaseMaxPower" )

	line( "  what Sinew read:" )
	line( "    morale  " .. tostring( morale ) .. " / " .. tostring( maxMorale ) )
	line( "    power   " .. tostring( power )  .. " / " .. tostring( maxPower ) )

	---------------------------------------------------------------------------------------------
	-- what the morale bar then did with them
	---------------------------------------------------------------------------------------------
	local window = SINEW.Self.window

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
	line( "    fill color " .. SINEW.DescribeColor( bar.fill:GetBackColor() ) )
	line( "    track color " .. SINEW.DescribeColor( bar.track:GetBackColor() ) )

	if bar.valueLabel ~= nil then
		-- both the template and what it rendered to: a blank readout is either an empty template or a
		-- template whose every tag came back empty, and those look identical on screen
		line( "    left  '" .. tostring( SINEW.Settings.selfFormatBarLeft ) .. "'  ->  '"
			.. tostring( bar.valueLabel:GetText() ) .. "'" )
		line( "    right '" .. tostring( SINEW.Settings.selfFormatBarRight ) .. "'  ->  '"
			.. tostring( bar.pctLabel:GetText() ) .. "'" )
		line( "    text color  " .. SINEW.DescribeColor( bar.valueLabel:GetForeColor() ) )
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
	line( "    main  '" .. tostring( SINEW.Settings.selfFormatNameMain ) .. "'  ->  '"
		.. tostring( row.nameLabel:GetText() ) .. "'" )
	line( "    aside '" .. tostring( SINEW.Settings.selfFormatNameAside ) .. "'  ->  '"
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

	line( "  settings: abbreviateNumbers " .. tostring( SINEW.Settings.abbreviateNumbers )
		.. ", opacity " .. tostring( SINEW.Settings.opacity ) )
	line( "  window: " .. window.window:GetWidth() .. " x " .. window.window:GetHeight()
		.. "  visible " .. tostring( window.window:IsVisible() )
		.. "  opacity " .. tostring( window.window:GetOpacity() ) )

end

function command:Execute( cmd, args )

	-- the argument string arrives raw, so "/sinew  move " has to reach the same branch as "/sinew move"
	local name = string.lower( string.match( args or "", "^%s*(%S*)" ) or "" )

	if name == "move" then

		SINEW.SetMoveMode( not MOVE )
		Turbine.Shell.WriteLine( "Sinew: drag mode " .. ( MOVE and "on" or "off" ) )

	elseif name == "self" then

		SINEW.Settings.selfVisible = not SINEW.Settings.selfVisible
		SINEW.Save()
		SINEW.Self.window:SetShown( true )
		Turbine.Shell.WriteLine( "Sinew: player bars " .. ( SINEW.Settings.selfVisible and "shown" or "hidden" ) )

	elseif name == "target" then

		SINEW.Settings.targetVisible = not SINEW.Settings.targetVisible
		SINEW.Save()
		SINEW.Target.window:SetShown( SINEW.Target.entity ~= nil )
		Turbine.Shell.WriteLine( "Sinew: target bars " .. ( SINEW.Settings.targetVisible and "shown" or "hidden" ) )

	elseif name == "format" or name == "formats" then

		Formats()

	elseif name == "debug" then

		-- never allowed to throw: this is the tool for when something is already wrong
		local ok, err = pcall( Debug )

		if not ok then
			Turbine.Shell.WriteLine( "Sinew: debug failed - " .. tostring( err ) )
		end

	elseif name == "reset" then

		SINEW.ResetSettings()
		Turbine.Shell.WriteLine( "Sinew: settings reset" )

	else
		Usage()
	end

end

function command:GetHelp()
	return "Sinew -- /sinew for the command list"
end

-- a reload can leave the previous registration pointing at a script state that no longer exists, so
-- AddCommand is allowed to fail. Losing the command is survivable; throwing out of Main.lua is not.
for _, name in ipairs( { "sinew" } ) do
	local ok, err = pcall( Turbine.Shell.AddCommand, name, command )
	if not ok then
		Turbine.Shell.WriteLine( "Sinew: /" .. name .. " unavailable (" .. tostring( err ) .. ")" )
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

		SINEW.Self.Dispose()
		SINEW.Target.Dispose()
		SINEW.Updater.Dispose()

		pcall( Turbine.Shell.RemoveCommand, command )

	end
end

Turbine.Shell.WriteLine( "Sinew v" .. SINEW.Version .. " loaded. /sinew for options." )
