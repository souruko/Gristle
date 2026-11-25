---------------------------------------------------------------------------------------------------
-- Gristle - the bar widget
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
--     fill     Control   the current value. Driven by SetWidth, plus SetLeft on a bar that fills
--                        from the right, both behind the same dirty flag.
--     temp     Control   temporary morale ("bubble"), parked at the far end from where the fill
--                        starts.
--     flash[]  Control   the chunk just lost, faded out by the Updater. A small pool, so two hits
--                        landing together each get their own segment.
--   overlay    Window    the sheen and the threshold marks, in a layer of their own above clip.
--     highlight Control  a see-through light strip along the top of the whole track, and
--     shade     Control  a see-through dark one along the bottom. Together they fake the gradient
--                        the engine cannot draw. Full width and static, so they cost nothing per
--                        update: over the fill they read as a sheen, over the track as glass.
--     ticks[]  Control   one pixel marks at the warn and danger percentages ( morale bar only )
--
-- The overlay has to be its own Window. Inside a Window, a see-through child does not blend with
-- the sibling drawn under it - it REPLACES those pixels, alpha and all, and the blend only happens
-- when the whole Window is laid over whatever is behind it. Put in clip, the sheen punched holes
-- through the fill and showed the dark track through them: measured in game, a grey band on top
-- and a black one below, over a full amber bar. In a layer of its own, the hole it punches is in
-- an empty layer, so it blends over the finished fill exactly as intended.
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

GRISTLE.Bar = {}

local BAND_NORMAL = 1
local BAND_WARN   = 2
local BAND_DANGER = 3

-- above this, a readout over that surface turns dark. See toneFor.
GRISTLE.DarkTextLuminance = 0.65

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
--   fillFromRight the fill grows from the right-hand end, and drains towards it
---------------------------------------------------------------------------------------------------
function GRISTLE.Bar.New( root, options )

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

	-- the fill's direction, set apart from the readouts' so either can be had without the other.
	-- Everything that places a segment works in "logical" pixels measured from where the fill
	-- starts, and Span turns that into a real left edge at the setter - so the maths is written once.
	bar.fillFromRight = options.fillFromRight and true or false

	bar.x, bar.y, bar.width, bar.height = 0, 0, 1, 1

	-- the real left edge of a segment that starts `left` logical pixels in from where the fill starts
	function bar:Span( left, width )
		if self.fillFromRight then
			return self.width - left - width
		end
		return left
	end

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

	bar.frame = GRISTLE.Rect( root )
	bar.track = GRISTLE.Rect( root )

	bar.clip = GRISTLE.ClipWindow( root )
	bar.fill = GRISTLE.Rect( bar.clip )

	if bar.allowTemp then
		bar.temp = GRISTLE.Rect( bar.clip )
		bar.temp:SetVisible( false )
	end

	bar.flashes = {}

	if bar.allowFlash then
		for i = 1, GRISTLE.FlashPool do
			local control = GRISTLE.Rect( bar.clip )
			control:SetVisible( false )
			bar.flashes[i] = { control = control, start = 0, duration = 0.35 }
		end
	end

	-- every bar gets the sheen; the strips are parked until the first layout gives them a size
	bar.overlay   = GRISTLE.ClipWindow( root )
	bar.highlight = GRISTLE.Rect( bar.overlay )
	bar.shade     = GRISTLE.Rect( bar.overlay )

	-- the threshold marks only mean anything on a bar that changes colour at those thresholds
	bar.ticks = {}

	if bar.threshold then
		bar.ticks[1] = { control = GRISTLE.Rect( bar.overlay ), key = "warnPercent" }
		bar.ticks[2] = { control = GRISTLE.Rect( bar.overlay ), key = "dangerPercent" }
	end

	if bar.showLabels then

		bar.labelBack = GRISTLE.ClipWindow( root )

		-- created with an alignment rather than left to default to one, because the two labels share
		-- a clipping window and are both full width: if they read from the same end, the longer one
		-- is drawn straight through the shorter
		bar.valueLabel = GRISTLE.Label( bar.labelBack, Turbine.UI.ContentAlignment.MiddleLeft )
		bar.pctLabel   = GRISTLE.Label( bar.labelBack, Turbine.UI.ContentAlignment.MiddleRight )

	end

	---------------------------------------------------------------------------------------------------
	-- draw order
	---------------------------------------------------------------------------------------------------

	function bar:ApplyZOrder()

		local z = self.zBase

		GRISTLE.ForceZOrder( self.frame, z + 1 )
		GRISTLE.ForceZOrder( self.track, z + 2 )
		GRISTLE.ForceZOrder( self.clip,  z + 3 )

		GRISTLE.ForceZOrder( self.fill, 1 )

		if self.temp ~= nil then
			GRISTLE.ForceZOrder( self.temp, 2 )
		end

		for i = 1, #self.flashes do
			GRISTLE.ForceZOrder( self.flashes[i].control, 3 )
		end

		-- over the fill, the bubble and the flash, so all three share the same sheen; under the text
		GRISTLE.ForceZOrder( self.overlay, z + 4 )
		GRISTLE.ForceZOrder( self.highlight, 1 )
		GRISTLE.ForceZOrder( self.shade, 1 )

		for i = 1, #self.ticks do
			GRISTLE.ForceZOrder( self.ticks[i].control, 2 )
		end

		if self.labelBack ~= nil then
			GRISTLE.ForceZOrder( self.labelBack, z + 5 )
			GRISTLE.ForceZOrder( self.valueLabel, 1 )
			GRISTLE.ForceZOrder( self.pctLabel, 2 )
		end

	end

	---------------------------------------------------------------------------------------------------
	-- colours and fonts, re-read from settings on every apply so the options panel is live
	---------------------------------------------------------------------------------------------------

	function bar:ApplyColors()

		local settings = GRISTLE.Settings

		self.frame:SetBackColor( GRISTLE.Color( settings.colorBorder ) )
		self.track:SetBackColor( GRISTLE.Color( settings.colorTrack ) )

		if self.temp ~= nil then
			self.temp:SetBackColor( GRISTLE.Color( settings.colorTemp ) )
		end

		for i = 1, #self.flashes do
			self.flashes[i].control:SetBackColor( GRISTLE.Color( settings.colorFlash ) )
		end

		if self.valueLabel ~= nil then
			self.valueLabel:SetForeColor( GRISTLE.Color( settings.colorText ) )
			self.valueLabel:SetOutlineColor( Turbine.UI.Color.Black )
			self.pctLabel:SetForeColor( GRISTLE.Color( settings.colorText ) )
			self.pctLabel:SetOutlineColor( Turbine.UI.Color.Black )
		end

		-- what the labels were just set to, so the contrast check knows what is on screen
		self._valueTone = "light"
		self._pctTone   = "light"

		for i = 1, #self.ticks do
			self.ticks[i].control:SetBackColor( GRISTLE.AlphaColor( 0.45 ) )
		end

		self:ApplySheen()

		-- forces the fill colour, the contrast and the ticks to be re-applied on the next update
		self._band          = nil
		self._blendKey      = nil
		self._fillColor     = nil
		self._tickBarWidth  = nil

	end

	---------------------------------------------------------------------------------------------------
	-- the sheen: two see-through strips, sized from the bar's height and the sheen setting
	---------------------------------------------------------------------------------------------------
	-- Restated on every layout and every colour apply rather than per update, because nothing about
	-- it depends on the value. A hairline is too thin for two strips, so it gets a one pixel highlight
	-- and no shade.
	---------------------------------------------------------------------------------------------------
	function bar:ApplySheen()

		local sheen  = tonumber( GRISTLE.Settings.sheen ) or 0
		local width  = self.width
		local height = self.height

		if sheen <= 0 then
			self.highlight:SetVisible( false )
			self.shade:SetVisible( false )
			return
		end

		self.highlight:SetBackColor( GRISTLE.AlphaColor( sheen, { R = 1, G = 1, B = 1 } ) )
		self.shade:SetBackColor( GRISTLE.AlphaColor( sheen * 0.8 ) )

		if height <= 6 then

			self.highlight:SetPosition( 0, 0 )
			self.highlight:SetSize( width, 1 )
			self.highlight:SetVisible( true )
			self.shade:SetVisible( false )

		else

			local top    = math.max( 1, math.floor( height * 0.35 ) )
			local bottom = math.max( 1, math.floor( height * 0.25 ) )

			self.highlight:SetPosition( 0, 0 )
			self.highlight:SetSize( width, top )
			self.highlight:SetVisible( true )

			self.shade:SetPosition( 0, height - bottom )
			self.shade:SetSize( width, bottom )
			self.shade:SetVisible( true )

		end

	end

	---------------------------------------------------------------------------------------------------
	-- the threshold marks, placed against the width the morale actually has
	---------------------------------------------------------------------------------------------------
	-- A bubble shrinks that width, and the marks have to shrink with it or they would sit at the
	-- wrong percentage of the morale they are describing. Guarded by the width, so the setters only
	-- run when a bubble comes or goes.
	---------------------------------------------------------------------------------------------------
	function bar:PlaceTicks( barWidth )

		if #self.ticks == 0 or barWidth == self._tickBarWidth then return end

		self._tickBarWidth = barWidth

		local settings = GRISTLE.Settings

		for i = 1, #self.ticks do

			local tick = self.ticks[i]
			local x = math.floor( barWidth * ( tonumber( settings[ tick.key ] ) or 0 ) / 100 )

			tick.control:SetPosition( self:Span( x, 1 ), 0 )
			tick.control:SetSize( 1, self.height )
			tick.control:SetVisible( settings.showTicks and x > 0 and x < barWidth or false )

		end

	end

	function bar:ApplyFonts()

		if self.valueLabel == nil then return end

		local settings = GRISTLE.Settings

		-- one weight for both, so the pair reads as one readout rather than a headline and a footnote
		self.valueLabel:SetFont( GRISTLE.ResolveFont( settings.fontSize,        settings.boldValue ) )
		self.pctLabel:SetFont(   GRISTLE.ResolveFont( settings.percentFontSize, settings.boldValue ) )

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

	-- the fill colour for a band, read from settings, as a plain { R, G, B } table: the contrast
	-- check needs the numbers, and GRISTLE.Color turns it into the engine's object at the setter
	function bar:BandColorTable( band )

		local settings = GRISTLE.Settings

		if not self.threshold then
			return settings[ self.colorKey ]
		end

		if band == BAND_DANGER then
			return settings.colorMoraleDanger
		elseif band == BAND_WARN then
			return settings.colorMoraleWarn
		end

		return settings[ self.colorKey ]

	end

	function bar:BandColor( band )
		return GRISTLE.Color( self:BandColorTable( band ) )
	end

	-- the blended fill: "danger" and "warn" are flat, a whole percent above warn slides from the
	-- warn colour at the warn line up to the normal colour at full
	function bar:BlendColor( key )

		local settings = GRISTLE.Settings

		if key == "danger" then return settings.colorMoraleDanger end
		if key == "warn"   then return settings.colorMoraleWarn end

		local warn = tonumber( settings.warnPercent ) or 50

		return GRISTLE.LerpColor( settings.colorMoraleWarn, settings[ self.colorKey ],
			( key - warn ) / math.max( 1, 100 - warn ) )

	end

	---------------------------------------------------------------------------------------------------
	-- geometry
	---------------------------------------------------------------------------------------------------

	function bar:Layout( x, y, width, height )

		local border = GRISTLE.Settings.showBorder and GRISTLE.Border or 0

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
		self.fill:SetPosition( self:Span( 0, 0 ), 0 )
		self.fill:SetSize( 0, self.height )
		self._lastFillWidth = nil
		self._lastBarWidth  = nil

		if self.temp ~= nil then
			self.temp:SetPosition( self:Span( self.width, 0 ), 0 )
			self.temp:SetSize( 0, self.height )
			self._lastTempWidth = nil
			self._lastTempLeft  = nil
		end

		for i = 1, #self.flashes do
			GRISTLE.Updater.StopFade( self.flashes[i] )
			self.flashes[i].control:SetSize( 0, self.height )
		end

		self.overlay:SetPosition( x + border, y + border )
		self.overlay:SetSize( self.width, self.height )

		self:ApplySheen()

		-- placed against the full width until the first reading says whether a bubble shrinks it
		self._tickBarWidth = nil
		self:PlaceTicks( self.width )

		if self.labelBack ~= nil then

			local labelWidth = math.max( 1, self.width - 2 * GRISTLE.LabelPadding )

			self.labelBack:SetPosition( x + border + GRISTLE.LabelPadding, y + border )
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
		local border = GRISTLE.Settings.showBorder and GRISTLE.Border or 0
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

		local border = GRISTLE.Settings.showBorder and GRISTLE.Border or 0

		-- the background: the painted border and the empty track behind the fill
		self.frame:SetVisible( self._visible and border > 0 )
		self.track:SetVisible( self._visible )

		-- the data: everything that describes a value
		local data = self._visible and not self._blank

		self.clip:SetVisible( data )
		self.overlay:SetVisible( data )

		if self.labelBack ~= nil then
			self.labelBack:SetVisible( data )
		end

		if not data then
			for i = 1, #self.flashes do
				GRISTLE.Updater.StopFade( self.flashes[i] )
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
		self._blendKey      = nil

		for i = 1, #self.flashes do
			GRISTLE.Updater.StopFade( self.flashes[i] )
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

		local settings = GRISTLE.Settings

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

		self:PlaceTicks( barWidth )

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
				local lost = self._lastFillWidth - fillWidth
				record.control:SetPosition( self:Span( fillWidth, lost ), 0 )
				record.control:SetSize( lost, self.height )
				GRISTLE.Updater.StartFade( record )
			end

		end

		if fillWidth ~= self._lastFillWidth then
			self._lastFillWidth = fillWidth
			if self.fillFromRight then
				self.fill:SetLeft( self.width - fillWidth )
			end
			self.fill:SetWidth( fillWidth )
		end

		self._lastMax      = max
		self._lastBarWidth = barWidth

		-----------------------------------------------------------------------------------------------
		-- threshold colour, applied once on entering a band rather than on every update
		-----------------------------------------------------------------------------------------------

		if self.threshold and settings.colorBlend then

			-- Only the healthy half slides. Below warn the bar holds the warn colour, and danger is
			-- not faded into: it lands all at once, because a colour that creeps towards red is a
			-- colour you notice late. The danger test uses the exact share, like the hard bands, so
			-- both modes go red at the same moment.
			--
			-- The slide is quantised to a whole percent, so the colour is set at most once per point
			-- rather than on every tick of a heal-over-time; the two flat stretches share one key each.
			local exact  = 100 * current / max
			local warn   = tonumber( settings.warnPercent )   or 50
			local danger = tonumber( settings.dangerPercent ) or 25

			local key

			if exact <= danger then
				key = "danger"
			elseif exact <= warn then
				key = "warn"
			else
				key = math.floor( exact )
			end

			if key ~= self._blendKey then
				self._blendKey  = key
				self._band      = nil
				self._fillColor = self:BlendColor( key )
				self.fill:SetBackColor( GRISTLE.Color( self._fillColor ) )
			end

		else

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
				self._band      = band
				self._blendKey  = nil
				self._fillColor = self:BandColorTable( band )
				self.fill:SetBackColor( GRISTLE.Color( self._fillColor ) )
			end

		end

		-----------------------------------------------------------------------------------------------
		-- bubble
		-----------------------------------------------------------------------------------------------

		if self.temp ~= nil then

			if maxTemp > 0 and temp > 0 then

				local tempWidth = math.floor( ( self.width - barWidth ) * ( temp / maxTemp ) )

				-- from the right, the bubble's real left edge moves with its width as well as with
				-- the morale share, so either change has to re-place it
				local moved = barWidth ~= self._lastTempLeft
					or ( self.fillFromRight and tempWidth ~= self._lastTempWidth )

				if tempWidth ~= self._lastTempWidth then
					self._lastTempWidth = tempWidth
					self.temp:SetSize( tempWidth, self.height )
				end

				if moved then
					self._lastTempLeft = barWidth
					self.temp:SetPosition( self:Span( barWidth, tempWidth ), 0 )
				end

				self.temp:SetVisible( true )

			else
				self.temp:SetVisible( false )
				self._lastTempWidth = nil
				self._lastTempLeft  = nil
			end

		end

		self:ApplyContrast( fillWidth )

	end

	---------------------------------------------------------------------------------------------------
	-- readout contrast
	---------------------------------------------------------------------------------------------------
	-- Each label is judged by what is under the end it reads from: that is where its text starts, and
	-- the one part of it guaranteed to be drawn. Over a bright surface it goes dark, with its outline
	-- in the surface's own colour so the outline disappears rather than ringing the dark glyphs in
	-- black. A label that straddles the edge of the fill is judged by its anchor and accepts the rest.
	---------------------------------------------------------------------------------------------------

	-- what colour is drawn at x pixels in from the left of the track
	function bar:SurfaceAt( x, fillWidth )

		local settings = GRISTLE.Settings

		-- the caches below are all logical, measured from where the fill starts
		if self.fillFromRight then
			x = self.width - 1 - x
		end

		if x < fillWidth then
			return self._fillColor or settings[ self.colorKey ]
		end

		if self.temp ~= nil and self.temp:IsVisible() and self._lastTempLeft ~= nil then
			local left = self._lastTempLeft
			if x >= left and x < left + ( self._lastTempWidth or 0 ) then
				return settings.colorTemp
			end
		end

		return settings.colorTrack

	end

	-- "light", or "dark:" plus the surface it sits on, which is also what the outline is set to
	local function toneFor( surface )

		if not GRISTLE.Settings.textContrast or surface == nil then
			return "light", nil
		end

		-- 0.65 sits between the default green ( 0.56, white text reads fine ) and amber ( 0.76, it does not)
		if GRISTLE.Luminance( surface ) > GRISTLE.DarkTextLuminance then
			return "dark:" .. GRISTLE.ColorToHex( surface ), surface
		end

		return "light", nil

	end

	local function applyTone( label, tone, surface, text )

		local settings = GRISTLE.Settings

		if surface ~= nil then
			label:SetForeColor( GRISTLE.Color( settings.colorTextDark ) )
			label:SetOutlineColor( GRISTLE.Color( surface ) )
		else
			label:SetForeColor( GRISTLE.Color( settings.colorText ) )
			label:SetOutlineColor( Turbine.UI.Color.Black )
		end

		-- a label's colour is not guaranteed to repaint until its text is set again
		label:SetText( text or "" )

	end

	function bar:ApplyContrast( fillWidth )

		if not self.showLabels then return end

		-- a few pixels in from where each label's text starts
		local nearLeft  = GRISTLE.LabelPadding + 2
		local nearRight = self.width - GRISTLE.LabelPadding - 3

		local valueX = self.alignRight and nearRight or nearLeft
		local pctX   = self.alignRight and nearLeft  or nearRight

		local valueTone, valueSurface = toneFor( self:SurfaceAt( valueX, fillWidth ) )
		local pctTone,   pctSurface   = toneFor( self:SurfaceAt( pctX,   fillWidth ) )

		if valueTone ~= self._valueTone then
			self._valueTone = valueTone
			applyTone( self.valueLabel, valueTone, valueSurface, self._lastValueText )
		end

		if pctTone ~= self._pctTone then
			self._pctTone = pctTone
			applyTone( self.pctLabel, pctTone, pctSurface, self._lastPctText )
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

		local leftText  = GRISTLE.Format.Render( GRISTLE.Settings[ self.formatKeys.left ],  self.context )
		local rightText = GRISTLE.Format.Render( GRISTLE.Settings[ self.formatKeys.right ], self.context )

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
