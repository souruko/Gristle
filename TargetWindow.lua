---------------------------------------------------------------------------------------------------
-- Sinew - the current target's bars
---------------------------------------------------------------------------------------------------
-- Same window as the player's, but the entity it describes changes constantly, so the vital events
-- have to be detached from the old target and attached to the new one on every TargetChanged.
--
-- Not everything targetable is an Actor. Chests, doors, crafting stations and quest objects have no
-- GetMorale at all, so the bar is hidden for them rather than erroring. Entity kinds, duck-typed the
-- way Potato does it:
--
--   no GetLevel      -> an object   ( no vitals )
--   no GetAlignment  -> an NPC or monster
--   both             -> a player
---------------------------------------------------------------------------------------------------

SINEW.Target = {}

local VITAL_EVENTS = {
	"MoraleChanged",
	"MaxMoraleChanged",
	"BaseMaxMoraleChanged",
	"TemporaryMoraleChanged",
	"MaxTemporaryMoraleChanged",
	"PowerChanged",
	"MaxPowerChanged",
	"BaseMaxPowerChanged",
}

-- kept apart from the vitals so the name row is not re-rendered thirty times a second during a
-- fight. These two fire at most once per target.
local INFO_EVENTS = {
	"NameChanged",
	"LevelChanged",
}

SINEW.Target.entity = nil

---------------------------------------------------------------------------------------------------

function SINEW.Target.RefreshName()

	local window = SINEW.Target.window
	local entity = SINEW.Target.entity

	if window == nil or entity == nil then return end

	window:SetName( SINEW.ReadName( entity ), SINEW.ReadLevel( entity ) )

end

-- returns true once the morale actually read, which is what tells a pending retry to stop
function SINEW.Target.Refresh()

	local window = SINEW.Target.window
	local entity = SINEW.Target.entity

	if window == nil or entity == nil then return false end

	local morale, maxMorale = SINEW.ReadVital( entity, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

	if morale == nil then
		-- Nothing to report: an object, something that has not finished loading, or a target that
		-- stopped answering (died, despawned, went out of range). Leaving the last known value on
		-- screen would be a lie, so the bar and the readout go - but the frame and the name stay,
		-- because you still have that thing selected and that is worth seeing. The retry started by
		-- Attach is what decides whether the numbers are coming.
		window:SetVitalsShown( false )
		window:SetShown( true )
		return false
	end

	window:SetVitalsShown( true )

	local temp, maxTemp = SINEW.ReadVital( entity, "GetTemporaryMorale", "GetMaxTemporaryMorale" )

	window:SetMorale( morale, maxMorale, temp or 0, maxTemp or 0 )

	-- passed through even when it is nil. Plenty of monsters report no power at all, and the window
	-- has to hide the hairline for them rather than leave the last target's reading on screen.
	local power, maxPower = SINEW.ReadVital( entity, "GetPower", "GetMaxPower", "GetBaseMaxPower" )

	window:SetPower( power, maxPower )

	window:SetShown( true )

	return true

end

---------------------------------------------------------------------------------------------------
-- read the target, and keep trying for a few seconds if it was not ready
---------------------------------------------------------------------------------------------------
-- The engine hands out the entity before its data arrives, so the first read after a target change
-- regularly comes back empty. Without this the bar stays blank until that target's morale happens
-- to change, which for anything you are not fighting is never.
---------------------------------------------------------------------------------------------------
function SINEW.Target.RefreshPersistently()

	if SINEW.Target.Refresh() then
		SINEW.Updater.StopRetry( "target" )
		return true
	end

	SINEW.Updater.Retry( "target", function()
		-- the retry outlives the target that started it, so it has to stop when the target changes
		-- rather than resurrect a window describing something you are no longer looking at
		if SINEW.Target.entity == nil then
			return true
		end
		SINEW.Target.RefreshName()
		return SINEW.Target.Refresh()
	end )

	return false

end

---------------------------------------------------------------------------------------------------
-- target swap
---------------------------------------------------------------------------------------------------

function SINEW.Target.Attach( entity )

	local window = SINEW.Target.window
	if window == nil then return end

	-- detach from whoever we were watching, or the old target keeps driving our handler
	if SINEW.Target.entity ~= nil then
		SINEW.RemoveCallbacks( SINEW.Target.entity, VITAL_EVENTS, SINEW.Target.OnVital )
		SINEW.RemoveCallbacks( SINEW.Target.entity, INFO_EVENTS,  SINEW.Target.OnInfo )
	end

	SINEW.Target.entity = nil

	-- whatever was pending belonged to the previous target
	SINEW.Updater.StopRetry( "target" )

	-- clear the caches before anything new arrives, so the first update after a swap cannot be
	-- mistaken for incoming damage and flash
	window:Reset()

	-- nothing selected is the only case that takes the frame off screen
	if entity == nil then
		window:SetEntity( nil )
		window:SetShown( false )
		return
	end

	SINEW.Target.entity = entity

	window:SetEntity( entity )

	-- everything targetable has a name, including the chests and doors that have no vitals, so the
	-- name is tracked whatever this turns out to be
	SINEW.AddCallbacks( entity, INFO_EVENTS, SINEW.Target.OnInfo )

	-- read here rather than in Refresh: Refresh runs on every morale event, and re-reading a name
	-- that only changes when the target does would cost two calls a frame for nothing
	SINEW.Target.RefreshName()

	-- a test of what the entity is, not of what it currently reports: a mob whose data has not
	-- arrived yet still has to be subscribed to, or nothing is listening when it does arrive
	if SINEW.HasVitals( entity ) then

		SINEW.AddCallbacks( entity, VITAL_EVENTS, SINEW.Target.OnVital )

		SINEW.Target.RefreshPersistently()

	else

		-- an object: the frame and its name, over an empty background. There is nothing to wait for
		-- here, so no retry is started.
		window:SetVitalsShown( false )
		window:SetShown( true )

	end

end

---------------------------------------------------------------------------------------------------
-- build and subscribe
---------------------------------------------------------------------------------------------------

function SINEW.Target.Create()

	SINEW.Target.window = SINEW.VitalWindow.New( {
		keys = {
			left        = "targetLeft",
			top         = "targetTop",
			width       = "targetWidth",
			barHeight   = "targetBarHeight",
			powerHeight = "targetPowerHeight",
			gap         = "targetGap",
			showPower   = "targetShowPower",
			showName    = "targetShowName",
			visible     = "targetVisible",

			formatBarLeft   = "targetFormatBarLeft",
			formatBarRight  = "targetFormatBarRight",
			formatNameMain  = "targetFormatNameMain",
			formatNameAside = "targetFormatNameAside",
		},
		-- the player window is the only thing this one can mirror
		mirrorKeys = {
			left = "selfLeft",
			top  = "selfTop",
		},
		-- the mirror image of the player frame: the name, the level and both of the morale bar's
		-- readouts all read inward from the right rather than the left
		alignRight = true,
		showLabels = true,
		threshold  = true,
		allowFlash = true,
		allowTemp  = true,
	} )

	SINEW.Target.OnVital = function( sender, args )
		SINEW.Target.Refresh()
	end

	SINEW.Target.OnInfo = function( sender, args )
		SINEW.Target.RefreshName()
	end

	SINEW.Target.OnTargetChanged = function( sender, args )
		SINEW.Target.Attach( LOCALPLAYER:GetTarget() )
	end

	-- appended rather than assigned. Worth knowing: Gibberish3 assigns LocalPlayer.TargetChanged
	-- directly, which overwrites the slot instead of appending to it. If Sinew loads first its
	-- handler is dropped; loading Sinew after Gibberish3 appends to the existing chain and both work.
	SINEW.AddCallback( LOCALPLAYER, "TargetChanged", SINEW.Target.OnTargetChanged )

	SINEW.Target.window:ApplyOpacity()

	-- pick up whatever is already targeted, so a reload mid-fight does not leave the bar blank
	SINEW.Target.Attach( LOCALPLAYER:GetTarget() )

end

function SINEW.Target.Dispose()

	if SINEW.Target.window == nil then return end

	SINEW.Updater.StopRetry( "target" )

	if SINEW.Target.entity ~= nil then
		SINEW.RemoveCallbacks( SINEW.Target.entity, VITAL_EVENTS, SINEW.Target.OnVital )
		SINEW.RemoveCallbacks( SINEW.Target.entity, INFO_EVENTS,  SINEW.Target.OnInfo )
		SINEW.Target.entity = nil
	end

	SINEW.RemoveCallback( LOCALPLAYER, "TargetChanged", SINEW.Target.OnTargetChanged )

	SINEW.Target.window:Dispose()
	SINEW.Target.window = nil

end
