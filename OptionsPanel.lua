---------------------------------------------------------------------------------------------------
-- Gristle - the options panel
---------------------------------------------------------------------------------------------------
-- A ListBox of rows, each row a plain Control with hand-placed widgets, the same shape as
-- VitalTarget's panel. Numbers use a stepper rather than a text box plus Apply button: a stepper
-- cannot be left holding an invalid value, and every change is visible immediately.
--
-- Everything commits straight away - there is no Apply/Cancel. The bars are the preview.
--
-- What is handed to the Plugin Manager is a plain Control holding the ListBox and a scrollbar side
-- by side, not the ListBox itself. The rows add up to far more than the manager will draw, and a
-- ListBox simply clips what does not fit -- there is no "it grew too tall" to notice, the bottom of
-- the panel is just quietly not there. The scrollbar cannot be a child of the ListBox either: a
-- ListBox draws the items it was given and nothing else, so anything else parented to it never
-- appears. Same arrangement as LootLogs/UI/Window/LootPopup.lua.
---------------------------------------------------------------------------------------------------

local PANEL_WIDTH  = 600
local PANEL_HEIGHT = 700                              -- the viewport the manager gives us
local SCROLL_WIDTH = 10
local ROW_WIDTH    = PANEL_WIDTH - SCROLL_WIDTH       -- rows stop short of the bar, not under it
local HINT_LEFT    = 320                              -- right-hand hint column
local HINT_WIDTH   = ROW_WIDTH - HINT_LEFT
local MARGIN       = 30

local GOLD    = Turbine.UI.Color( 0.75, 0.58, 0.18 )
local DIMGOLD = Turbine.UI.Color( 0.30, 0.22, 0.06 )
local FIELD   = Turbine.UI.Color( 0.05, 0.05, 0.07 )  -- behind an editable text box

local FONT_SECTION = Turbine.UI.Lotro.Font.BookAntiqua16
local FONT_BODY    = Turbine.UI.Lotro.Font.BookAntiqua18
local FONT_SMALL   = Turbine.UI.Lotro.Font.Verdana12
local FONT_TITLE   = Turbine.UI.Lotro.Font.BookAntiqua36

-- one shared swatch set for every colour row: white, the name row's off-white, the three morale
-- bands, power blue, bubble cyan, a violet, and the near-black used for the track
local SWATCHES = {
	{ R = 1.00, G = 1.00, B = 1.00 },
	{ R = 0.90, G = 0.87, B = 0.78 },
	{ R = 0.22, G = 0.78, B = 0.35 },
	{ R = 0.98, G = 0.76, B = 0.16 },
	{ R = 0.92, G = 0.22, B = 0.20 },
	{ R = 0.25, G = 0.60, B = 0.95 },
	{ R = 0.45, G = 0.85, B = 1.00 },
	{ R = 0.70, G = 0.35, B = 0.95 },
	{ R = 0.07, G = 0.07, B = 0.09 },
}

---------------------------------------------------------------------------------------------------
-- row primitives
---------------------------------------------------------------------------------------------------

local function Row( height )

	local row = Turbine.UI.Control()
	row:SetSize( ROW_WIDTH, height )

	return row

end

local function SectionLabel( parent, text, top )

	local label = Turbine.UI.Label()
	label:SetParent( parent )
	label:SetPosition( MARGIN, top or 0 )
	label:SetSize( 400, 20 )
	label:SetFont( FONT_SECTION )
	label:SetForeColor( GOLD )
	label:SetText( text )

	return label

end

local function TextLabel( parent, text, left, top, width, font )

	local label = Turbine.UI.Label()
	label:SetParent( parent )
	label:SetPosition( left, top )
	label:SetSize( width, 20 )
	label:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleLeft )
	label:SetFont( font or FONT_SMALL )
	label:SetText( text )

	return label

end

---------------------------------------------------------------------------------------------------
-- a stepper: [-] value [+]
--
-- decimals is the number of places to show; it also sets how the value is rounded, so a 0.05 step
-- cannot drift into 0.15000000000000002
--
-- Normally it reads and writes GRISTLE.Settings[ key ] directly. Two hooks override that, for values
-- that are not simply a number in the settings:
--
--   get     read the displayed value from somewhere else   ( window positions are stored as screen
--                                                             ratios but have to be shown in pixels )
--   nudge   handle the - / + press entirely, given a direction, and do its own saving
--   display render the value as text instead of as a number   ( the font family is a name )
--
-- valueWidth widens the box between the buttons, for a value that is a word rather than a number.
---------------------------------------------------------------------------------------------------
local function Stepper( parent, label, left, top, options )

	TextLabel( parent, label, left, top, options.labelWidth or 150 )

	local valueLeft = left + ( options.labelWidth or 150 )
	local valueWidth = options.valueWidth or 56

	local minus = Turbine.UI.Lotro.Button()
	minus:SetParent( parent )
	minus:SetPosition( valueLeft, top )
	minus:SetSize( 24, 20 )
	minus:SetText( "-" )

	local value = Turbine.UI.Label()
	value:SetParent( parent )
	value:SetPosition( valueLeft + 26, top )
	value:SetSize( valueWidth, 20 )
	value:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleCenter )
	value:SetFont( FONT_SMALL )

	local plus = Turbine.UI.Lotro.Button()
	plus:SetParent( parent )
	plus:SetPosition( valueLeft + valueWidth + 28, top )
	plus:SetSize( 24, 20 )
	plus:SetText( "+" )

	local decimals = options.decimals or 0

	local function render()

		if options.display ~= nil then
			value:SetText( options.display() )
			return
		end

		local current

		if options.get ~= nil then
			current = tonumber( options.get() ) or 0
		else
			current = tonumber( GRISTLE.Settings[ options.key ] ) or 0
		end

		if decimals > 0 then
			value:SetText( string.format( "%." .. decimals .. "f", current ) )
		else
			value:SetText( tostring( math.floor( current ) ) )
		end

	end

	local function nudge( direction )

		if options.nudge ~= nil then

			-- owns the whole change, including saving it
			options.nudge( direction )

		else

			GRISTLE.Settings[ options.key ] = GRISTLE.StepValue(
				GRISTLE.Settings[ options.key ], direction, options.step,
				options.min, options.max, decimals )

			GRISTLE.Save()

		end

		if options.onChange ~= nil then
			options.onChange()
		else
			GRISTLE.ApplyAll()
		end

		-- rendered last, so a value the change was clamped or mirrored into shows what actually
		-- happened rather than what was asked for
		render()

	end

	minus.Click = function() nudge( -1 ) end
	plus.Click  = function() nudge(  1 ) end

	render()

	return render

end

---------------------------------------------------------------------------------------------------
-- a checkbox bound to a settings key
---------------------------------------------------------------------------------------------------
local function CheckBox( parent, label, left, top, key, onChange )

	local box = Turbine.UI.Lotro.CheckBox()
	box:SetParent( parent )
	box:SetPosition( left, top )
	box:SetSize( 420, 20 )
	box:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleLeft )
	box:SetFont( FONT_BODY )
	box:SetText( " " .. label )
	box:SetChecked( GRISTLE.Settings[ key ] and true or false )

	box.CheckedChanged = function()

		GRISTLE.Settings[ key ] = box:IsChecked()

		GRISTLE.Save()

		if onChange ~= nil then
			onChange()
		else
			GRISTLE.ApplyAll()
		end

	end

	return box

end

---------------------------------------------------------------------------------------------------
-- a template row: a label and the two text boxes for one line's two ends
---------------------------------------------------------------------------------------------------
-- Commits on every keystroke, like every other widget in this panel - there is no Apply, the bars
-- are the preview. A text box is the one widget here that could lose its value instead of merely
-- showing a stale one, so waiting for the box to lose focus is not an option: the Plugin Manager can
-- close the panel without FocusLost ever firing, and the line would be quietly thrown away.
--
-- ApplyFormats rather than ApplyAll, because relayouting both windows on every keystroke would clear
-- the dirty-flag caches and blank the bars until the next vital event.
---------------------------------------------------------------------------------------------------
-- A plain Turbine.UI.TextBox inside a Control painted as its background, rather than
-- Turbine.UI.Lotro.TextBox. That is the shape every working text field in this folder uses -
-- LootLogs' searches, Basil's, Gibberish3's - and the bare TextBox draws no background of its own,
-- so without the Control behind it there is nothing on screen to show the field is there.
--
-- Programmatic SetText does not fire TextChanged in the client, which is why the initial value below
-- can be set before the handler without saving on every panel open.
local function FormatRow( parent, label, top, leftKey, rightKey )

	TextLabel( parent, label, MARGIN, top, 110 )

	local function Box( left, key )

		local back = Turbine.UI.Control()
		back:SetParent( parent )
		back:SetPosition( left, top )
		back:SetSize( 200, 20 )
		back:SetBackColor( FIELD )

		local box = Turbine.UI.TextBox()
		box:SetParent( back )
		box:SetPosition( 3, 2 )
		box:SetSize( 194, 16 )
		box:SetMultiline( false )
		box:SetFont( FONT_SMALL )
		box:SetBackColor( FIELD )
		box:SetForeColor( Turbine.UI.Color( 1, 1, 1 ) )
		box:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleLeft )
		box:SetText( tostring( GRISTLE.Settings[ key ] or "" ) )

		box.TextChanged = function()
			GRISTLE.Settings[ key ] = box:GetText()
			GRISTLE.Save()
			GRISTLE.ApplyFormats()
		end

		return box

	end

	Box( MARGIN + 115, leftKey )
	Box( MARGIN + 325, rightKey )

end

---------------------------------------------------------------------------------------------------
-- a colour row: current value, the preset swatches, then a box for any colour as a hex code
---------------------------------------------------------------------------------------------------
-- The hex box commits on every keystroke like the template boxes, but only once what is typed is a
-- whole six-digit code: halfway through typing "F9C229" the box holds "F9C", and reading that as a
-- colour would flicker the bar through dark nonsense on the way to the one you meant. A swatch
-- click rewrites the box, so the two can never disagree about what is set.
---------------------------------------------------------------------------------------------------
local function ColorRow( parent, label, top, key )

	TextLabel( parent, label, MARGIN, top, 150 )

	local preview = Turbine.UI.Control()
	preview:SetParent( parent )
	preview:SetPosition( MARGIN + 150, top )
	preview:SetSize( 34, 20 )
	preview:SetBackColor( GRISTLE.Color( GRISTLE.Settings[ key ] ) )

	local hexBack = Turbine.UI.Control()
	hexBack:SetParent( parent )
	hexBack:SetPosition( MARGIN + 470, top )
	hexBack:SetSize( 76, 20 )
	hexBack:SetBackColor( FIELD )

	local hex = Turbine.UI.TextBox()
	hex:SetParent( hexBack )
	hex:SetPosition( 3, 2 )
	hex:SetSize( 70, 16 )
	hex:SetMultiline( false )
	hex:SetFont( FONT_SMALL )
	hex:SetBackColor( FIELD )
	hex:SetForeColor( Turbine.UI.Color( 1, 1, 1 ) )
	hex:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleLeft )
	hex:SetText( "#" .. GRISTLE.ColorToHex( GRISTLE.Settings[ key ] ) )

	-- the client does not fire TextChanged for a programmatic SetText, but nothing promises that,
	-- and a swatch click rewriting the box must not commit the same colour a second time
	local updating = false

	hex.TextChanged = function()

		if updating then return end

		local value = GRISTLE.HexToColor( hex:GetText() )

		if value == nil then return end

		GRISTLE.Settings[ key ] = value

		preview:SetBackColor( GRISTLE.Color( value ) )

		GRISTLE.Save()
		GRISTLE.ApplyAll()

	end

	for i = 1, #SWATCHES do

		local swatch = Turbine.UI.Control()
		swatch:SetParent( parent )
		swatch:SetPosition( MARGIN + 196 + ( i - 1 ) * 30, top )
		swatch:SetSize( 26, 20 )
		swatch:SetBackColor( GRISTLE.Color( SWATCHES[i] ) )
		swatch:SetMouseVisible( true )

		swatch.MouseDown = function( sender, args )

			if args.Button ~= Turbine.UI.MouseButton.Left then return end

			-- copied, so the settings never alias the shared SWATCHES table
			GRISTLE.Settings[ key ] = GRISTLE.DeepCopy( SWATCHES[i] )

			preview:SetBackColor( GRISTLE.Color( GRISTLE.Settings[ key ] ) )

			updating = true
			hex:SetText( "#" .. GRISTLE.ColorToHex( GRISTLE.Settings[ key ] ) )
			updating = false

			GRISTLE.Save()
			GRISTLE.ApplyAll()

		end

	end

end

---------------------------------------------------------------------------------------------------
-- the panel
---------------------------------------------------------------------------------------------------

function GRISTLE.CreateOptionsPanel()

	local panel = Turbine.UI.Control()
	panel:SetSize( PANEL_WIDTH, PANEL_HEIGHT )

	local list = Turbine.UI.ListBox()
	list:SetParent( panel )
	list:SetPosition( 0, 0 )
	list:SetSize( ROW_WIDTH, PANEL_HEIGHT )

	-- takes the mouse so the wheel scrolls it. A list you can only move by dragging the bar is half
	-- a scrollbar, and this one is long enough that it matters.
	list:SetMouseVisible( true )

	local scroll = Turbine.UI.Lotro.ScrollBar()
	scroll:SetParent( panel )
	scroll:SetOrientation( Turbine.UI.Orientation.Vertical )
	scroll:SetPosition( ROW_WIDTH, 0 )
	scroll:SetSize( SCROLL_WIDTH, PANEL_HEIGHT )

	list:SetVerticalScrollBar( scroll )

	-- the rows live on the ListBox, not on the Control handed back, so the tests have to be able to
	-- reach it to count them
	panel.listBox = list

	local function Divider()

		local row = Row( 18 )

		local line = Turbine.UI.Control()
		line:SetParent( row )
		line:SetPosition( MARGIN, 8 )
		line:SetSize( ROW_WIDTH - 2 * MARGIN, 1 )
		line:SetBackColor( DIMGOLD )

		list:AddItem( row )

	end

	-----------------------------------------------------------------------------------------------
	-- title
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 64 )

		local title = Turbine.UI.Label()
		title:SetParent( row )
		title:SetSize( ROW_WIDTH, 50 )
		title:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleCenter )
		title:SetFont( FONT_TITLE )
		title:SetForeColor( GOLD )
		title:SetText( "Gristle" )

		local version = Turbine.UI.Label()
		version:SetParent( row )
		version:SetPosition( 0, 46 )
		version:SetSize( ROW_WIDTH, 16 )
		version:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleCenter )
		version:SetFont( FONT_SMALL )
		-- deliberately names no skin: the companion skin has been renamed twice already, and a stale
		-- name here is worse than no name
		version:SetText( "v" .. GRISTLE.Version .. "  -  /gristle for the command list" )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- window
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 144 )

		SectionLabel( row, "WINDOW" )

		local moveBox = Turbine.UI.Lotro.CheckBox()
		moveBox:SetParent( row )
		moveBox:SetPosition( MARGIN, 24 )
		moveBox:SetSize( 420, 20 )
		moveBox:SetTextAlignment( Turbine.UI.ContentAlignment.MiddleLeft )
		moveBox:SetFont( FONT_BODY )
		moveBox:SetText( " Drag mode - both bars become movable" )
		moveBox:SetChecked( MOVE )

		moveBox.CheckedChanged = function()
			GRISTLE.SetMoveMode( moveBox:IsChecked() )
		end

		CheckBox( row, "Show the player bars",  MARGIN, 48, "selfVisible", function()
			GRISTLE.Self.window:SetShown( true )
		end )

		CheckBox( row, "Show the target bars",  MARGIN, 72, "targetVisible", function()
			GRISTLE.Target.window:SetShown( GRISTLE.Target.entity ~= nil )
		end )

		-- a move, not a rebuild: ApplyAll would clear every bar's cache and blank them until the next
		-- vital event, which on a quiet target could be a while
		CheckBox( row, "Mirror the target bars across the screen", MARGIN, 96, "mirrorTarget", function()
			GRISTLE.ApplyPositions()
		end )

		TextLabel( row, "its own saved position is then ignored - drag either frame and both move",
			MARGIN + 24, 118, ROW_WIDTH - MARGIN - 24 )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- fine positioning
	-----------------------------------------------------------------------------------------------
	-- a drag lands wherever the mouse was released. Lining a frame up against a quickslot bar or
	-- another plugin's window needs finer than that, so each axis gets a one-pixel step.
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 172 )

		SectionLabel( row, "FINE POSITION" )

		-- reads the window's real on-screen position rather than the setting, so the number shown is
		-- what you see: the setting is a screen ratio, and it is ignored entirely while mirroring
		local function Axis( window, label, top, axis )

			Stepper( row, label, MARGIN, top, {

				get = function()
					if window() == nil then return 0 end
					local left, winTop = window().window:GetPosition()
					return axis == "x" and left or winTop
				end,

				nudge = function( direction )
					if window() == nil then return end
					if axis == "x" then
						window():Nudge( direction, 0 )
					else
						window():Nudge( 0, direction )
					end
				end,

				-- Nudge already moved, clamped, mirrored and saved; rebuilding the bars on top of
				-- that would clear every dirty-flag cache for nothing
				onChange = function() end,

			} )

		end

		local function selfWindow()   return GRISTLE.Self.window end
		local function targetWindow() return GRISTLE.Target.window end

		TextLabel( row, "Player frame", MARGIN, 24, 150, FONT_BODY )
		Axis( selfWindow, "    across",  48, "x" )
		Axis( selfWindow, "    down",    72, "y" )

		TextLabel( row, "Target frame", MARGIN, 100, 150, FONT_BODY )
		Axis( targetWindow, "    across", 124, "x" )
		Axis( targetWindow, "    down",   148, "y" )

		TextLabel( row, "one pixel a press", HINT_LEFT, 48, HINT_WIDTH )
		TextLabel( row, "mirrored, the target follows the player", HINT_LEFT, 124, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- player bar
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 196 )

		SectionLabel( row, "PLAYER BAR" )

		Stepper( row, "Width",            MARGIN, 26, { key = "selfWidth",       min = 40, max = 1200, step = 10 } )
		Stepper( row, "Morale height",    MARGIN, 50, { key = "selfBarHeight",   min = 6,  max = 160,  step = 2 } )
		Stepper( row, "Power height",     MARGIN, 74, { key = "selfPowerHeight", min = 1,  max = 60,   step = 1 } )
		Stepper( row, "Gap",              MARGIN, 98, { key = "selfGap",         min = 0,  max = 40,   step = 1 } )

		CheckBox( row, "Show the power hairline", MARGIN, 122, "selfShowPower" )
		CheckBox( row, "Show your name above it", MARGIN, 146, "selfShowName" )
		CheckBox( row, "Show your class icon beside the name", MARGIN, 170, "selfShowClassIcon" )

		TextLabel( row, "the gap spaces the name, the bar and the hairline alike", HINT_LEFT, 98, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- target bar
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 196 )

		SectionLabel( row, "TARGET BAR" )

		Stepper( row, "Width",            MARGIN, 26, { key = "targetWidth",       min = 40, max = 1200, step = 10 } )
		Stepper( row, "Morale height",    MARGIN, 50, { key = "targetBarHeight",   min = 6,  max = 160,  step = 2 } )
		Stepper( row, "Power height",     MARGIN, 74, { key = "targetPowerHeight", min = 1,  max = 60,   step = 1 } )
		Stepper( row, "Gap",              MARGIN, 98, { key = "targetGap",         min = 0,  max = 40,   step = 1 } )

		CheckBox( row, "Show the power hairline",         MARGIN, 122, "targetShowPower" )
		CheckBox( row, "Show the target's name above it", MARGIN, 146, "targetShowName" )
		CheckBox( row, "Show a player target's class icon",   MARGIN, 170, "targetShowClassIcon" )

		-- hints go beside a stepper, never beside a checkbox: a checkbox is 420 wide whatever its
		-- text, so a label parked to its right lands on top of its hit region and eats the click
		TextLabel( row, "the hairline hides itself for a target with no power", HINT_LEFT, 98, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- readouts
	-----------------------------------------------------------------------------------------------
	-- Four templates per frame rather than a checkbox per question. The tag names fit here; what
	-- each one means does not, and there is no tooltip to put it in, so this points at
	-- /gristle format for the rest.
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 368 )

		SectionLabel( row, "READOUTS" )

		TextLabel( row, "tags:  [cur]  [max]  [perc]  [deficit]  [temp]  [maxtemp]",
			MARGIN, 24, ROW_WIDTH - 2 * MARGIN )
		TextLabel( row, "          [pow]  [maxpow]  [powperc]  [name]  [level]",
			MARGIN, 42, ROW_WIDTH - 2 * MARGIN )
		TextLabel( row, "modifiers:  [cur:short] 12.5k    [cur:full] 12,480    [perc:1] one decimal",
			MARGIN, 60, ROW_WIDTH - 2 * MARGIN )

		FormatRow( row, "Player bar",   84, "selfFormatBarLeft",    "selfFormatBarRight" )
		FormatRow( row, "Player name", 108, "selfFormatNameMain",   "selfFormatNameAside" )
		FormatRow( row, "Target bar",  132, "targetFormatBarLeft",  "targetFormatBarRight" )
		FormatRow( row, "Target name", 156, "targetFormatNameMain", "targetFormatNameAside" )

		TextLabel( row, "the first box reads inward from the frame's own end - left on the player",
			MARGIN, 180, ROW_WIDTH - 2 * MARGIN )
		TextLabel( row, "clear a box to drop that readout.  /gristle format explains every tag",
			MARGIN, 198, ROW_WIDTH - 2 * MARGIN )

		-- only the rendered strings change, so this does not go through ApplyAll and rebuild both
		-- windows to re-print four labels
		CheckBox( row, "Abbreviate large numbers - 12.5k rather than 12,480", MARGIN, 222,
			"abbreviateNumbers", function()
				GRISTLE.ApplyFormats()
			end )

		CheckBox( row, "Bold the bar readouts - Trajan Pro and Book Antiqua only", MARGIN, 246, "boldValue" )

		-- cycles through GRISTLE.FontFamilies rather than offering a list: the panel has no dropdown,
		-- and there are only a handful of families
		Stepper( row, "Font", MARGIN, 272, {
			labelWidth = 60,
			valueWidth = 112,
			display = function()
				local family = GRISTLE.FindFontFamily( GRISTLE.Settings.fontFamily )
				return family ~= nil and family.label or "?"
			end,
			nudge = function( direction )
				local families = GRISTLE.FontFamilies
				local _, index = GRISTLE.FindFontFamily( GRISTLE.Settings.fontFamily )
				index = ( ( ( index or 1 ) - 1 + direction ) % #families ) + 1
				GRISTLE.Settings.fontFamily = families[ index ].key
				GRISTLE.Save()
			end,
		} )

		Stepper( row, "First box size",  MARGIN, 296, { key = "fontSize",        min = 8, max = 23, step = 2 } )
		Stepper( row, "Second box size", MARGIN, 320, { key = "percentFontSize", min = 8, max = 23, step = 2 } )
		Stepper( row, "Name row size",   MARGIN, 344, { key = "nameFontSize",    min = 8, max = 23, step = 2 } )

		TextLabel( row, "one font for the name row and both readouts", HINT_LEFT, 272, HINT_WIDTH )
		TextLabel( row, "and from the right on the target, name row and readouts alike",
			HINT_LEFT, 296, HINT_WIDTH )
		TextLabel( row, "the name row's height follows its own size", HINT_LEFT, 344, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- behaviour
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 196 )

		SectionLabel( row, "BEHAVIOUR" )

		CheckBox( row, "Draw a border",              MARGIN, 24, "showBorder" )
		CheckBox( row, "Flash the morale just lost", MARGIN, 48, "flash" )

		-- the one setting that decides whether the HUD takes the mouse at all, so the label says
		-- what you get rather than naming the control
		CheckBox( row, "Clickable frames - target, right-click menu, tooltip", MARGIN, 72,
			"entityControl", function()
				if GRISTLE.Self.window   ~= nil then GRISTLE.Self.window:ApplyEntity()   end
				if GRISTLE.Target.window ~= nil then GRISTLE.Target.window:ApplyEntity() end
			end )

		Stepper( row, "Flash length",   MARGIN, 96,  { key = "flashDuration", min = 0.05, max = 2.0, step = 0.05, decimals = 2 } )
		Stepper( row, "Warn below %",   MARGIN, 120, { key = "warnPercent",   min = 2,    max = 99,  step = 5 } )
		Stepper( row, "Danger below %", MARGIN, 144, { key = "dangerPercent", min = 1,    max = 98,  step = 5 } )

		-- one value for both windows, in or out of combat. Only the opacity needs re-applying, so
		-- this does not go through ApplyAll and rebuild both windows to change one number.
		Stepper( row, "Opacity",        MARGIN, 168, { key = "opacity",       min = 0.05, max = 1.0, step = 0.05, decimals = 2,
			onChange = function()
				if GRISTLE.Self.window   ~= nil then GRISTLE.Self.window:ApplyOpacity()   end
				if GRISTLE.Target.window ~= nil then GRISTLE.Target.window:ApplyOpacity() end
			end } )

		TextLabel( row, "off makes the bars click-through again", HINT_LEFT, 96,  HINT_WIDTH )
		TextLabel( row, "warn and danger are re-sorted if they cross", HINT_LEFT, 120, HINT_WIDTH )
		TextLabel( row, "drag mode ignores it, so a faint HUD stays grabbable", HINT_LEFT, 168, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- appearance
	-----------------------------------------------------------------------------------------------
	-- The finish on the bars rather than what they say. All of it is drawn over the fill inside the
	-- bar's clipping window, so none of it can spill past the end of the track.
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 124 )

		SectionLabel( row, "APPEARANCE" )

		Stepper( row, "Sheen", MARGIN, 24, { key = "sheen", min = 0, max = 0.5, step = 0.05, decimals = 2 } )

		CheckBox( row, "Mark the warn and danger thresholds",     MARGIN, 50,  "showTicks" )
		CheckBox( row, "Dark text over a bright fill",            MARGIN, 74,  "textContrast" )
		CheckBox( row, "Blend colours smoothly as morale drops",  MARGIN, 98,  "colorBlend" )

		TextLabel( row, "a light top and a dark bottom.  0 is flat", HINT_LEFT, 24, HINT_WIDTH )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- colours
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 268 )

		SectionLabel( row, "COLOURS" )

		ColorRow( row, "Morale",            26,  "colorMorale" )
		ColorRow( row, "Morale, warning",   50,  "colorMoraleWarn" )
		ColorRow( row, "Morale, danger",    74,  "colorMoraleDanger" )
		ColorRow( row, "Power",             98,  "colorPower" )
		ColorRow( row, "Temporary morale",  122, "colorTemp" )
		ColorRow( row, "Damage flash",      146, "colorFlash" )
		ColorRow( row, "Empty / deficit",   170, "colorTrack" )
		ColorRow( row, "Text",              194, "colorText" )
		ColorRow( row, "Text on bright fill", 218, "colorTextDark" )
		ColorRow( row, "Name row",          242, "colorName" )

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- shared across characters
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 86 )

		SectionLabel( row, "ALL CHARACTERS" )

		local status = TextLabel( row, "", MARGIN, 58, 520 )

		local function refreshStatus()
			if GRISTLE.HasGlobalSettings() then
				status:SetText( "A shared copy exists. Loading it replaces this character's settings." )
			else
				status:SetText( "No shared copy yet. Until there is one, every save also writes it." )
			end
		end

		local saveButton = Turbine.UI.Lotro.Button()
		saveButton:SetParent( row )
		saveButton:SetPosition( MARGIN, 28 )
		saveButton:SetSize( 180, 24 )
		saveButton:SetText( "Save as shared" )

		saveButton.Click = function()
			GRISTLE.SaveGlobalSettings()
			refreshStatus()
			Turbine.Shell.WriteLine( "Gristle: settings saved as the shared copy." )
		end

		local loadButton = Turbine.UI.Lotro.Button()
		loadButton:SetParent( row )
		loadButton:SetPosition( MARGIN + 196, 28 )
		loadButton:SetSize( 180, 24 )
		loadButton:SetText( "Load shared" )

		loadButton.Click = function()
			if GRISTLE.LoadGlobalSettings() then
				Turbine.Shell.WriteLine( "Gristle: shared settings loaded. Reopen this panel to refresh it." )
			else
				Turbine.Shell.WriteLine( "Gristle: there is no shared copy to load." )
			end
		end

		refreshStatus()

		list:AddItem( row )
	end

	Divider()

	-----------------------------------------------------------------------------------------------
	-- reset
	-----------------------------------------------------------------------------------------------
	do
		local row = Row( 60 )

		local reset = Turbine.UI.Lotro.Button()
		reset:SetParent( row )
		reset:SetPosition( MARGIN, 14 )
		reset:SetSize( 180, 24 )
		reset:SetText( "Reset to defaults" )

		reset.Click = function()
			GRISTLE.ResetSettings()
			Turbine.Shell.WriteLine( "Gristle: settings reset. Reopen this panel to refresh it." )
		end

		TextLabel( row, "the panel's own widgets refresh when it is reopened", MARGIN + 196, 16, ROW_WIDTH - MARGIN - 196 )

		list:AddItem( row )
	end

	return panel

end
