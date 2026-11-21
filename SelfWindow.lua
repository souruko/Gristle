---------------------------------------------------------------------------------------------------
-- Sinew - the player's own bars
---------------------------------------------------------------------------------------------------
-- Entirely event-driven. The engine fires a *Changed event for every vital that moves, so there is
-- nothing to poll; the only per-frame work in the plugin is the damage flash fade.
--
-- Note that mounted combat is not covered: while on a war-steed the relevant vitals live on
-- CombatMount rather than on the player, which is a separate entity with its own events.
---------------------------------------------------------------------------------------------------

SINEW.Self = {}

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
function SINEW.Self.RefreshMorale()

	local window = SINEW.Self.window
	if window == nil then return false end

	local morale, maxMorale = SINEW.ReadVital( LOCALPLAYER, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

	if morale == nil then
		return false
	end

	-- nil when there is no bubble at all, which SetVital reads as "no temporary morale"
	local temp, maxTemp = SINEW.ReadVital( LOCALPLAYER, "GetTemporaryMorale", "GetMaxTemporaryMorale" )

	window:SetMorale( morale, maxMorale, temp or 0, maxTemp or 0 )

	return true

end

function SINEW.Self.RefreshPower()

	local window = SINEW.Self.window
	if window == nil then return false end

	local power, maxPower = SINEW.ReadVital( LOCALPLAYER, "GetPower", "GetMaxPower", "GetBaseMaxPower" )

	if power == nil then
		return false
	end

	window:SetPower( power, maxPower )

	return true

end

function SINEW.Self.RefreshName()

	local window = SINEW.Self.window
	if window == nil then return end

	window:SetName( SINEW.ReadName( LOCALPLAYER ), SINEW.ReadLevel( LOCALPLAYER ) )

end

-- true only when every vital read, which is what tells a pending retry it can stop
function SINEW.Self.Refresh()

	SINEW.Self.RefreshName()

	-- both are called, not short-circuited: power must still be drawn on a tick where morale failed
	local morale = SINEW.Self.RefreshMorale()
	local power  = SINEW.Self.RefreshPower()

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
function SINEW.Self.RefreshPersistently()

	if SINEW.Self.Refresh() then
		SINEW.Updater.StopRetry( "self" )
		return true
	end

	SINEW.Updater.Retry( "self", SINEW.Self.Refresh )

	return false

end

---------------------------------------------------------------------------------------------------
-- build and subscribe
---------------------------------------------------------------------------------------------------

function SINEW.Self.Create()

	SINEW.Self.window = SINEW.VitalWindow.New( {
		keys = {
			left        = "selfLeft",
			top         = "selfTop",
			width       = "selfWidth",
			barHeight   = "selfBarHeight",
			powerHeight = "selfPowerHeight",
			gap         = "selfGap",
			showPower   = "selfShowPower",
			showName    = "selfShowName",
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
	SINEW.Self.OnMorale = function( sender, args )
		SINEW.Self.RefreshMorale()
	end

	SINEW.Self.OnPower = function( sender, args )
		SINEW.Self.RefreshPower()
	end

	SINEW.Self.OnInfo = function( sender, args )
		SINEW.Self.RefreshName()
	end

	-- appended rather than assigned: LocalPlayer is shared with every other loaded plugin, and a
	-- direct assignment would silently drop whatever was already listening
	SINEW.AddCallbacks( LOCALPLAYER, MORALE_EVENTS, SINEW.Self.OnMorale )
	SINEW.AddCallbacks( LOCALPLAYER, POWER_EVENTS,  SINEW.Self.OnPower )
	SINEW.AddCallbacks( LOCALPLAYER, INFO_EVENTS,   SINEW.Self.OnInfo )

	-- nothing subscribes to InCombatChanged any more. It existed only to swap between an in-combat
	-- and an out-of-combat opacity, and the opacity is now one fixed value.

	SINEW.Self.window:SetShown( true )
	SINEW.Self.window:ApplyOpacity()

	-- the player is the entity the plugin describes, so the window binds to them once and never
	-- rebinds; only the target window swaps entities
	SINEW.Self.window:SetEntity( LOCALPLAYER )

	SINEW.Self.RefreshPersistently()

end

function SINEW.Self.Dispose()

	if SINEW.Self.window == nil then return end

	SINEW.RemoveCallbacks( LOCALPLAYER, MORALE_EVENTS, SINEW.Self.OnMorale )
	SINEW.RemoveCallbacks( LOCALPLAYER, POWER_EVENTS,  SINEW.Self.OnPower )
	SINEW.RemoveCallbacks( LOCALPLAYER, INFO_EVENTS,   SINEW.Self.OnInfo )

	SINEW.Updater.StopRetry( "self" )

	-- dropped before the target window is torn down, so a drag handler can never reach a disposed
	-- mirror through it
	SINEW.Self.window.mirrorFollower = nil

	SINEW.Self.window:Dispose()
	SINEW.Self.window = nil

end
