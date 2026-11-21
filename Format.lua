---------------------------------------------------------------------------------------------------
-- Sinew - the readout templates
---------------------------------------------------------------------------------------------------
-- A readout is a line of text with tags in it: "[cur]  [perc]" renders as "12,480  74%". Four
-- templates per window - two inside the morale bar and two on the name row - replace what used to
-- be three on/off switches shared by both windows.
--
-- Why a template rather than more switches. The switches could only ever answer the questions they
-- were written for, and every new one meant another checkbox that interacted with the others: show
-- the number, show the percentage, show the level, and then "show the number but only as a
-- percentage on the target" needs a fourth. A template answers all of them and the ones nobody has
-- asked for yet, and it costs one setting per slot instead of one per question.
--
-- Two rules make a template behave the way you want on a HUD rather than the way a naive
-- substitution would:
--
--   * a tag with nothing to say renders as nothing - no bubble means [temp] is empty, full morale
--     means [deficit] is empty, a chest has no level so [level] is empty.
--
--   * if *every* tag in a template came back empty the whole line goes, and what is left is
--     trimmed. That is what makes "Level [level]" print nothing at all for a chest instead of a
--     bare "Level", and what makes "[cur]  [temp]" close its own gap when the bubble is gone.
--     A template with no tags in it is literal text and always shows.
--
-- Clearing a template is how a readout is switched off, which is why there is no separate switch.
---------------------------------------------------------------------------------------------------

SINEW.Format = {}

---------------------------------------------------------------------------------------------------
-- the tags
---------------------------------------------------------------------------------------------------
-- Keyed by tag name, and the context they read is keyed the same way, so a tag and the field it
-- describes cannot drift apart. A resolver returns a string, possibly empty; empty is what the
-- collapse rule above keys off, so "there is no bubble" must never come back as "0".
--
-- The context is the window's, not the bar's: the morale bar and the name row render against the
-- same one. That is deliberate - it is what lets a template inside the morale bar name the power
-- reading, which is otherwise unreachable, because the hairline is four pixels tall and carries no
-- text of its own.
---------------------------------------------------------------------------------------------------

local TAGS = {}

local function NumberTag( field )

	return function( context, modifier )

		local value = tonumber( context[ field ] )

		if value == nil then return "" end

		return SINEW.FormatValue( value, modifier )

	end

end

TAGS.cur    = NumberTag( "cur" )
TAGS.max    = NumberTag( "max" )
TAGS.pow    = NumberTag( "pow" )
TAGS.maxpow = NumberTag( "maxpow" )

-- the bubble carries its own plus sign. It is morale sitting on top of your morale rather than a
-- reading in its own right, and "+125" is how it reads; a bare 125 beside a morale number invites
-- being read as part of it.
TAGS.temp = function( context, modifier )

	local value = tonumber( context.temp )

	if value == nil or value <= 0 then return "" end

	return "+" .. SINEW.FormatValue( value, modifier )

end

TAGS.maxtemp = function( context, modifier )

	local value = tonumber( context.maxtemp )

	if value == nil or value <= 0 then return "" end

	return SINEW.FormatValue( value, modifier )

end

-- blank at full, which is the whole point of it: the number appears exactly when there is something
-- missing, and gets out of the way the rest of the time
TAGS.deficit = function( context, modifier )

	local current, max = tonumber( context.cur ), tonumber( context.max )

	if current == nil or max == nil or max - current <= 0 then return "" end

	return "-" .. SINEW.FormatValue( max - current, modifier )

end

local function PercentTag( currentField, maxField )

	return function( context, modifier )

		local current, max = tonumber( context[ currentField ] ), tonumber( context[ maxField ] )

		if current == nil or max == nil or max <= 0 then return "" end

		return SINEW.FormatPercent( current, max, tonumber( modifier ) )

	end

end

TAGS.perc    = PercentTag( "cur", "max" )
TAGS.powperc = PercentTag( "pow", "maxpow" )

TAGS.name = function( context )
	return context.name ~= nil and tostring( context.name ) or ""
end

-- the bare number, so the word in front of it is yours to choose - which is also the one piece of
-- localisation Sinew needs, since a German client wants "Stufe 150" rather than "Level 150"
TAGS.level = function( context )

	local level = tonumber( context.level )

	if level == nil then return "" end

	return tostring( math.floor( level ) )

end

---------------------------------------------------------------------------------------------------
-- the help text
---------------------------------------------------------------------------------------------------
-- Ordered, because the table above is not, and this is the only documentation a player gets: it is
-- printed by /sinew format and abbreviated in the options panel. There is no tooltip to put it in.
---------------------------------------------------------------------------------------------------

SINEW.Format.Help = {
	{ "[cur]",     "the current value - morale in the morale bar" },
	{ "[max]",     "its maximum" },
	{ "[perc]",    "the percentage, as 74%" },
	{ "[deficit]", "how much is missing, as -3,240. Blank at full" },
	{ "[temp]",    "temporary morale, as +125. Blank when there is none" },
	{ "[maxtemp]", "the bubble's own maximum" },
	{ "[pow]",     "power, so the morale bar can carry the number the hairline cannot" },
	{ "[maxpow]",  "maximum power" },
	{ "[powperc]", "power as a percentage" },
	{ "[name]",    "who the frame is describing" },
	{ "[level]",   "their level, as a bare number. Blank for a chest or a door" },
}

SINEW.Format.Modifiers = {
	{ "[cur:short]", "always abbreviated - 12.5k" },
	{ "[cur:full]",  "never abbreviated - 12,480" },
	{ "[perc:1]",    "a decimal place on a percentage, up to [perc:2]" },
}

---------------------------------------------------------------------------------------------------
-- render
---------------------------------------------------------------------------------------------------
function SINEW.Format.Render( template, context )

	-- a euro savefile turns anything that parses as a number back into one, so a template of "100"
	-- arrives here as a number rather than a string
	local text = tostring( template or "" )

	if text == "" then return "" end

	context = context or {}

	local tags, filled = 0, 0

	-- no nested brackets, so an unclosed "[cur" is left alone as literal text rather than swallowing
	-- the rest of the line looking for its closing bracket
	local rendered = string.gsub( text, "%[([^%[%]]*)%]", function( body )

		tags = tags + 1

		local name, modifier = string.match( body, "^([^:]*):?(.*)$" )

		local resolver = TAGS[ string.lower( name or "" ) ]

		if resolver == nil then
			-- handed back exactly as it was typed, and counted as filled so the collapse rule cannot
			-- eat it. This game has no log file, so a typo that rendered as nothing would look
			-- identical to a tag that correctly had nothing to say; left on screen it says which.
			filled = filled + 1
			return "[" .. body .. "]"
		end

		local value = resolver( context, ( modifier ~= nil and modifier ~= "" ) and modifier or nil )

		if value ~= "" then
			filled = filled + 1
		end

		return value

	end )

	if tags > 0 and filled == 0 then
		return ""
	end

	-- a template is padded around the tags that may empty - "[cur]  [temp]" - so the padding has to
	-- go when the tag does
	return ( string.match( rendered, "^%s*(.-)%s*$" ) )

end
