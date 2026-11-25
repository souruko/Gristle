---------------------------------------------------------------------------------------------------
-- Gristle - the current target's bars
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

GRISTLE.Target = {}

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

GRISTLE.Target.entity = nil

---------------------------------------------------------------------------------------------------

function GRISTLE.Target.RefreshName()

	local window = GRISTLE.Target.window
	local entity = GRISTLE.Target.entity

	if window == nil or entity == nil then return end

	window:SetName( GRISTLE.ReadName( entity ), GRISTLE.ReadLevel( entity ), GRISTLE.ReadClass( entity ) )

end

-- returns true once the morale actually read, which is what tells a pending retry to stop
function GRISTLE.Target.Refresh()

	local window = GRISTLE.Target.window
	local entity = GRISTLE.Target.entity

	if window == nil or entity == nil then return false end

	local morale, maxMorale = GRISTLE.ReadVital( entity, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

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

	-- A player target's class can arrive after the entity does, like its vitals, and unlike its
	-- name nothing fires when it does. So while a player target is still showing no icon, every
	-- vital event asks again. Only while it is missing, and only for an entity that has GetClass
	-- at all: once it is found, or for a monster, this costs one table lookup.
	if GRISTLE.Target.ClassPending() then
		GRISTLE.Target.RefreshName()
	end

	local temp, maxTemp = GRISTLE.ReadVital( entity, "GetTemporaryMorale", "GetMaxTemporaryMorale" )

	window:SetMorale( morale, maxMorale, temp or 0, maxTemp or 0 )

	-- passed through even when it is nil. Plenty of monsters report no power at all, and the window
	-- has to hide the hairline for them rather than leave the last target's reading on screen.
	local power, maxPower = GRISTLE.ReadVital( entity, "GetPower", "GetMaxPower", "GetBaseMaxPower" )

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
-- true while the target is a player whose class has not come through yet. A monster has no
-- GetClass and is never pending; a class with no emblem in the table counts as come through, since
-- asking again will not change the answer.
function GRISTLE.Target.ClassPending()

	local window = GRISTLE.Target.window
	local entity = GRISTLE.Target.entity

	if window == nil or entity == nil or entity.GetClass == nil then
		return false
	end

	return GRISTLE.ReadClass( entity ) == nil

end

function GRISTLE.Target.RefreshPersistently()

	-- done only once the vitals have read AND the class has, so a player target standing still at
	-- full morale - which fires no events at all - still gets its icon when the class arrives
	if GRISTLE.Target.Refresh() and not GRISTLE.Target.ClassPending() then
		GRISTLE.Updater.StopRetry( "target" )
		return true
	end

	GRISTLE.Updater.Retry( "target", function()
		-- the retry outlives the target that started it, so it has to stop when the target changes
		-- rather than resurrect a window describing something you are no longer looking at
		if GRISTLE.Target.entity == nil then
			return true
		end
		GRISTLE.Target.RefreshName()
		return GRISTLE.Target.Refresh() and not GRISTLE.Target.ClassPending()
	end )

	return false

end

---------------------------------------------------------------------------------------------------
-- target swap
---------------------------------------------------------------------------------------------------

function GRISTLE.Target.Attach( entity )

	local window = GRISTLE.Target.window
	if window == nil then return end

	-- detach from whoever we were watching, or the old target keeps driving our handler
	if GRISTLE.Target.entity ~= nil then
		GRISTLE.RemoveCallbacks( GRISTLE.Target.entity, VITAL_EVENTS, GRISTLE.Target.OnVital )
		GRISTLE.RemoveCallbacks( GRISTLE.Target.entity, INFO_EVENTS,  GRISTLE.Target.OnInfo )
	end

	GRISTLE.Target.entity = nil

	-- whatever was pending belonged to the previous target
	GRISTLE.Updater.StopRetry( "target" )

	-- clear the caches before anything new arrives, so the first update after a swap cannot be
	-- mistaken for incoming damage and flash
	window:Reset()

	-- nothing selected is the only case that takes the frame off screen
	if entity == nil then
		window:SetEntity( nil )
		window:SetShown( false )
		return
	end

	GRISTLE.Target.entity = entity

	window:SetEntity( entity )

	-- everything targetable has a name, including the chests and doors that have no vitals, so the
	-- name is tracked whatever this turns out to be
	GRISTLE.AddCallbacks( entity, INFO_EVENTS, GRISTLE.Target.OnInfo )

	-- read here rather than in Refresh: Refresh runs on every morale event, and re-reading a name
	-- that only changes when the target does would cost two calls a frame for nothing
	GRISTLE.Target.RefreshName()

	-- a test of what the entity is, not of what it currently reports: a mob whose data has not
	-- arrived yet still has to be subscribed to, or nothing is listening when it does arrive
	if GRISTLE.HasVitals( entity ) then

		GRISTLE.AddCallbacks( entity, VITAL_EVENTS, GRISTLE.Target.OnVital )

		GRISTLE.Target.RefreshPersistently()

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

function GRISTLE.Target.Create()

	GRISTLE.Target.window = GRISTLE.VitalWindow.New( {
		keys = {
			left        = "targetLeft",
			top         = "targetTop",
			width       = "targetWidth",
			barHeight   = "targetBarHeight",
			powerHeight = "targetPowerHeight",
			gap         = "targetGap",
			showPower   = "targetShowPower",
			showName    = "targetShowName",
			showClassIcon = "targetShowClassIcon",
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

	GRISTLE.Target.OnVital = function( sender, args )
		GRISTLE.Target.Refresh()
	end

	GRISTLE.Target.OnInfo = function( sender, args )
		GRISTLE.Target.RefreshName()
	end

	GRISTLE.Target.OnTargetChanged = function( sender, args )
		GRISTLE.Target.Attach( LOCALPLAYER:GetTarget() )
	end

	-- appended rather than assigned. Worth knowing: Gibberish3 assigns LocalPlayer.TargetChanged
	-- directly, which overwrites the slot instead of appending to it. If Gristle loads first its
	-- handler is dropped; loading Gristle after Gibberish3 appends to the existing chain and both work.
	GRISTLE.AddCallback( LOCALPLAYER, "TargetChanged", GRISTLE.Target.OnTargetChanged )

	GRISTLE.Target.window:ApplyOpacity()

	-- pick up whatever is already targeted, so a reload mid-fight does not leave the bar blank
	GRISTLE.Target.Attach( LOCALPLAYER:GetTarget() )

end

function GRISTLE.Target.Dispose()

	if GRISTLE.Target.window == nil then return end

	GRISTLE.Updater.StopRetry( "target" )

	if GRISTLE.Target.entity ~= nil then
		GRISTLE.RemoveCallbacks( GRISTLE.Target.entity, VITAL_EVENTS, GRISTLE.Target.OnVital )
		GRISTLE.RemoveCallbacks( GRISTLE.Target.entity, INFO_EVENTS,  GRISTLE.Target.OnInfo )
		GRISTLE.Target.entity = nil
	end

	GRISTLE.RemoveCallback( LOCALPLAYER, "TargetChanged", GRISTLE.Target.OnTargetChanged )

	GRISTLE.Target.window:Dispose()
	GRISTLE.Target.window = nil

end
