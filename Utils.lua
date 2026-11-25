---------------------------------------------------------------------------------------------------
-- Gristle - helpers
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- euro client number conversion
---------------------------------------------------------------------------------------------------
-- German and French clients cannot round-trip numbers or numeric table keys through the savefile
-- serialiser. Every plugin in this folder works around it the same way: write every number as a
-- string, turn it back on load. Ported from Potato/main.lua.
---------------------------------------------------------------------------------------------------

function GRISTLE.IsEuroClient()
	return Turbine.Shell.IsCommand( "hilfe" ) or Turbine.Shell.IsCommand( "aide" )
end

function GRISTLE.ConvertToEuro( dataRaw )

	if type( dataRaw ) ~= "table" then
		return type( dataRaw ) == "number" and tostring( dataRaw ) or dataRaw
	end

	-- class instances (Turbine.UI.Color and friends) are handed back untouched: walking them with
	-- pairs() flattens them into something the game can no longer use
	if getmetatable( dataRaw ) ~= nil then
		return dataRaw
	end

	local newData = {}

	for key, value in pairs( dataRaw ) do

		local newKey = type( key ) == "number" and tostring( key ) or key
		local newValue

		if type( value ) == "table" then
			newValue = GRISTLE.ConvertToEuro( value )
		elseif type( value ) == "number" then
			newValue = tostring( value )
		else
			newValue = value
		end

		newData[ newKey ] = newValue

	end

	return newData

end

-- idempotent on savefiles written before the euro fix: numbers survive tonumber unchanged, and
-- strings that are not numbers fall back to themselves
function GRISTLE.ConvertFromEuro( dataRaw )

	if type( dataRaw ) ~= "table" then
		local n = tonumber( dataRaw )
		return n ~= nil and n or dataRaw
	end

	if getmetatable( dataRaw ) ~= nil then
		return dataRaw
	end

	local newData = {}

	for key, value in pairs( dataRaw ) do

		local newKey = tonumber( key )
		if newKey == nil then newKey = key end

		local newValue

		if type( value ) == "table" then
			newValue = GRISTLE.ConvertFromEuro( value )
		else
			newValue = tonumber( value )
			if newValue == nil then newValue = value end
		end

		newData[ newKey ] = newValue

	end

	return newData

end

---------------------------------------------------------------------------------------------------
-- tables
---------------------------------------------------------------------------------------------------

-- class instances are aliased rather than copied, same reason as ConvertToEuro
function GRISTLE.DeepCopy( value )

	if type( value ) ~= "table" or getmetatable( value ) ~= nil then
		return value
	end

	local copy = {}

	for key, inner in pairs( value ) do
		copy[ key ] = GRISTLE.DeepCopy( inner )
	end

	return copy

end

---------------------------------------------------------------------------------------------------
-- colours
---------------------------------------------------------------------------------------------------
-- settings hold { R, G, B } tables; the engine wants Turbine.UI.Color. Rebuilt on read rather than
-- cached, because a cached Color would have to be stripped out of the savefile payload again.
---------------------------------------------------------------------------------------------------

function GRISTLE.Color( value )

	if value == nil then
		return Turbine.UI.Color.White
	end

	-- already a Color
	if getmetatable( value ) ~= nil then
		return value
	end

	return Turbine.UI.Color( value.R or 0, value.G or 0, value.B or 0 )

end

function GRISTLE.ColorTable( r, g, b )
	return { R = r, G = g, B = b }
end

-- a see-through colour. The engine's four-argument form puts alpha FIRST, which is easy to get
-- backwards, so it is spelled out once here rather than at every call site.
function GRISTLE.AlphaColor( alpha, value )
	value = value or { R = 0, G = 0, B = 0 }
	return Turbine.UI.Color( alpha, value.R or 0, value.G or 0, value.B or 0 )
end

-- a straight line from a to b; t is clamped, so a percentage a hair outside its band cannot
-- overshoot into a colour neither end asked for
function GRISTLE.LerpColor( a, b, t )

	if t < 0 then t = 0 end
	if t > 1 then t = 1 end

	return {
		R = ( a.R or 0 ) + ( ( b.R or 0 ) - ( a.R or 0 ) ) * t,
		G = ( a.G or 0 ) + ( ( b.G or 0 ) - ( a.G or 0 ) ) * t,
		B = ( a.B or 0 ) + ( ( b.B or 0 ) - ( a.B or 0 ) ) * t,
	}

end

-- perceived brightness, 0..1. Decides whether a readout sitting on this colour wants dark text.
function GRISTLE.Luminance( value )
	return 0.299 * ( value.R or 0 ) + 0.587 * ( value.G or 0 ) + 0.114 * ( value.B or 0 )
end

---------------------------------------------------------------------------------------------------
-- hex colour codes, for the options panel's free entry box
---------------------------------------------------------------------------------------------------
-- Six digits, an optional leading #, either case. Anything else is nil rather than a guess: the box
-- commits on every keystroke, so a half-typed code has to be refused, not read as a dark colour.
---------------------------------------------------------------------------------------------------

function GRISTLE.ColorToHex( value )

	local function channel( x )
		local n = math.floor( ( tonumber( x ) or 0 ) * 255 + 0.5 )
		if n < 0 then n = 0 end
		if n > 255 then n = 255 end
		return n
	end

	return string.format( "%02X%02X%02X", channel( value.R ), channel( value.G ), channel( value.B ) )

end

function GRISTLE.HexToColor( text )

	if type( text ) ~= "string" then return nil end

	local digits = string.match( text, "^%s*#?(%x%x%x%x%x%x)%s*$" )

	if digits == nil then return nil end

	return {
		R = tonumber( string.sub( digits, 1, 2 ), 16 ) / 255,
		G = tonumber( string.sub( digits, 3, 4 ), 16 ) / 255,
		B = tonumber( string.sub( digits, 5, 6 ), 16 ) / 255,
	}

end

---------------------------------------------------------------------------------------------------
-- positions
---------------------------------------------------------------------------------------------------
-- saved as a ratio of the screen so a resolution change does not strand a window off-screen
---------------------------------------------------------------------------------------------------

function GRISTLE.Round( value )
	return math.floor( ( tonumber( value ) or 0 ) + 0.5 )
end

function GRISTLE.RatioToPixel( left, top )
	return GRISTLE.Round( left * GRISTLE.ScreenWidth ), GRISTLE.Round( top * GRISTLE.ScreenHeight )
end

function GRISTLE.PixelToRatio( left, top )
	return left / GRISTLE.ScreenWidth, top / GRISTLE.ScreenHeight
end

---------------------------------------------------------------------------------------------------
-- mirroring, for the target window's "mirror the player frame" mode
---------------------------------------------------------------------------------------------------
-- Reflected across the screen's vertical centre line, so the two frames end up the same distance in
-- from opposite edges of the screen and at the same height.
--
-- It is the *far* edge that is mirrored, not the left edge: the source's gap from the left edge
-- becomes the mirror's gap from the right edge. That is what makes a pair of frames of different
-- widths still look symmetric, which left-edge mirroring would not.
--
-- The reflection is its own inverse, which is what lets the target window be dragged in mirror mode:
-- the same call turns a dropped mirror position back into the source position it implies.
---------------------------------------------------------------------------------------------------
function GRISTLE.MirrorLeft( left, width )
	return GRISTLE.ScreenWidth - ( tonumber( left ) or 0 ) - ( tonumber( width ) or 0 )
end

-- the far edge is applied first, so a window wider than the screen keeps its top left corner
-- visible instead of hanging off the top
function GRISTLE.ClampToScreen( left, top, width, height )

	if left > GRISTLE.ScreenWidth - width then
		left = GRISTLE.ScreenWidth - width
	end

	if top > GRISTLE.ScreenHeight - height then
		top = GRISTLE.ScreenHeight - height
	end

	if left < 0 then left = 0 end
	if top  < 0 then top  = 0 end

	return left, top

end

---------------------------------------------------------------------------------------------------
-- forced setters
---------------------------------------------------------------------------------------------------
-- LOTRO drops a setter that does not change the value, so the value has to move once before it is
-- set to the one actually wanted. Ported from Gibberish3/UTILS/Functions.lua.
---------------------------------------------------------------------------------------------------

function GRISTLE.ForceZOrder( control, zOrder )

	if control == nil then return end

	control:SetZOrder( zOrder + 100 )
	control:SetZOrder( zOrder )

end

function GRISTLE.ForceOpacity( control, opacity )

	if control == nil then return end

	if control:GetOpacity() == opacity then
		control:SetOpacity( opacity == 0 and 1 or 0 )
	end

	control:SetOpacity( opacity )

end

---------------------------------------------------------------------------------------------------
-- control factory
---------------------------------------------------------------------------------------------------
-- every control Gristle draws is mouse-invisible by construction: the HUD has to be click-through,
-- and a single control that forgets this swallows clicks on whatever is behind it
---------------------------------------------------------------------------------------------------

function GRISTLE.Rect( parent, color )

	local control = Turbine.UI.Control()
	control:SetParent( parent )
	control:SetMouseVisible( false )

	if color ~= nil then
		control:SetBackColor( GRISTLE.Color( color ) )
	end

	return control

end

function GRISTLE.ClipWindow( parent )

	-- a Turbine.UI.Window clips its children. That is the whole reason the fill lives inside one:
	-- it can never bleed past the end of the track, however the maths comes out.
	local window = Turbine.UI.Window()
	window:SetParent( parent )
	window:SetMouseVisible( false )
	window:SetBackColor( nil )

	-- A Window is created HIDDEN by the engine, unlike a Control. Nothing is drawn inside a hidden
	-- parent however visible the children believe themselves to be, which is how the morale bar came
	-- to report a full-width green fill and a rendered readout while showing an empty track: both of
	-- them live inside one of these. The power hairline escaped it only because the window layout
	-- calls SetVisible on that bar explicitly.
	window:SetVisible( true )

	return window

end

function GRISTLE.Label( parent, alignment )

	local label = Turbine.UI.Label()
	label:SetParent( parent )
	label:SetMouseVisible( false )
	label:SetMultiline( false )
	label:SetTextAlignment( alignment )

	-- Every label Gristle draws sits over a bar or over the world, so it needs to be legible against
	-- whatever ends up behind it. The outline *style* alone is not enough: the engine picks its own
	-- outline colour, and a pale outline on pale text over a pale bar is no outline at all. Black is
	-- stated, so the text reads over a full green bar, an empty dark track and the scenery alike.
	label:SetFontStyle( Turbine.UI.FontStyle.Outline )
	label:SetOutlineColor( Turbine.UI.Color.Black )

	return label

end

---------------------------------------------------------------------------------------------------
-- number formatting
---------------------------------------------------------------------------------------------------

-- 12480 -> "12,480". Grouping is hand-rolled because string.format has no thousands flag in 5.1.
function GRISTLE.FormatNumber( value )

	local n = math.floor( tonumber( value ) or 0 )
	local sign = ""

	if n < 0 then
		sign = "-"
		n = -n
	end

	local digits = tostring( n )
	local grouped = ""

	while #digits > 3 do
		grouped = "," .. string.sub( digits, -3 ) .. grouped
		digits = string.sub( digits, 1, -4 )
	end

	return sign .. digits .. grouped

end

---------------------------------------------------------------------------------------------------
-- the same number, abbreviated
---------------------------------------------------------------------------------------------------
-- 12,480 is six glyphs of which the last three never tell you anything you act on, and at level cap
-- a morale number is seven. "12.5k" is what the WoW frames settled on and it reads at a glance.
--
-- The precision steps down as the number grows rather than staying fixed, because one decimal place
-- is worth having at 12.5k and worth nothing at 243.2k. A trailing zero is dropped: 12.0k is not
-- more precise than 12k, it just looks it.
---------------------------------------------------------------------------------------------------
function GRISTLE.FormatShort( value )

	local n = math.floor( tonumber( value ) or 0 )
	local sign = ""

	if n < 0 then
		sign = "-"
		n = -n
	end

	-- below a thousand there is nothing to abbreviate
	if n < 1000 then
		return sign .. tostring( n )
	end

	local scaled, suffix, decimals

	if n < 1000000 then
		scaled, suffix = n / 1000, "k"
		decimals = ( n < 100000 ) and 1 or 0
	else
		scaled, suffix = n / 1000000, "M"
		decimals = 2
	end

	local text = string.format( "%." .. decimals .. "f", scaled )

	if decimals > 0 then
		text = string.gsub( text, "%.?0+$", "" )
	end

	return sign .. text .. suffix

end

---------------------------------------------------------------------------------------------------
-- a number for a readout, honouring the abbreviation setting unless the tag overrode it
---------------------------------------------------------------------------------------------------
-- The per-tag override exists because the two readouts in one bar want different answers: the big
-- morale number is worth abbreviating and a deficit of -240 is not.
---------------------------------------------------------------------------------------------------
function GRISTLE.FormatValue( value, mode )

	if mode == "short" then
		return GRISTLE.FormatShort( value )
	end

	if mode == "full" then
		return GRISTLE.FormatNumber( value )
	end

	if GRISTLE.Settings.abbreviateNumbers then
		return GRISTLE.FormatShort( value )
	end

	return GRISTLE.FormatNumber( value )

end

---------------------------------------------------------------------------------------------------
-- step a value, as the options panel's steppers do
---------------------------------------------------------------------------------------------------
-- rounded to the step's own precision, because repeatedly adding 0.05 in binary floating point
-- drifts into 0.15000000000000002 and then prints and saves as that
---------------------------------------------------------------------------------------------------
function GRISTLE.StepValue( current, direction, step, low, high, decimals )

	local value = ( tonumber( current ) or low ) + direction * step

	local factor = 10 ^ ( decimals or 0 )
	value = math.floor( value * factor + 0.5 ) / factor

	if value < low  then value = low  end
	if value > high then value = high end

	return value

end

-- decimals is optional and clamped to 0..2: a HUD percentage with three decimal places is noise,
-- and the template it comes from is user-typed, so [perc:9] has to land somewhere sane
function GRISTLE.FormatPercent( current, max, decimals )

	if max == nil or max <= 0 then
		return "0%"
	end

	local places = math.floor( tonumber( decimals ) or 0 )

	if places < 0 then places = 0 end
	if places > 2 then places = 2 end

	return string.format( "%." .. places .. "f%%", 100 * current / max )

end

---------------------------------------------------------------------------------------------------
-- event callbacks
---------------------------------------------------------------------------------------------------
-- Turbine events are a single field on the object. Assigning to it directly stomps whatever was
-- already there, which matters because LocalPlayer is shared with every other loaded plugin, so
-- handlers are appended to a table instead. Ported from VitalTarget/Handler.lua.
---------------------------------------------------------------------------------------------------

function GRISTLE.AddCallback( object, event, callback )

	if object == nil then return callback end

	if object[ event ] == nil then
		object[ event ] = callback
	elseif type( object[ event ] ) == "table" then
		table.insert( object[ event ], callback )
	else
		object[ event ] = { object[ event ], callback }
	end

	return callback

end

function GRISTLE.RemoveCallback( object, event, callback )

	if object == nil then return end

	if object[ event ] == callback then

		object[ event ] = nil

	elseif type( object[ event ] ) == "table" then

		local handlers = object[ event ]

		for i = 1, #handlers do
			if handlers[i] == callback then
				table.remove( handlers, i )
				break
			end
		end

		-- an emptied list has to go, not sit there as an orphan. LocalPlayer outlives the plugin, so
		-- an empty table left on one of its event slots is a leak we hand to whoever loads next --
		-- and it stops a later AddCallback from storing its handler bare.
		if #handlers == 0 then
			object[ event ] = nil
		end

	end

end

-- attach / detach the same handler across a list of event names in one go
function GRISTLE.AddCallbacks( object, events, callback )
	for i = 1, #events do
		GRISTLE.AddCallback( object, events[i], callback )
	end
end

function GRISTLE.RemoveCallbacks( object, events, callback )
	for i = 1, #events do
		GRISTLE.RemoveCallback( object, events[i], callback )
	end
end

---------------------------------------------------------------------------------------------------
-- vitals reading
---------------------------------------------------------------------------------------------------
-- not every targetable entity is an Actor. Chests, doors and crafting stations have no GetMorale at
-- all, so the read is wrapped rather than guarded by a type check - the same approach Potato takes.
---------------------------------------------------------------------------------------------------

-- one getter, wrapped: a missing member, a throw, or a non-number all come back as nil
function GRISTLE.CallVital( entity, getter )

	if entity == nil or getter == nil or entity[ getter ] == nil then
		return nil
	end

	local ok, value = pcall( function() return entity[ getter ]( entity ) end )

	if not ok or type( value ) ~= "number" then
		return nil
	end

	return value

end

---------------------------------------------------------------------------------------------------
-- current and max for one vital
---------------------------------------------------------------------------------------------------
-- baseMaxGetter is a fallback for the maximum, and it is not paranoia: the engine's GetMaxMorale
-- can answer 0 where GetBaseMaxMorale answers the real figure, and a maximum of 0 makes a bar
-- undrawable - there is no percentage of zero. Without the fallback the bar stays blank while the
-- power bar beside it, whose maximum happened to read, works perfectly.
--
-- A current value of 0 is kept: that is a dead target, which is worth drawing. Only the maximum has
-- to be positive.
---------------------------------------------------------------------------------------------------
function GRISTLE.ReadVital( entity, getter, maxGetter, baseMaxGetter )

	local current = GRISTLE.CallVital( entity, getter )

	if current == nil then
		return nil, nil
	end

	local max = GRISTLE.CallVital( entity, maxGetter )

	if max == nil or max <= 0 then
		max = GRISTLE.CallVital( entity, baseMaxGetter )
	end

	if max == nil or max <= 0 then
		return nil, nil
	end

	return current, max

end

---------------------------------------------------------------------------------------------------
-- true for anything that can show a morale bar
---------------------------------------------------------------------------------------------------
-- Deliberately a test of what the entity *is*, not of what it currently answers. The engine hands
-- out an entity before its data has arrived, so a mob you just targeted can report a morale of 0,
-- or throw, for a fraction of a second - and judging it on that reading rejects it outright, which
-- means no handlers are attached and nothing is ever listening when the real values show up. The
-- bar then stays blank for as long as you keep that target.
--
-- VitalTarget got this right by gating on GetLevel (VitalTarget/UI.lua:198): chests, doors and
-- crafting stations have no GetLevel, every Actor does. The member test costs nothing and cannot
-- be fooled by a value that has not loaded yet.
---------------------------------------------------------------------------------------------------
function GRISTLE.HasVitals( entity )

	if entity == nil then
		return false
	end

	-- no GetLevel means an object rather than an Actor, and objects have no vitals at all
	return entity.GetLevel ~= nil and entity.GetMorale ~= nil and entity.GetMaxMorale ~= nil

end

---------------------------------------------------------------------------------------------------
-- diagnostics
---------------------------------------------------------------------------------------------------
-- Runtime errors in this game surface only in the chat window and there is no log file, so when a
-- bar is blank the only way to tell "the engine answered nothing" apart from "we drew it in a
-- colour you cannot see" is to ask the client and print both. /gristle debug does that.
---------------------------------------------------------------------------------------------------

-- what one getter actually answers, as text: missing, threw, the wrong type, or a value
function GRISTLE.DescribeGetter( entity, getter )

	if entity == nil then
		return "no entity"
	end

	if entity[ getter ] == nil then
		return "no such member"
	end

	local ok, value = pcall( function() return entity[ getter ]( entity ) end )

	if not ok then
		return "threw: " .. tostring( value )
	end

	return tostring( value ) .. "  (" .. type( value ) .. ")"

end

function GRISTLE.DescribeColor( value )

	if value == nil then
		return "nil"
	end

	if getmetatable( value ) ~= nil then
		-- a real Turbine.UI.Color; its components are readable as fields
		return string.format( "Color %.2f %.2f %.2f",
			tonumber( value.R ) or -1, tonumber( value.G ) or -1, tonumber( value.B ) or -1 )
	end

	return string.format( "%.2f %.2f %.2f",
		tonumber( value.R ) or -1, tonumber( value.G ) or -1, tonumber( value.B ) or -1 )

end

---------------------------------------------------------------------------------------------------
-- name and level, for the name row
---------------------------------------------------------------------------------------------------
-- Wrapped the same way the vitals are, and for the same reason: GetName is on Entity so everything
-- targetable has it, but GetLevel is on Actor, so a chest or a door does not. An entity whose name
-- has not resolved yet answers an empty string rather than nil, so the row can render either way.
---------------------------------------------------------------------------------------------------

function GRISTLE.ReadName( entity )

	if entity == nil or entity.GetName == nil then
		return ""
	end

	local ok, name = pcall( function() return entity:GetName() end )

	if not ok or type( name ) ~= "string" then
		return ""
	end

	return name

end

-- nil for anything without a level, which the name row reads as "print nothing"
function GRISTLE.ReadLevel( entity )

	if entity == nil or entity.GetLevel == nil then
		return nil
	end

	local ok, level = pcall( function() return entity:GetLevel() end )

	if not ok or type( level ) ~= "number" or level <= 0 then
		return nil
	end

	return level

end

-- nil for anything that is not a player. GetClass lives on Player, not on Actor, so a monster or an
-- NPC has no such member at all; a creep in the Ettenmoors is a player and does. Whether the class
-- that comes back has an icon is the caller's question - this only reads it.
function GRISTLE.ReadClass( entity )

	if entity == nil or entity.GetClass == nil then
		return nil
	end

	local ok, class = pcall( function() return entity:GetClass() end )

	if not ok or type( class ) ~= "number" then
		return nil
	end

	return class

end
