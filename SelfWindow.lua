---------------------------------------------------------------------------------------------------
-- Gristle - the player's own bars
---------------------------------------------------------------------------------------------------
-- Entirely event-driven. The engine fires a *Changed event for every vital that moves, so there is
-- nothing to poll; the only per-frame work in the plugin is the damage flash fade.
--
-- Note that mounted combat is not covered: while on a war-steed the relevant vitals live on
-- CombatMount rather than on the player, which is a separate entity with its own events.
---------------------------------------------------------------------------------------------------

GRISTLE.Self = {}

local MORALE_EVENTS = {
	"MoraleChanged",
	"MaxMoraleChanged",
	"BaseMaxMoraleChanged",
	"TemporaryMoraleChanged",
	"MaxTemporaryMoraleChanged",
}

local POWER_EVENTS = {
	"PowerChanged",
	"MaxPowerChanged",
	"BaseMaxPowerChanged",
	"TemporaryPowerChanged",
	"MaxTemporaryPowerChanged",
}

-- the name row's own events. NameChanged is here not because a character gets renamed but because
-- the entity's name is not always resolved at the moment the plugin loads, and LevelChanged is what
-- makes the row correct itself the instant you ding rather than at the next reload.
local INFO_EVENTS = {
	"NameChanged",
	"LevelChanged",
}

---------------------------------------------------------------------------------------------------

-- returns true once the vital actually read, which is what tells a pending retry to stop
function GRISTLE.Self.RefreshMorale()

	local window = GRISTLE.Self.window
	if window == nil then return false end

	local morale, maxMorale = GRISTLE.ReadVital( LOCALPLAYER, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

	if morale == nil then
		return false
	end

	-- nil when there is no bubble at all, which SetVital reads as "no temporary morale"
	local temp, maxTemp = GRISTLE.ReadVital( LOCALPLAYER, "GetTemporaryMorale", "GetMaxTemporaryMorale" )

	window:SetMorale( morale, maxMorale, temp or 0, maxTemp or 0 )

	return true

end

function GRISTLE.Self.RefreshPower()

	local window = GRISTLE.Self.window
	if window == nil then return false end

	local power, maxPower = GRISTLE.ReadVital( LOCALPLAYER, "GetPower", "GetMaxPower", "GetBaseMaxPower" )

	if power == nil then
		return false
	end

	window:SetPower( power, maxPower )

	return true

end

function GRISTLE.Self.RefreshName()

	local window = GRISTLE.Self.window
	if window == nil then return end

	window:SetName( GRISTLE.ReadName( LOCALPLAYER ), GRISTLE.ReadLevel( LOCALPLAYER ), GRISTLE.ReadClass( LOCALPLAYER ) )

end

-- true only when every vital read, which is what tells a pending retry it can stop
function GRISTLE.Self.Refresh()

	GRISTLE.Self.RefreshName()

	-- both are called, not short-circuited: power must still be drawn on a tick where morale failed
	local morale = GRISTLE.Self.RefreshMorale()
	local power  = GRISTLE.Self.RefreshPower()

	return morale and power

end

---------------------------------------------------------------------------------------------------
-- read everything, and keep trying for a few seconds if any of it was not ready
---------------------------------------------------------------------------------------------------
-- This is what the empty morale bar needed. The player's vitals are not always readable the instant
-- the plugin loads, and the player is the one entity whose vitals then sit unchanged for minutes:
-- at full morale out of combat nothing fires, so a single failed read left the bar blank until
-- something finally hit you. The power hairline beside it was full the whole time, because that
-- read happened to succeed.
---------------------------------------------------------------------------------------------------
function GRISTLE.Self.RefreshPersistently()

	if GRISTLE.Self.Refresh() then
		GRISTLE.Updater.StopRetry( "self" )
		return true
	end

	GRISTLE.Updater.Retry( "self", GRISTLE.Self.Refresh )

	return false

end

---------------------------------------------------------------------------------------------------
-- build and subscribe
---------------------------------------------------------------------------------------------------

function GRISTLE.Self.Create()

	GRISTLE.Self.window = GRISTLE.VitalWindow.New( {
		keys = {
			left        = "selfLeft",
			top         = "selfTop",
			width       = "selfWidth",
			barHeight   = "selfBarHeight",
			powerHeight = "selfPowerHeight",
			gap         = "selfGap",
			showPower   = "selfShowPower",
			showName    = "selfShowName",
			showClassIcon = "selfShowClassIcon",
			visible     = "selfVisible",

			formatBarLeft   = "selfFormatBarLeft",
			formatBarRight  = "selfFormatBarRight",
			formatNameMain  = "selfFormatNameMain",
			formatNameAside = "selfFormatNameAside",
		},
		showLabels = true,
		threshold  = true,
		allowFlash = true,
		allowTemp  = true,
	} )

	-- stored on the module so the exact same function object can be handed to RemoveCallback later;
	-- an anonymous closure here could never be detached
	GRISTLE.Self.OnMorale = function( sender, args )
		GRISTLE.Self.RefreshMorale()
	end

	GRISTLE.Self.OnPower = function( sender, args )
		GRISTLE.Self.RefreshPower()
	end

	GRISTLE.Self.OnInfo = function( sender, args )
		GRISTLE.Self.RefreshName()
	end

	-- appended rather than assigned: LocalPlayer is shared with every other loaded plugin, and a
	-- direct assignment would silently drop whatever was already listening
	GRISTLE.AddCallbacks( LOCALPLAYER, MORALE_EVENTS, GRISTLE.Self.OnMorale )
	GRISTLE.AddCallbacks( LOCALPLAYER, POWER_EVENTS,  GRISTLE.Self.OnPower )
	GRISTLE.AddCallbacks( LOCALPLAYER, INFO_EVENTS,   GRISTLE.Self.OnInfo )

	-- nothing subscribes to InCombatChanged any more. It existed only to swap between an in-combat
	-- and an out-of-combat opacity, and the opacity is now one fixed value.

	GRISTLE.Self.window:SetShown( true )
	GRISTLE.Self.window:ApplyOpacity()

	-- the player is the entity the plugin describes, so the window binds to them once and never
	-- rebinds; only the target window swaps entities
	GRISTLE.Self.window:SetEntity( LOCALPLAYER )

	GRISTLE.Self.RefreshPersistently()

end

function GRISTLE.Self.Dispose()

	if GRISTLE.Self.window == nil then return end

	GRISTLE.RemoveCallbacks( LOCALPLAYER, MORALE_EVENTS, GRISTLE.Self.OnMorale )
	GRISTLE.RemoveCallbacks( LOCALPLAYER, POWER_EVENTS,  GRISTLE.Self.OnPower )
	GRISTLE.RemoveCallbacks( LOCALPLAYER, INFO_EVENTS,   GRISTLE.Self.OnInfo )

	GRISTLE.Updater.StopRetry( "self" )

	-- dropped before the target window is torn down, so a drag handler can never reach a disposed
	-- mirror through it
	GRISTLE.Self.window.mirrorFollower = nil

	GRISTLE.Self.window:Dispose()
	GRISTLE.Self.window = nil

end
