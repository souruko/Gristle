---------------------------------------------------------------------------------------------------
-- Sinew - the bar widget
---------------------------------------------------------------------------------------------------
-- One widget serves every bar in the plugin: the player's morale, the player's power hairline, the
-- target's morale. Differences are options, not subclasses.
--
-- Structure, and why:
--
--   frame      Control   the painted border. A rectangle one pixel bigger on every side than the
--                        track, drawn underneath it - cheaper and sharper than four edge controls.
--   track      Control   the deficit: what morale you are missing. Always full width.
--   clip       Window    a Turbine.UI.Window clips its children. This is the load-bearing trick:
--                        the fill, the bubble and the flash segments all live inside it, so none of
--                        them can bleed past the end of the track however the maths comes out.
--     fill     Control   the current value. Driven by SetWidth only, never repositioned.
--     temp     Control   temporary morale ("bubble"), parked at the right-hand end.
--     flash[]  Control   the chunk just lost, faded out by the Updater. A small pool, so two hits
--                        landing together each get their own segment.
--   labelBack  Window    inset so text never touches the border, and clips rather than wraps.
--     value    Label     the left-hand readout.
--     percent  Label     the right-hand readout.
--
-- The two labels are named for what they held before the readouts became templates - the absolute
-- number and the percentage - and keep those names because that is still what they default to. What
-- either one actually says is now whatever its template renders to; see Format.lua.
--
-- Both Windows are parented to the root window rather than nested inside the Controls, because a
-- Window inside a Control does not reliably draw above its siblings. Same arrangement as
-- Gibberish3's BAR element.
---------------------------------------------------------------------------------------------------

SINEW.Bar = {}

local BAND_NORMAL = 1
local BAND_WARN   = 2
local BAND_DANGER = 3

---------------------------------------------------------------------------------------------------
-- options:
--   showLabels    draw the two readout labels               ( default false )
--   threshold     recolour as the value drops               ( default false )
--   allowFlash    show the incoming-damage flash            ( default false )
--   allowTemp     reserve room for temporary morale         ( default false )
--   color         palette key for the fill when in band 1   ( required )
--   zBase         z-order band, so stacked bars cannot interleave
--   formatKeys    { left, right } settings keys naming this bar's two templates
--   context       the owning window's render context, shared with its name row
--   alignRight    read the first readout inward from the right-hand end, the second from the left
---------------------------------------------------------------------------------------------------
function SINEW.Bar.New( root, options )

	local bar = {}

	bar.root       = root
	bar.showLabels = options.showLabels or false
	bar.threshold  = options.threshold or false
	bar.allowFlash = options.allowFlash or false
	bar.allowTemp  = options.allowTemp or false
	bar.colorKey   = options.color
	bar.zBase      = options.zBase or 10

	-- the context is held by reference and mutated in place by the window, so it is always current
	-- without the bar having to be handed it again
	bar.formatKeys = options.formatKeys or {}
	bar.context    = options.context or {}

	-- fixed per frame rather than configurable, the same way the name row above is. The two readouts
	-- flip with the name, so the whole frame reads inward from one end: the player's from the left
	-- and the target's from the right.
	bar.alignRight = options.alignRight and true or false

	bar.x, bar.y, bar.width, bar.height = 0, 0, 1, 1

	-- dirty-flag caches. At 30+ updates a second most calls ask for a width or a string the control
	-- already has, and a redundant setter is not free.
	bar._lastFillWidth = nil
	bar._lastTempWidth = nil
	bar._lastTempLeft  = nil
	bar._lastValueText = nil
	bar._lastPctText   = nil
	bar._lastMax       = nil
	bar._lastBarWidth  = nil
	bar._band          = nil

	---------------------------------------------------------------------------------------------------
	-- build
	---------------------------------------------------------------------------------------------------

	bar.frame = SINEW.Rect( root )
	bar.track = SINEW.Rect( root )

	bar.clip = SINEW.ClipWindow( root )
	bar.fill = SINEW.Rect( bar.clip )

	if bar.allowTemp then
		bar.temp = SINEW.Rect( bar.clip )
		bar.temp:SetVisible( false )
	end

	bar.flashes = {}

	if bar.allowFlash then
		for i = 1, SINEW.FlashPool do
			local control = SINEW.Rect( bar.clip )
			control:SetVisible( false )
			bar.flashes[i] = { control = control, start = 0, duration = 0.35 }
		end
	end

	if bar.showLabels then

		bar.labelBack = SINEW.ClipWindow( root )

		-- created with an alignment rather than left to default to one, because the two labels share
		-- a clipping window and are both full width: if they read from the same end, the longer one
		-- is drawn straight through the shorter
		bar.valueLabel = SINEW.Label( bar.labelBack, Turbine.UI.ContentAlignment.MiddleLeft )
		bar.pctLabel   = SINEW.Label( bar.labelBack, Turbine.UI.ContentAlignment.MiddleRight )

	end

	---------------------------------------------------------------------------------------------------
	-- draw order
	---------------------------------------------------------------------------------------------------

	function bar:ApplyZOrder()

		local z = self.zBase

		SINEW.ForceZOrder( self.frame, z + 1 )
		SINEW.ForceZOrder( self.track, z + 2 )
		SINEW.ForceZOrder( self.clip,  z + 3 )

		SINEW.ForceZOrder( self.fill, 1 )

		if self.temp ~= nil then
			SINEW.ForceZOrder( self.temp, 2 )
		end

		for i = 1, #self.flashes do
			SINEW.ForceZOrder( self.flashes[i].control, 3 )
		end

		if self.labelBack ~= nil then
			SINEW.ForceZOrder( self.labelBack, z + 4 )
			SINEW.ForceZOrder( self.valueLabel, 1 )
			SINEW.ForceZOrder( self.pctLabel, 2 )
		end

	end

	---------------------------------------------------------------------------------------------------
	-- colours and fonts, re-read from settings on every apply so the options panel is live
	---------------------------------------------------------------------------------------------------

	function bar:ApplyColors()

		local settings = SINEW.Settings

		self.frame:SetBackColor( SINEW.Color( settings.colorBorder ) )
		self.track:SetBackColor( SINEW.Color( settings.colorTrack ) )

		if self.temp ~= nil then
			self.temp:SetBackColor( SINEW.Color( settings.colorTemp ) )
		end

		for i = 1, #self.flashes do
			self.flashes[i].control:SetBackColor( SINEW.Color( settings.colorFlash ) )
		end

		if self.valueLabel ~= nil then
			self.valueLabel:SetForeColor( SINEW.Color( settings.colorText ) )
			self.pctLabel:SetForeColor( SINEW.Color( settings.colorText ) )
		end

		-- forces the fill colour to be re-applied on the next update
		self._band = nil

	end

	function bar:ApplyFonts()

		if self.valueLabel == nil then return end

		local settings = SINEW.Settings

		self.valueLabel:SetFont( SINEW.ResolveFont( settings.fontSize, settings.boldValue ) )
		self.pctLabel:SetFont( SINEW.ResolveFont( settings.percentFontSize, false ) )

	end

	---------------------------------------------------------------------------------------------------
	-- which end each readout reads inward from, decided once by the frame that owns this bar
	---------------------------------------------------------------------------------------------------
	-- Mirrors the name row above it. The player frame reads left to right and the target frame right
	-- to left, so the pair reads as a reflection - which is what they look like once the target is
	-- mirrored across the screen, and reads correctly even when it is not.
	--
	-- Restated rather than left to the constructor, so a relayout cannot lose it.
	---------------------------------------------------------------------------------------------------
	function bar:ApplyAlignment()

		if self.valueLabel == nil then return end

		local alignment = Turbine.UI.ContentAlignment

		if self.alignRight then
			self.valueLabel:SetTextAlignment( alignment.MiddleRight )
			self.pctLabel:SetTextAlignment( alignment.MiddleLeft )
		else
			self.valueLabel:SetTextAlignment( alignment.MiddleLeft )
			self.pctLabel:SetTextAlignment( alignment.MiddleRight )
		end

	end

	-- the fill colour for a band, read from settings
	function bar:BandColor( band )

		local settings = SINEW.Settings

		if not self.threshold then
			return SINEW.Color( settings[ self.colorKey ] )
		end

		if band == BAND_DANGER then
			return SINEW.Color( settings.colorMoraleDanger )
		elseif band == BAND_WARN then
			return SINEW.Color( settings.colorMoraleWarn )
		end

		return SINEW.Color( settings[ self.colorKey ] )

	end

	---------------------------------------------------------------------------------------------------
	-- geometry
	---------------------------------------------------------------------------------------------------

	function bar:Layout( x, y, width, height )

		local border = SINEW.Settings.showBorder and SINEW.Border or 0

		self.x, self.y = x, y
		self.width  = math.max( 1, math.floor( width ) )
		self.height = math.max( 1, math.floor( height ) )

		self.frame:SetPosition( x, y )
		self.frame:SetSize( self.width + 2 * border, self.height + 2 * border )

		self.track:SetPosition( x + border, y + border )
		self.track:SetSize( self.width, self.height )

		self.clip:SetPosition( x + border, y + border )
		self.clip:SetSize( self.width, self.height )

		-- this zeroes the fill behind the dirty flag's back, so the cache has to go too or the next
		-- update can decide it has nothing to do and leave the bar empty
		self.fill:SetPosition( 0, 0 )
		self.fill:SetSize( 0, self.height )
		self._lastFillWidth = nil
		self._lastBarWidth  = nil

		if self.temp ~= nil then
			self.temp:SetPosition( self.width, 0 )
			self.temp:SetSize( 0, self.height )
			self._lastTempWidth = nil
			self._lastTempLeft  = nil
		end

		for i = 1, #self.flashes do
			SINEW.Updater.StopFade( self.flashes[i] )
			self.flashes[i].control:SetSize( 0, self.height )
		end

		if self.labelBack ~= nil then

			local labelWidth = math.max( 1, self.width - 2 * SINEW.LabelPadding )

			self.labelBack:SetPosition( x + border + SINEW.LabelPadding, y + border )
			self.labelBack:SetSize( labelWidth, self.height )

			self.valueLabel:SetPosition( 0, 0 )
			self.valueLabel:SetSize( labelWidth, self.height )

			self.pctLabel:SetPosition( 0, 0 )
			self.pctLabel:SetSize( labelWidth, self.height )

			self._lastValueText = nil
			self._lastPctText   = nil

		end

		self:ApplyZOrder()

		-- re-stated after every layout: the border appears and disappears with the border setting,
		-- and the clipping windows the fill and the readout live in are created hidden by the engine
		self:ApplyVisibility()

	end

	-- full outer size this bar occupies, so the owning window can size itself
	function bar:OuterSize()
		local border = SINEW.Settings.showBorder and SINEW.Border or 0
		return self.width + 2 * border, self.height + 2 * border
	end

	---------------------------------------------------------------------------------------------------
	-- visibility, in two independent parts
	---------------------------------------------------------------------------------------------------
	--   visible   the bar as a whole: border, background and data
	--   blank     the background only, with no fill, no bubble, no flash and no readout
	--
	-- Blank is what a target with no morale gets - a chest, a door, a crafting station. The frame
	-- and its name stay on screen so you can see what you have selected; there is simply nothing to
	-- report inside it. Keeping the two flags apart matters because a blanked bar must come back
	-- the moment you target something with vitals again, without a relayout.
	---------------------------------------------------------------------------------------------------

	bar._visible = true
	bar._blank   = false

	function bar:ApplyVisibility()

		local border = SINEW.Settings.showBorder and SINEW.Border or 0

		-- the background: the painted border and the empty track behind the fill
		self.frame:SetVisible( self._visible and border > 0 )
		self.track:SetVisible( self._visible )

		-- the data: everything that describes a value
		local data = self._visible and not self._blank

		self.clip:SetVisible( data )

		if self.labelBack ~= nil then
			self.labelBack:SetVisible( data )
		end

		if not data then
			for i = 1, #self.flashes do
				SINEW.Updater.StopFade( self.flashes[i] )
			end
		end

	end

	function bar:SetVisible( visible )
		self._visible = visible and true or false
		self:ApplyVisibility()
	end

	function bar:SetBlank( blank )

		local wanted = blank and true or false

		if wanted == self._blank then return end

		self._blank = wanted

		-- the caches describe a bar that is no longer on screen, and leaving them would let the
		-- first real reading after a blank period be mistaken for damage
		if wanted then
			self:Reset()
		end

		self:ApplyVisibility()

	end

	---------------------------------------------------------------------------------------------------
	-- clear every cache and every fading segment
	-- called when the bar starts describing a different entity, so the first update after a target
	-- change cannot be mistaken for incoming damage
	---------------------------------------------------------------------------------------------------
	function bar:Reset()

		self._lastFillWidth = nil
		self._lastTempWidth = nil
		self._lastTempLeft  = nil
		self._lastValueText = nil
		self._lastPctText   = nil
		self._lastMax       = nil
		self._lastBarWidth  = nil
		self._band          = nil

		for i = 1, #self.flashes do
			SINEW.Updater.StopFade( self.flashes[i] )
		end

		self.fill:SetWidth( 0 )

		if self.temp ~= nil then
			self.temp:SetVisible( false )
		end

		-- emptied rather than left for the next render. The window clears its context in the same
		-- breath, but a readout still holding the last target's morale over the new one's bar is the
		-- exact lie this is here to prevent, and the next render may be a while coming.
		if self.showLabels then

			self._lastValueText = ""
			self._lastPctText   = ""

			self.valueLabel:SetText( "" )
			self.pctLabel:SetText( "" )

		end

	end

	---------------------------------------------------------------------------------------------------
	-- claim a flash segment
	-- prefer a free one; if all four are mid-fade, take over the one that started earliest, since it
	-- is the closest to invisible anyway
	---------------------------------------------------------------------------------------------------
	function bar:ClaimFlash()

		local oldest, oldestStart = nil, nil

		for i = 1, #self.flashes do

			local record = self.flashes[i]

			if not record.control:IsVisible() then
				return record
			end

			if oldestStart == nil or record.start < oldestStart then
				oldest, oldestStart = record, record.start
			end

		end

		return oldest

	end

	---------------------------------------------------------------------------------------------------
	-- the single entry point
	--
	-- current / max    the vital itself
	-- temp / maxTemp   temporary morale, nil or 0 when there is none
	---------------------------------------------------------------------------------------------------
	function bar:SetVital( current, max, temp, maxTemp )

		if current == nil or max == nil or max <= 0 then
			return
		end

		local settings = SINEW.Settings

		if current < 0 then current = 0 end
		if current > max then current = max end

		temp    = temp or 0
		maxTemp = maxTemp or 0

		-----------------------------------------------------------------------------------------------
		-- how much of the track the real morale gets
		--
		-- a bubble takes a proportional slice off the right-hand end and the morale fill shrinks into
		-- what is left, the way VitalTarget did it. The share is capped at half the bar though: a
		-- bubble bigger than max morale would otherwise leave no readable morale bar at all.
		-----------------------------------------------------------------------------------------------

		local barWidth = self.width

		if self.allowTemp and maxTemp > 0 then
			local share = maxTemp / max
			if share > 0.5 then share = 0.5 end
			barWidth = math.floor( self.width * ( 1 - share ) )
			if barWidth < 1 then barWidth = 1 end
		end

		-----------------------------------------------------------------------------------------------
		-- fill
		-----------------------------------------------------------------------------------------------

		local fillWidth = math.floor( current / max * barWidth )

		-- a drop in fill width only means damage if the scale did not move underneath it. A max
		-- morale change or a bubble appearing both shrink the fill without anything having been hit.
		local sameScale = ( self._lastMax == max ) and ( self._lastBarWidth == barWidth )

		if self.allowFlash
			and settings.flash
			and sameScale
			and self._lastFillWidth ~= nil
			and fillWidth < self._lastFillWidth then

			local record = self:ClaimFlash()

			if record ~= nil then
				record.duration = settings.flashDuration or 0.35
				record.control:SetPosition( fillWidth, 0 )
				record.control:SetSize( self._lastFillWidth - fillWidth, self.height )
				SINEW.Updater.StartFade( record )
			end

		end

		if fillWidth ~= self._lastFillWidth then
			self._lastFillWidth = fillWidth
			self.fill:SetWidth( fillWidth )
		end

		self._lastMax      = max
		self._lastBarWidth = barWidth

		-----------------------------------------------------------------------------------------------
		-- threshold colour, applied once on entering a band rather than on every update
		-----------------------------------------------------------------------------------------------

		local band = BAND_NORMAL

		if self.threshold then

			local percent = 100 * current / max

			if percent <= ( settings.dangerPercent or 25 ) then
				band = BAND_DANGER
			elseif percent <= ( settings.warnPercent or 50 ) then
				band = BAND_WARN
			end

		end

		if band ~= self._band then
			self._band = band
			self.fill:SetBackColor( self:BandColor( band ) )
		end

		-----------------------------------------------------------------------------------------------
		-- bubble
		-----------------------------------------------------------------------------------------------

		if self.temp ~= nil then

			if maxTemp > 0 and temp > 0 then

				local tempWidth = math.floor( ( self.width - barWidth ) * ( temp / maxTemp ) )

				if barWidth ~= self._lastTempLeft then
					self._lastTempLeft = barWidth
					self.temp:SetPosition( barWidth, 0 )
				end

				if tempWidth ~= self._lastTempWidth then
					self._lastTempWidth = tempWidth
					self.temp:SetSize( tempWidth, self.height )
				end

				self.temp:SetVisible( true )

			else
				self.temp:SetVisible( false )
				self._lastTempWidth = nil
				self._lastTempLeft  = nil
			end

		end

	end

	---------------------------------------------------------------------------------------------------
	-- the readouts
	---------------------------------------------------------------------------------------------------
	-- Driven by the window rather than by SetVital, because a template is allowed to name something
	-- this bar does not carry: the morale bar's left-hand readout can show power, and the power
	-- hairline is four pixels tall and has no labels of its own to show it in. The window updates one
	-- context from every source it has and then asks everything to re-render.
	--
	-- Guarded by the rendered string, so SetText is not called thirty times a second with the text
	-- that is already on screen. That guard is why re-rendering on every vital event is cheap enough
	-- to do unconditionally: a render is a gsub over a short string, not an engine call.
	---------------------------------------------------------------------------------------------------
	function bar:RenderLabels()

		if not self.showLabels then return end

		local leftText  = SINEW.Format.Render( SINEW.Settings[ self.formatKeys.left ],  self.context )
		local rightText = SINEW.Format.Render( SINEW.Settings[ self.formatKeys.right ], self.context )

		if leftText ~= self._lastValueText then
			self._lastValueText = leftText
			self.valueLabel:SetText( leftText )
		end

		if rightText ~= self._lastPctText then
			self._lastPctText = rightText
			self.pctLabel:SetText( rightText )
		end

	end

	---------------------------------------------------------------------------------------------------

	bar:ApplyColors()
	bar:ApplyFonts()
	bar:ApplyAlignment()

	return bar

end
