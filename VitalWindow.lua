---------------------------------------------------------------------------------------------------
-- Gristle - the window that holds a set of bars
---------------------------------------------------------------------------------------------------
-- The self window and the target window are the same object with different settings keys and
-- different data sources, so they share this. It owns:
--
--   * a frameless, click-through top level window
--   * the name row above everything
--   * the dominant morale bar
--   * the power hairline underneath it
--   * a drag handle that covers the whole window, mouse-visible only in move mode
--
-- The handle deliberately overlays the bars rather than sitting above them. Shifting the layout
-- when move mode is toggled would make the bars jump out from under the cursor mid-drag.
--
-- Rows are stacked top to bottom and the window grows to fit whichever of them are switched on.
-- The window's saved position is its top left corner, so turning the name row on pushes the bars
-- down rather than lifting the name above where they already were - which is what you want when
-- the bars are the thing you aimed at a spot on screen.
---------------------------------------------------------------------------------------------------

GRISTLE.VitalWindow = {}

---------------------------------------------------------------------------------------------------
-- options:
--   keys        settings key names for this window ( see SelfWindow / TargetWindow )
--   showLabels  draw value / percent on the morale bar
--   threshold   recolour morale as it drops
--   allowFlash  show the incoming-damage flash
--   allowTemp   reserve room for temporary morale
--   mirrorKeys  settings keys of the window this one may mirror, or nil if it never mirrors
--   alignRight  this whole frame reads inward from the right-hand end rather than the left: the
--               name, the level and both of the morale bar's readouts flip together
--               - and both bars fill from the right and drain towards it
---------------------------------------------------------------------------------------------------
function GRISTLE.VitalWindow.New( options )

	local self = {}

	self.keys = options.keys

	-- only the target window has these; the player window is always positioned by its own setting
	self.mirrorKeys = options.mirrorKeys

	-- set by Main once both windows exist: the window that has to be dragged along with this one
	-- while mirroring is on. Nothing else couples the two.
	self.mirrorFollower = nil

	self.window = Turbine.UI.Window()
	self.window:SetVisible( false )
	self.window:SetBackColor( nil )
	-- the HUD has to be click-through: without this the window eats clicks on the world behind it
	self.window:SetMouseVisible( false )

	---------------------------------------------------------------------------------------------------
	-- the entity element
	---------------------------------------------------------------------------------------------------
	-- The game's own EntityControl rather than a plain rectangle. Bound to an entity it carries the
	-- behaviour the stock vitals panels have and Lua cannot reimplement: click to target, right-click
	-- for the context menu, the entity tooltip, and being a drop target for raid assignments.
	--
	-- It is the bottom layer and covers the whole window, and everything drawn over it is
	-- mouse-invisible, so the clicks fall through to it. Same arrangement as
	-- Potato/ui/potatoTooltip.lua.
	--
	-- It is also the one thing in Gristle that is deliberately *not* click-through, which is why it
	-- can be switched off: with it on, the frames stop being holes you can click the world through.
	---------------------------------------------------------------------------------------------------

	self.entityControl = Turbine.UI.Lotro.EntityControl()
	self.entityControl:SetParent( self.window )
	self.entityControl:SetPosition( 0, 0 )
	self.entityControl:SetVisible( false )

	---------------------------------------------------------------------------------------------------
	-- the render context
	---------------------------------------------------------------------------------------------------
	-- One table describing whatever this window is showing, keyed by the tag names in Format.lua:
	-- cur, max, temp, maxtemp, pow, maxpow, name, level. Held here rather than on the widgets, and
	-- handed to both of them by reference so it is mutated in one place.
	--
	-- That is what makes a template free of where it sits: [level] works inside the morale bar and
	-- [perc] works on the name row, and - the reason it is worth the indirection - [pow] works in
	-- the morale bar, which is the only way a power number can be shown at all. The hairline is four
	-- pixels tall; there is nowhere on it to put text.
	--
	-- Every field starts absent, which every tag renders as nothing. A window that has not read its
	-- entity yet shows an empty frame rather than a zero.
	---------------------------------------------------------------------------------------------------

	self.context = { name = "" }

	-- one reading direction for the whole frame, not one per row. The name row and the bar's two
	-- readouts all take it, so the player frame reads left to right and the target frame right to
	-- left and the pair is a reflection rather than two frames that happen to be near each other.
	self.alignRight = options.alignRight and true or false

	self.nameRow = GRISTLE.NameRow.New( self.window, {
		zBase      = 50,
		alignRight = self.alignRight,
		formatKeys = { main = self.keys.formatNameMain, aside = self.keys.formatNameAside },
		iconKey    = self.keys.showClassIcon,
		context    = self.context,
	} )

	self.moraleBar = GRISTLE.Bar.New( self.window, {
		showLabels = options.showLabels,
		threshold  = options.threshold,
		allowFlash = options.allowFlash,
		allowTemp  = options.allowTemp,
		color      = "colorMorale",
		zBase      = 10,
		formatKeys = { left = self.keys.formatBarLeft, right = self.keys.formatBarRight },
		context    = self.context,
		alignRight = self.alignRight,
		fillFromRight = self.alignRight,
	} )

	self.powerBar = GRISTLE.Bar.New( self.window, {
		showLabels = false,
		threshold  = false,
		allowFlash = false,
		allowTemp  = false,
		color      = "colorPower",
		zBase      = 30,
		fillFromRight = self.alignRight,
	} )

	---------------------------------------------------------------------------------------------------
	-- drag handle
	---------------------------------------------------------------------------------------------------

	self.moveControl = Turbine.UI.Control()
	self.moveControl:SetParent( self.window )
	self.moveControl:SetPosition( 0, 0 )
	self.moveControl:SetMouseVisible( false )
	self.moveControl:SetVisible( false )

	self.moveControl.MouseDown = function( sender, args )
		if args.Button == Turbine.UI.MouseButton.Left then
			self.dragging = true
			self.dragStartX = args.X
			self.dragStartY = args.Y
		end
	end

	self.moveControl.MouseMove = function( sender, args )

		if not self.dragging then return end

		local x, y = self.window:GetPosition()

		x = x + ( args.X - self.dragStartX )
		y = y + ( args.Y - self.dragStartY )

		x, y = GRISTLE.ClampToScreen( x, y, self.window:GetWidth(), self.window:GetHeight() )

		self.window:SetPosition( x, y )

		-- the mirror follows live rather than catching up on mouse up. In move mode both windows are
		-- on screen, so a mirror that only snapped at the end would look broken for the whole drag.
		if self.mirrorFollower ~= nil and self.mirrorFollower:IsMirrored() then
			self.mirrorFollower:MirrorFrom( x, y )
		end

	end

	self.moveControl.MouseUp = function( sender, args )

		if args.Button ~= Turbine.UI.MouseButton.Left then return end

		self.dragging = false

		self:CommitPosition()

	end

	---------------------------------------------------------------------------------------------------
	-- save wherever the window currently sits
	-- shared by the drag and the fine adjustment, so both handle mirroring the same way
	---------------------------------------------------------------------------------------------------
	function self:CommitPosition()

		local left, top = self.window:GetPosition()

		-------------------------------------------------------------------------------------------------
		-- a mirror writes back to what it mirrors, rather than to its own position, which mirroring
		-- ignores. The pair stays locked together and either one can be the one you move.
		-------------------------------------------------------------------------------------------------
		if self:IsMirrored() then

			local sourceLeft = GRISTLE.MirrorLeft( left, self.window:GetWidth() )

			GRISTLE.Settings[ self.mirrorKeys.left ], GRISTLE.Settings[ self.mirrorKeys.top ] =
				GRISTLE.PixelToRatio( sourceLeft, top )

			GRISTLE.Save()

			-- the window that moved is already where it belongs; the one it mirrors is not
			GRISTLE.ApplyPositions()

			return

		end

		-- stored as a screen ratio, so changing resolution does not strand the window off-screen
		GRISTLE.Settings[ self.keys.left ], GRISTLE.Settings[ self.keys.top ] = GRISTLE.PixelToRatio( left, top )

		GRISTLE.Save()

	end

	---------------------------------------------------------------------------------------------------
	-- move by a pixel or two, for the adjustment a drag cannot make
	---------------------------------------------------------------------------------------------------
	-- A drag is quantised to wherever the mouse happened to be released, and a HUD lined up against
	-- a quickslot bar or another plugin's frame needs finer than that.
	---------------------------------------------------------------------------------------------------
	function self:Nudge( dx, dy )

		local left, top = self.window:GetPosition()
		local width, height = self.window:GetSize()

		left, top = GRISTLE.ClampToScreen( left + dx, top + dy, width, height )

		self.window:SetPosition( left, top )

		-- live, so a mirrored pair stays mirrored as it is nudged
		if self.mirrorFollower ~= nil and self.mirrorFollower:IsMirrored() then
			self.mirrorFollower:MirrorFrom( left, top )
		end

		self:CommitPosition()

	end

	---------------------------------------------------------------------------------------------------
	-- geometry
	---------------------------------------------------------------------------------------------------

	function self:ApplyLayout()

		local settings = GRISTLE.Settings
		local keys = self.keys

		local border = settings.showBorder and GRISTLE.Border or 0

		local width       = math.max( 20, math.floor( settings[ keys.width ] or 260 ) )
		local barHeight   = math.max( 4,  math.floor( settings[ keys.barHeight ] or 34 ) )
		local powerHeight = math.max( 1,  math.floor( settings[ keys.powerHeight ] or 4 ) )
		-- one gap setting spaces every stacked row: name to morale, and morale to power. Two separate
		-- knobs for the same visual rhythm would only ever be set to the same number.
		local gap         = math.max( 0,  math.floor( settings[ keys.gap ] or 2 ) )
		local showPower   = settings[ keys.showPower ] and true or false
		local showName    = settings[ keys.showName ] and true or false

		local top = 0

		if showName then
			local nameHeight = GRISTLE.NameRowHeight( keys.showClassIcon )
			self.nameRow:Layout( 0, 0, width, nameHeight )
			top = nameHeight + gap
		end

		self.nameRow:SetVisible( showName )
		self.showName = showName

		self.moraleBar:Layout( 0, top, width, barHeight )

		-- stated rather than assumed. The morale bar is always shown, but "always shown" used to mean
		-- "never told to be", which left its clipping windows at whatever the engine built them as -
		-- and the engine builds a Window hidden.
		self.moraleBar:SetVisible( true )

		local totalHeight = top + barHeight + 2 * border

		if showPower then
			-- at gap 0 the two bars share one border line rather than stacking two: the power bar's
			-- top edge is laid over the morale bar's bottom edge. Same colour, and neither frame
			-- reaches the other's track, so whichever paints last makes no difference.
			local powerTop = ( gap == 0 ) and ( totalHeight - border ) or ( totalHeight + gap )
			self.powerBar:Layout( 0, powerTop, width, powerHeight )
			totalHeight = powerTop + powerHeight + 2 * border
		end

		self.powerBar:SetVisible( showPower )
		self.showPower = showPower

		-- a fresh layout starts out assuming the entity has power; SetPower takes it away again the
		-- moment it turns out not to
		self.powerShown = showPower

		local totalWidth = width + 2 * border

		self.window:SetSize( totalWidth, totalHeight )

		self.moveControl:SetSize( totalWidth, totalHeight )

		-- covers the whole frame, so anywhere on the bars is clickable
		self.entityControl:SetSize( totalWidth, totalHeight )
		self:ApplyEntity()

		-- above everything. The bars give themselves explicit z-orders in Layout, which would
		-- otherwise bury the handle created before them and leave nothing to grab.
		GRISTLE.ForceZOrder( self.moveControl, 1000 )

		-- on every layout, not just on load: making the bar wider can push it off the screen edge,
		-- and a mirrored window's position depends on its own width
		self:ApplyPosition()

	end

	---------------------------------------------------------------------------------------------------
	-- is this window currently a mirror of another?
	---------------------------------------------------------------------------------------------------
	function self:IsMirrored()
		return self.mirrorKeys ~= nil and GRISTLE.Settings.mirrorTarget and true or false
	end

	---------------------------------------------------------------------------------------------------
	-- position only - no bar is touched, so this is what a move goes through. ApplyLayout has to
	-- rebuild the bars and clears every dirty-flag cache doing it, which would blank the bars until
	-- the next vital event; a drag must not pay that.
	---------------------------------------------------------------------------------------------------
	function self:ApplyPosition()

		local settings = GRISTLE.Settings
		local keys = self.keys

		local width, height = self.window:GetSize()

		local left, top

		if self:IsMirrored() then
			local sourceLeft, sourceTop = GRISTLE.RatioToPixel(
				settings[ self.mirrorKeys.left ] or 0.4, settings[ self.mirrorKeys.top ] or 0.5 )
			left, top = GRISTLE.MirrorLeft( sourceLeft, width ), sourceTop
		else
			left, top = GRISTLE.RatioToPixel( settings[ keys.left ] or 0.4, settings[ keys.top ] or 0.5 )
		end

		left, top = GRISTLE.ClampToScreen( left, top, width, height )

		self.window:SetPosition( left, top )

	end

	---------------------------------------------------------------------------------------------------
	-- place this window as the mirror of a source sitting at a given pixel position
	-- used live during a drag, where the source's settings have not been written yet
	---------------------------------------------------------------------------------------------------
	function self:MirrorFrom( sourceLeft, sourceTop )

		local width, height = self.window:GetSize()

		local left, top = GRISTLE.ClampToScreen(
			GRISTLE.MirrorLeft( sourceLeft, width ), sourceTop, width, height )

		self.window:SetPosition( left, top )

	end

	function self:ApplyColors()
		self.nameRow:ApplyColors()
		self.moraleBar:ApplyColors()
		self.powerBar:ApplyColors()
	end

	function self:ApplyFonts()
		self.nameRow:ApplyFonts()
		self.nameRow:ApplyAlignment()
		self.moraleBar:ApplyFonts()
		self.moraleBar:ApplyAlignment()
		self.powerBar:ApplyFonts()
	end

	---------------------------------------------------------------------------------------------------
	-- one fixed opacity, applied to the whole window
	---------------------------------------------------------------------------------------------------
	function self:ApplyOpacity()

		local opacity = tonumber( GRISTLE.Settings.opacity ) or 1

		-- in move mode the window must stay clearly visible whatever the setting says, or a HUD turned
		-- down to a faint shadow becomes a thing you cannot find in order to drag it
		if MOVE then
			opacity = 1
		end

		GRISTLE.ForceOpacity( self.window, opacity )

	end

	function self:ApplyMove()

		self.moveControl:SetMouseVisible( MOVE )
		self.moveControl:SetVisible( MOVE )

		if MOVE then
			self.moveControl:SetBackColor( GRISTLE.Color( GRISTLE.Palette.handle ) )
			self.moveControl:SetOpacity( 0.35 )
		end

		self:ApplyOpacity()

	end

	---------------------------------------------------------------------------------------------------
	-- data
	---------------------------------------------------------------------------------------------------

	---------------------------------------------------------------------------------------------------
	-- bind the entity element to whoever this window is describing
	-- nil unbinds it, so a window with no target cannot be clicked to re-target the last one
	---------------------------------------------------------------------------------------------------
	function self:SetEntity( entity )

		self.entity = entity

		-- SetEntity is on EntityControl but not in the published API listing, so it is called
		-- defensively: losing the context menu is survivable, throwing out of a target change is not
		pcall( function() self.entityControl:SetEntity( entity ) end )

		self:ApplyEntity()

	end

	function self:ApplyEntity()

		local wanted = GRISTLE.Settings.entityControl and self.entity ~= nil

		self.entityControl:SetVisible( wanted and true or false )
		self.entityControl:SetMouseVisible( wanted and true or false )

		-- under every bar, so the bars are what you see and it is only what you click
		GRISTLE.ForceZOrder( self.entityControl, 1 )

	end

	---------------------------------------------------------------------------------------------------
	-- re-render every readout from the context as it currently stands
	---------------------------------------------------------------------------------------------------
	-- Called from every setter below rather than only from the one whose data changed, because a
	-- template can name any field: putting the name inside the bar means a name change has to reach
	-- the bar, and putting the morale on the name row means a morale change has to reach the row.
	-- Both widgets compare the rendered string before touching a label, so the only cost of the
	-- extra work is a gsub over a short template.
	---------------------------------------------------------------------------------------------------
	function self:RenderText()
		self.moraleBar:RenderLabels()
		self.nameRow:Render()
	end

	-- class is a Turbine.Gameplay.Class value, or nil for anything that is not a player. Only a
	-- class with an emblem in GRISTLE.ClassIcons gets one; the rest show no icon rather than a wrong one.
	function self:SetName( name, level, class )

		self.context.name  = name or ""
		self.context.level = level

		self.nameRow:SetClassIcon( class ~= nil and GRISTLE.ClassIcons[ class ] or nil )

		self:RenderText()

	end

	---------------------------------------------------------------------------------------------------
	-- does this window have vitals to report?
	---------------------------------------------------------------------------------------------------
	-- A chest, a door or a crafting station is a perfectly good thing to have selected and has no
	-- morale at all. The frame stays up with its name and its empty background, because what you
	-- want to know is what you have got selected; hiding the whole frame answers that with nothing.
	--
	-- Both bars go blank together, so an object shows the same empty two-bar frame a creature
	-- does rather than a lone morale track. The power track only appears if power is switched on
	-- at all. Coming back, SetPower runs straight after this and decides from the real reading
	-- whether the power bar stays - a creature with no power still loses its hairline there.
	---------------------------------------------------------------------------------------------------
	function self:SetVitalsShown( shown )

		self.moraleBar:SetBlank( not shown )
		self.powerBar:SetBlank( not shown )

		if not shown then
			self.powerShown = self.showPower and true or false
			self.powerBar:SetVisible( self.powerShown )
		end

	end

	function self:SetMorale( current, max, temp, maxTemp )

		self.context.cur     = current
		self.context.max     = max
		self.context.temp    = temp
		self.context.maxtemp = maxTemp

		self.moraleBar:SetVital( current, max, temp, maxTemp )

		self:RenderText()

	end

	---------------------------------------------------------------------------------------------------
	-- nil means "this entity has no power to show", which is the normal case for a great many
	-- monsters. The hairline is hidden rather than left sitting there as an empty track, but the
	-- window keeps its height: shrinking it would make the whole HUD jump every time you tabbed
	-- between a caster and a bear.
	---------------------------------------------------------------------------------------------------
	function self:SetPower( current, max )

		-- recorded before the early return below. The hairline can be switched off while a template
		-- in the morale bar still names [pow], and that readout has to keep working.
		self.context.pow    = current
		self.context.maxpow = max

		self:RenderText()

		if not self.showPower then return end

		local available = ( current ~= nil and max ~= nil and max > 0 )

		if available ~= self.powerShown then
			self.powerShown = available
			self.powerBar:SetVisible( available )
		end

		if available then
			self.powerBar:SetVital( current, max )
		end

	end

	function self:Reset()

		-- the context describes an entity this window has stopped showing. Left alone, a template
		-- naming a vital would print the previous target's numbers over the new one's bar for as long
		-- as it took the new reading to arrive - which for anything you are not fighting is forever.
		local context = self.context

		context.cur,  context.max    = nil, nil
		context.temp, context.maxtemp = nil, nil
		context.pow,  context.maxpow = nil, nil
		context.name, context.level  = "", nil

		self.nameRow:Reset()
		self.moraleBar:Reset()
		self.powerBar:Reset()

	end

	function self:SetShown( shown )

		local wanted = shown and ( GRISTLE.Settings[ self.keys.visible ] ~= false )

		self.window:SetVisible( wanted and true or false )

	end

	-- show the window regardless of whether it has anything to describe, so there is something to
	-- grab in move mode. Still obeys the "hide this window entirely" setting.
	function self:ForceShown()
		self.window:SetVisible( GRISTLE.Settings[ self.keys.visible ] ~= false )
	end

	---------------------------------------------------------------------------------------------------
	-- a top level window is not torn down by anything else, so without this it survives a
	-- /plugins refresh as an orphan parked on screen
	---------------------------------------------------------------------------------------------------
	function self:Dispose()
		self:Reset()
		-- unbound before the window goes, so nothing is left holding an entity reference
		self:SetEntity( nil )
		self.window:SetVisible( false )
		self.window:SetParent( nil )
	end

	---------------------------------------------------------------------------------------------------

	self:ApplyLayout()

	return self

end
