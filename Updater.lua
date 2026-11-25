---------------------------------------------------------------------------------------------------
-- Gristle - the one and only per-frame updater
---------------------------------------------------------------------------------------------------
-- Everything in Gristle is event-driven except the damage flash, which has to fade. Rather than give
-- each flash segment its own Update, one control drives all of them on a fixed interval and turns
-- itself off the moment nothing is fading. Idle cost is then genuinely zero.
--
-- Pattern taken from Gibberish3/UI_ELEMENTS/WINDOWS/Functions.lua; the 1x1 visible top-level window
-- as the update host is MouseFinder's driver.
---------------------------------------------------------------------------------------------------

GRISTLE.Updater = {}

local INTERVAL = 0.033   -- ~30 Hz; enough steps for a 0.35 s fade to read as smooth

local fading = {}        -- set of records currently fading: record -> true
local lastUpdate = 0

---------------------------------------------------------------------------------------------------
-- deferred re-reads
---------------------------------------------------------------------------------------------------
-- A vital is not always readable the moment you ask for it. The engine hands out an entity before
-- its data has arrived, so GetMorale / GetMaxMorale can answer 0 or throw for the first fraction of
-- a second after a target change - and on the player, for the first fraction of a second after the
-- plugin loads.
--
-- An event-driven plugin cannot shrug that off. If the first read fails, nothing redraws the bar
-- until the vital next *changes*, and a player standing at full morale out of combat never fires
-- one. That is how the morale bar ended up empty while the power hairline beside it was full.
--
-- So a failed read schedules itself to be tried again. The callback returns true once it has
-- something, and the retry stops; otherwise it gives up after a few seconds rather than polling
-- forever, because "this entity genuinely has no morale" has to terminate too.
---------------------------------------------------------------------------------------------------

local RETRY_INTERVAL = 0.25
local RETRY_ATTEMPTS = 12     -- 3 seconds, which is far longer than the engine has ever needed

local retries = {}            -- key -> { callback, attempts, dueAt }

local driver = Turbine.UI.Window()
driver:SetSize( 1, 1 )
driver:SetPosition( 0, 0 )
driver:SetMouseVisible( false )
driver:SetVisible( true )
driver:SetWantsUpdates( false )

---------------------------------------------------------------------------------------------------
-- a record is { control = <Control>, start = <gameTime>, duration = <seconds> }
-- the caller owns the control and the record; the updater only drives the opacity
---------------------------------------------------------------------------------------------------
function GRISTLE.Updater.StartFade( record )

	if record == nil or record.control == nil then
		return
	end

	record.start = Turbine.Engine.GetGameTime()

	record.control:SetVisible( true )
	GRISTLE.ForceOpacity( record.control, 1 )

	fading[ record ] = true

	driver:SetWantsUpdates( true )

end

function GRISTLE.Updater.StopFade( record )

	if record == nil then return end

	fading[ record ] = nil

	if record.control ~= nil then
		record.control:SetVisible( false )
	end

end

---------------------------------------------------------------------------------------------------
-- keep calling callback until it returns true, or until the attempts run out
-- keyed, so re-targeting twice in a second replaces the pending retry instead of stacking them up
---------------------------------------------------------------------------------------------------
function GRISTLE.Updater.Retry( key, callback )

	if key == nil or callback == nil then return end

	retries[ key ] = {
		callback = callback,
		attempts = RETRY_ATTEMPTS,
		dueAt    = Turbine.Engine.GetGameTime() + RETRY_INTERVAL,
	}

	driver:SetWantsUpdates( true )

end

function GRISTLE.Updater.StopRetry( key )
	if key ~= nil then
		retries[ key ] = nil
	end
end

function GRISTLE.Updater.Clear()

	for record in pairs( fading ) do
		if record.control ~= nil then
			record.control:SetVisible( false )
		end
	end

	fading = {}
	retries = {}
	driver:SetWantsUpdates( false )

end

function driver:Update()

	local gameTime = Turbine.Engine.GetGameTime()

	if gameTime - lastUpdate < INTERVAL then
		return
	end

	lastUpdate = gameTime

	-- snapshot before iterating: finishing a fade mutates the set
	local records = {}
	for record in pairs( fading ) do
		records[ #records + 1 ] = record
	end

	for i = 1, #records do

		local record = records[i]
		local duration = record.duration or 0.35
		local elapsed = gameTime - ( record.start or gameTime )

		if duration <= 0 or elapsed >= duration then
			GRISTLE.Updater.StopFade( record )
		else
			-- linear would look like it stops abruptly; squaring front-loads the fade so the hit
			-- registers hard and then gets out of the way
			local remaining = 1 - ( elapsed / duration )
			GRISTLE.ForceOpacity( record.control, remaining * remaining )
		end

	end

	-----------------------------------------------------------------------------------------------
	-- deferred re-reads
	-----------------------------------------------------------------------------------------------
	-- snapshotted for the same reason as the fades: a callback is allowed to schedule or cancel a
	-- retry, including its own

	local keys = {}
	for key in pairs( retries ) do
		keys[ #keys + 1 ] = key
	end

	for i = 1, #keys do

		local record = retries[ keys[i] ]

		if record ~= nil and gameTime >= record.dueAt then

			record.attempts = record.attempts - 1

			-- a throwing callback must not take the driver down with it, and must not retry forever
			local ok, done = pcall( record.callback )

			if not ok or done or record.attempts <= 0 then
				retries[ keys[i] ] = nil
			else
				record.dueAt = gameTime + RETRY_INTERVAL
			end

		end

	end

	if next( fading ) == nil and next( retries ) == nil then
		driver:SetWantsUpdates( false )
	end

end

---------------------------------------------------------------------------------------------------
-- teardown; without this the driver survives a /plugins refresh as an orphan still asking for an
-- Update every frame
---------------------------------------------------------------------------------------------------
function GRISTLE.Updater.Dispose()

	GRISTLE.Updater.Clear()

	driver:SetVisible( false )
	driver:SetParent( nil )

end
