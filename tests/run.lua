--=================================================================================================
--= Sinew tests
--=
--= Run from the plugin root with a desktop Lua (the game ships 5.1):
--=
--=     cd Sinew && lua tests/run.lua
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
                                power = 500, maxPower = 500, kind = "player" } )

stub.Install( player, { euro = euro } )

print( euro and "=== German/French client ===" or "=== English client ===" )

---------------------------------------------------------------------------------------------------
section( "load" )
---------------------------------------------------------------------------------------------------

local ok, err = pcall( function() import( "Sinew.Main" ) end )

check( "Main.lua loads against the Turbine stub", ok, true )

if not ok then
	print( "          " .. tostring( err ) )
	print( "\naborting: nothing below can run" )
	os.exit( 1 )
end

check( "the self window was built",   SINEW.Self.window   ~= nil, true )
check( "the target window was built", SINEW.Target.window ~= nil, true )
check( "a load banner was printed",   #stub.lines > 0, true )

---------------------------------------------------------------------------------------------------
section( "defaults and clamping" )
---------------------------------------------------------------------------------------------------

check( "version stamped", SINEW.Settings.version, 4 )
check( "self width defaulted", SINEW.Settings.selfWidth, 260 )
check( "the target hairline is on by default", SINEW.Settings.targetShowPower, true )
check( "both name rows are on by default",
	SINEW.Settings.selfShowName and SINEW.Settings.targetShowName, true )
check( "colours are plain tables, not Color instances",
	getmetatable( SINEW.Settings.colorMorale ), nil )

-- the settings must not alias the shared palette, or editing one would edit the other
SINEW.Settings.colorMorale.R = 0.123
check( "settings do not alias SINEW.Palette", SINEW.Palette.morale.R, 0.22 )
SINEW.Settings.colorMorale.R = 0.22

-- deliberately invalid values, as a hand-edited savefile could contain
SINEW.Settings.selfWidth     = 0
SINEW.Settings.selfBarHeight = "banana"
SINEW.Settings.warnPercent   = 20
SINEW.Settings.dangerPercent = 90
SINEW.Settings.colorMorale   = "not a colour"
SINEW.Settings.opacity       = 99

SINEW.NormaliseSettings()

check( "a zero width is clamped up",        SINEW.Settings.selfWidth, 40 )
check( "a non-numeric height falls back",   SINEW.Settings.selfBarHeight, 34 )
check( "a broken colour falls back",        SINEW.Settings.colorMorale.G, 0.78 )
check( "an over-range opacity is clamped",  SINEW.Settings.opacity, 1.0 )
check( "danger is pushed below warn",       SINEW.Settings.dangerPercent < SINEW.Settings.warnPercent, true )

SINEW.Settings.nameFontSize = 99
SINEW.NormaliseSettings()
check( "an over-range name size is clamped", SINEW.Settings.nameFontSize, 23 )

---------------------------------------------------------------------------------------------------
-- the 1 -> 2 migration
---------------------------------------------------------------------------------------------------
-- filling in a missing key cannot deliver a changed default: a version 1 savefile already holds the
-- old value, so without the migration the target hairline would stay off forever on every existing
-- character

SINEW.Settings = { version = 1, targetShowPower = false, selfWidth = 300 }
SINEW.NormaliseSettings()

check( "a version 1 savefile has the target hairline turned on", SINEW.Settings.targetShowPower, true )
check( "and is restamped",                                      SINEW.Settings.version, 4 )
check( "while its own settings are left alone",                 SINEW.Settings.selfWidth, 300 )

-- but a deliberate choice made since must survive the next load
SINEW.Settings.targetShowPower = false
SINEW.NormaliseSettings()
check( "a current savefile is not migrated a second time", SINEW.Settings.targetShowPower, false )

---------------------------------------------------------------------------------------------------
-- the 3 -> 4 migration
---------------------------------------------------------------------------------------------------
-- The three readout switches became four templates per window. A switch that was on has to become
-- the template it used to produce, and a switch that was off has to become an empty one - clearing a
-- template is the only way a readout is turned off now, so "it was off" is not expressible any
-- other way.

SINEW.Settings = { version = 3, showValue = true, showPercent = true, showLevel = true }
SINEW.NormaliseSettings()

check( "a version 3 savefile keeps its absolute number",
	SINEW.Settings.selfFormatBarLeft, "[cur]  [temp]" )
check( "and its percentage",       SINEW.Settings.selfFormatBarRight, "[perc]" )
check( "and its name",             SINEW.Settings.selfFormatNameMain, "[name]" )
check( "and its level",            SINEW.Settings.selfFormatNameAside, "Level [level]" )
check( "the target frame too",     SINEW.Settings.targetFormatBarRight, "[perc]" )
check( "and the dead switches are gone", SINEW.Settings.showValue, nil )
check( "all three of them",
	SINEW.Settings.showPercent == nil and SINEW.Settings.showLevel == nil, true )

-- a switch that was off becomes a cleared template, not a defaulted one
SINEW.Settings = { version = 3, showValue = false, showPercent = true, showLevel = false }
SINEW.NormaliseSettings()

check( "a readout that was switched off comes through empty",
	SINEW.Settings.selfFormatBarLeft, "" )
check( "and a level that was switched off too",
	SINEW.Settings.targetFormatNameAside, "" )
check( "while the one that was on is kept",
	SINEW.Settings.selfFormatBarRight, "[perc]" )

-- and an emptied template must survive the next load rather than being refilled from the defaults
SINEW.NormaliseSettings()
check( "an empty template is not defaulted back", SINEW.Settings.selfFormatBarLeft, "" )

---------------------------------------------------------------------------------------------------
-- a hand-edited or euro savefile
---------------------------------------------------------------------------------------------------

SINEW.Settings = {}
SINEW.NormaliseSettings()

-- a German or French savefile turns anything that parses as a number back into one
SINEW.Settings.selfFormatBarLeft = 100
SINEW.NormaliseSettings()
check( "a numeric template is coerced to a string", SINEW.Settings.selfFormatBarLeft, "100" )

SINEW.Settings.selfFormatBarLeft = { "not a template" }
SINEW.NormaliseSettings()
check( "a template that is not text falls back",
	SINEW.Settings.selfFormatBarLeft, SINEW.Defaults.selfFormatBarLeft )

-- the one setting with no natural upper bound. The bar clips what does not fit, so an enormous
-- template would not be visible, only rendered.
SINEW.Settings.selfFormatBarLeft = string.rep( "[cur]", 200 )
SINEW.NormaliseSettings()
check( "an absurd template is capped", string.len( SINEW.Settings.selfFormatBarLeft ), 120 )

SINEW.Settings = {}
SINEW.NormaliseSettings()
SINEW.ApplyAll()

---------------------------------------------------------------------------------------------------
section( "number formatting" )
---------------------------------------------------------------------------------------------------

check( "zero",            SINEW.FormatNumber( 0 ),       "0" )
check( "three digits",    SINEW.FormatNumber( 999 ),     "999" )
check( "four digits",     SINEW.FormatNumber( 1000 ),    "1,000" )
check( "five digits",     SINEW.FormatNumber( 12480 ),   "12,480" )
check( "seven digits",    SINEW.FormatNumber( 1234567 ), "1,234,567" )
check( "negative",        SINEW.FormatNumber( -1500 ),   "-1,500" )
check( "fractional down", SINEW.FormatNumber( 1000.9 ),  "1,000" )

check( "percent",          SINEW.FormatPercent( 500, 1000 ), "50%" )
check( "percent rounds",   SINEW.FormatPercent( 834, 1000 ), "83%" )
check( "percent, zero max", SINEW.FormatPercent( 10, 0 ),    "0%" )

check( "percent, one decimal",  SINEW.FormatPercent( 743, 1000, 1 ), "74.3%" )
check( "percent, two decimals", SINEW.FormatPercent( 743, 1000, 2 ), "74.30%" )
-- the decimal count comes out of a user-typed template, so [perc:9] has to land somewhere
check( "percent, decimals clamped", SINEW.FormatPercent( 743, 1000, 9 ), "74.30%" )
check( "percent, junk decimals",    SINEW.FormatPercent( 500, 1000, "x" ), "50%" )

---------------------------------------------------------------------------------------------------
-- the abbreviated form
---------------------------------------------------------------------------------------------------
-- The precision steps down as the number grows, and a trailing zero is dropped: 12.0k is not more
-- precise than 12k, it only looks it.

check( "short, below a thousand",   SINEW.FormatShort( 743 ),     "743" )
check( "short, exactly a thousand", SINEW.FormatShort( 1000 ),    "1k" )
check( "short, one decimal kept",   SINEW.FormatShort( 1500 ),    "1.5k" )
check( "short, five digits",        SINEW.FormatShort( 12480 ),   "12.5k" )
check( "short, trailing zero gone", SINEW.FormatShort( 12000 ),   "12k" )
check( "short, decimal dropped at six digits", SINEW.FormatShort( 243200 ), "243k" )
check( "short, millions",           SINEW.FormatShort( 1240000 ), "1.24M" )
check( "short, a round million",    SINEW.FormatShort( 1000000 ), "1M" )
check( "short, negative",           SINEW.FormatShort( -12480 ),  "-12.5k" )
check( "short, zero",               SINEW.FormatShort( 0 ),       "0" )

-- FormatValue is what a tag calls: the setting decides, unless the tag said otherwise
SINEW.Settings.abbreviateNumbers = false
check( "unabbreviated by default",   SINEW.FormatValue( 12480 ), "12,480" )
check( "a tag can force the short form", SINEW.FormatValue( 12480, "short" ), "12.5k" )

SINEW.Settings.abbreviateNumbers = true
check( "the setting abbreviates",    SINEW.FormatValue( 12480 ), "12.5k" )
check( "a tag can force the long form", SINEW.FormatValue( 12480, "full" ), "12,480" )

SINEW.Settings.abbreviateNumbers = false

---------------------------------------------------------------------------------------------------
section( "readout templates" )
---------------------------------------------------------------------------------------------------
-- Rendering is pure, so it is tested without a window in the way. The context is keyed by the same
-- names as the tags, which is the whole reason a tag cannot drift from the field it describes.

local ctx = {
	cur = 743, max = 1000, temp = 0, maxtemp = 0,
	pow = 250, maxpow = 500, name = "Souru", level = 150,
}

local render = SINEW.Format.Render

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

local selfWindow = SINEW.Self.window
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
	effectivelyVisible( SINEW.Target.window.moraleBar.fill ), true )
check( "and its readout",
	effectivelyVisible( SINEW.Target.window.moraleBar.valueLabel ), true )

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
SINEW.Settings.selfFormatBarLeft = ""
SINEW.Settings.selfFormatBarRight = ""
player:SetMorale( 742 )
check( "clearing a template drops that readout", bar.valueLabel:GetText(), "" )
check( "and the other one with it",              bar.pctLabel:GetText(),   "" )

SINEW.Settings.selfFormatBarLeft  = SINEW.Defaults.selfFormatBarLeft
SINEW.Settings.selfFormatBarRight = SINEW.Defaults.selfFormatBarRight
player:SetMorale( 1000 )

---------------------------------------------------------------------------------------------------
-- a template is free of where it sits
---------------------------------------------------------------------------------------------------
-- The context lives on the window and both widgets render against it, so a tag works wherever it is
-- typed. The case that justifies the indirection is power inside the morale bar: the hairline is
-- four pixels tall, so without this there is no way to see a power number at all.

player:SetMorale( 743 )
player:SetPowerValue( 250 )

SINEW.Settings.selfFormatBarLeft  = "[cur]  [pow]"
SINEW.Settings.selfFormatBarRight = "[powperc]"
SINEW.ApplyFormats()

check( "power can be read inside the morale bar", bar.valueLabel:GetText(), "743  250" )
check( "and as a percentage",                     bar.pctLabel:GetText(),   "50%" )

-- and the other way round: a vital on the name row, which holds no data of its own
SINEW.Settings.selfFormatNameMain  = "[name]"
SINEW.Settings.selfFormatNameAside = "[perc]"
SINEW.ApplyFormats()

check( "a vital can be read on the name row",
	SINEW.Self.window.nameRow.extraLabel:GetText(), "74%" )

-- a morale event has to reach the name row now that its template can name a vital
player:SetMorale( 500 )
check( "a morale change reaches the name row",
	SINEW.Self.window.nameRow.extraLabel:GetText(), "50%" )

-- a power event has to reach the morale bar for the same reason
player:SetPowerValue( 125 )
check( "a power change reaches the morale bar", bar.pctLabel:GetText(), "25%" )

-- the hairline can be off while a template still names power
SINEW.Settings.selfShowPower = false
SINEW.ApplyAll()
player:SetPowerValue( 500 )
check( "power still reads with the hairline switched off", bar.pctLabel:GetText(), "100%" )

SINEW.Settings.selfShowPower = true

-- the deficit, in the place it is actually useful
SINEW.Settings.selfFormatBarRight = "[deficit]"
player:SetMorale( 1000 )
check( "the deficit is blank at full morale", bar.pctLabel:GetText(), "" )

player:SetMorale( 743 )
check( "and appears the moment something is missing", bar.pctLabel:GetText(), "-257" )

-- the abbreviation setting reaches a live readout without a relayout
SINEW.Settings.selfFormatBarLeft = "[cur]"
player:SetMaxMorale( 20000 )
player:SetMorale( 12480 )
check( "unabbreviated to begin with", bar.valueLabel:GetText(), "12,480" )

SINEW.Settings.abbreviateNumbers = true
SINEW.ApplyFormats()
check( "abbreviating is live",        bar.valueLabel:GetText(), "12.5k" )

SINEW.Settings.abbreviateNumbers = false
SINEW.ApplyFormats()
check( "and reversible",              bar.valueLabel:GetText(), "12,480" )

-- ApplyFormats must not do what ApplyAll does: a relayout clears every dirty-flag cache and blanks
-- the bars until the next vital event, which for your own morale at full health is a long way off
local fillBefore = bar.fill:GetWidth()
SINEW.ApplyFormats()
check( "re-rendering does not disturb the fill", bar.fill:GetWidth(), fillBefore )

-- and the dirty flag still holds through it
local textBefore = stub.Counted( bar.valueLabel, "SetText" )
SINEW.ApplyFormats()
SINEW.ApplyFormats()
check( "an unchanged render does not re-set the text",
	stub.Counted( bar.valueLabel, "SetText" ), textBefore )

player:SetMaxMorale( 1000 )
player:SetMorale( 1000 )
player:SetPowerValue( 500 )

SINEW.Settings.selfFormatBarLeft    = SINEW.Defaults.selfFormatBarLeft
SINEW.Settings.selfFormatBarRight   = SINEW.Defaults.selfFormatBarRight
SINEW.Settings.selfFormatNameMain   = SINEW.Defaults.selfFormatNameMain
SINEW.Settings.selfFormatNameAside  = SINEW.Defaults.selfFormatNameAside
SINEW.ApplyAll()

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
check( "healthy is the normal colour", bar.fill:GetBackColor().G, SINEW.Settings.colorMorale.G )

player:SetMorale( 400 )   -- below the 50% warn line
check( "below warn is the warn colour", bar.fill:GetBackColor().G, SINEW.Settings.colorMoraleWarn.G )

player:SetMorale( 200 )   -- below the 25% danger line
check( "below danger is the danger colour", bar.fill:GetBackColor().G, SINEW.Settings.colorMoraleDanger.G )

-- a band is applied once on entry, not on every update
local colorBefore = stub.Counted( bar.fill, "SetBackColor" )
player:SetMorale( 190 )
player:SetMorale( 180 )
player:SetMorale( 170 )
check( "staying in a band does not re-set the colour",
	stub.Counted( bar.fill, "SetBackColor" ), colorBefore )

player:SetMorale( 1000 )
check( "recovering returns to the normal colour", bar.fill:GetBackColor().G, SINEW.Settings.colorMorale.G )

-- the power bar must never threshold-colour: running low on power is not an emergency
local powerBar = selfWindow.powerBar
player:SetPowerValue( 10 )
check( "the power bar keeps its colour when low",
	powerBar.fill:GetBackColor().B, SINEW.Settings.colorPower.B )
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
check( "the pool caps at its size instead of erroring", visibleFlashes( bar ) <= SINEW.FlashPool, true )

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
SINEW.Settings.flash = false
player:SetMorale( 1000 )
player:SetMorale( 500 )
check( "the flash can be disabled", visibleFlashes( bar ), 0 )
SINEW.Settings.flash = true

---------------------------------------------------------------------------------------------------
section( "power hairline" )
---------------------------------------------------------------------------------------------------

player:SetPowerValue( 250 )
check( "half power is half the hairline", powerBar.fill:GetWidth(), 130 )
check( "the hairline is as thin as configured", powerBar.height, SINEW.Settings.selfPowerHeight )
check( "the hairline carries no labels", powerBar.valueLabel, nil )
check( "the hairline sits below the morale bar", powerBar.y > bar.y, true )

SINEW.Settings.selfShowPower = false
SINEW.ApplyAll()
check( "the hairline can be switched off", powerBar.track:IsVisible(), false )

SINEW.Settings.selfShowPower = true
SINEW.ApplyAll()
check( "and back on", powerBar.track:IsVisible(), true )

---------------------------------------------------------------------------------------------------
section( "target tracking" )
---------------------------------------------------------------------------------------------------

local targetWindow = SINEW.Target.window

check( "no target means a hidden window", targetWindow.window:IsVisible(), false )

local orc = stub.NewActor( { name = "Orc", morale = 8000, maxMorale = 10000, kind = "monster" } )
player:SetTarget( orc )

check( "targeting a monster shows the window", targetWindow.window:IsVisible(), true )
check( "and fills the bar to its morale",      targetWindow.moraleBar.fill:GetWidth(),
	math.floor( 8000 / 10000 * 260 ) )
check( "and reads out the percentage",         targetWindow.moraleBar.pctLabel:GetText(), "80%" )

orc:SetMorale( 5000 )
check( "the target's morale is tracked live", targetWindow.moraleBar.fill:GetWidth(), 130 )

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
check( "nor the power hairline",              targetWindow.powerBar.track:IsVisible(), false )
check( "an object has no level to show",      targetWindow.nameRow.extraLabel:GetText(), "" )

-- and the old target must have been let go
orc:SetMorale( 1 )
check( "the dropped target no longer drives the bar", SINEW.Target.entity, chest )
check( "and its handlers are gone",                   orc.MoraleChanged, nil )

-- targeting something with vitals again brings the bar straight back
orc:SetMorale( 5000 )
player:SetTarget( orc )
check( "the fill comes back",    targetWindow.moraleBar.clip:IsVisible(), true )
check( "the readout comes back", targetWindow.moraleBar.labelBack:IsVisible(), true )
check( "and it is filled",       targetWindow.moraleBar.fill:GetWidth(), 130 )
check( "with its readout",       targetWindow.moraleBar.pctLabel:GetText(), "50%" )

---------------------------------------------------------------------------------------------------
-- the two frames have their own templates
---------------------------------------------------------------------------------------------------
-- Per window rather than shared, unlike the font sizes: your own morale is the number you act on
-- and a target's is usually only a percentage, and that is the one question the three switches these
-- replaced could not answer.

SINEW.Settings.targetFormatBarLeft  = "[perc]"
SINEW.Settings.targetFormatBarRight = "[cur] / [max]"
SINEW.ApplyFormats()

check( "the target bar uses its own templates",
	targetWindow.moraleBar.valueLabel:GetText(), "50%" )
check( "both of them",
	targetWindow.moraleBar.pctLabel:GetText(), "5,000 / 10,000" )
-- tested by shape rather than by value: the player's morale at this point in the suite is whatever
-- the sections above left it at, and what matters is that it is still rendering its own template
check( "and the player bar did not take the target's percentage",
	string.find( SINEW.Self.window.moraleBar.valueLabel:GetText(), "%%" ), nil )

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

SINEW.Settings.targetFormatBarLeft  = SINEW.Defaults.targetFormatBarLeft
SINEW.Settings.targetFormatBarRight = SINEW.Defaults.targetFormatBarRight
SINEW.ApplyFormats()

player:SetTarget( nil )
check( "clearing the target hides the window", targetWindow.window:IsVisible(), false )

-- swapping between two live targets must not leak a handler
local a = stub.NewActor( { name = "A", morale = 100, maxMorale = 100, kind = "monster" } )
local b = stub.NewActor( { name = "B", morale = 50,  maxMorale = 100, kind = "monster" } )

player:SetTarget( a )
player:SetTarget( b )

check( "the new target is attached", SINEW.Target.entity, b )
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
check( "the hairline is as thin as configured",  targetPower.height, SINEW.Settings.targetPowerHeight )

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

SINEW.Settings.targetShowPower = false
SINEW.ApplyAll()
player:SetTarget( caster )
check( "the setting still wins over an available power", targetPower.track:IsVisible(), false )

SINEW.Settings.targetShowPower = true
SINEW.ApplyAll()
check( "and turning it back on restores the hairline", targetPower.track:IsVisible(), true )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "the name row" )
---------------------------------------------------------------------------------------------------

local selfName = selfWindow.nameRow

check( "the player's name is on the row",  selfName.nameLabel:GetText(), "Souru" )
check( "and their level beside it",        selfName.extraLabel:GetText(), "Level 100" )

-- the row is a text row, so its height follows its own font rather than a setting of its own
check( "the row height follows the name font", SINEW.NameHeight(), SINEW.Settings.nameFontSize + 4 )

-- and it pushes the bars down rather than lifting itself above where they already were
check( "the morale bar sits below the row",
	bar.y, SINEW.NameHeight() + SINEW.Settings.selfGap )

-- clipped, not wrapped: a name longer than the bar is cut off at the end of the bar
check( "the row is clipped to the bar's width",
	selfName.clip:GetWidth(), SINEW.Settings.selfWidth - 2 * SINEW.LabelPadding )

-- the dirty flag, as everywhere else
local nameBefore = stub.Counted( selfName.nameLabel, "SetText" )
SINEW.Self.RefreshName()
SINEW.Self.RefreshName()
check( "an unchanged name does not re-set the text",
	stub.Counted( selfName.nameLabel, "SetText" ), nameBefore )

SINEW.Settings.selfFormatNameAside = ""
SINEW.Self.RefreshName()
check( "clearing the aside template drops the level", selfName.extraLabel:GetText(), "" )

-- and the word in front of the number is the player's, which is the one bit of localisation Sinew
-- needs: a German client wants "Stufe 150"
SINEW.Settings.selfFormatNameAside = "Stufe [level]"
SINEW.Self.RefreshName()
check( "the label beside the level is the template's", selfName.extraLabel:GetText(), "Stufe 100" )

SINEW.Settings.selfFormatNameAside = SINEW.Defaults.selfFormatNameAside
SINEW.Self.RefreshName()
check( "and back on", selfName.extraLabel:GetText(), "Level 100" )

SINEW.Settings.selfShowName = false
SINEW.ApplyAll()

check( "the row can be switched off",            selfName.clip:IsVisible(), false )
check( "and the morale bar takes the top back",  bar.y, 0 )

SINEW.Settings.selfShowName = true
SINEW.ApplyAll()
check( "and switched back on", selfName.clip:IsVisible(), true )
check( "the name survives a relayout", selfName.nameLabel:GetText(), "Souru" )

-- the row has to be click-through like everything else Sinew draws
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

check( "ReadName of nil is an empty string", SINEW.ReadName( nil ), "" )
check( "ReadLevel of nil is nil",            SINEW.ReadLevel( nil ), nil )

player:SetTarget( nil )

---------------------------------------------------------------------------------------------------
section( "a maximum that reads zero" )
---------------------------------------------------------------------------------------------------
-- A maximum of 0 makes a bar undrawable -- there is no percentage of zero -- so a vital whose
-- GetMax* answers 0 produced a blank bar with no readout at all, while the bar beside it whose
-- maximum happened to read worked perfectly. GetBaseMax* is the fallback.

local zeroMax = stub.NewActor( { name = "ZeroMax", morale = 700, maxMorale = 1000, kind = "monster" } )
zeroMax.GetMaxMorale = function() return 0 end

local gotMorale, gotMax = SINEW.ReadVital( zeroMax, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

check( "a zero maximum falls back to the base maximum", gotMax, 1000 )
check( "and the current value is unchanged",            gotMorale, 700 )

-- with no fallback named, a zero maximum is still unreadable
check( "a zero maximum with no fallback reads nothing",
	SINEW.ReadVital( zeroMax, "GetMorale", "GetMaxMorale" ), nil )

-- both zero is genuinely unreadable
local bothZero = stub.NewActor( { name = "Both", morale = 10, maxMorale = 10, kind = "monster" } )
bothZero.GetMaxMorale     = function() return 0 end
bothZero.GetBaseMaxMorale = function() return 0 end

check( "both maxima at zero reads nothing",
	SINEW.ReadVital( bothZero, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" ), nil )

-- a current of 0 is a dead target, not an unreadable one, and must still draw
local dead = stub.NewActor( { name = "Dead", morale = 0, maxMorale = 1000, kind = "monster" } )
local deadCurrent, deadMax = SINEW.ReadVital( dead, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" )

check( "a current of zero still reads", deadCurrent, 0 )
check( "with its maximum intact",       deadMax, 1000 )

-- /sinew debug is the tool for when something is already wrong, so it has to work on a broken
-- entity above all. A diagnostic that throws is worse than none.
stub.lines = {}
local debugOk = pcall( function() stub.command:Execute( "sinew", "debug" ) end )

check( "the debug command runs", debugOk, true )
check( "and prints something",   #stub.lines > 5, true )

local printed = table.concat( stub.lines, "\n" )
check( "it reports the raw getter answers", string.find( printed, "GetBaseMaxMorale" ) ~= nil, true )
check( "and what was made of them",         string.find( printed, "what Sinew read" ) ~= nil, true )
check( "and the fill colour, for an invisible-bar diagnosis",
	string.find( printed, "fill color" ) ~= nil, true )
-- both the template and what it rendered to: a blank readout is either an empty template or one
-- whose every tag came back empty, and the two look identical on screen
check( "and the context every template was rendered against",
	string.find( printed, "the render context" ) ~= nil, true )

---------------------------------------------------------------------------------------------------
-- /sinew format is the only documentation a player gets
---------------------------------------------------------------------------------------------------
-- The options panel has room for the tag names and not for what they mean, and this game has no
-- tooltip to put the rest in. A readout is typed, so looking up what can be typed has to work.

stub.lines = {}
local formatOk = pcall( function() stub.command:Execute( "sinew", "format" ) end )

check( "the format command runs", formatOk, true )

local formatText = table.concat( stub.lines, "\n" )

check( "it lists every tag", #SINEW.Format.Help, 11 )

local missing = 0
for i = 1, #SINEW.Format.Help do
	if string.find( formatText, SINEW.Format.Help[i][1], 1, true ) == nil then
		missing = missing + 1
		print( "          not listed: " .. SINEW.Format.Help[i][1] )
	end
end

check( "and prints all of them", missing, 0 )
check( "with the modifiers",
	string.find( formatText, "[cur:short]", 1, true ) ~= nil, true )
check( "and what the frames are currently set to",
	string.find( formatText, "player bar", 1, true ) ~= nil, true )

-- every tag the help text advertises has to actually resolve, or the documentation lies
local unresolved = 0
for i = 1, #SINEW.Format.Help do
	local tag = SINEW.Format.Help[i][1]
	if SINEW.Format.Render( tag, { cur = 500, max = 1000, temp = 100, maxtemp = 200,
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
	SINEW.ReadVital( angry, "GetMorale", "GetMaxMorale", "GetBaseMaxMorale" ), nil )

-- and the whole way through, to the drawn bar
player.GetMaxMorale = function() return 0 end
player.morale = 500
bar:Reset()

check( "the player's bar fills from the base maximum", SINEW.Self.RefreshMorale(), true )
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

check( "an unready target is still attached to", SINEW.Target.entity, slow )
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

check( "a failed read leaves the bar empty", SINEW.Self.RefreshMorale(), false )

-- power still has to be drawn on a tick where morale failed, which is exactly what the screenshot
-- showed: a full hairline under an empty morale bar
check( "but power is still read", SINEW.Self.RefreshPower(), true )

SINEW.Self.RefreshPersistently()

playerReady = true
stub.Tick( 0.3 )

check( "the retry fills the morale bar in once it reads", bar.fill:GetWidth(), 260 )
check( "and the readout with it",                         bar.valueLabel:GetText(), "1,000" )

player.GetMaxMorale = realMaxMorale
SINEW.Updater.Clear()

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

-- it is the one thing in Sinew that takes the mouse, so it has to be switchable
SINEW.Settings.entityControl = false
SINEW.ApplyAll()

check( "switching it off restores a click-through HUD",
	selfWindow.entityControl:IsMouseVisible(), false )
check( "and takes it off screen", selfWindow.entityControl:IsVisible(), false )

SINEW.Settings.entityControl = true
SINEW.ApplyAll()
check( "and back on", selfWindow.entityControl:IsMouseVisible(), true )

---------------------------------------------------------------------------------------------------
section( "fine positioning" )
---------------------------------------------------------------------------------------------------

SINEW.Settings.mirrorTarget = false
SINEW.Settings.selfLeft, SINEW.Settings.selfTop = SINEW.PixelToRatio( 400, 500 )
SINEW.ApplyPositions()

selfWindow:Nudge( 1, 0 )
check( "one pixel right", selfWindow.window:GetLeft(), 401 )

selfWindow:Nudge( -1, 0 )
check( "and back",        selfWindow.window:GetLeft(), 400 )

selfWindow:Nudge( 0, -1 )
check( "one pixel up",    selfWindow.window:GetTop(),  499 )

-- a nudge saves, the same as a drag does
checkNear( "a nudge is saved", SINEW.Settings.selfTop, 499 / 1080 )

-- and it cannot walk a window off the screen
SINEW.Settings.selfLeft, SINEW.Settings.selfTop = SINEW.PixelToRatio( 0, 0 )
SINEW.ApplyPositions()
selfWindow:Nudge( -5, -5 )
check( "a nudge stops at the left edge", selfWindow.window:GetLeft(), 0 )
check( "and at the top edge",            selfWindow.window:GetTop(),  0 )

-- nudging a mirrored pair keeps them mirrored
SINEW.Settings.selfLeft, SINEW.Settings.selfTop = SINEW.PixelToRatio( 400, 500 )
SINEW.Settings.mirrorTarget = true
SINEW.ApplyPositions()

selfWindow:Nudge( 3, 0 )
check( "the player frame moved", selfWindow.window:GetLeft(), 403 )
check( "and its mirror moved with it",
	targetWindow.window:GetLeft(), 1920 - 403 - targetWindow.window:GetWidth() )

-- and nudging the mirror itself moves what it mirrors
targetWindow:Nudge( 2, 0 )
check( "nudging the mirror moved the player frame", selfWindow.window:GetLeft(), 401 )

SINEW.Settings.mirrorTarget = false
SINEW.ApplyPositions()

---------------------------------------------------------------------------------------------------
section( "frame alignment" )
---------------------------------------------------------------------------------------------------

-- Fixed per frame rather than configurable, and one direction for the whole frame: the player's
-- reads inward from the left and the target's inward from the right, name row and bar readouts
-- alike, so the pair is a reflection rather than two frames that happen to sit near each other.

local alignment = Turbine.UI.ContentAlignment

SINEW.ApplyAll()

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
SINEW.Settings.nameAlignRight = true
SINEW.NormaliseSettings()
check( "a stale name alignment setting is cleared", SINEW.Settings.nameAlignRight, nil )
check( "and it is not a default",                   SINEW.Defaults.nameAlignRight, nil )

-- a relayout must not quietly undo it
SINEW.Settings.nameFontSize = 16
SINEW.ApplyAll()
check( "the target's name is still right after a relayout",
	targetWindow.nameRow.nameLabel:GetTextAlignment(), alignment.MiddleRight )
check( "and its readouts too",
	targetWindow.moraleBar.valueLabel:GetTextAlignment(), alignment.MiddleRight )
SINEW.Settings.nameFontSize = 14
SINEW.ApplyAll()

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

SINEW.AddCallback( victim, "MoraleChanged", foreign )
check( "a single handler is stored bare", type( victim.MoraleChanged ), "function" )

local mine = function() end
SINEW.AddCallback( victim, "MoraleChanged", mine )
check( "a second handler promotes to a table", type( victim.MoraleChanged ), "table" )
check( "both are present", #victim.MoraleChanged, 2 )

victim:Fire( "MoraleChanged" )
check( "the pre-existing handler still runs", other.calls, 1 )

SINEW.RemoveCallback( victim, "MoraleChanged", mine )
check( "removing ours leaves theirs", #victim.MoraleChanged, 1 )

victim:Fire( "MoraleChanged" )
check( "theirs keeps running after ours is gone", other.calls, 2 )

SINEW.RemoveCallback( victim, "MoraleChanged", foreign )
check( "removing the last one clears the slot", victim.MoraleChanged, nil )

---------------------------------------------------------------------------------------------------
section( "options panel stepping" )
---------------------------------------------------------------------------------------------------

check( "an integer step", SINEW.StepValue( 260, 1, 10, 40, 1200, 0 ), 270 )
check( "stepping down",   SINEW.StepValue( 260, -1, 10, 40, 1200, 0 ), 250 )
check( "clamped at the top",    SINEW.StepValue( 1200, 1, 10, 40, 1200, 0 ), 1200 )
check( "clamped at the bottom", SINEW.StepValue( 40, -1, 10, 40, 1200, 0 ), 40 )
check( "a nil value lands on the minimum", SINEW.StepValue( nil, -1, 10, 40, 1200, 0 ), 40 )
check( "a junk value lands on the minimum", SINEW.StepValue( "x", -1, 10, 40, 1200, 0 ), 40 )

-- the reason StepValue exists: adding 0.05 twenty times in binary floating point drifts, and the
-- drifted value would be both printed and saved
local opacity = 0.05
for _ = 1, 19 do
	opacity = SINEW.StepValue( opacity, 1, 0.05, 0.05, 1.0, 2 )
end
check( "repeated 0.05 steps do not drift", opacity, 1.0 )

local fade = 0.35
fade = SINEW.StepValue( fade, 1, 0.05, 0.05, 2.0, 2 )
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

check( "there is a text box for every template", #boxes, 8 )

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
check( "and reaches the settings", SINEW.Settings.selfFormatBarLeft, "[perc:1]" )

local onDiskNow = Turbine.PluginData.Load( Turbine.DataScope.Character, "sinewSettings" )
check( "and the savefile", tostring( onDiskNow.selfFormatBarLeft ), "[perc:1]" )

-- a template survives the euro round trip, which turns anything that parses as a number back into
-- one. "[perc:1]" does not, which is the only reason this works at all.
check( "a template is still text on disk", type( onDiskNow.selfFormatBarLeft ), "string" )

SINEW.Settings.selfFormatBarLeft = SINEW.Defaults.selfFormatBarLeft
SINEW.Save()
SINEW.ApplyAll()

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

local ratioLeft, ratioTop = SINEW.PixelToRatio( 960, 540 )
checkNear( "pixel to ratio, left", ratioLeft, 0.5 )
checkNear( "pixel to ratio, top",  ratioTop,  0.5 )

local pixelLeft, pixelTop = SINEW.RatioToPixel( 0.5, 0.5 )
check( "ratio to pixel, left", pixelLeft, 960 )
check( "ratio to pixel, top",  pixelTop,  540 )

local cl, ct = SINEW.ClampToScreen( 5000, 5000, 260, 40 )
check( "clamped back inside, left", cl, 1920 - 260 )
check( "clamped back inside, top",  ct, 1080 - 40 )

local nl, nt = SINEW.ClampToScreen( -100, -100, 260, 40 )
check( "clamped off the near edge, left", nl, 0 )
check( "clamped off the near edge, top",  nt, 0 )

-- a window wider than the screen keeps its top left corner on screen
local wl, wt = SINEW.ClampToScreen( 10, 10, 4000, 40 )
check( "an oversized window keeps its left edge", wl, 0 )

---------------------------------------------------------------------------------------------------
section( "mirrored target position" )
---------------------------------------------------------------------------------------------------
-- the far edge is what is mirrored: a frame 100 in from the left puts its mirror 100 in from the
-- right, whatever the two widths are

check( "a frame at the left edge mirrors to the right edge",
	SINEW.MirrorLeft( 0, 260 ), 1920 - 260 )
check( "and 100 in from the left is 100 in from the right",
	SINEW.MirrorLeft( 100, 260 ), 1920 - 100 - 260 )

-- the reflection is its own inverse, which is what lets a mirrored window be dragged
check( "mirroring twice returns the original",
	SINEW.MirrorLeft( SINEW.MirrorLeft( 340, 260 ), 260 ), 340 )

-- a frame centred on the screen mirrors onto itself
check( "a centred frame mirrors onto itself",
	SINEW.MirrorLeft( ( 1920 - 260 ) / 2, 260 ), ( 1920 - 260 ) / 2 )

-- now through the real windows
SINEW.Settings.mirrorTarget = false
check( "the player window never mirrors", selfWindow:IsMirrored(), false )
check( "and the target window does not while it is off", targetWindow:IsMirrored(), false )

SINEW.Settings.selfLeft, SINEW.Settings.selfTop = SINEW.PixelToRatio( 300, 800 )
SINEW.Settings.targetLeft, SINEW.Settings.targetTop = SINEW.PixelToRatio( 100, 100 )
SINEW.ApplyPositions()

check( "unmirrored, the target keeps its own position, left", targetWindow.window:GetLeft(), 100 )
check( "unmirrored, the target keeps its own position, top",  targetWindow.window:GetTop(),  100 )

SINEW.Settings.mirrorTarget = true
SINEW.ApplyPositions()

check( "mirroring is live", targetWindow:IsMirrored(), true )
check( "the target reflects the player's position",
	targetWindow.window:GetLeft(), 1920 - 300 - targetWindow.window:GetWidth() )
check( "and sits at the player's height", targetWindow.window:GetTop(), 800 )
check( "the player window did not move", selfWindow.window:GetLeft(), 300 )

-- the saved target position is left alone while mirroring, so turning it off restores it
checkNear( "the target's own saved position is untouched",
	SINEW.Settings.targetLeft, 100 / 1920 )

SINEW.Settings.mirrorTarget = false
SINEW.ApplyPositions()
check( "turning it off restores the target's own position", targetWindow.window:GetLeft(), 100 )

---------------------------------------------------------------------------------------------------
-- dragging either frame while mirroring
---------------------------------------------------------------------------------------------------

SINEW.Settings.mirrorTarget = true
SINEW.SetMoveMode( true )
SINEW.ApplyPositions()

-- dragging the player frame carries the mirror live, not just on mouse up
selfWindow.moveControl.MouseDown( nil, { Button = 1, X = 0, Y = 0 } )
selfWindow.moveControl.MouseMove( nil, { Button = 1, X = 40, Y = 0 } )

local draggedLeft = selfWindow.window:GetLeft()
check( "the player frame moved", draggedLeft, 340 )
check( "and the mirror followed during the drag",
	targetWindow.window:GetLeft(), 1920 - draggedLeft - targetWindow.window:GetWidth() )

selfWindow.moveControl.MouseUp( nil, { Button = 1, X = 40, Y = 0 } )
checkNear( "the drag saved the player's position", SINEW.Settings.selfLeft, 340 / 1920 )

-- and dragging the mirror writes back to what it mirrors, rather than to a position it ignores
targetWindow.moveControl.MouseDown( nil, { Button = 1, X = 0, Y = 0 } )
targetWindow.moveControl.MouseMove( nil, { Button = 1, X = -50, Y = 0 } )
targetWindow.moveControl.MouseUp( nil, { Button = 1, X = -50, Y = 0 } )

-- the mirror moved 50 left, so its source moves 50 right
checkNear( "dragging the mirror moved the player frame", SINEW.Settings.selfLeft, 390 / 1920 )
check( "the player frame is where the mirror put it", selfWindow.window:GetLeft(), 390 )
check( "and the two are still reflections",
	targetWindow.window:GetLeft(), 1920 - 390 - targetWindow.window:GetWidth() )

-- a mirrored window must not write a position of its own
checkNear( "the mirror still has not touched its own saved position",
	SINEW.Settings.targetLeft, 100 / 1920 )

-- a resize has to re-place the mirror, since its position depends on its own width
SINEW.Settings.targetWidth = 400
SINEW.ApplyAll()
check( "a wider mirror is re-placed from its new width",
	targetWindow.window:GetLeft(), 1920 - 390 - targetWindow.window:GetWidth() )

SINEW.Settings.targetWidth = 260
SINEW.Settings.mirrorTarget = false
SINEW.SetMoveMode( false )
SINEW.ApplyAll()

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
local converted = SINEW.ConvertToEuro( sample )

check( "numbers become strings",       type( converted.width ), "string" )
check( "nested numbers too",           type( converted.nested.height ), "string" )
check( "numeric keys become strings",  converted["3"], "numeric key" )
check( "booleans survive",             converted.flag, true )
check( "strings survive",              converted.name, "morale" )
check( "Color instances pass through untouched", converted.color, sample.color )

local back = SINEW.ConvertFromEuro( converted )

check( "numbers come back",        back.width, 260 )
checkNear( "fractions come back",  back.nested.ratio, 0.755 )
check( "numeric keys come back",   back[3], "numeric key" )
check( "booleans still survive",   back.flag, true )
check( "strings still survive",    back.name, "morale" )

-- idempotent on a savefile written before the euro fix
local plain = SINEW.ConvertFromEuro( sample )
check( "already-numeric data survives a second pass", plain.width, 260 )

-- a real save and load through the fake disk
SINEW.Settings.selfWidth = 310
SINEW.Settings.selfTop = 0.42
SINEW.Save()

local onDisk = Turbine.PluginData.Load( Turbine.DataScope.Character, "sinewSettings" )
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
local reloaded = euro and SINEW.ConvertFromEuro( onDisk ) or onDisk
check( "the changed value survives the full save/load path", reloaded.selfWidth, 310 )
checkNear( "and so does a fractional one", reloaded.selfTop, 0.42 )

-- with no account copy at load time, every save mirrors to it
local mirrored = Turbine.PluginData.Load( Turbine.DataScope.Account, "sinewSettings" )
check( "the account copy was mirrored", mirrored ~= nil, true )
check( "SINEW reports a shared copy exists", SINEW.HasGlobalSettings(), true )

---------------------------------------------------------------------------------------------------
section( "drag" )
---------------------------------------------------------------------------------------------------

SINEW.SetMoveMode( true )
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
	SINEW.Settings.selfLeft, movedLeft / 1920 )

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

SINEW.SetMoveMode( false )
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

SINEW.Settings.opacity = 1.0
SINEW.ApplyAll()
checkNear( "full opacity is applied", selfWindow.window:GetOpacity(), 1.0 )

SINEW.Settings.opacity = 0.6
SINEW.ApplyAll()
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
SINEW.SetMoveMode( true )
checkNear( "drag mode overrides the opacity", selfWindow.window:GetOpacity(), 1.0 )

SINEW.SetMoveMode( false )
checkNear( "and leaving drag mode restores it", selfWindow.window:GetOpacity(), 0.6 )

-- zero would be invisible with no visible way back
SINEW.Settings.opacity = 0
SINEW.NormaliseSettings()
check( "opacity is floored above invisible", SINEW.Settings.opacity, 0.05 )

SINEW.Settings.opacity = 1.0
SINEW.ApplyAll()

-- an existing savefile's dead keys are cleared rather than left to linger
SINEW.Settings = { version = 2, opacityCombat = 1.0, opacityIdle = 0.55, selfWidth = 280 }
SINEW.NormaliseSettings()

check( "the old combat opacity is gone", SINEW.Settings.opacityCombat, nil )
check( "the old idle opacity too",       SINEW.Settings.opacityIdle,   nil )
check( "the new one is defaulted",       SINEW.Settings.opacity,       1.0 )
check( "and the savefile is restamped",  SINEW.Settings.version,       4 )
check( "other settings are left alone",  SINEW.Settings.selfWidth,     280 )

SINEW.Settings = {}
SINEW.NormaliseSettings()
SINEW.ApplyAll()

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
