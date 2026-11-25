--=================================================================================================
--= Gristle tests
--=
--= Run from the plugin root with a desktop Lua (the game ships 5.1):
--=
--=     cd Gristle && lua tests/run.lua
--=
--= NOT loaded by the game -- nothing imports tests/ from Main.lua, so the folder is inert in the
--= client. These cannot test drawing. They test the bar arithmetic, the bubble geometry, the
--= damage-flash trigger conditions, the dirty flags, the event plumbing and the savefile round
--= trip, which is where a regression would otherwise only show up mid-raid.
--=================================================================================================

local passed, failed = 0, 0

local function check( name, got, want )
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print( string.format( "  FAIL  %s\n          got:  %s\n          want: %s",
			name, tostring( got ), tostring( want ) ) )
	end
end

local function checkNear( name, got, want, tolerance )
	if type( got ) == "number" and math.abs( got - want ) <= ( tolerance or 0.0001 ) then
		passed = passed + 1
	else
		failed = failed + 1
		print( string.format( "  FAIL  %s\n          got:  %s\n          want: ~%s",
			name, tostring( got ), tostring( want ) ) )
	end
end

local function section( title )
	print( "\n" .. title )
end

---------------------------------------------------------------------------------------------------

local stub = dofile( "tests/turbine_stub.lua" )

-- "euro" runs the whole suite as a German/French client, where every number has to be stringified
-- on the way into the savefile and turned back on the way out. run_all.sh runs both.
local euro = ( ... ) == "euro" or arg ~= nil and arg[1] == "euro"

local player = stub.NewActor( { name = "Souru", morale = 1000, maxMorale = 1000,
                                power = 500, maxPower = 500, kind = "player", class = 24 } )

stub.Install( player, { euro = euro } )

print( euro and "=== German/French client ===" or "=== English client ===" )

---------------------------------------------------------------------------------------------------
section( "load" )
---------------------------------------------------------------------------------------------------

local ok, err = pcall( function() import( "Gristle.Main" ) end )

check( "Main.lua loads against the Turbine stub", ok, true )

if not ok then
	print( "          " .. tostring( err ) )
	print( "\naborting: nothing below can run" )
	os.exit( 1 )
end

check( "the self window was built",   GRISTLE.Self.window   ~= nil, true )
check( "the target window was built", GRISTLE.Target.window ~= nil, true )
check( "a load banner was printed",   #stub.lines > 0, true )

---------------------------------------------------------------------------------------------------
section( "defaults and clamping" )
---------------------------------------------------------------------------------------------------

check( "version stamped", GRISTLE.Settings.version, 4 )
check( "self width defaulted", GRISTLE.Settings.selfWidth, 260 )
check( "the target hairline is on by default", GRISTLE.Settings.targetShowPower, true )
check( "both name rows are on by default",
	GRISTLE.Settings.selfShowName and GRISTLE.Settings.targetShowName, true )
check( "colours are plain tables, not Color instances",
	getmetatable( GRISTLE.Settings.colorMorale ), nil )

-- the settings must not alias the shared palette, or editing one would edit the other
GRISTLE.Settings.colorMorale.R = 0.123
check( "settings do not alias GRISTLE.Palette", GRISTLE.Palette.morale.R, 0.22 )
GRISTLE.Settings.colorMorale.R = 0.22

-- deliberately invalid values, as a hand-edited savefile could contain
GRISTLE.Settings.selfWidth     = 0
GRISTLE.Settings.selfBarHeight = "banana"
GRISTLE.Settings.warnPercent   = 20
GRISTLE.Settings.dangerPercent = 90
GRISTLE.Settings.colorMorale   = "not a colour"
GRISTLE.Settings.opacity       = 99

GRISTLE.NormaliseSettings()

check( "a zero width is clamped up",        GRISTLE.Settings.selfWidth, 40 )
check( "a non-numeric height falls back",   GRISTLE.Settings.selfBarHeight, 34 )
check( "a broken colour falls back",        GRISTLE.Settings.colorMorale.G, 0.78 )
check( "an over-range opacity is clamped",  GRISTLE.Settings.opacity, 1.0 )
check( "danger is pushed below warn",       GRISTLE.Settings.dangerPercent < GRISTLE.Settings.warnPercent, true )

GRISTLE.Settings.nameFontSize = 99
GRISTLE.NormaliseSettings()
check( "an over-range name size is clamped", GRISTLE.Settings.nameFontSize, 23 )

---------------------------------------------------------------------------------------------------
-- the 1 -> 2 migration
---------------------------------------------------------------------------------------------------
-- filling in a missing key cannot deliver a changed default: a version 1 savefile already holds the
-- old value, so without the migration the target hairline would stay off forever on every existing
-- character

GRISTLE.Settings = { version = 1, targetShowPower = false, selfWidth = 300 }
GRISTLE.NormaliseSettings()

check( "a version 1 savefile has the target hairline turned on", GRISTLE.Settings.targetShowPower, true )
check( "and is restamped",                                      GRISTLE.Settings.version, 4 )
check( "while its own settings are left alone",                 GRISTLE.Settings.selfWidth, 300 )

-- but a deliberate choice made since must survive the next load
GRISTLE.Settings.targetShowPower = false
GRISTLE.NormaliseSettings()
check( "a current savefile is not migrated a second time", GRISTLE.Settings.targetShowPower, false )

---------------------------------------------------------------------------------------------------
-- the 3 -> 4 migration
---------------------------------------------------------------------------------------------------
-- The three readout switches became four templates per window. A switch that was on has to become
-- the template it used to produce, and a switch that was off has to become an empty one - clearing a
-- template is the only way a readout is turned off now, so "it was off" is not expressible any
-- other way.

GRISTLE.Settings = { version = 3, showValue = true, showPercent = true, showLevel = true }
GRISTLE.NormaliseSettings()

check( "a version 3 savefile keeps its absolute number",
	GRISTLE.Settings.selfFormatBarLeft, "[cur]  [temp]" )
check( "and its percentage",       GRISTLE.Settings.selfFormatBarRight, "[perc]" )
check( "and its name",             GRISTLE.Settings.selfFormatNameMain, "[name]" )
check( "and its level",            GRISTLE.Settings.selfFormatNameAside, "Level [level]" )
check( "the target frame too",     GRISTLE.Settings.targetFormatBarRight, "[perc]" )
check( "and the dead switches are gone", GRISTLE.Settings.showValue, nil )
check( "all three of them",
	GRISTLE.Settings.showPercent == nil and GRISTLE.Settings.showLevel == nil, true )

-- a switch that was off becomes a cleared template, not a defaulted one
GRISTLE.Settings = { version = 3, showValue = false, showPercent = true, showLevel = false }
GRISTLE.NormaliseSettings()

check( "a readout that was switched off comes through empty",
	GRISTLE.Settings.selfFormatBarLeft, "" )
check( "and a level that was switched off too",
	GRISTLE.Settings.targetFormatNameAside, "" )
check( "while the one that was on is kept",
	GRISTLE.Settings.selfFormatBarRight, "[perc]" )

-- and an emptied template must survive the next load rather than being refilled from the defaults
GRISTLE.NormaliseSettings()
check( "an empty template is not defaulted back", GRISTLE.Settings.selfFormatBarLeft, "" )

---------------------------------------------------------------------------------------------------
-- a hand-edited or euro savefile
---------------------------------------------------------------------------------------------------

GRISTLE.Settings = {}
GRISTLE.NormaliseSettings()

-- a German or French savefile turns anything that parses as a number back into one
GRISTLE.Settings.selfFormatBarLeft = 100
GRISTLE.NormaliseSettings()
check( "a numeric template is coerced to a string", GRISTLE.Settings.selfFormatBarLeft, "100" )

GRISTLE.Settings.selfFormatBarLeft = { "not a template" }
GRISTLE.NormaliseSettings()
check( "a template that is not text falls back",
	GRISTLE.Settings.selfFormatBarLeft, GRISTLE.Defaults.selfFormatBarLeft )

-- the one setting with no natural upper bound. The bar clips what does not fit, so an enormous
-- template would not be visible, only rendered.
GRISTLE.Settings.selfFormatBarLeft = string.rep( "[cur]", 200 )
GRISTLE.NormaliseSettings()
check( "an absurd template is capped", string.len( GRISTLE.Settings.selfFormatBarLeft ), 120 )

GRISTLE.Settings = {}
GRISTLE.NormaliseSettings()
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
section( "number formatting" )
---------------------------------------------------------------------------------------------------

check( "zero",            GRISTLE.FormatNumber( 0 ),       "0" )
check( "three digits",    GRISTLE.FormatNumber( 999 ),     "999" )
check( "four digits",     GRISTLE.FormatNumber( 1000 ),    "1,000" )
check( "five digits",     GRISTLE.FormatNumber( 12480 ),   "12,480" )
check( "seven digits",    GRISTLE.FormatNumber( 1234567 ), "1,234,567" )
check( "negative",        GRISTLE.FormatNumber( -1500 ),   "-1,500" )
check( "fractional down", GRISTLE.FormatNumber( 1000.9 ),  "1,000" )

check( "percent",          GRISTLE.FormatPercent( 500, 1000 ), "50%" )
check( "percent rounds",   GRISTLE.FormatPercent( 834, 1000 ), "83%" )
check( "percent, zero max", GRISTLE.FormatPercent( 10, 0 ),    "0%" )

check( "percent, one decimal",  GRISTLE.FormatPercent( 743, 1000, 1 ), "74.3%" )
check( "percent, two decimals", GRISTLE.FormatPercent( 743, 1000, 2 ), "74.30%" )
-- the decimal count comes out of a user-typed template, so [perc:9] has to land somewhere
check( "percent, decimals clamped", GRISTLE.FormatPercent( 743, 1000, 9 ), "74.30%" )
check( "percent, junk decimals",    GRISTLE.FormatPercent( 500, 1000, "x" ), "50%" )

---------------------------------------------------------------------------------------------------
-- the abbreviated form
---------------------------------------------------------------------------------------------------
-- The precision steps down as the number grows, and a trailing zero is dropped: 12.0k is not more
-- precise than 12k, it only looks it.

check( "short, below a thousand",   GRISTLE.FormatShort( 743 ),     "743" )
check( "short, exactly a thousand", GRISTLE.FormatShort( 1000 ),    "1k" )
check( "short, one decimal kept",   GRISTLE.FormatShort( 1500 ),    "1.5k" )
check( "short, five digits",        GRISTLE.FormatShort( 12480 ),   "12.5k" )
check( "short, trailing zero gone", GRISTLE.FormatShort( 12000 ),   "12k" )
check( "short, decimal dropped at six digits", GRISTLE.FormatShort( 243200 ), "243k" )
check( "short, millions",           GRISTLE.FormatShort( 1240000 ), "1.24M" )
check( "short, a round million",    GRISTLE.FormatShort( 1000000 ), "1M" )
check( "short, negative",           GRISTLE.FormatShort( -12480 ),  "-12.5k" )
check( "short, zero",               GRISTLE.FormatShort( 0 ),       "0" )

-- FormatValue is what a tag calls: the setting decides, unless the tag said otherwise
GRISTLE.Settings.abbreviateNumbers = false
check( "unabbreviated by default",   GRISTLE.FormatValue( 12480 ), "12,480" )
check( "a tag can force the short form", GRISTLE.FormatValue( 12480, "short" ), "12.5k" )

GRISTLE.Settings.abbreviateNumbers = true
check( "the setting abbreviates",    GRISTLE.FormatValue( 12480 ), "12.5k" )
check( "a tag can force the long form", GRISTLE.FormatValue( 12480, "full" ), "12,480" )

GRISTLE.Settings.abbreviateNumbers = false

---------------------------------------------------------------------------------------------------
section( "readout templates" )
---------------------------------------------------------------------------------------------------
-- Rendering is pure, so it is tested without a window in the way. The context is keyed by the same
-- names as the tags, which is the whole reason a tag cannot drift from the field it describes.

local ctx = {
	cur = 743, max = 1000, temp = 0, maxtemp = 0,
	pow = 250, maxpow = 500, name = "Souru", level = 150,
}

local render = GRISTLE.Format.Render

check( "a bare tag",       render( "[cur]", ctx ),    "743" )
check( "its maximum",      render( "[max]", ctx ),    "1,000" )
check( "a percentage",     render( "[perc]", ctx ),   "74%" )
check( "with a decimal",   render( "[perc:1]", ctx ), "74.3%" )
check( "the name",         render( "[name]", ctx ),   "Souru" )
check( "the bare level",   render( "[level]", ctx ),  "150" )
check( "literal text around a tag", render( "Level [level]", ctx ), "Level 150" )
check( "two tags",         render( "[cur] / [max]", ctx ), "743 / 1,000" )
check( "text with no tags at all is literal", render( "morale", ctx ), "morale" )
check( "an empty template", render( "", ctx ), "" )
check( "a nil template",    render( nil, ctx ), "" )

-- power, which is the one reading that has nowhere else to go: the hairline is four pixels tall
check( "power",               render( "[pow]", ctx ),     "250" )
check( "maximum power",       render( "[maxpow]", ctx ),  "500" )
check( "power as a percentage", render( "[powperc]", ctx ), "50%" )

-- the deficit, blank at full
check( "the deficit",            render( "[deficit]", ctx ), "-257" )
check( "the deficit is blank at full",
	render( "[deficit]", { cur = 1000, max = 1000 } ), "" )

-- the bubble carries its own plus sign and disappears with the bubble
check( "no bubble renders as nothing", render( "[temp]", ctx ), "" )
check( "a bubble carries its plus",
	render( "[temp]", { temp = 125, maxtemp = 250 } ), "+125" )
check( "the bubble's maximum",
	render( "[maxtemp]", { temp = 125, maxtemp = 250 } ), "250" )

-- the collapse rule, which is what makes a template behave on a HUD
check( "the padding around an empty tag goes with it",
	render( "[cur]  [temp]", ctx ), "743" )
check( "and comes back with the bubble",
	render( "[cur]  [temp]", { cur = 1000, max = 1000, temp = 125, maxtemp = 250 } ),
	"1,000  +125" )
check( "a line whose every tag is empty is dropped entirely",
	render( "Level [level]", { name = "Chest" } ), "" )
check( "but one filled tag keeps the line",
	render( "Level [level] of [name]", ctx ), "Level 150 of Souru" )
check( "a tag that cannot read anything is empty",
	render( "[cur]", {} ), "" )

-- modifiers
check( "a modifier on a tag",      render( "[cur:short]", ctx ), "743" )
check( "and on a bigger number",   render( "[max:short]", ctx ), "1k" )
check( "tags are case insensitive", render( "[CUR]", ctx ), "743" )

-- a typo has to be visible. This game has no log file, so a tag that silently rendered as nothing
-- would look exactly like a tag that correctly had nothing to say.
check( "an unknown tag is handed back as typed", render( "[morale]", ctx ), "[morale]" )
check( "and keeps the line from collapsing",
	render( "[morale] [temp]", ctx ), "[morale]" )
check( "an unclosed bracket is left alone", render( "[cur", ctx ), "[cur" )

-- a German or French savefile turns anything that parses as a number back into one
check( "a numeric template still renders", render( 100, ctx ), "100" )

---------------------------------------------------------------------------------------------------
section( "morale bar arithmetic" )
---------------------------------------------------------------------------------------------------

local selfWindow = GRISTLE.Self.window
local bar = selfWindow.moraleBar

check( "bar laid out at the configured width", bar.width, 260 )

player:SetMorale( 1000 )
check( "full morale fills the bar", bar.fill:GetWidth(), 260 )

player:SetMorale( 500 )
check( "half morale is half the bar", bar.fill:GetWidth(), 130 )

player:SetMorale( 1 )
check( "one morale is a sliver, not zero", bar.fill:GetWidth(), 0 )

player:SetMorale( 0 )
check( "dead is empty", bar.fill:GetWidth(), 0 )

-- values the engine should never send, but a bad max would crash the division
player:SetMorale( 5000 )
check( "morale above max is clamped", bar.fill:GetWidth(), 260 )

player.morale = -50
player:Fire( "MoraleChanged" )
check( "negative morale is clamped", bar.fill:GetWidth(), 0 )

player:SetMorale( 1000 )

---------------------------------------------------------------------------------------------------
section( "everything the bar draws is actually on screen" )
---------------------------------------------------------------------------------------------------
-- The engine creates a Window hidden and a Control visible. The fill and the readout both live
-- inside Windows, for the clipping, so a Window left at its default is a bar that computes a
-- perfectly correct full-width fill and draws none of it. That is exactly what happened: in the
-- client the morale bar reported a 280px green fill and a '532,088' readout over an empty track,
-- while the power hairline beside it worked -- because the window layout calls SetVisible on the
-- power bar explicitly and never did on the morale bar.
--
-- A control is only really on screen if every parent above it is too, which is what this walks.

local function effectivelyVisible( control )

	while control ~= nil do
		if not control:IsVisible() then return false end
		control = control:GetParent()
	end

	return true

end

player:SetMorale( 1000 )

check( "the morale fill is on screen",  effectivelyVisible( bar.fill ), true )
check( "its clipping window is shown",  bar.clip:IsVisible(), true )
check( "the readout is on screen",      effectivelyVisible( bar.valueLabel ), true )
check( "its label window is shown",     bar.labelBack:IsVisible(), true )
check( "the percentage too",            effectivelyVisible( bar.pctLabel ), true )
check( "and the track behind them",     effectivelyVisible( bar.track ), true )

-- the bubble and the flash segments share the same clipping window, so they ride on the same fix
check( "the bubble can be drawn",       effectivelyVisible( bar.temp ) or not bar.temp:IsVisible(), true )

-- the name row is a clipping window too
check( "the name row is on screen",
	effectivelyVisible( selfWindow.nameRow.nameLabel ), true )

-- and the same for the target frame, which is the one that is hidden and shown constantly
local onScreen = stub.NewActor( { name = "Visible", morale = 50, maxMorale = 100, kind = "monster" } )
player:SetTarget( onScreen )

check( "the target's fill is on screen",
	effectivelyVisible( GRISTLE.Target.window.moraleBar.fill ), true )
check( "and its readout",
	effectivelyVisible( GRISTLE.Target.window.moraleBar.valueLabel ), true )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "labels" )
---------------------------------------------------------------------------------------------------

player:SetMorale( 743 )
check( "value label shows the absolute number", bar.valueLabel:GetText(), "743" )
check( "percent label shows the percentage",    bar.pctLabel:GetText(),   "74%" )

-- the dirty flag: pushing the same value again must not touch the label
local before = stub.Counted( bar.valueLabel, "SetText" )
player:Fire( "MoraleChanged" )
player:Fire( "MoraleChanged" )
player:Fire( "MoraleChanged" )
check( "an unchanged value does not re-set the text",
	stub.Counted( bar.valueLabel, "SetText" ), before )

local widthBefore = stub.Counted( bar.fill, "SetWidth" )
player:Fire( "MoraleChanged" )
check( "an unchanged value does not re-set the width",
	stub.Counted( bar.fill, "SetWidth" ), widthBefore )

-- clearing a template is how a readout is turned off: there is no separate switch, because an empty
-- template and a switched-off readout are the same thing
GRISTLE.Settings.selfFormatBarLeft = ""
GRISTLE.Settings.selfFormatBarRight = ""
player:SetMorale( 742 )
check( "clearing a template drops that readout", bar.valueLabel:GetText(), "" )
check( "and the other one with it",              bar.pctLabel:GetText(),   "" )

GRISTLE.Settings.selfFormatBarLeft  = GRISTLE.Defaults.selfFormatBarLeft
GRISTLE.Settings.selfFormatBarRight = GRISTLE.Defaults.selfFormatBarRight
player:SetMorale( 1000 )

---------------------------------------------------------------------------------------------------
-- a template is free of where it sits
---------------------------------------------------------------------------------------------------
-- The context lives on the window and both widgets render against it, so a tag works wherever it is
-- typed. The case that justifies the indirection is power inside the morale bar: the hairline is
-- four pixels tall, so without this there is no way to see a power number at all.

player:SetMorale( 743 )
player:SetPowerValue( 250 )

GRISTLE.Settings.selfFormatBarLeft  = "[cur]  [pow]"
GRISTLE.Settings.selfFormatBarRight = "[powperc]"
GRISTLE.ApplyFormats()

check( "power can be read inside the morale bar", bar.valueLabel:GetText(), "743  250" )
check( "and as a percentage",                     bar.pctLabel:GetText(),   "50%" )

-- and the other way round: a vital on the name row, which holds no data of its own
GRISTLE.Settings.selfFormatNameMain  = "[name]"
GRISTLE.Settings.selfFormatNameAside = "[perc]"
GRISTLE.ApplyFormats()

check( "a vital can be read on the name row",
	GRISTLE.Self.window.nameRow.extraLabel:GetText(), "74%" )

-- a morale event has to reach the name row now that its template can name a vital
player:SetMorale( 500 )
check( "a morale change reaches the name row",
	GRISTLE.Self.window.nameRow.extraLabel:GetText(), "50%" )

-- a power event has to reach the morale bar for the same reason
player:SetPowerValue( 125 )
check( "a power change reaches the morale bar", bar.pctLabel:GetText(), "25%" )

-- the hairline can be off while a template still names power
GRISTLE.Settings.selfShowPower = false
GRISTLE.ApplyAll()
player:SetPowerValue( 500 )
check( "power still reads with the hairline switched off", bar.pctLabel:GetText(), "100%" )

GRISTLE.Settings.selfShowPower = true

-- the deficit, in the place it is actually useful
GRISTLE.Settings.selfFormatBarRight = "[deficit]"
player:SetMorale( 1000 )
check( "the deficit is blank at full morale", bar.pctLabel:GetText(), "" )

player:SetMorale( 743 )
check( "and appears the moment something is missing", bar.pctLabel:GetText(), "-257" )

-- the abbreviation setting reaches a live readout without a relayout
GRISTLE.Settings.selfFormatBarLeft = "[cur]"
player:SetMaxMorale( 20000 )
player:SetMorale( 12480 )
check( "unabbreviated to begin with", bar.valueLabel:GetText(), "12,480" )

GRISTLE.Settings.abbreviateNumbers = true
GRISTLE.ApplyFormats()
check( "abbreviating is live",        bar.valueLabel:GetText(), "12.5k" )

GRISTLE.Settings.abbreviateNumbers = false
GRISTLE.ApplyFormats()
check( "and reversible",              bar.valueLabel:GetText(), "12,480" )

-- ApplyFormats must not do what ApplyAll does: a relayout clears every dirty-flag cache and blanks
-- the bars until the next vital event, which for your own morale at full health is a long way off
local fillBefore = bar.fill:GetWidth()
GRISTLE.ApplyFormats()
check( "re-rendering does not disturb the fill", bar.fill:GetWidth(), fillBefore )

-- and the dirty flag still holds through it
local textBefore = stub.Counted( bar.valueLabel, "SetText" )
GRISTLE.ApplyFormats()
GRISTLE.ApplyFormats()
check( "an unchanged render does not re-set the text",
	stub.Counted( bar.valueLabel, "SetText" ), textBefore )

player:SetMaxMorale( 1000 )
player:SetMorale( 1000 )
player:SetPowerValue( 500 )

GRISTLE.Settings.selfFormatBarLeft    = GRISTLE.Defaults.selfFormatBarLeft
GRISTLE.Settings.selfFormatBarRight   = GRISTLE.Defaults.selfFormatBarRight
GRISTLE.Settings.selfFormatNameMain   = GRISTLE.Defaults.selfFormatNameMain
GRISTLE.Settings.selfFormatNameAside  = GRISTLE.Defaults.selfFormatNameAside
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
section( "temporary morale (bubble)" )
---------------------------------------------------------------------------------------------------

-- a bubble worth a quarter of max morale takes a quarter off the right of the track
player:SetBubble( 250, 250 )

check( "the morale fill is confined to the remaining 75%", bar.fill:GetWidth(), 195 )
check( "the bubble is visible",                            bar.temp:IsVisible(), true )
check( "the bubble starts where the morale bar ends",      bar.temp:GetLeft(),   195 )
check( "a full bubble fills its slice",                    bar.temp:GetWidth(),  65 )

-- half the bubble spent
player:SetBubble( 125, 250 )
check( "a half bubble is half its slice", bar.temp:GetWidth(), 32 )

check( "the value label shows the bubble too", bar.valueLabel:GetText(), "1,000  +125" )

-- an absurd bubble must not squeeze the morale bar out of existence
player:SetBubble( 4000, 4000 )
check( "an oversized bubble is capped at half the bar", bar.fill:GetWidth(), 130 )

player:SetBubble( 0, 0 )
check( "the bubble goes away",              bar.temp:IsVisible(), false )
check( "the morale bar takes the width back", bar.fill:GetWidth(), 260 )

---------------------------------------------------------------------------------------------------
section( "threshold colouring" )
---------------------------------------------------------------------------------------------------

player:SetMorale( 1000 )
check( "healthy is the normal colour", bar.fill:GetBackColor().G, GRISTLE.Settings.colorMorale.G )

player:SetMorale( 400 )   -- below the 50% warn line
check( "below warn is the warn colour", bar.fill:GetBackColor().G, GRISTLE.Settings.colorMoraleWarn.G )

player:SetMorale( 200 )   -- below the 25% danger line
check( "below danger is the danger colour", bar.fill:GetBackColor().G, GRISTLE.Settings.colorMoraleDanger.G )

-- a band is applied once on entry, not on every update
local colorBefore = stub.Counted( bar.fill, "SetBackColor" )
player:SetMorale( 190 )
player:SetMorale( 180 )
player:SetMorale( 170 )
check( "staying in a band does not re-set the colour",
	stub.Counted( bar.fill, "SetBackColor" ), colorBefore )

player:SetMorale( 1000 )
check( "recovering returns to the normal colour", bar.fill:GetBackColor().G, GRISTLE.Settings.colorMorale.G )

-- the power bar must never threshold-colour: running low on power is not an emergency
local powerBar = selfWindow.powerBar
player:SetPowerValue( 10 )
check( "the power bar keeps its colour when low",
	powerBar.fill:GetBackColor().B, GRISTLE.Settings.colorPower.B )
player:SetPowerValue( 500 )

---------------------------------------------------------------------------------------------------
section( "incoming damage flash" )
---------------------------------------------------------------------------------------------------

local function visibleFlashes( b )
	local n = 0
	for i = 1, #b.flashes do
		if b.flashes[i].control:IsVisible() then n = n + 1 end
	end
	return n
end

bar:Reset()
player:SetMorale( 1000 )
check( "the first value never flashes", visibleFlashes( bar ), 0 )

player:SetMorale( 600 )
check( "taking damage spawns one flash", visibleFlashes( bar ), 1 )

local flash = nil
for i = 1, #bar.flashes do
	if bar.flashes[i].control:IsVisible() then flash = bar.flashes[i].control end
end

check( "the flash starts where the bar now ends", flash:GetLeft(), 156 )
check( "the flash covers exactly the morale lost", flash:GetWidth(), 260 - 156 )

-- healing must not flash
local countBefore = visibleFlashes( bar )
player:SetMorale( 800 )
check( "healing does not spawn a flash", visibleFlashes( bar ), countBefore )

-- the fade decays and then clears
stub.Tick( 0.1 )
check( "the flash is fading", flash:GetOpacity() < 1, true )
stub.Tick( 0.4 )
check( "the flash is gone once its duration elapses", flash:IsVisible(), false )

-- four hits in a row each get their own segment
bar:Reset()
player:SetMorale( 1000 )
player:SetMorale( 900 )
player:SetMorale( 800 )
player:SetMorale( 700 )
check( "overlapping hits each get a segment", visibleFlashes( bar ), 3 )

-- the pool is finite and must recycle rather than run out
player:SetMorale( 600 )
player:SetMorale( 500 )
player:SetMorale( 400 )
check( "the pool caps at its size instead of erroring", visibleFlashes( bar ) <= GRISTLE.FlashPool, true )

-- a max morale change rescales the bar; that is not damage
bar:Reset()
player:SetMorale( 1000 )
player:SetMaxMorale( 2000 )
check( "a max morale change does not flash", visibleFlashes( bar ), 0 )
player:SetMaxMorale( 1000 )

-- a bubble appearing shrinks the fill; that is not damage either
bar:Reset()
player:SetMorale( 1000 )
player:SetBubble( 250, 250 )
check( "a bubble appearing does not flash", visibleFlashes( bar ), 0 )
player:SetBubble( 0, 0 )

-- and it can be turned off
bar:Reset()
GRISTLE.Settings.flash = false
player:SetMorale( 1000 )
player:SetMorale( 500 )
check( "the flash can be disabled", visibleFlashes( bar ), 0 )
GRISTLE.Settings.flash = true

---------------------------------------------------------------------------------------------------
section( "power hairline" )
---------------------------------------------------------------------------------------------------

player:SetPowerValue( 250 )
check( "half power is half the hairline", powerBar.fill:GetWidth(), 130 )
check( "the hairline is as thin as configured", powerBar.height, GRISTLE.Settings.selfPowerHeight )
check( "the hairline carries no labels", powerBar.valueLabel, nil )
check( "the hairline sits below the morale bar", powerBar.y > bar.y, true )

GRISTLE.Settings.selfShowPower = false
GRISTLE.ApplyAll()
check( "the hairline can be switched off", powerBar.track:IsVisible(), false )

GRISTLE.Settings.selfShowPower = true
GRISTLE.ApplyAll()
check( "and back on", powerBar.track:IsVisible(), true )

---------------------------------------------------------------------------------------------------
section( "target tracking" )
---------------------------------------------------------------------------------------------------

local targetWindow = GRISTLE.Target.window

check( "no target means a hidden window", targetWindow.window:IsVisible(), false )

local orc = stub.NewActor( { name = "Orc", morale = 8000, maxMorale = 10000, kind = "monster" } )
player:SetTarget( orc )

check( "targeting a monster shows the window", targetWindow.window:IsVisible(), true )
check( "and fills the bar to its morale",      targetWindow.moraleBar.fill:GetWidth(),
	math.floor( 8000 / 10000 * 260 ) )
check( "and reads out the percentage",         targetWindow.moraleBar.pctLabel:GetText(), "80%" )

orc:SetMorale( 5000 )
check( "the target's morale is tracked live", targetWindow.moraleBar.fill:GetWidth(), 130 )

-- the target frame is the player's reflected: its bar fills from the right and drains towards it
do
	local tbar = targetWindow.moraleBar

	check( "the target's fill hugs the right-hand end",
		tbar.fill:GetLeft() + tbar.fill:GetWidth(), tbar.width )
	check( "the player's fill still starts at the left", bar.fill:GetLeft(), 0 )

	local before = tbar.fill:GetLeft()
	orc:SetMorale( 2500 )

	local hit = nil
	for i = 1, #tbar.flashes do
		if tbar.flashes[i].control:IsVisible() then hit = tbar.flashes[i].control end
	end

	check( "the target's flash is the strip just lost, on the left of the fill",
		hit ~= nil and hit:GetLeft(), before )
	check( "and ends where the fill now begins",
		hit ~= nil and hit:GetLeft() + hit:GetWidth(), tbar.fill:GetLeft() )

	local warnTick = tbar.ticks[1].control
	check( "the warn mark is measured from the right",
		warnTick:GetLeft(), tbar.width - 1 - math.floor( tbar.width * GRISTLE.Settings.warnPercent / 100 ) )

	-- the bubble sits at the far end from where the fill starts: the left
	orc:SetBubble( 2500, 2500 )
	check( "the target's bubble shows",         tbar.temp:IsVisible(), true )
	check( "and is parked at the left-hand end", tbar.temp:GetLeft(), 0 )
	check( "and fills the quarter the morale gave up", tbar.temp:GetWidth(), tbar.width - tbar._lastBarWidth )

	-- half spent: from the right, the bubble still has to touch the morale slice, so its left edge moves
	orc:SetBubble( 1250, 2500 )
	check( "a half-spent bubble still meets the morale slice",
		tbar.temp:GetLeft() + tbar.temp:GetWidth(), tbar.width - tbar._lastBarWidth )

	orc:SetBubble( 0, 0 )
	orc:SetMorale( 5000 )
end

-- a chest has no GetMorale at all. The frame stays up with its name over an empty background --
-- what you have selected is worth seeing -- but there is nothing to report inside it.
local chest = stub.NewActor( { name = "Chest", kind = "object" } )
chest.GetMorale = nil
chest.GetMaxMorale = nil

player:SetTarget( chest )

check( "targeting an object keeps the frame", targetWindow.window:IsVisible(), true )
check( "and shows its name",                  targetWindow.nameRow.nameLabel:GetText(), "Chest" )
check( "the background is still drawn",       targetWindow.moraleBar.track:IsVisible(), true )
check( "but the fill is not",                 targetWindow.moraleBar.clip:IsVisible(), false )
check( "nor the readout",                     targetWindow.moraleBar.labelBack:IsVisible(), false )
-- both bars go blank together, so an object shows the same empty two-bar frame a creature does
check( "the power background is drawn too",   targetWindow.powerBar.track:IsVisible(), true )
check( "but the power has no fill",           targetWindow.powerBar.clip:IsVisible(), false )
check( "an object has no level to show",      targetWindow.nameRow.extraLabel:GetText(), "" )

-- and the old target must have been let go
orc:SetMorale( 1 )
check( "the dropped target no longer drives the bar", GRISTLE.Target.entity, chest )
check( "and its handlers are gone",                   orc.MoraleChanged, nil )

-- targeting something with vitals again brings the bar straight back
orc:SetMorale( 5000 )
player:SetTarget( orc )
check( "the fill comes back",    targetWindow.moraleBar.clip:IsVisible(), true )
check( "the readout comes back", targetWindow.moraleBar.labelBack:IsVisible(), true )
check( "and it is filled",       targetWindow.moraleBar.fill:GetWidth(), 130 )
check( "with its readout",       targetWindow.moraleBar.pctLabel:GetText(), "50%" )
check( "the power fill comes back too", targetWindow.powerBar.clip:IsVisible(), true )
check( "and it is filled",              targetWindow.powerBar.fill:GetWidth(), 260 )

---------------------------------------------------------------------------------------------------
-- the two frames have their own templates
---------------------------------------------------------------------------------------------------
-- Per window rather than shared, unlike the font sizes: your own morale is the number you act on
-- and a target's is usually only a percentage, and that is the one question the three switches these
-- replaced could not answer.

GRISTLE.Settings.targetFormatBarLeft  = "[perc]"
GRISTLE.Settings.targetFormatBarRight = "[cur] / [max]"
GRISTLE.ApplyFormats()

check( "the target bar uses its own templates",
	targetWindow.moraleBar.valueLabel:GetText(), "50%" )
check( "both of them",
	targetWindow.moraleBar.pctLabel:GetText(), "5,000 / 10,000" )
-- tested by shape rather than by value: the player's morale at this point in the suite is whatever
-- the sections above left it at, and what matters is that it is still rendering its own template
check( "and the player bar did not take the target's percentage",
	string.find( GRISTLE.Self.window.moraleBar.valueLabel:GetText(), "%%" ), nil )

---------------------------------------------------------------------------------------------------
-- a target swap cannot leave the old one's numbers on screen
---------------------------------------------------------------------------------------------------
-- The context is cleared on every swap. Without that, a template naming a vital would print the
-- previous target's morale over the new one's bar until a fresh reading arrived - which for anything
-- you are not fighting is never.

player:SetTarget( nil )

check( "losing the target clears the readout",
	targetWindow.moraleBar.valueLabel:GetText(), "" )
check( "and the other one",
	targetWindow.moraleBar.pctLabel:GetText(), "" )
check( "and the context behind them", targetWindow.context.cur, nil )

-- an object has no vitals at all, so its context must not carry the last monster's
player:SetTarget( orc )
player:SetTarget( chest )

check( "an object inherits no morale from the target before it", targetWindow.context.cur, nil )
check( "but it does report its name",                            targetWindow.context.name, "Chest" )

player:SetTarget( orc )

GRISTLE.Settings.targetFormatBarLeft  = GRISTLE.Defaults.targetFormatBarLeft
GRISTLE.Settings.targetFormatBarRight = GRISTLE.Defaults.targetFormatBarRight
GRISTLE.ApplyFormats()

player:SetTarget( nil )
check( "clearing the target hides the window", targetWindow.window:IsVisible(), false )

-- swapping between two live targets must not leak a handler
local a = stub.NewActor( { name = "A", morale = 100, maxMorale = 100, kind = "monster" } )
local b = stub.NewActor( { name = "B", morale = 50,  maxMorale = 100, kind = "monster" } )

player:SetTarget( a )
player:SetTarget( b )

check( "the new target is attached", GRISTLE.Target.entity, b )
check( "the old target was detached", a.MoraleChanged, nil )
check( "the bar shows the new target", targetWindow.moraleBar.fill:GetWidth(), 130 )

-- a target swap must not read as damage
check( "a target swap does not flash", visibleFlashes( targetWindow.moraleBar ), 0 )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "the target's power hairline" )
---------------------------------------------------------------------------------------------------
-- on by default since version 2. The interesting case is a target that reports no power at all,
-- which is most of the monsters in the game: the hairline has to take itself off screen rather than
-- sit there as an empty track or keep the previous target's reading.

local targetPower = targetWindow.powerBar

local caster = stub.NewActor( { name = "Caster", morale = 1000, maxMorale = 1000,
                                power = 300, maxPower = 600, kind = "monster" } )

player:SetTarget( caster )

check( "a target with power shows the hairline", targetPower.track:IsVisible(), true )
check( "and fills it to its power",              targetPower.fill:GetWidth(), 130 )
check( "the hairline is as thin as configured",  targetPower.height, GRISTLE.Settings.targetPowerHeight )

caster:SetPowerValue( 600 )
check( "the target's power is tracked live", targetPower.fill:GetWidth(), 260 )

-- a bear: no power member at all, the way the engine reports most monsters
local bear = stub.NewActor( { name = "Bear", morale = 4000, maxMorale = 4000, kind = "monster" } )
bear.GetPower = nil
bear.GetMaxPower = nil

player:SetTarget( bear )

check( "a target with no power hides the hairline", targetPower.track:IsVisible(), false )
check( "but keeps its morale bar",                  targetWindow.moraleBar.track:IsVisible(), true )
check( "and the window itself",                     targetWindow.window:IsVisible(), true )

-- the window must not resize, or the HUD jumps every time you tab between a caster and a bear
local steadyHeight = targetWindow.window:GetHeight()
player:SetTarget( caster )
check( "a powered target brings the hairline back", targetPower.track:IsVisible(), true )
check( "and the window never changed height",       targetWindow.window:GetHeight(), steadyHeight )

-- a target reporting zero max power counts as having none
local husk = stub.NewActor( { name = "Husk", morale = 500, maxMorale = 500,
                              power = 0, maxPower = 0, kind = "monster" } )
player:SetTarget( husk )
check( "a zero max power counts as no power", targetPower.track:IsVisible(), false )

-- from an object, whose empty frame shows both tracks, to a creature with no power: the power
-- track must still go. SetPower decides from the real reading, not from the blank frame.
local crate = stub.NewActor( { name = "Crate", kind = "object" } )
crate.GetMorale = nil
crate.GetMaxMorale = nil
player:SetTarget( crate )
check( "an object shows the empty power track", targetPower.track:IsVisible(), true )
player:SetTarget( bear )
check( "a powerless creature after it drops the track", targetPower.track:IsVisible(), false )
check( "and keeps its morale",                          targetWindow.moraleBar.clip:IsVisible(), true )

GRISTLE.Settings.targetShowPower = false
GRISTLE.ApplyAll()
player:SetTarget( caster )
check( "the setting still wins over an available power", targetPower.track:IsVisible(), false )

GRISTLE.Settings.targetShowPower = true
GRISTLE.ApplyAll()
check( "and turning it back on restores the hairline", targetPower.track:IsVisible(), true )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "the name row" )
---------------------------------------------------------------------------------------------------

local selfName = selfWindow.nameRow

check( "the player's name is on the row",  selfName.nameLabel:GetText(), "Souru" )
check( "and their level beside it",        selfName.extraLabel:GetText(), "Level 100" )

-- the row is a text row, so its height follows its own font rather than a setting of its own
check( "the row height follows the name font", GRISTLE.NameHeight(), GRISTLE.Settings.nameFontSize + 4 )

-- and it pushes the bars down rather than lifting itself above where they already were
check( "the morale bar sits below the row",
	bar.y, GRISTLE.NameRowHeight( "selfShowClassIcon" ) + GRISTLE.Settings.selfGap )

-- gap 0 shares one border line between morale and power instead of drawing two side by side
do
	local savedGap, savedBorder = GRISTLE.Settings.selfGap, GRISTLE.Settings.showBorder
	local power = selfWindow.powerBar

	GRISTLE.Settings.showBorder = true
	GRISTLE.Settings.selfGap = 0
	GRISTLE.ApplyAll()
	check( "at gap 0 the power bar's top border overlays the morale bar's bottom border",
		power.y, bar.y + bar.height + GRISTLE.Border )
	local _, windowHeight = selfWindow.window:GetSize()
	check( "and the window is one border shorter for it",
		windowHeight, power.y + power.height + 2 * GRISTLE.Border )

	GRISTLE.Settings.selfGap = 3
	GRISTLE.ApplyAll()
	check( "a non-zero gap still separates the two borders",
		power.y, bar.y + bar.height + 2 * GRISTLE.Border + 3 )

	GRISTLE.Settings.showBorder = false
	GRISTLE.Settings.selfGap = 0
	GRISTLE.ApplyAll()
	check( "without a border, gap 0 butts the bars together",
		power.y, bar.y + bar.height )

	GRISTLE.Settings.selfGap, GRISTLE.Settings.showBorder = savedGap, savedBorder
	GRISTLE.ApplyAll()
end

-- clipped, not wrapped: a name longer than the bar is cut off at the end of the bar
check( "the row is clipped to the bar's width",
	selfName.clip:GetWidth(), GRISTLE.Settings.selfWidth - 2 * GRISTLE.LabelPadding )

-- the dirty flag, as everywhere else
local nameBefore = stub.Counted( selfName.nameLabel, "SetText" )
GRISTLE.Self.RefreshName()
GRISTLE.Self.RefreshName()
check( "an unchanged name does not re-set the text",
	stub.Counted( selfName.nameLabel, "SetText" ), nameBefore )

GRISTLE.Settings.selfFormatNameAside = ""
GRISTLE.Self.RefreshName()
check( "clearing the aside template drops the level", selfName.extraLabel:GetText(), "" )

-- and the word in front of the number is the player's, which is the one bit of localisation Gristle
-- needs: a German client wants "Stufe 150"
GRISTLE.Settings.selfFormatNameAside = "Stufe [level]"
GRISTLE.Self.RefreshName()
check( "the label beside the level is the template's", selfName.extraLabel:GetText(), "Stufe 100" )

GRISTLE.Settings.selfFormatNameAside = GRISTLE.Defaults.selfFormatNameAside
GRISTLE.Self.RefreshName()
check( "and back on", selfName.extraLabel:GetText(), "Level 100" )

GRISTLE.Settings.selfShowName = false
GRISTLE.ApplyAll()

check( "the row can be switched off",            selfName.clip:IsVisible(), false )
check( "and the morale bar takes the top back",  bar.y, 0 )

GRISTLE.Settings.selfShowName = true
GRISTLE.ApplyAll()
check( "and switched back on", selfName.clip:IsVisible(), true )
check( "the name survives a relayout", selfName.nameLabel:GetText(), "Souru" )

-- the row has to be click-through like everything else Gristle draws
check( "the row is click-through",  selfName.clip:IsMouseVisible(), false )
check( "the name label too",        selfName.nameLabel:IsMouseVisible(), false )
check( "the level label too",       selfName.extraLabel:IsMouseVisible(), false )

---------------------------------------------------------------------------------------------------
-- the target's name row
---------------------------------------------------------------------------------------------------

local targetName = targetWindow.nameRow

player:SetTarget( caster )
check( "the target's name is on its row", targetName.nameLabel:GetText(), "Caster" )
check( "with its level",                  targetName.extraLabel:GetText(), "Level 100" )

player:SetTarget( bear )
check( "swapping target replaces the name", targetName.nameLabel:GetText(), "Bear" )

-- a rename has to reach the row without a target swap
bear.name = "Angry Bear"
bear:Fire( "NameChanged" )
check( "a rename reaches the row", targetName.nameLabel:GetText(), "Angry Bear" )

-- and so does a level change
bear.GetLevel = function() return 42 end
bear:Fire( "LevelChanged" )
check( "a level change reaches the row", targetName.extraLabel:GetText(), "Level 42" )

-- the name must not outlive the target it describes
player:SetTarget( nil )
check( "losing the target clears the name",  targetName.nameLabel:GetText(), "" )
check( "and the level with it",              targetName.extraLabel:GetText(), "" )

-- no GetLevel means an object rather than an Actor, whatever else it appears to report, so it gets
-- the frame-and-name treatment rather than a morale bar. This is the gate VitalTarget uses.
local levelless = stub.NewActor( { name = "Thing", morale = 10, maxMorale = 10, kind = "monster" } )
levelless.GetLevel = nil
player:SetTarget( levelless )

check( "a target with no level is treated as an object",
	targetWindow.moraleBar.clip:IsVisible(), false )
check( "but its name is still shown", targetName.nameLabel:GetText(), "Thing" )
check( "and the frame stays up",      targetWindow.window:IsVisible(), true )

-- but a level that merely fails to read prints nothing and leaves the name alone
local hidden = stub.NewActor( { name = "Thing", morale = 10, maxMorale = 10, kind = "monster" } )
hidden.GetLevel = function() error( "not ready" ) end
player:SetTarget( hidden )
check( "an unreadable level still shows the name", targetName.nameLabel:GetText(), "Thing" )
check( "and prints no level",                      targetName.extraLabel:GetText(), "" )

-- an entity whose name has not resolved yet
local unnamed = stub.NewActor( { name = "X", morale = 10, maxMorale = 10, kind = "monster" } )
unnamed.GetName = nil
player:SetTarget( unnamed )
check( "a nameless target reads as empty, not nil", targetName.nameLabel:GetText(), "" )

check( "ReadName of nil is an empty string", GRISTLE.ReadName( nil ), "" )
check( "ReadLevel of nil is nil",            GRISTLE.ReadLevel( nil ), nil )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "class icons" )
---------------------------------------------------------------------------------------------------

local Class = Turbine.Gameplay.Class

check( "a known class has an emblem",            GRISTLE.ClassIcons[ Class.Captain ], 0x41007DE7 )
check( "a creep class has one too",              GRISTLE.ClassIcons[ Class.Reaver ],  0x41007DED )
-- the stub's enum names five classes and has no Hunter: a class the client does not know must be
-- skipped at load, not turned into a nil key that throws
do
	local n = 0
	for _ in pairs( GRISTLE.ClassIcons ) do n = n + 1 end
	check( "only classes the client knows get an entry", n, 5 )
end

check( "ReadClass of nil is nil",                GRISTLE.ReadClass( nil ), nil )
check( "ReadClass of the player",                GRISTLE.ReadClass( player ), Class.Captain )

local selfIcon = selfName.icon
local ICON = GRISTLE.ClassIconSize
local border = GRISTLE.Settings.showBorder and GRISTLE.Border or 0

GRISTLE.Self.RefreshName()
check( "the player's class icon is shown",       selfIcon:IsVisible(), true )
check( "and it is the captain emblem",           selfIcon:GetBackground(), 0x41007DE7 )
check( "it is drawn at the art's own size",      selfIcon:GetWidth(), ICON )
check( "and as tall",                            selfIcon:GetHeight(), ICON )
check( "it is click-through",                    selfIcon:IsMouseVisible(), false )

-- scaling was tried in game and drew the emblem tiled through the clip: no stretch mode, no edge
-- attachments, and not inside the clip window
check( "no stretch mode is ever set",            selfIcon:GetStretchMode(), nil )
check( "no edge attachments",                    selfIcon:GetEdges(), nil )
check( "the icon is not inside the clip",        selfIcon:GetParent() ~= selfName.clip, true )

-- the row is grown to the icon rather than the icon shrunk to the row
check( "the row is at least as tall as the icon",
	GRISTLE.NameRowHeight( "selfShowClassIcon" ), math.max( GRISTLE.NameHeight(), ICON ) )
check( "the morale bar sits below the taller row",
	bar.y, GRISTLE.NameRowHeight( "selfShowClassIcon" ) + GRISTLE.Settings.selfGap )

-- on the player frame the icon is at the left end, where the name would start, and the name after it
check( "the icon sits where the name used to start",
	selfIcon:GetLeft(), selfName.clip:GetLeft() )
check( "centred down the row",
	selfIcon:GetTop(), math.floor( ( GRISTLE.NameRowHeight( "selfShowClassIcon" ) - ICON ) / 2 ) )
check( "the name is pushed past it",             selfName.nameLabel:GetLeft(), ICON + GRISTLE.ClassIconGap )
check( "and loses that much width",
	selfName.nameLabel:GetWidth(), selfName.clip:GetWidth() - ICON - GRISTLE.ClassIconGap )
check( "the level is not moved",                 selfName.extraLabel:GetLeft(), 0 )

-- an unchanged class does not re-set the texture
local backgroundsBefore = stub.Counted( selfIcon, "SetBackground" )
GRISTLE.Self.RefreshName()
GRISTLE.Self.RefreshName()
check( "an unchanged class does not swap the texture",
	stub.Counted( selfIcon, "SetBackground" ), backgroundsBefore )

-- a bigger name font makes a taller row, and the icon stays its own size, centred in it
GRISTLE.Settings.nameFontSize = 23
GRISTLE.ApplyAll()
check( "the icon keeps its size under a larger font", selfIcon:GetWidth(), ICON )
check( "and is centred in the taller row",
	selfIcon:GetTop(), math.floor( ( GRISTLE.NameHeight() - ICON ) / 2 ) )
GRISTLE.Settings.nameFontSize = GRISTLE.Defaults.nameFontSize
GRISTLE.ApplyAll()

-- hiding the name row has to take the icon with it, though it is not inside the row's clip
GRISTLE.Settings.selfShowName = false
GRISTLE.ApplyAll()
check( "hiding the name row hides the icon",     selfIcon:IsVisible(), false )
GRISTLE.Settings.selfShowName = true
GRISTLE.ApplyAll()
check( "and showing it brings the icon back",    selfIcon:IsVisible(), true )

-- switched off, the name takes its place back
GRISTLE.Settings.selfShowClassIcon = false
GRISTLE.ApplyAll()
check( "the icon can be switched off",           selfIcon:IsVisible(), false )
check( "and the name returns to the edge",       selfName.nameLabel:GetLeft(), 0 )
check( "and the row goes back to its font's height",
	GRISTLE.NameRowHeight( "selfShowClassIcon" ), GRISTLE.NameHeight() )
check( "at the full width",                      selfName.nameLabel:GetWidth(), selfName.clip:GetWidth() )

GRISTLE.Settings.selfShowClassIcon = true
GRISTLE.ApplyAll()
check( "and back on",                            selfIcon:IsVisible(), true )
check( "with the right emblem still",            selfIcon:GetBackground(), 0x41007DE7 )

-- the target frame reads from the right, so its icon is at the right-hand end
local targetIcon = targetName.icon

local burglar = stub.NewActor( { name = "Sneak", morale = 100, maxMorale = 100, kind = "player", class = Class.Burglar } )
player:SetTarget( burglar )
check( "a player target shows its class",        targetIcon:IsVisible(), true )
check( "the burglar emblem",                     targetIcon:GetBackground(), 0x41007DEB )
check( "at the right-hand end",
	targetIcon:GetLeft(), targetName.clip:GetLeft() + targetName.clip:GetWidth() - ICON )
check( "the name stops short of it",
	targetName.nameLabel:GetLeft() + targetName.nameLabel:GetWidth(),
	targetName.clip:GetWidth() - ICON - GRISTLE.ClassIconGap )

local minstrel = stub.NewActor( { name = "Singer", morale = 100, maxMorale = 100, kind = "player", class = Class.Minstrel } )
player:SetTarget( minstrel )
check( "swapping player targets swaps the emblem", targetIcon:GetBackground(), 0x41007DE6 )

-- a monster has no GetClass: no icon, and the name goes back to the edge
local wolf = stub.NewActor( { name = "Wolf", morale = 100, maxMorale = 100, kind = "monster" } )
player:SetTarget( wolf )
check( "a monster shows no icon",                targetIcon:IsVisible(), false )
check( "and its name runs to the edge",          targetName.nameLabel:GetWidth(), targetName.clip:GetWidth() )

-- a class with no emblem in the table shows nothing rather than a wrong one
local oddity = stub.NewActor( { name = "Odd", morale = 100, maxMorale = 100, kind = "player", class = 9999 } )
player:SetTarget( oddity )
check( "an unrecognised class shows no icon",    targetIcon:IsVisible(), false )

-- a GetClass that throws is a missing class, not an error out of the target change
local broken = stub.NewActor( { name = "Broken", morale = 100, maxMorale = 100, kind = "player" } )
broken.GetClass = function() error( "not ready" ) end
player:SetTarget( broken )
check( "a throwing GetClass shows no icon",      targetIcon:IsVisible(), false )
check( "and the name is still there",            targetName.nameLabel:GetText(), "Broken" )

-- the icon must not outlive the target it describes
player:SetTarget( burglar )
player:SetTarget( nil )
check( "losing the target clears the icon",      targetIcon:IsVisible(), false )

-- the setting is per frame
GRISTLE.Settings.targetShowClassIcon = false
GRISTLE.ApplyAll()
player:SetTarget( burglar )
check( "the target's icon has its own switch",   targetIcon:IsVisible(), false )
check( "independent of the player's",            selfIcon:IsVisible(), true )
GRISTLE.Settings.targetShowClassIcon = true
GRISTLE.ApplyAll()
check( "and turning it back on shows it at once", targetIcon:IsVisible(), true )

player:SetTarget( nil )

-- a player target whose class has not arrived yet, standing at full morale so nothing fires: the
-- retry has to keep asking until the class turns up, then stop
do
	local classReady = false
	local late = stub.NewActor( { name = "Late", morale = 100, maxMorale = 100, kind = "player" } )
	late.GetClass = function() if classReady then return Class.Guardian end return nil end

	player:SetTarget( late )
	check( "a class that has not arrived shows no icon yet", targetIcon:IsVisible(), false )
	check( "and the target is still pending",                GRISTLE.Target.ClassPending(), true )

	classReady = true
	stub.Tick( 0.3 )
	check( "the retry picks the class up when it arrives",   targetIcon:IsVisible(), true )
	check( "with the right emblem",                          targetIcon:GetBackground(), 0x41007DE8 )
	check( "and nothing is pending any more",                GRISTLE.Target.ClassPending(), false )

	-- a monster is never pending, so it never keeps a retry alive
	player:SetTarget( wolf )
	check( "a monster is never class-pending",               GRISTLE.Target.ClassPending(), false )

	-- the debug command has to report the class read for both frames
	player:SetTarget( burglar )
	stub.lines = {}
	local ok = pcall( function() stub.command:Execute( "gristle", "debug" ) end )
	local printed = table.concat( stub.lines, "\n" )
	check( "debug runs with a player target",                ok, true )
	check( "and reports the target's GetClass",
		string.find( printed, "target class icon" ) ~= nil and string.find( printed, "GetClass" ) ~= nil, true )

	player:SetTarget( nil )
	stub.lines = {}
	ok = pcall( function() stub.command:Execute( "gristle", "debug" ) end )
	check( "and with no target at all",                      ok, true )
end

---------------------------------------------------------------------------------------------------
section( "a maximum that reads zero" )
---------------------------------------------------------------------------------------------------
-- A maximum of 0 makes a bar undrawable -- there is no percentage of zero -- so a vital whose
-- GetMax* answers 0 produced a blank bar with no readout at all, while the bar beside it whose
-- maximum happened to read worked perfectly. GetBaseMax* is the fallback.

local zeroMax = stub.NewActor( { name = "ZeroMax", morale = 700, maxMorale = 1000, kind = "monster" } )
zeroMax.GetMaxMorale = function() return 0 end

local gotMorale, gotMax = GRISTLE.ReadVital( zeroMax, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

check( "a zero maximum falls back to the base maximum", gotMax, 1000 )
check( "and the current value is unchanged",            gotMorale, 700 )

-- with no fallback named, a zero maximum is still unreadable
check( "a zero maximum with no fallback reads nothing",
	GRISTLE.ReadVital( zeroMax, "GetMorale", "GetMaxMorale" ), nil )

-- both zero is genuinely unreadable
local bothZero = stub.NewActor( { name = "Both", morale = 10, maxMorale = 10, kind = "monster" } )
bothZero.GetMaxMorale     = function() return 0 end
bothZero.GetBaseMaxMorale = function() return 0 end

check( "both maxima at zero reads nothing",
	GRISTLE.ReadVital( bothZero, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" ), nil )

-- a current of 0 is a dead target, not an unreadable one, and must still draw
local dead = stub.NewActor( { name = "Dead", morale = 0, maxMorale = 1000, kind = "monster" } )
local deadCurrent, deadMax = GRISTLE.ReadVital( dead, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

check( "a current of zero still reads", deadCurrent, 0 )
check( "with its maximum intact",       deadMax, 1000 )

-- /gristle debug is the tool for when something is already wrong, so it has to work on a broken
-- entity above all. A diagnostic that throws is worse than none.
stub.lines = {}
local debugOk = pcall( function() stub.command:Execute( "gristle", "debug" ) end )

check( "the debug command runs", debugOk, true )
check( "and prints something",   #stub.lines > 5, true )

local printed = table.concat( stub.lines, "\n" )
check( "it reports the raw getter answers", string.find( printed, "GetBaseMaxMorale" ) ~= nil, true )
check( "and what was made of them",         string.find( printed, "what Gristle read" ) ~= nil, true )
check( "and the fill colour, for an invisible-bar diagnosis",
	string.find( printed, "fill color" ) ~= nil, true )
-- both the template and what it rendered to: a blank readout is either an empty template or one
-- whose every tag came back empty, and the two look identical on screen
check( "and the context every template was rendered against",
	string.find( printed, "the render context" ) ~= nil, true )

---------------------------------------------------------------------------------------------------
-- /gristle format is the only documentation a player gets
---------------------------------------------------------------------------------------------------
-- The options panel has room for the tag names and not for what they mean, and this game has no
-- tooltip to put the rest in. A readout is typed, so looking up what can be typed has to work.

stub.lines = {}
local formatOk = pcall( function() stub.command:Execute( "gristle", "format" ) end )

check( "the format command runs", formatOk, true )

local formatText = table.concat( stub.lines, "\n" )

check( "it lists every tag", #GRISTLE.Format.Help, 11 )

local missing = 0
for i = 1, #GRISTLE.Format.Help do
	if string.find( formatText, GRISTLE.Format.Help[i][1], 1, true ) == nil then
		missing = missing + 1
		print( "          not listed: " .. GRISTLE.Format.Help[i][1] )
	end
end

check( "and prints all of them", missing, 0 )
check( "with the modifiers",
	string.find( formatText, "[cur:short]", 1, true ) ~= nil, true )
check( "and what the frames are currently set to",
	string.find( formatText, "player bar", 1, true ) ~= nil, true )

-- every tag the help text advertises has to actually resolve, or the documentation lies
local unresolved = 0
for i = 1, #GRISTLE.Format.Help do
	local tag = GRISTLE.Format.Help[i][1]
	if GRISTLE.Format.Render( tag, { cur = 500, max = 1000, temp = 100, maxtemp = 200,
	                              pow = 250, maxpow = 500, name = "Souru", level = 150 } ) == tag then
		unresolved = unresolved + 1
		print( "          not a real tag: " .. tag )
	end
end

check( "and every one of them is a real tag", unresolved, 0 )

-- a getter that throws is survived rather than propagated
local angry = stub.NewActor( { name = "Angry", morale = 10, maxMorale = 10, kind = "monster" } )
angry.GetMorale = function() error( "no" ) end

check( "a throwing getter reads nothing",
	GRISTLE.ReadVital( angry, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" ), nil )

-- and the whole way through, to the drawn bar
player.GetMaxMorale = function() return 0 end
player.morale = 500
bar:Reset()

check( "the player's bar fills from the base maximum", GRISTLE.Self.RefreshMorale(), true )
check( "and is drawn",                                 bar.fill:GetWidth(), 130 )
check( "with its readout",                             bar.valueLabel:GetText(), "500" )

player.GetMaxMorale = function( e ) return e.maxMorale end
player:SetMorale( 1000 )

---------------------------------------------------------------------------------------------------
section( "a vital that is not readable yet" )
---------------------------------------------------------------------------------------------------
-- The engine hands out an entity before its data arrives, so the first read can answer 0 or throw.
-- A single failed read used to be permanent: nothing redraws the bar until the vital next *changes*,
-- and a player at full morale out of combat never fires one. That is the empty morale bar.

-- a target whose morale is not there yet must still be attached to and must still be waited for
local slow = stub.NewActor( { name = "Slow", morale = 900, maxMorale = 1000, kind = "monster" } )

-- both maxima have to be unreadable: a maximum of 0 from GetMaxMorale now falls back to
-- GetBaseMaxMorale, so zeroing only the first no longer simulates an unready entity
local ready = false
slow.GetMaxMorale     = function( e ) return ready and 1000 or 0 end
slow.GetBaseMaxMorale = function( e ) return ready and 1000 or 0 end
slow.GetMorale        = function( e ) return ready and 900 or 0 end

player:SetTarget( slow )

check( "an unready target is still attached to", GRISTLE.Target.entity, slow )
check( "its handlers are attached",              type( slow.MoraleChanged ) ~= "nil", true )
check( "the frame is up with its name",          targetName.nameLabel:GetText(), "Slow" )
check( "but no bar until it reads",              targetWindow.moraleBar.clip:IsVisible(), false )

-- nothing has changed, so nothing will fire. Only the retry can rescue this.
ready = true
stub.Tick( 0.3 )

check( "the retry picks it up once it reads", targetWindow.window:IsVisible(), true )
check( "and fills the bar",                   targetWindow.moraleBar.fill:GetWidth(),
	math.floor( 900 / 1000 * 260 ) )

-- and it stops once it has succeeded, rather than polling for ever
stub.Tick( 0.3 )
stub.Tick( 0.3 )

local stillTicking = false
for i = 1, #stub.updaters do
	if stub.updaters[i]:WantsUpdates() then stillTicking = true end
end
check( "the retry stops once it has read", stillTicking, false )

-- a target that never becomes readable has to give up rather than poll for ever
local broken = stub.NewActor( { name = "Broken", morale = 10, maxMorale = 10, kind = "monster" } )
broken.GetMaxMorale     = function() return 0 end
broken.GetBaseMaxMorale = function() return 0 end

player:SetTarget( broken )
check( "an unreadable target shows no bar", targetWindow.moraleBar.clip:IsVisible(), false )
check( "but still its name",                targetName.nameLabel:GetText(), "Broken" )

for _ = 1, 20 do stub.Tick( 0.3 ) end

stillTicking = false
for i = 1, #stub.updaters do
	if stub.updaters[i]:WantsUpdates() then stillTicking = true end
end
check( "the retry gives up instead of polling for ever", stillTicking, false )

-- re-targeting must drop the previous target's pending retry rather than let it fire later
player:SetTarget( slow )
player:SetTarget( nil )

for _ = 1, 4 do stub.Tick( 0.3 ) end
check( "a retry cannot resurrect a dropped target", targetWindow.window:IsVisible(), false )

---------------------------------------------------------------------------------------------------
-- the player, which is the case that actually broke
---------------------------------------------------------------------------------------------------
-- The player is the one entity whose vitals can sit unchanged for minutes. A failed read at load
-- left the morale bar empty while the power hairline beside it was full, for as long as nothing
-- hit you.

local playerReady = true
local realMaxMorale = player.GetMaxMorale

player.GetMaxMorale     = function( e ) return playerReady and 1000 or 0 end
player.GetBaseMaxMorale = function( e ) return playerReady and 1000 or 0 end

-- set on the actor directly rather than through SetMorale, which would fire the event and refresh
-- the bar -- the whole point here is that nothing fires
player.morale, player.maxMorale = 1000, 1000

bar:Reset()
playerReady = false

check( "a failed read leaves the bar empty", GRISTLE.Self.RefreshMorale(), false )

-- power still has to be drawn on a tick where morale failed, which is exactly what the screenshot
-- showed: a full hairline under an empty morale bar
check( "but power is still read", GRISTLE.Self.RefreshPower(), true )

GRISTLE.Self.RefreshPersistently()

playerReady = true
stub.Tick( 0.3 )

check( "the retry fills the morale bar in once it reads", bar.fill:GetWidth(), 260 )
check( "and the readout with it",                         bar.valueLabel:GetText(), "1,000" )

player.GetMaxMorale = realMaxMorale
GRISTLE.Updater.Clear()

---------------------------------------------------------------------------------------------------
section( "the entity element" )
---------------------------------------------------------------------------------------------------
-- the game's own control, which is what gives the frames click-to-target and the right-click menu

check( "the player frame is bound to the player",
	selfWindow.entityControl:GetEntity(), player )
check( "and it takes the mouse",
	selfWindow.entityControl:IsMouseVisible(), true )

-- it is the bottom layer: everything drawn over it is click-through, so the clicks reach it
check( "it sits under every bar",
	selfWindow.entityControl:GetZOrder() < selfWindow.moraleBar.frame:GetZOrder(), true )
check( "and under the name row",
	selfWindow.entityControl:GetZOrder() < selfWindow.nameRow.clip:GetZOrder(), true )
check( "but under the drag handle too",
	selfWindow.entityControl:GetZOrder() < selfWindow.moveControl:GetZOrder(), true )

check( "it covers the whole frame, width",  selfWindow.entityControl:GetWidth(),
	selfWindow.window:GetWidth() )
check( "it covers the whole frame, height", selfWindow.entityControl:GetHeight(),
	selfWindow.window:GetHeight() )

-- the target frame rebinds on every target change
local victimA = stub.NewActor( { name = "A", morale = 100, maxMorale = 100, kind = "monster" } )
player:SetTarget( victimA )
check( "the target frame binds to the target", targetWindow.entityControl:GetEntity(), victimA )

player:SetTarget( nil )
check( "and unbinds when the target goes", targetWindow.entityControl:GetEntity(), nil )
check( "so a dead frame cannot be clicked", targetWindow.entityControl:IsMouseVisible(), false )

-- it is the one thing in Gristle that takes the mouse, so it has to be switchable
GRISTLE.Settings.entityControl = false
GRISTLE.ApplyAll()

check( "switching it off restores a click-through HUD",
	selfWindow.entityControl:IsMouseVisible(), false )
check( "and takes it off screen", selfWindow.entityControl:IsVisible(), false )

GRISTLE.Settings.entityControl = true
GRISTLE.ApplyAll()
check( "and back on", selfWindow.entityControl:IsMouseVisible(), true )

---------------------------------------------------------------------------------------------------
section( "fine positioning" )
---------------------------------------------------------------------------------------------------

GRISTLE.Settings.mirrorTarget = false
GRISTLE.Settings.selfLeft, GRISTLE.Settings.selfTop = GRISTLE.PixelToRatio( 400, 500 )
GRISTLE.ApplyPositions()

selfWindow:Nudge( 1, 0 )
check( "one pixel right", selfWindow.window:GetLeft(), 401 )

selfWindow:Nudge( -1, 0 )
check( "and back",        selfWindow.window:GetLeft(), 400 )

selfWindow:Nudge( 0, -1 )
check( "one pixel up",    selfWindow.window:GetTop(),  499 )

-- a nudge saves, the same as a drag does
checkNear( "a nudge is saved", GRISTLE.Settings.selfTop, 499 / 1080 )

-- and it cannot walk a window off the screen
GRISTLE.Settings.selfLeft, GRISTLE.Settings.selfTop = GRISTLE.PixelToRatio( 0, 0 )
GRISTLE.ApplyPositions()
selfWindow:Nudge( -5, -5 )
check( "a nudge stops at the left edge", selfWindow.window:GetLeft(), 0 )
check( "and at the top edge",            selfWindow.window:GetTop(),  0 )

-- nudging a mirrored pair keeps them mirrored
GRISTLE.Settings.selfLeft, GRISTLE.Settings.selfTop = GRISTLE.PixelToRatio( 400, 500 )
GRISTLE.Settings.mirrorTarget = true
GRISTLE.ApplyPositions()

selfWindow:Nudge( 3, 0 )
check( "the player frame moved", selfWindow.window:GetLeft(), 403 )
check( "and its mirror moved with it",
	targetWindow.window:GetLeft(), 1920 - 403 - targetWindow.window:GetWidth() )

-- and nudging the mirror itself moves what it mirrors
targetWindow:Nudge( 2, 0 )
check( "nudging the mirror moved the player frame", selfWindow.window:GetLeft(), 401 )

GRISTLE.Settings.mirrorTarget = false
GRISTLE.ApplyPositions()

---------------------------------------------------------------------------------------------------
section( "frame alignment" )
---------------------------------------------------------------------------------------------------

-- Fixed per frame rather than configurable, and one direction for the whole frame: the player's
-- reads inward from the left and the target's inward from the right, name row and bar readouts
-- alike, so the pair is a reflection rather than two frames that happen to sit near each other.

local alignment = Turbine.UI.ContentAlignment

GRISTLE.ApplyAll()

check( "the player's name sits left",
	selfName.nameLabel:GetTextAlignment(), alignment.MiddleLeft )
check( "and the player's level takes the right",
	selfName.extraLabel:GetTextAlignment(), alignment.MiddleRight )

check( "the target's name sits right",
	targetWindow.nameRow.nameLabel:GetTextAlignment(), alignment.MiddleRight )
check( "and the target's level takes the left",
	targetWindow.nameRow.extraLabel:GetTextAlignment(), alignment.MiddleLeft )

---------------------------------------------------------------------------------------------------
-- the bar's two readouts flip with the name above them
---------------------------------------------------------------------------------------------------

check( "the player's first readout sits left",
	bar.valueLabel:GetTextAlignment(), alignment.MiddleLeft )
check( "and its second takes the right",
	bar.pctLabel:GetTextAlignment(), alignment.MiddleRight )

check( "the target's first readout sits right",
	targetWindow.moraleBar.valueLabel:GetTextAlignment(), alignment.MiddleRight )
check( "and its second takes the left",
	targetWindow.moraleBar.pctLabel:GetTextAlignment(), alignment.MiddleLeft )

-- the readouts have to agree with the name row above them, or the frame reads in two directions
check( "the target's bar and name row read the same way",
	targetWindow.moraleBar.valueLabel:GetTextAlignment(),
	targetWindow.nameRow.nameLabel:GetTextAlignment() )
check( "and the player's do too",
	bar.valueLabel:GetTextAlignment(), selfName.nameLabel:GetTextAlignment() )

-- the two labels share one clipping window and are both full width, so reading from the same end
-- would draw the longer one straight through the shorter
check( "a frame's two readouts never read from the same end",
	bar.valueLabel:GetTextAlignment() ~= bar.pctLabel:GetTextAlignment(), true )

-- it is not a setting any more, and a savefile that still carries one is cleaned rather than left
-- holding a value nothing reads
GRISTLE.Settings.nameAlignRight = true
GRISTLE.NormaliseSettings()
check( "a stale name alignment setting is cleared", GRISTLE.Settings.nameAlignRight, nil )
check( "and it is not a default",                   GRISTLE.Defaults.nameAlignRight, nil )

-- a relayout must not quietly undo it
GRISTLE.Settings.nameFontSize = 16
GRISTLE.ApplyAll()
check( "the target's name is still right after a relayout",
	targetWindow.nameRow.nameLabel:GetTextAlignment(), alignment.MiddleRight )
check( "and its readouts too",
	targetWindow.moraleBar.valueLabel:GetTextAlignment(), alignment.MiddleRight )
GRISTLE.Settings.nameFontSize = 14
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
-- every label is outlined in black, so it reads over a full bar, an empty track and the world alike
---------------------------------------------------------------------------------------------------

check( "the morale value is outlined",
	bar.valueLabel._outlineColor ~= nil, true )
check( "and the outline is black",
	bar.valueLabel._outlineColor.R == 0 and bar.valueLabel._outlineColor.G == 0
		and bar.valueLabel._outlineColor.B == 0, true )
check( "the percentage too",  bar.pctLabel._outlineColor ~= nil, true )
check( "the name as well",    selfName.nameLabel._outlineColor ~= nil, true )
check( "and the level",       selfName.extraLabel._outlineColor ~= nil, true )

---------------------------------------------------------------------------------------------------
section( "additive event callbacks" )
---------------------------------------------------------------------------------------------------

-- the whole reason for AddCallback: LocalPlayer is shared with every other loaded plugin
local other = { calls = 0 }
local foreign = function() other.calls = other.calls + 1 end

local victim = stub.NewActor( { kind = "monster" } )

GRISTLE.AddCallback( victim, "MoraleChanged", foreign )
check( "a single handler is stored bare", type( victim.MoraleChanged ), "function" )

local mine = function() end
GRISTLE.AddCallback( victim, "MoraleChanged", mine )
check( "a second handler promotes to a table", type( victim.MoraleChanged ), "table" )
check( "both are present", #victim.MoraleChanged, 2 )

victim:Fire( "MoraleChanged" )
check( "the pre-existing handler still runs", other.calls, 1 )

GRISTLE.RemoveCallback( victim, "MoraleChanged", mine )
check( "removing ours leaves theirs", #victim.MoraleChanged, 1 )

victim:Fire( "MoraleChanged" )
check( "theirs keeps running after ours is gone", other.calls, 2 )

GRISTLE.RemoveCallback( victim, "MoraleChanged", foreign )
check( "removing the last one clears the slot", victim.MoraleChanged, nil )

---------------------------------------------------------------------------------------------------
section( "options panel stepping" )
---------------------------------------------------------------------------------------------------

check( "an integer step", GRISTLE.StepValue( 260, 1, 10, 40, 1200, 0 ), 270 )
check( "stepping down",   GRISTLE.StepValue( 260, -1, 10, 40, 1200, 0 ), 250 )
check( "clamped at the top",    GRISTLE.StepValue( 1200, 1, 10, 40, 1200, 0 ), 1200 )
check( "clamped at the bottom", GRISTLE.StepValue( 40, -1, 10, 40, 1200, 0 ), 40 )
check( "a nil value lands on the minimum", GRISTLE.StepValue( nil, -1, 10, 40, 1200, 0 ), 40 )
check( "a junk value lands on the minimum", GRISTLE.StepValue( "x", -1, 10, 40, 1200, 0 ), 40 )

-- the reason StepValue exists: adding 0.05 twenty times in binary floating point drifts, and the
-- drifted value would be both printed and saved
local opacity = 0.05
for _ = 1, 19 do
	opacity = GRISTLE.StepValue( opacity, 1, 0.05, 0.05, 1.0, 2 )
end
check( "repeated 0.05 steps do not drift", opacity, 1.0 )

local fade = 0.35
fade = GRISTLE.StepValue( fade, 1, 0.05, 0.05, 2.0, 2 )
check( "a fractional step stays exact", fade, 0.4 )

check( "the options panel was built", plugin.GetOptionsPanel() ~= nil, true )

local optionsPanel = plugin.GetOptionsPanel()
local optionsList  = optionsPanel.listBox

check( "the rows live on a ListBox inside it", optionsList ~= nil, true )
check( "and it has its rows", optionsList:GetItemCount() > 10, true )

---------------------------------------------------------------------------------------------------
-- the readout templates have to be typeable
---------------------------------------------------------------------------------------------------
-- Eight text boxes, one per template. A template that can only be set by hand-editing the savefile
-- is not a setting.

-- walked recursively: a bare TextBox paints no background of its own, so each one sits inside a
-- Control that does, the way every working text field in this folder is built
local boxes = {}

local function collectBoxes( control )

	local children = control:GetChildren()

	for c = 1, #children do
		if children[c]._kind == "TextBox" then
			table.insert( boxes, children[c] )
		end
		collectBoxes( children[c] )
	end

end

for i = 1, optionsList:GetItemCount() do
	collectBoxes( optionsList._items[i] )
end

-- eight template boxes in the readouts section, then one hex box per colour row below them
check( "there is a text box for every template and every colour", #boxes, 8 + 10 )

-- and each one has something painted behind it, or the field is invisible
local unbacked = 0
for i = 1, #boxes do
	if boxes[i]:GetParent() == nil or boxes[i]:GetParent():GetBackColor() == nil then
		unbacked = unbacked + 1
	end
end

check( "each box has a background behind it", unbacked, 0 )

---------------------------------------------------------------------------------------------------
-- and committing has to happen on the keystroke
---------------------------------------------------------------------------------------------------
-- There is no Apply in this panel, and waiting for the box to lose focus is not an option: the
-- Plugin Manager can close the panel without FocusLost ever firing, and the line would be quietly
-- thrown away.

local firstBox = boxes[1]

firstBox:SetText( "[perc:1]" )
local typedOk = pcall( function() firstBox.TextChanged( firstBox, {} ) end )

check( "typing in a box commits", typedOk, true )
check( "and reaches the settings", GRISTLE.Settings.selfFormatBarLeft, "[perc:1]" )

local onDiskNow = Turbine.PluginData.Load( Turbine.DataScope.Character, "gristleSettings" )
check( "and the savefile", tostring( onDiskNow.selfFormatBarLeft ), "[perc:1]" )

-- a template survives the euro round trip, which turns anything that parses as a number back into
-- one. "[perc:1]" does not, which is the only reason this works at all.
check( "a template is still text on disk", type( onDiskNow.selfFormatBarLeft ), "string" )

GRISTLE.Settings.selfFormatBarLeft = GRISTLE.Defaults.selfFormatBarLeft
GRISTLE.Save()
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
-- the panel must scroll
---------------------------------------------------------------------------------------------------
-- The rows add up to well over twice the height the Plugin Manager will draw. A ListBox clips what
-- does not fit and says nothing, so without a scrollbar every section past the top of the list is
-- simply unreachable -- which is exactly how it shipped, with the readouts cut off mid-section.

local contentHeight = 0
for i = 1, optionsList:GetItemCount() do
	contentHeight = contentHeight + select( 2, optionsList._items[i]:GetSize() )
end

check( "the content really is taller than the viewport",
	contentHeight > select( 2, optionsList:GetSize() ), true )

check( "so a vertical scrollbar is attached", optionsList:GetVerticalScrollBar() ~= nil, true )
check( "and it is vertical",
	optionsList:GetVerticalScrollBar():GetOrientation(), Turbine.UI.Orientation.Vertical )

-- the wheel has to work, not just the bar
check( "the list takes the mouse, so the wheel scrolls it", optionsList:IsMouseVisible(), true )

-- the bar sits beside the rows rather than over them
local listWidth  = select( 1, optionsList:GetSize() )
local scrollLeft = optionsList:GetVerticalScrollBar():GetLeft()

check( "the scrollbar starts where the rows end", scrollLeft, listWidth )

-- and no row reaches under it
local widest = 0
for i = 1, optionsList:GetItemCount() do
	local w = select( 1, optionsList._items[i]:GetSize() )
	if w > widest then widest = w end
end

check( "no row runs under the scrollbar", widest <= listWidth, true )

---------------------------------------------------------------------------------------------------
-- nothing sticks out of the row that owns it
---------------------------------------------------------------------------------------------------
-- The panel is hand-placed co-ordinates all the way down, so adding a setting to a section means
-- remembering to grow the row that holds it. Forgetting looks exactly like the clipped panel did:
-- the widget is simply not drawn, with nothing said about it.

-- Walked recursively, because a template box is nested inside the Control painted behind it: a
-- widget that escapes its own background is just as invisible as one that escapes its row.

local overflows = 0

local function checkFits( index, control )

	local width, height = control:GetSize()
	local children = control:GetChildren()

	for c = 1, #children do

		local x, y = children[c]:GetPosition()
		local w, h = children[c]:GetSize()

		if x + w > width or y + h > height then
			overflows = overflows + 1
			print( string.format( "          row %d: %s at %d,%d +%dx%d escapes %dx%d (%s)",
				index, children[c]._kind, x, y, w, h, width, height,
				tostring( children[c]:GetText() ) ) )
		end

		checkFits( index, children[c] )

	end

end

for i = 1, optionsList:GetItemCount() do
	checkFits( i, optionsList._items[i] )
end

check( "every widget fits inside its section", overflows, 0 )

---------------------------------------------------------------------------------------------------
section( "positions" )
---------------------------------------------------------------------------------------------------

local ratioLeft, ratioTop = GRISTLE.PixelToRatio( 960, 540 )
checkNear( "pixel to ratio, left", ratioLeft, 0.5 )
checkNear( "pixel to ratio, top",  ratioTop,  0.5 )

local pixelLeft, pixelTop = GRISTLE.RatioToPixel( 0.5, 0.5 )
check( "ratio to pixel, left", pixelLeft, 960 )
check( "ratio to pixel, top",  pixelTop,  540 )

local cl, ct = GRISTLE.ClampToScreen( 5000, 5000, 260, 40 )
check( "clamped back inside, left", cl, 1920 - 260 )
check( "clamped back inside, top",  ct, 1080 - 40 )

local nl, nt = GRISTLE.ClampToScreen( -100, -100, 260, 40 )
check( "clamped off the near edge, left", nl, 0 )
check( "clamped off the near edge, top",  nt, 0 )

-- a window wider than the screen keeps its top left corner on screen
local wl, wt = GRISTLE.ClampToScreen( 10, 10, 4000, 40 )
check( "an oversized window keeps its left edge", wl, 0 )

---------------------------------------------------------------------------------------------------
section( "mirrored target position" )
---------------------------------------------------------------------------------------------------
-- the far edge is what is mirrored: a frame 100 in from the left puts its mirror 100 in from the
-- right, whatever the two widths are

check( "a frame at the left edge mirrors to the right edge",
	GRISTLE.MirrorLeft( 0, 260 ), 1920 - 260 )
check( "and 100 in from the left is 100 in from the right",
	GRISTLE.MirrorLeft( 100, 260 ), 1920 - 100 - 260 )

-- the reflection is its own inverse, which is what lets a mirrored window be dragged
check( "mirroring twice returns the original",
	GRISTLE.MirrorLeft( GRISTLE.MirrorLeft( 340, 260 ), 260 ), 340 )

-- a frame centred on the screen mirrors onto itself
check( "a centred frame mirrors onto itself",
	GRISTLE.MirrorLeft( ( 1920 - 260 ) / 2, 260 ), ( 1920 - 260 ) / 2 )

-- now through the real windows
GRISTLE.Settings.mirrorTarget = false
check( "the player window never mirrors", selfWindow:IsMirrored(), false )
check( "and the target window does not while it is off", targetWindow:IsMirrored(), false )

GRISTLE.Settings.selfLeft, GRISTLE.Settings.selfTop = GRISTLE.PixelToRatio( 300, 800 )
GRISTLE.Settings.targetLeft, GRISTLE.Settings.targetTop = GRISTLE.PixelToRatio( 100, 100 )
GRISTLE.ApplyPositions()

check( "unmirrored, the target keeps its own position, left", targetWindow.window:GetLeft(), 100 )
check( "unmirrored, the target keeps its own position, top",  targetWindow.window:GetTop(),  100 )

GRISTLE.Settings.mirrorTarget = true
GRISTLE.ApplyPositions()

check( "mirroring is live", targetWindow:IsMirrored(), true )
check( "the target reflects the player's position",
	targetWindow.window:GetLeft(), 1920 - 300 - targetWindow.window:GetWidth() )
check( "and sits at the player's height", targetWindow.window:GetTop(), 800 )
check( "the player window did not move", selfWindow.window:GetLeft(), 300 )

-- the saved target position is left alone while mirroring, so turning it off restores it
checkNear( "the target's own saved position is untouched",
	GRISTLE.Settings.targetLeft, 100 / 1920 )

GRISTLE.Settings.mirrorTarget = false
GRISTLE.ApplyPositions()
check( "turning it off restores the target's own position", targetWindow.window:GetLeft(), 100 )

---------------------------------------------------------------------------------------------------
-- dragging either frame while mirroring
---------------------------------------------------------------------------------------------------

GRISTLE.Settings.mirrorTarget = true
GRISTLE.SetMoveMode( true )
GRISTLE.ApplyPositions()

-- dragging the player frame carries the mirror live, not just on mouse up
selfWindow.moveControl.MouseDown( nil, { Button = 1, X = 0, Y = 0 } )
selfWindow.moveControl.MouseMove( nil, { Button = 1, X = 40, Y = 0 } )

local draggedLeft = selfWindow.window:GetLeft()
check( "the player frame moved", draggedLeft, 340 )
check( "and the mirror followed during the drag",
	targetWindow.window:GetLeft(), 1920 - draggedLeft - targetWindow.window:GetWidth() )

selfWindow.moveControl.MouseUp( nil, { Button = 1, X = 40, Y = 0 } )
checkNear( "the drag saved the player's position", GRISTLE.Settings.selfLeft, 340 / 1920 )

-- and dragging the mirror writes back to what it mirrors, rather than to a position it ignores
targetWindow.moveControl.MouseDown( nil, { Button = 1, X = 0, Y = 0 } )
targetWindow.moveControl.MouseMove( nil, { Button = 1, X = -50, Y = 0 } )
targetWindow.moveControl.MouseUp( nil, { Button = 1, X = -50, Y = 0 } )

-- the mirror moved 50 left, so its source moves 50 right
checkNear( "dragging the mirror moved the player frame", GRISTLE.Settings.selfLeft, 390 / 1920 )
check( "the player frame is where the mirror put it", selfWindow.window:GetLeft(), 390 )
check( "and the two are still reflections",
	targetWindow.window:GetLeft(), 1920 - 390 - targetWindow.window:GetWidth() )

-- a mirrored window must not write a position of its own
checkNear( "the mirror still has not touched its own saved position",
	GRISTLE.Settings.targetLeft, 100 / 1920 )

-- a resize has to re-place the mirror, since its position depends on its own width
GRISTLE.Settings.targetWidth = 400
GRISTLE.ApplyAll()
check( "a wider mirror is re-placed from its new width",
	targetWindow.window:GetLeft(), 1920 - 390 - targetWindow.window:GetWidth() )

GRISTLE.Settings.targetWidth = 260
GRISTLE.Settings.mirrorTarget = false
GRISTLE.SetMoveMode( false )
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
section( "savefile round trip" )
---------------------------------------------------------------------------------------------------

local sample = {
	width = 260,
	nested = { height = 34, ratio = 0.755 },
	flag = true,
	name = "morale",
	[3] = "numeric key",
	color = Turbine.UI.Color( 0.2, 0.4, 0.6 ),
}

-- deliberately not called "euro": that is the locale flag, and shadowing it here silently turned
-- the English run into a half-euro one
local converted = GRISTLE.ConvertToEuro( sample )

check( "numbers become strings",       type( converted.width ), "string" )
check( "nested numbers too",           type( converted.nested.height ), "string" )
check( "numeric keys become strings",  converted["3"], "numeric key" )
check( "booleans survive",             converted.flag, true )
check( "strings survive",              converted.name, "morale" )
check( "Color instances pass through untouched", converted.color, sample.color )

local back = GRISTLE.ConvertFromEuro( converted )

check( "numbers come back",        back.width, 260 )
checkNear( "fractions come back",  back.nested.ratio, 0.755 )
check( "numeric keys come back",   back[3], "numeric key" )
check( "booleans still survive",   back.flag, true )
check( "strings still survive",    back.name, "morale" )

-- idempotent on a savefile written before the euro fix
local plain = GRISTLE.ConvertFromEuro( sample )
check( "already-numeric data survives a second pass", plain.width, 260 )

-- a real save and load through the fake disk
GRISTLE.Settings.selfWidth = 310
GRISTLE.Settings.selfTop = 0.42
GRISTLE.Save()

local onDisk = Turbine.PluginData.Load( Turbine.DataScope.Character, "gristleSettings" )
check( "the character scope was written", onDisk ~= nil, true )
check( "colours are stored as plain tables", getmetatable( onDisk.colorMorale ), nil )
check( "no Color instance leaked into the savefile", onDisk.colorMorale.R ~= nil, true )

-- on a German or French client every number must have gone to disk as a string, because those
-- clients cannot round-trip a number through the serialiser
if euro then
	check( "numbers were stringified for the euro client", type( onDisk.selfWidth ), "string" )
	check( "nested numbers too", type( onDisk.colorMorale.R ), "string" )
else
	check( "numbers stay numbers on an English client", type( onDisk.selfWidth ), "number" )
end

-- and the value survives whichever path it took
local reloaded = euro and GRISTLE.ConvertFromEuro( onDisk ) or onDisk
check( "the changed value survives the full save/load path", reloaded.selfWidth, 310 )
checkNear( "and so does a fractional one", reloaded.selfTop, 0.42 )

-- with no account copy at load time, every save mirrors to it
local mirrored = Turbine.PluginData.Load( Turbine.DataScope.Account, "gristleSettings" )
check( "the account copy was mirrored", mirrored ~= nil, true )
check( "GRISTLE reports a shared copy exists", GRISTLE.HasGlobalSettings(), true )

---------------------------------------------------------------------------------------------------
section( "drag" )
---------------------------------------------------------------------------------------------------

GRISTLE.SetMoveMode( true )
check( "move mode makes the handle clickable", selfWindow.moveControl:IsMouseVisible(), true )
check( "and the target window grabbable with no target", targetWindow.window:IsVisible(), true )

local startLeft, startTop = selfWindow.window:GetPosition()

selfWindow.moveControl.MouseDown( nil, { Button = 1, X = 10, Y = 10 } )
selfWindow.moveControl.MouseMove( nil, { Button = 1, X = 40, Y = 30 } )

local movedLeft, movedTop = selfWindow.window:GetPosition()
check( "dragging moves the window by the delta, left", movedLeft, startLeft + 30 )
check( "dragging moves the window by the delta, top",  movedTop,  startTop + 20 )

selfWindow.moveControl.MouseUp( nil, { Button = 1, X = 40, Y = 30 } )

checkNear( "mouse up saves the new position as a ratio",
	GRISTLE.Settings.selfLeft, movedLeft / 1920 )

-- a drag must not be able to strand a window off-screen
selfWindow.moveControl.MouseDown( nil, { Button = 1, X = 0, Y = 0 } )
selfWindow.moveControl.MouseMove( nil, { Button = 1, X = 9000, Y = 9000 } )
local farLeft, farTop = selfWindow.window:GetPosition()
check( "a drag off the right edge is clamped", farLeft <= 1920, true )
check( "a drag off the bottom edge is clamped", farTop <= 1080, true )
selfWindow.moveControl.MouseUp( nil, { Button = 1, X = 9000, Y = 9000 } )

-- a right-click must not start a drag
selfWindow.moveControl.MouseDown( nil, { Button = 2, X = 0, Y = 0 } )
local rl, rt = selfWindow.window:GetPosition()
selfWindow.moveControl.MouseMove( nil, { Button = 2, X = 500, Y = 500 } )
check( "a right-click does not drag", selfWindow.window:GetLeft(), rl )

-- the handle is created before the bars give themselves explicit z-orders, so without a forced
-- z-order of its own it ends up buried and unclickable
check( "the handle sits above every bar control",
	selfWindow.moveControl:GetZOrder() > selfWindow.powerBar.clip:GetZOrder(), true )

GRISTLE.SetMoveMode( false )
check( "leaving move mode makes the handle click-through", selfWindow.moveControl:IsMouseVisible(), false )
check( "and hides the target window again", targetWindow.window:IsVisible(), false )

---------------------------------------------------------------------------------------------------
section( "click-through" )
---------------------------------------------------------------------------------------------------
-- a single control that forgets SetMouseVisible(false) swallows clicks on the world behind it

check( "the self window is click-through",   selfWindow.window:IsMouseVisible(),   false )
check( "the target window is click-through", targetWindow.window:IsMouseVisible(), false )

local function allClickThrough( b )
	local controls = { b.frame, b.track, b.clip, b.fill }
	if b.temp ~= nil then table.insert( controls, b.temp ) end
	if b.labelBack ~= nil then
		table.insert( controls, b.labelBack )
		table.insert( controls, b.valueLabel )
		table.insert( controls, b.pctLabel )
	end
	for i = 1, #b.flashes do table.insert( controls, b.flashes[i].control ) end
	for i = 1, #controls do
		if controls[i]:IsMouseVisible() then return false end
	end
	return true
end

check( "every morale bar control is click-through", allClickThrough( bar ), true )
check( "every power bar control is click-through",  allClickThrough( powerBar ), true )
check( "every target bar control is click-through", allClickThrough( targetWindow.moraleBar ), true )

---------------------------------------------------------------------------------------------------
section( "opacity" )
---------------------------------------------------------------------------------------------------
-- one fixed value, deliberately not tied to combat any more

GRISTLE.Settings.opacity = 1.0
GRISTLE.ApplyAll()
checkNear( "full opacity is applied", selfWindow.window:GetOpacity(), 1.0 )

GRISTLE.Settings.opacity = 0.6
GRISTLE.ApplyAll()
checkNear( "a lowered opacity reaches the player window", selfWindow.window:GetOpacity(), 0.6 )
checkNear( "and the target window",                       targetWindow.window:GetOpacity(), 0.6 )

-- the whole point of the change: entering and leaving combat must not touch it
player:SetCombat( true )
checkNear( "entering combat does not change it", selfWindow.window:GetOpacity(), 0.6 )

player:SetCombat( false )
checkNear( "and leaving it does not either",     selfWindow.window:GetOpacity(), 0.6 )

-- nothing listens to combat any more, so the plugin must not have left a handler on the shared
-- LocalPlayer for it
check( "no combat handler is attached to LocalPlayer", player.InCombatChanged, nil )

-- a faint HUD still has to be findable in order to drag it
GRISTLE.SetMoveMode( true )
checkNear( "drag mode overrides the opacity", selfWindow.window:GetOpacity(), 1.0 )

GRISTLE.SetMoveMode( false )
checkNear( "and leaving drag mode restores it", selfWindow.window:GetOpacity(), 0.6 )

-- zero would be invisible with no visible way back
GRISTLE.Settings.opacity = 0
GRISTLE.NormaliseSettings()
check( "opacity is floored above invisible", GRISTLE.Settings.opacity, 0.05 )

GRISTLE.Settings.opacity = 1.0
GRISTLE.ApplyAll()

-- an existing savefile's dead keys are cleared rather than left to linger
GRISTLE.Settings = { version = 2, opacityCombat = 1.0, opacityIdle = 0.55, selfWidth = 280 }
GRISTLE.NormaliseSettings()

check( "the old combat opacity is gone", GRISTLE.Settings.opacityCombat, nil )
check( "the old idle opacity too",       GRISTLE.Settings.opacityIdle,   nil )
check( "the new one is defaulted",       GRISTLE.Settings.opacity,       1.0 )
check( "and the savefile is restamped",  GRISTLE.Settings.version,       4 )
check( "other settings are left alone",  GRISTLE.Settings.selfWidth,     280 )

GRISTLE.Settings = {}
GRISTLE.NormaliseSettings()
GRISTLE.ApplyAll()

---------------------------------------------------------------------------------------------------
section( "idle cost" )
---------------------------------------------------------------------------------------------------
-- nothing fading means nothing asking for an Update, or the plugin burns a slice of every frame
-- forever just to decide it has no work

stub.Tick( 1.0 )
stub.Tick( 1.0 )

local anyWantsUpdates = false
for i = 1, #stub.updaters do
	if stub.updaters[i]:WantsUpdates() then anyWantsUpdates = true end
end

check( "the fade driver switches itself off when idle", anyWantsUpdates, false )

bar:Reset()
player:SetMorale( 1000 )
player:SetMorale( 500 )

anyWantsUpdates = false
for i = 1, #stub.updaters do
	if stub.updaters[i]:WantsUpdates() then anyWantsUpdates = true end
end

check( "and back on when a flash starts", anyWantsUpdates, true )

---------------------------------------------------------------------------------------------------
section( "appearance: sheen, threshold marks, contrast, blend, hex colours" )
---------------------------------------------------------------------------------------------------
-- wrapped in a block: the main chunk is close to Lua 5.1's 200-local limit
do

	local b = GRISTLE.Self.window.moraleBar
	local s = GRISTLE.Settings

	player:SetBubble( 0, 0 )
	player:SetMorale( 1000 )

	-- hex codes ------------------------------------------------------------------------------------

	check( "a colour turns into a hex code", GRISTLE.ColorToHex( { R = 1, G = 0, B = 0.5 } ), "FF0080" )

	local parsed = GRISTLE.HexToColor( "#f9c229" )
	check( "a hex code parses, either case, with a #", parsed ~= nil, true )
	check( "and round-trips", GRISTLE.ColorToHex( parsed ), "F9C229" )
	check( "without the # too", GRISTLE.ColorToHex( GRISTLE.HexToColor( "00ff00" ) ), "00FF00" )
	check( "five digits is refused",  GRISTLE.HexToColor( "#12345" ), nil )
	check( "seven digits is refused", GRISTLE.HexToColor( "1234567" ), nil )
	check( "non-hex is refused",      GRISTLE.HexToColor( "GGGGGG" ), nil )
	check( "a number is refused",     GRISTLE.HexToColor( 123456 ), nil )

	-- lerp -----------------------------------------------------------------------------------------

	local black, white = { R = 0, G = 0, B = 0 }, { R = 1, G = 1, B = 1 }
	checkNear( "lerp at 0 is the start", GRISTLE.LerpColor( black, white, 0 ).R, 0 )
	checkNear( "lerp at 1 is the end",   GRISTLE.LerpColor( black, white, 1 ).G, 1 )
	checkNear( "lerp at half is between", GRISTLE.LerpColor( black, white, 0.5 ).B, 0.5 )
	checkNear( "lerp is clamped", GRISTLE.LerpColor( black, white, 7 ).R, 1 )

	-- sheen ----------------------------------------------------------------------------------------

	check( "sheen is on by default",          s.sheen, 0.15 )
	check( "the highlight is shown",           b.highlight:IsVisible(), true )
	check( "the shade is shown",               b.shade:IsVisible(), true )
	check( "the highlight spans the track",    b.highlight:GetWidth(), b.width )
	check( "the shade sits at the bottom",
		select( 2, b.shade:GetPosition() ) + b.shade:GetHeight(), b.height )
	checkNear( "the highlight is see-through", b.highlight:GetBackColor().A, 0.15 )
	-- Inside one Window a see-through child replaces the pixels under it rather than blending with
	-- them, so a sheen sharing the fill's window punched holes through to the track. Measured in
	-- game: grey and black bands over a full bar. It has to be a layer of its own, above the fill.
	check( "the sheen is not in the fill's window",   b.highlight:GetParent() ~= b.clip, true )
	check( "nor are the threshold marks",             b.ticks[1].control:GetParent() ~= b.clip, true )
	check( "it is in a window of its own",            b.highlight:GetParent(), b.overlay )
	check( "the marks share it",                      b.ticks[1].control:GetParent(), b.overlay )
	check( "that layer is above the fill's",          b.overlay:GetZOrder() > b.clip:GetZOrder(), true )
	check( "and below the readouts",                  b.overlay:GetZOrder() < b.labelBack:GetZOrder(), true )
	check( "it sits exactly over the track",          b.overlay:GetLeft(), b.clip:GetLeft() )
	check( "at the track's size",                     b.overlay:GetWidth(), b.clip:GetWidth() )
	check( "and it is on screen",                     effectivelyVisible( b.highlight ), true )
	check( "the sheen lets clicks through", b.highlight:IsMouseVisible(), false )

	local hairline = GRISTLE.Self.window.powerBar
	check( "the hairline gets a one pixel highlight", hairline.highlight:GetHeight(), 1 )
	check( "and no shade",                            hairline.shade:IsVisible(), false )

	s.sheen = 0
	GRISTLE.ApplyAll()
	check( "sheen 0 hides the highlight", b.highlight:IsVisible(), false )
	check( "and the shade",               b.shade:IsVisible(), false )

	s.sheen = 0.9
	GRISTLE.NormaliseSettings()
	check( "sheen is capped at half", s.sheen, 0.5 )
	s.sheen = "rubbish"
	GRISTLE.NormaliseSettings()
	check( "a nonsense sheen falls back to the default", s.sheen, 0.15 )
	GRISTLE.ApplyAll()

	-- threshold marks ------------------------------------------------------------------------------

	player:SetMorale( 1000 )
	check( "there are two marks on the morale bar", #b.ticks, 2 )
	check( "none on the hairline",                  #hairline.ticks, 0 )
	check( "the warn mark is at 50%",   b.ticks[1].control:GetLeft(), 130 )
	check( "the danger mark is at 25%", b.ticks[2].control:GetLeft(), 65 )
	check( "the marks are shown",       b.ticks[1].control:IsVisible(), true )

	-- a bubble shrinks the morale's share of the track, and the marks have to follow
	player:SetBubble( 250, 250 )
	check( "with a bubble the warn mark moves in",   b.ticks[1].control:GetLeft(), 97 )
	check( "and the danger mark too",                b.ticks[2].control:GetLeft(), 48 )

	local placed = stub.Counted( b.ticks[1].control, "SetPosition" )
	player:SetMorale( 900 )
	player:SetMorale( 800 )
	check( "the marks are not moved while the width holds",
		stub.Counted( b.ticks[1].control, "SetPosition" ), placed )

	player:SetBubble( 0, 0 )
	check( "and go back when it is gone", b.ticks[1].control:GetLeft(), 130 )

	s.showTicks = false
	GRISTLE.ApplyAll()
	check( "switching them off hides them", b.ticks[1].control:IsVisible(), false )
	s.showTicks = "yes"
	GRISTLE.NormaliseSettings()
	check( "a non-boolean switch falls back to its default", s.showTicks, true )
	GRISTLE.ApplyAll()

	-- contrast -------------------------------------------------------------------------------------

	local dark = s.colorTextDark

	-- the default green is bright-ish but white still reads on it
	player:SetMorale( 1000 )
	check( "white text stays on the default green", b.valueLabel:GetForeColor().R, s.colorText.R )

	-- amber, the way this plugin's own author runs it
	s.colorMorale = { R = 0.98, G = 0.76, B = 0.16 }
	GRISTLE.ApplyAll()
	player:SetMorale( 1000 )
	check( "dark text on a bright fill",        b.valueLabel:GetForeColor().R, dark.R )
	checkNear( "its outline is the fill colour", b.valueLabel:GetOutlineColor().R, 0.98 )
	check( "and the text is still there",       b.valueLabel:GetText(), "1,000" )
	check( "the right-hand readout too, at full", b.pctLabel:GetForeColor().R, dark.R )

	-- the fill drops away from under the right-hand readout but not the left
	player:SetMorale( 800 )
	check( "the readout over the track goes back to white", b.pctLabel:GetForeColor().R, s.colorText.R )
	check( "with a black outline again",                    b.pctLabel:GetOutlineColor().R, 0 )
	check( "the readout still over the fill stays dark",    b.valueLabel:GetForeColor().R, dark.R )

	local recoloured = stub.Counted( b.valueLabel, "SetText" )
	player:SetMorale( 790 )
	player:SetMorale( 780 )
	check( "the colour is not re-applied while nothing flips",
		stub.Counted( b.valueLabel, "SetText" ) - recoloured <= 2, true )

	-- into the danger band, whose red is dark: the left readout goes back to white
	player:SetMorale( 100 )
	check( "dark red takes white text", b.valueLabel:GetForeColor().R, s.colorText.R )

	s.textContrast = false
	GRISTLE.ApplyAll()
	player:SetMorale( 1000 )
	check( "with contrast off the text stays white", b.valueLabel:GetForeColor().R, s.colorText.R )
	s.textContrast = true

	-- blend ----------------------------------------------------------------------------------------

	s.colorMorale = { R = 0, G = 1, B = 0 }
	s.colorMoraleWarn = { R = 1, G = 1, B = 0 }
	s.colorMoraleDanger = { R = 1, G = 0, B = 0 }
	s.colorBlend = true
	GRISTLE.ApplyAll()

	player:SetMorale( 1000 )
	checkNear( "blend at full is the morale colour", b.fill:GetBackColor().R, 0 )
	player:SetMorale( 750 )
	checkNear( "halfway to warn is halfway between", b.fill:GetBackColor().R, 0.5 )
	player:SetMorale( 500 )
	checkNear( "at warn it is the warn colour",       b.fill:GetBackColor().G, 1 )
	-- below warn the colour holds: only the healthy half slides
	player:SetMorale( 375 )
	checkNear( "between warn and danger it holds the warn colour", b.fill:GetBackColor().G, 1 )
	checkNear( "all of it",                                        b.fill:GetBackColor().R, 1 )

	local held = stub.Counted( b.fill, "SetBackColor" )
	player:SetMorale( 360 )
	player:SetMorale( 300 )
	check( "and is not re-set while it holds", stub.Counted( b.fill, "SetBackColor" ), held )

	-- danger is not faded into: one step over the line and it is fully red
	player:SetMorale( 251 )
	checkNear( "just above danger is still the warn colour", b.fill:GetBackColor().G, 1 )
	player:SetMorale( 250 )
	checkNear( "at danger it is the danger colour, fully",   b.fill:GetBackColor().G, 0 )
	checkNear( "with nothing of warn left in it",            b.fill:GetBackColor().R, 1 )
	player:SetMorale( 100 )
	checkNear( "below danger it stays the danger colour",    b.fill:GetBackColor().G, 0 )

	local blended = stub.Counted( b.fill, "SetBackColor" )
	player:SetMorale( 101 )
	player:SetMorale( 102 )
	check( "and is not re-set while it holds either", stub.Counted( b.fill, "SetBackColor" ), blended )

	player:SetMorale( 800 )
	blended = stub.Counted( b.fill, "SetBackColor" )
	player:SetMorale( 801 )
	player:SetMorale( 802 )
	check( "the slide is set once per whole percent, not per event",
		stub.Counted( b.fill, "SetBackColor" ), blended )

	s.colorBlend = false
	GRISTLE.ApplyAll()
	player:SetMorale( 750 )
	checkNear( "blend off goes back to hard bands", b.fill:GetBackColor().R, 0 )

	-- the two readouts share one weight -------------------------------------------------------------

	s.boldValue = true
	s.fontSize, s.percentFontSize = 16, 14
	GRISTLE.ApplyAll()
	check( "with bold on, the number is bold",          b.valueLabel:GetFont(), "font:VerdanaBold16" )
	check( "and so is the percentage beside it",        b.pctLabel:GetFont(),   "font:VerdanaBold16" )

	s.boldValue = false
	GRISTLE.ApplyAll()
	check( "with bold off, the number keeps its size",  b.valueLabel:GetFont(), "font:Verdana16" )
	check( "and the percentage keeps its own",          b.pctLabel:GetFont(),   "font:Verdana14" )

	s.boldValue = true
	GRISTLE.ApplyAll()

	-- the hex boxes in the options panel -----------------------------------------------------------

	-- the colour rows come after the template boxes; the first of them is Morale
	local moraleHex = boxes[9]

	moraleHex:SetText( "FF0" )
	moraleHex.TextChanged( moraleHex, {} )
	checkNear( "half a code is not committed", s.colorMorale.R, 0 )

	moraleHex:SetText( "#ff0000" )
	moraleHex.TextChanged( moraleHex, {} )
	checkNear( "a whole code is", s.colorMorale.R, 1 )
	checkNear( "every channel of it", s.colorMorale.G, 0 )

	local saved = Turbine.PluginData.Load( Turbine.DataScope.Character, "gristleSettings" )
	checkNear( "and reaches the savefile", tonumber( saved.colorMorale.R ), 1 )

	player:SetMorale( 1000 )
	checkNear( "and the bar", b.fill:GetBackColor().R, 1 )

	-- back to stock for whatever runs after this
	for _, key in ipairs( { "colorMorale", "colorMoraleWarn", "colorMoraleDanger" } ) do
		s[ key ] = GRISTLE.DeepCopy( GRISTLE.Defaults[ key ] )
	end
	GRISTLE.Save()
	GRISTLE.ApplyAll()
	player:SetMorale( 1000 )

end

---------------------------------------------------------------------------------------------------
section( "teardown" )
---------------------------------------------------------------------------------------------------

local targetActor = stub.NewActor( { name = "Final", morale = 10, maxMorale = 10, kind = "monster" } )
player:SetTarget( targetActor )

plugin.Unload()

check( "the player's morale handler was detached",  player.MoraleChanged, nil )
check( "the player's power handler was detached",   player.PowerChanged, nil )
check( "the player's name handler was detached",    player.NameChanged, nil )
check( "the player's level handler was detached",   player.LevelChanged, nil )
check( "the target changed handler was detached",   player.TargetChanged, nil )
check( "no combat handler was left behind",         player.InCombatChanged, nil )
check( "the target's handler was detached",         targetActor.MoraleChanged, nil )
check( "the target's name handler was detached",    targetActor.NameChanged, nil )
check( "the target's level handler was detached",   targetActor.LevelChanged, nil )

local stillUpdating = false
for i = 1, #stub.updaters do
	if stub.updaters[i]:WantsUpdates() then stillUpdating = true end
end
check( "nothing is left asking for updates", stillUpdating, false )

---------------------------------------------------------------------------------------------------

print( string.format( "\n%d passed, %d failed", passed, failed ) )

os.exit( failed == 0 and 0 or 1 )
